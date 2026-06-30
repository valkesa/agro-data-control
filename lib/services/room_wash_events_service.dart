import 'package:cloud_firestore/cloud_firestore.dart';

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
