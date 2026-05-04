import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/door_openings_models.dart';

class DoorOpeningsRepository {
  const DoorOpeningsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  Stream<DoorStateRecord?> watchDoorState({
    required String tenantId,
    required String siteId,
    required String doorId,
  }) {
    final String path = FirestorePaths.doorStateDoc(
      tenantId: tenantId,
      siteId: siteId,
      doorId: doorId,
    );
    debugPrint('[Firestore] door state stream started path=$path');
    return firestore.doc(path).snapshots().map((
      DocumentSnapshot<Map<String, dynamic>> snapshot,
    ) {
      if (!snapshot.exists) {
        return null;
      }
      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      return DoorStateRecord.fromFirestore(data, documentId: snapshot.id);
    });
  }

  Stream<List<DoorOpeningRecord>> watchDoorHistory({
    required String tenantId,
    required String siteId,
    required String doorId,
    int limit = 20,
  }) {
    final String path = FirestorePaths.doorOpeningsCollection(
      tenantId: tenantId,
      siteId: siteId,
      doorId: doorId,
    );
    debugPrint(
      '[Firestore] door history stream started path=$path limit=$limit',
    );
    return firestore
        .collection(path)
        .orderBy('openedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          return snapshot.docs
              .map(
                (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    DoorOpeningRecord.fromFirestore(
                      doc.data(),
                      documentId: doc.id,
                    ),
              )
              .toList(growable: false);
        });
  }

  Stream<List<DoorOpeningRecord>> watchDoorMonthHistory({
    required String tenantId,
    required String siteId,
    required String doorId,
    required DateTime monthStart,
    int limit = 500,
  }) {
    final String path = FirestorePaths.doorOpeningsCollection(
      tenantId: tenantId,
      siteId: siteId,
      doorId: doorId,
    );
    debugPrint(
      '[Firestore] door month history stream started path=$path monthStart=$monthStart',
    );
    return firestore
        .collection(path)
        .where(
          'openedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart),
        )
        .orderBy('openedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          return snapshot.docs
              .map(
                (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    DoorOpeningRecord.fromFirestore(
                      doc.data(),
                      documentId: doc.id,
                    ),
              )
              .toList(growable: false);
        });
  }

  Stream<List<DoorOpeningRecord>> watchDoorOpeningsForCleanup({
    required String tenantId,
    required String siteId,
    required String doorId,
    int limit = 200,
  }) {
    final String path = FirestorePaths.doorOpeningsCollection(
      tenantId: tenantId,
      siteId: siteId,
      doorId: doorId,
    );
    debugPrint(
      '[Firestore] door cleanup stream started path=$path limit=$limit',
    );
    return firestore
        .collection(path)
        .orderBy('openedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          return snapshot.docs
              .map(
                (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    DoorOpeningRecord.fromFirestore(
                      doc.data(),
                      documentId: doc.id,
                    ),
              )
              .toList(growable: false);
        });
  }

  Future<void> deleteDoorOpenings({
    required String tenantId,
    required String siteId,
    required String doorId,
    required Iterable<String> openingIds,
  }) async {
    final List<String> ids = openingIds
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final String path = FirestorePaths.doorOpeningsCollection(
      tenantId: tenantId,
      siteId: siteId,
      doorId: doorId,
    );
    debugPrint(
      '[Firestore] door cleanup delete started path=$path count=${ids.length}',
    );
    final WriteBatch batch = firestore.batch();
    for (final String openingId in ids) {
      batch.delete(firestore.collection(path).doc(openingId));
    }
    await batch.commit();
    debugPrint('[Firestore] door cleanup delete done path=$path');
  }
}
