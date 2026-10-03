import 'package:cloud_firestore/cloud_firestore.dart';

import '../device_capabilities/capability_metric_definition.dart';
import '../device_capabilities/capability_records.dart';
import '../firebase/firestore_paths.dart';
import 'firestore_timestamp_adapter.dart';
import 'firestore_version_conflict.dart';

/// N7.1 §2/§4/§11 — persistence for `capabilityMetrics/{key}`, global
/// metric library (§3). No `watchXxx()` stream (§5) — admin-only.
class CapabilityMetricRepository {
  const CapabilityMetricRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  static const List<String> _timestampFields = ['createdAt', 'updatedAt'];

  Future<List<CapabilityMetricRecord>> fetchAll() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(FirestorePaths.capabilityMetricsCollection())
        .get();
    final List<CapabilityMetricRecord> results = <CapabilityMetricRecord>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final CapabilityMetricRecord? record = CapabilityMetricRecord.fromMap(
        normalizeFirestoreTimestamps(
          doc.data(),
          timestampFields: _timestampFields,
        ),
      );
      if (record != null) results.add(record);
    }
    return results;
  }

  Future<CapabilityMetricRecord?> fetchOne(String metricKey) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await firestore
        .doc(FirestorePaths.capabilityMetricDoc(metricKey))
        .get();
    if (!snapshot.exists) return null;
    return CapabilityMetricRecord.fromMap(
      normalizeFirestoreTimestamps(
        snapshot.data() ?? <String, Object?>{},
        timestampFields: _timestampFields,
      ),
    );
  }

  Future<void> create(CapabilityMetricDefinition metric) async {
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.capabilityMetricDoc(metric.key),
    );
    final created = await firestore.runTransaction<bool>((transaction) async {
      if ((await transaction.get(reference)).exists) return false;
      transaction.set(reference, <String, Object?>{
        ...metric.toMap(),
        'schemaVersion': supportedCapabilityRecordSchemaVersion,
        'enabled': true,
        'recordVersion': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!created) {
      throw FirestoreAlreadyExists(
        entityType: 'capabilityMetric',
        entityId: metric.key,
      );
    }
  }

  Future<void> setEnabled(String metricKey, bool enabled) => firestore
      .doc(FirestorePaths.capabilityMetricDoc(metricKey))
      .update(<String, Object?>{
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<int> save({
    required CapabilityMetricDefinition metric,
    required bool enabled,
    required int expectedVersion,
  }) async {
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.capabilityMetricDoc(metric.key),
    );
    final outcome = await firestore.runTransaction<Object>((
      Transaction transaction,
    ) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);
      if (!snapshot.exists) {
        throw StateError('CapabilityMetric remota inexistente: ${metric.key}');
      }
      final int actualVersion =
          (snapshot.data()?['recordVersion'] as int?) ?? 1;
      if (actualVersion != expectedVersion) {
        return FirestoreVersionMismatchResult(actualVersion);
      }
      final int nextVersion = expectedVersion + 1;
      transaction.set(reference, <String, Object?>{
        ...metric.toMap(),
        'schemaVersion': supportedCapabilityRecordSchemaVersion,
        'enabled': enabled,
        'recordVersion': nextVersion,
        'createdAt':
            snapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return nextVersion;
    });
    if (outcome is FirestoreVersionMismatchResult) {
      throw FirestoreVersionConflict(
        entityType: 'capabilityMetric',
        entityId: metric.key,
        expectedVersion: expectedVersion,
        actualVersion: outcome.actualVersion,
      );
    }
    return outcome as int;
  }
}
