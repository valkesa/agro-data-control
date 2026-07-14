import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../firebase/firestore_paths.dart';
import '../models/room_wash_event.dart';

class RoomWashEventsService {
  const RoomWashEventsService({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  Future<String> create({
    required String tenantId,
    required String siteId,
    required RoomWashEvent event,
  }) async {
    final String path = FirestorePaths.roomWashEventsCollection(
      tenantId: tenantId,
      siteId: siteId,
    );
    final DocumentReference<Map<String, dynamic>> doc = _db
        .collection(path)
        .doc();
    await doc.set(event.toCreatePayload());
    return doc.id;
  }

  Future<bool> publishOperationalEvent({
    required String tenantId,
    required String siteId,
    required RoomWashEvent event,
    String? backendSnapshotEndpoint,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[room-wash] operational publish skipped: no Firebase user');
      return false;
    }

    final String? token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      debugPrint('[room-wash] operational publish skipped: empty token');
      return false;
    }

    final Uri uri = _operationalEventUri(backendSnapshotEndpoint);
    final Map<String, Object?> body = <String, Object?>{
      'tenantId': tenantId,
      'siteId': siteId,
      'roomNumber': event.roomNumber,
      'washedAt': event.washedAt.toUtc().toIso8601String(),
      'operatorId': event.createdByUid,
      'operatorName': event.createdByName,
    };

    try {
      final http.Response response = await http
          .post(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 6));
      final bool ok = response.statusCode >= 200 && response.statusCode < 300;
      debugPrint(
        '[room-wash] operational publish status=${response.statusCode} ok=$ok tenant=$tenantId site=$siteId room=${event.roomNumber}',
      );
      return ok;
    } on TimeoutException catch (error) {
      debugPrint('[room-wash] operational publish timeout: $error');
      return false;
    } catch (error) {
      debugPrint('[room-wash] operational publish failed: $error');
      return false;
    }
  }

  Future<bool> syncBackendCache({
    required String siteId,
    required RoomWashEvent event,
    String? backendSnapshotEndpoint,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[room-wash] cache sync skipped: no Firebase user');
      return false;
    }

    final String? token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      debugPrint('[room-wash] cache sync skipped: empty token');
      return false;
    }

    try {
      final http.Response response = await http
          .post(
            _roomWashCacheUri(backendSnapshotEndpoint),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'siteId': siteId,
              'roomId': event.roomId,
              'roomNumber': event.roomNumber,
              'washedAt': event.washedAt.toUtc().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 6));
      final bool ok = response.statusCode >= 200 && response.statusCode < 300;
      debugPrint(
        '[room-wash] cache sync status=${response.statusCode} ok=$ok site=$siteId room=${event.roomNumber}',
      );
      return ok;
    } on TimeoutException catch (error) {
      debugPrint('[room-wash] cache sync timeout: $error');
      return false;
    } catch (error) {
      debugPrint('[room-wash] cache sync failed: $error');
      return false;
    }
  }

  Uri _operationalEventUri(String? backendSnapshotEndpoint) {
    final String endpoint = backendSnapshotEndpoint?.trim().isNotEmpty == true
        ? backendSnapshotEndpoint!.trim()
        : AppConfig.currentBackendSnapshotUrl;
    final Uri snapshotUri = Uri.parse(endpoint);
    return snapshotUri.replace(
      path: '/api/operational-events/room-wash',
      query: '',
    );
  }

  Uri _roomWashCacheUri(String? backendSnapshotEndpoint) {
    final String endpoint = backendSnapshotEndpoint?.trim().isNotEmpty == true
        ? backendSnapshotEndpoint!.trim()
        : AppConfig.currentBackendSnapshotUrl;
    final Uri snapshotUri = Uri.parse(endpoint);
    return snapshotUri.replace(path: '/api/room-wash/cache', query: '');
  }

  Future<List<RoomWashEvent>> fetchByRange({
    required String tenantId,
    required String siteId,
    required DateTime start,
    required DateTime end,
    String? roomId,
  }) async {
    final String path = FirestorePaths.roomWashEventsCollection(
      tenantId: tenantId,
      siteId: siteId,
    );
    Query<Map<String, dynamic>> query = _db
        .collection(path)
        .where('tenantId', isEqualTo: tenantId)
        .where('washedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('washedAt', isLessThan: Timestamp.fromDate(end));
    if (roomId != null) {
      query = query.where('roomId', isEqualTo: roomId);
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot = await query
        .orderBy('washedAt')
        .get();
    return snapshot.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              RoomWashEvent.fromFirestore(doc.data(), documentId: doc.id),
        )
        .whereType<RoomWashEvent>()
        .toList(growable: false);
  }

  Future<RoomWashEvent?> fetchLatestRecentForRoom({
    required String tenantId,
    required String siteId,
    required int roomNumber,
    required DateTime since,
  }) async {
    final String path = FirestorePaths.roomWashEventsCollection(
      tenantId: tenantId,
      siteId: siteId,
    );
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
        .collection(path)
        .where('tenantId', isEqualTo: tenantId)
        .where('roomNumber', isEqualTo: roomNumber)
        .where('washedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('washedAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    final QueryDocumentSnapshot<Map<String, dynamic>> doc = snapshot.docs.first;
    return RoomWashEvent.fromFirestore(doc.data(), documentId: doc.id);
  }
}
