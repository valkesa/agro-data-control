import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';

class ActiveUserPresence {
  const ActiveUserPresence({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.activeSince,
    required this.lastSeenAt,
  });

  final String uid;
  final String displayName;
  final String email;
  final String role;
  final DateTime? activeSince;
  final DateTime? lastSeenAt;

  static ActiveUserPresence fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return ActiveUserPresence(
      uid: data['uid']?.toString() ?? doc.id,
      displayName: data['displayName']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      role: data['role']?.toString() ?? '',
      activeSince: _readDateTime(data['activeSince']),
      lastSeenAt: _readDateTime(data['lastSeenAt']),
    );
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}

class PresenceService {
  const PresenceService({
    FirebaseFirestore? firestore,
    this.activeThreshold = const Duration(minutes: 5),
  }) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final Duration activeThreshold;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _presenceCollection(
    String workspaceId,
  ) {
    return _db.collection(
      FirestorePaths.workspacePresenceCollection(workspaceId),
    );
  }

  DocumentReference<Map<String, dynamic>> _presenceDoc({
    required String workspaceId,
    required String uid,
  }) {
    return _db.doc(FirestorePaths.workspacePresenceDoc(workspaceId, uid));
  }

  Stream<List<ActiveUserPresence>> watchActiveUsers({
    required String workspaceId,
    int limit = 50,
  }) {
    return _presenceCollection(workspaceId)
        .where('isOnline', isEqualTo: true)
        .orderBy('lastSeenAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          final DateTime minLastSeen = DateTime.now().subtract(activeThreshold);
          return snapshot.docs
              .map(ActiveUserPresence.fromFirestore)
              .where((ActiveUserPresence user) {
                final DateTime? lastSeenAt = user.lastSeenAt;
                return lastSeenAt != null && lastSeenAt.isAfter(minLastSeen);
              })
              .toList(growable: false);
        });
  }

  Future<void> markOnline({
    required String workspaceId,
    required User user,
    required String? role,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _presenceDoc(
      workspaceId: workspaceId,
      uid: user.uid,
    );
    final String email = user.email ?? '';
    final String displayName = _displayNameFor(user);

    try {
      await _db.runTransaction((Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>> snapshot =
            await transaction.get(ref);
        final Map<String, dynamic>? data = snapshot.data();
        final bool wasOnline = data?['isOnline'] == true;
        final Object? previousLastSeen = data?['lastSeenAt'];
        final bool previousSessionIsFresh =
            previousLastSeen is Timestamp &&
            previousLastSeen.toDate().isAfter(
              DateTime.now().subtract(activeThreshold),
            );
        final Object activeSince = wasOnline && previousSessionIsFresh
            ? (data?['activeSince'] ?? FieldValue.serverTimestamp())
            : FieldValue.serverTimestamp();

        transaction.set(ref, <String, Object?>{
          'uid': user.uid,
          'displayName': displayName,
          'email': email,
          'role': role ?? '',
          'isOnline': true,
          'activeSince': activeSince,
          'lastSeenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (error, stackTrace) {
      debugPrint('[Presence] markOnline error=$error');
      debugPrint('[Presence] markOnline stack=$stackTrace');
    }
  }

  Future<void> heartbeat({
    required String workspaceId,
    required User user,
    required String? role,
  }) async {
    try {
      await _presenceDoc(
        workspaceId: workspaceId,
        uid: user.uid,
      ).set(<String, Object?>{
        'uid': user.uid,
        'displayName': _displayNameFor(user),
        'email': user.email ?? '',
        'role': role ?? '',
        'isOnline': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error, stackTrace) {
      debugPrint('[Presence] heartbeat error=$error');
      debugPrint('[Presence] heartbeat stack=$stackTrace');
    }
  }

  Future<void> markOffline({
    required String workspaceId,
    required User user,
  }) async {
    try {
      await _presenceDoc(
        workspaceId: workspaceId,
        uid: user.uid,
      ).set(<String, Object?>{
        'uid': user.uid,
        'displayName': _displayNameFor(user),
        'email': user.email ?? '',
        'isOnline': false,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error, stackTrace) {
      debugPrint('[Presence] markOffline error=$error');
      debugPrint('[Presence] markOffline stack=$stackTrace');
    }
  }

  String _displayNameFor(User user) {
    final String? displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final String email = user.email ?? '';
    final int atIndex = email.indexOf('@');
    if (atIndex > 0) {
      return email.substring(0, atIndex);
    }
    return user.uid;
  }
}
