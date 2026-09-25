import 'package:cloud_firestore/cloud_firestore.dart';

import '../device_capabilities/capability_indicator_definition.dart';
import '../device_capabilities/capability_records.dart';
import '../firebase/firestore_paths.dart';
import 'firestore_timestamp_adapter.dart';
import 'firestore_version_conflict.dart';

/// N7.1 §2/§4/§12 — persistence for `capabilityIndicators/{key}`, global
/// indicator library (§3). Same shape as [CapabilityMetricRepository].
class CapabilityIndicatorRepository {
  const CapabilityIndicatorRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  static const List<String> _timestampFields = ['createdAt', 'updatedAt'];

  Future<List<CapabilityIndicatorRecord>> fetchAll() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(FirestorePaths.capabilityIndicatorsCollection())
        .get();
    final List<CapabilityIndicatorRecord> results =
        <CapabilityIndicatorRecord>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final CapabilityIndicatorRecord? record =
          CapabilityIndicatorRecord.fromMap(
            normalizeFirestoreTimestamps(
              doc.data(),
              timestampFields: _timestampFields,
            ),
          );
      if (record != null) results.add(record);
    }
    return results;
  }

  Future<CapabilityIndicatorRecord?> fetchOne(String indicatorKey) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await firestore
        .doc(FirestorePaths.capabilityIndicatorDoc(indicatorKey))
        .get();
    if (!snapshot.exists) return null;
    return CapabilityIndicatorRecord.fromMap(
      normalizeFirestoreTimestamps(
        snapshot.data() ?? <String, Object?>{},
        timestampFields: _timestampFields,
      ),
    );
  }

  Future<void> create(CapabilityIndicatorDefinition indicator) async {
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.capabilityIndicatorDoc(indicator.key),
    );
    if ((await reference.get()).exists) {
      throw StateError(
        'Ya existe un CapabilityIndicator con key "${indicator.key}".',
      );
    }
    await reference.set(<String, Object?>{
      ...indicator.toMap(),
      'schemaVersion': supportedCapabilityRecordSchemaVersion,
      'enabled': true,
      'recordVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<int> save({
    required CapabilityIndicatorDefinition indicator,
    required bool enabled,
    required int expectedVersion,
  }) {
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.capabilityIndicatorDoc(indicator.key),
    );
    return firestore.runTransaction<int>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);
      if (!snapshot.exists) {
        throw StateError(
          'CapabilityIndicator remota inexistente: ${indicator.key}',
        );
      }
      final int actualVersion =
          (snapshot.data()?['recordVersion'] as int?) ?? 1;
      if (actualVersion != expectedVersion) {
        throw FirestoreVersionConflict(
          entityType: 'capabilityIndicator',
          entityId: indicator.key,
          expectedVersion: expectedVersion,
          actualVersion: actualVersion,
        );
      }
      final int nextVersion = expectedVersion + 1;
      transaction.set(reference, <String, Object?>{
        ...indicator.toMap(),
        'schemaVersion': supportedCapabilityRecordSchemaVersion,
        'enabled': enabled,
        'recordVersion': nextVersion,
        'createdAt':
            snapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return nextVersion;
    });
  }
}
