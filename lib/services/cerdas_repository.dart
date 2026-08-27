import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/cerdas_models.dart';

class CerdasRepository {
  const CerdasRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  Stream<PigStatsRecord?> watchPigStats({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) {
    return watchPigStatsForKey(
      CerdasContextKey.legacy(tenantId: tenantId, siteId: siteId, plcId: plcId),
    );
  }

  Stream<PigStatsRecord?> watchPigStatsForKey(CerdasContextKey key) {
    final String path = _pigStatsDocPath(key);
    debugPrint('[Firestore] pig stats stream started path=$path');
    return firestore.doc(path).snapshots().map((
      DocumentSnapshot<Map<String, dynamic>> snapshot,
    ) {
      if (!snapshot.exists) {
        return null;
      }
      return PigStatsRecord.fromFirestore(
        snapshot.data() ?? <String, dynamic>{},
      );
    });
  }

  Stream<List<PigMovementRecord>> watchPigMovements({
    required String tenantId,
    required String siteId,
    required String plcId,
    int limit = 10,
  }) {
    return watchPigMovementsForKey(
      CerdasContextKey.legacy(tenantId: tenantId, siteId: siteId, plcId: plcId),
      limit: limit,
    );
  }

  Stream<List<PigMovementRecord>> watchPigMovementsForKey(
    CerdasContextKey key, {
    int limit = 10,
  }) {
    final String path = _pigMovementsCollectionPath(key);
    debugPrint(
      '[Firestore] pig movements stream started path=$path limit=$limit',
    );
    return firestore
        .collection(path)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          return snapshot.docs
              .map(
                (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    PigMovementRecord.fromFirestore(
                      doc.data(),
                      documentId: doc.id,
                    ),
              )
              .toList(growable: false);
        });
  }

  String _pigStatsDocPath(CerdasContextKey key) {
    if (key.isLegacy) {
      return FirestorePaths.pigStatsDoc(
        tenantId: key.tenantId,
        siteId: key.siteId,
        plcId: key.plcId!,
      );
    }
    if (key.isDynamic && key.isRoomScoped) {
      return FirestorePaths.deviceRoomPigStatsDoc(
        tenantId: key.tenantId,
        deviceId: key.deviceId!,
        roomId: key.roomId!,
      );
    }
    if (key.isDynamic) {
      return FirestorePaths.devicePigStatsDoc(
        tenantId: key.tenantId,
        deviceId: key.deviceId!,
      );
    }
    throw ArgumentError.value(key.debugLabel, 'key', 'Invalid cerdas context');
  }

  String _pigMovementsCollectionPath(CerdasContextKey key) {
    if (key.isLegacy) {
      return FirestorePaths.pigMovementsCollection(
        tenantId: key.tenantId,
        siteId: key.siteId,
        plcId: key.plcId!,
      );
    }
    if (key.isDynamic && key.isRoomScoped) {
      return FirestorePaths.deviceRoomPigMovementsCollection(
        tenantId: key.tenantId,
        deviceId: key.deviceId!,
        roomId: key.roomId!,
      );
    }
    if (key.isDynamic) {
      return FirestorePaths.devicePigMovementsCollection(
        tenantId: key.tenantId,
        deviceId: key.deviceId!,
      );
    }
    throw ArgumentError.value(key.debugLabel, 'key', 'Invalid cerdas context');
  }

  Stream<List<PigExitReasonRecord>> watchPigExitReasons({
    required String tenantId,
    required String siteId,
  }) {
    final String path = FirestorePaths.pigExitReasonsCollection(
      tenantId: tenantId,
      siteId: siteId,
    );
    debugPrint('[Firestore] pig exit reasons stream started path=$path');
    return firestore.collection(path).snapshots().map((
      QuerySnapshot<Map<String, dynamic>> snapshot,
    ) {
      final List<PigExitReasonRecord> records = snapshot.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                PigExitReasonRecord.fromFirestore(
                  doc.data(),
                  documentId: doc.id,
                ),
          )
          .where((PigExitReasonRecord r) => r.normalizedName.isNotEmpty)
          .toList(growable: false);
      records.sort(
        (PigExitReasonRecord a, PigExitReasonRecord b) =>
            a.normalizedName.compareTo(b.normalizedName),
      );
      return records;
    });
  }

  Future<void> addPigMovement({
    required String tenantId,
    required String siteId,
    required String plcId,
    required String type,
    required DateTime date,
    required int quantity,
    String? reasonId,
    String? reasonName,
    required String userId,
    required String userName,
  }) async {
    return addPigMovementForKey(
      CerdasContextKey.legacy(tenantId: tenantId, siteId: siteId, plcId: plcId),
      type: type,
      date: date,
      quantity: quantity,
      reasonId: reasonId,
      reasonName: reasonName,
      userId: userId,
      userName: userName,
    );
  }

  Future<void> addPigMovementForKey(
    CerdasContextKey key, {
    required String type,
    required DateTime date,
    required int quantity,
    String? reasonId,
    String? reasonName,
    required String userId,
    required String userName,
  }) async {
    assert(type == 'in' || type == 'out', 'type must be "in" or "out"');
    assert(quantity > 0, 'quantity must be positive');

    final String statsPath = _pigStatsDocPath(key);
    final String movementsPath = _pigMovementsCollectionPath(key);

    debugPrint(
      '[Firestore] pig movement transaction key=${key.debugLabel} type=$type qty=$quantity',
    );

    await firestore.runTransaction((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> statsSnapshot =
          await transaction.get(firestore.doc(statsPath));

      final int currentCount = statsSnapshot.exists
          ? (_parseInt(statsSnapshot.data()?['currentCount']) ?? 0)
          : 0;

      final int newCount;
      if (type == 'in') {
        newCount = currentCount + quantity;
      } else {
        newCount = currentCount - quantity;
        if (newCount < 0) {
          throw Exception(
            'Stock insuficiente: solo hay $currentCount '
            '${currentCount == 1 ? 'cerda disponible' : 'cerdas disponibles'}.',
          );
        }
      }

      final DocumentReference<Map<String, dynamic>> movementRef = firestore
          .collection(movementsPath)
          .doc();

      transaction.set(movementRef, <String, dynamic>{
        'type': type,
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'quantity': quantity,
        'reasonId': reasonId,
        'reasonName': reasonName,
        'userId': userId,
        'userName': userName,
        'tenantId': key.tenantId,
        'siteId': key.siteId,
        if (key.plcId != null) 'plcId': key.plcId,
        if (key.deviceId != null) 'deviceId': key.deviceId,
        if (key.roomId != null) 'roomId': key.roomId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(firestore.doc(statsPath), <String, dynamic>{
        'currentCount': newCount,
        'tenantId': key.tenantId,
        'siteId': key.siteId,
        if (key.plcId != null) 'plcId': key.plcId,
        if (key.deviceId != null) 'deviceId': key.deviceId,
        if (key.roomId != null) 'roomId': key.roomId,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': userId,
      }, SetOptions(merge: true));
    });

    debugPrint(
      '[Firestore] pig movement transaction done key=${key.debugLabel} type=$type qty=$quantity',
    );
  }

  Future<PigExitReasonRecord> addPigExitReason({
    required String tenantId,
    required String siteId,
    required String name,
    required String userId,
  }) async {
    final String path = FirestorePaths.pigExitReasonsCollection(
      tenantId: tenantId,
      siteId: siteId,
    );
    final String trimmedName = name.trim();
    final String normalizedName = trimmedName.toLowerCase();

    final DocumentReference<Map<String, dynamic>> ref = firestore
        .collection(path)
        .doc();
    await ref.set(<String, dynamic>{
      'name': trimmedName,
      'normalizedName': normalizedName,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': userId,
    });

    debugPrint(
      '[Firestore] pig exit reason created id=${ref.id} name=$trimmedName',
    );

    return PigExitReasonRecord(
      reasonId: ref.id,
      name: trimmedName,
      normalizedName: normalizedName,
    );
  }
}

int? _parseInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
