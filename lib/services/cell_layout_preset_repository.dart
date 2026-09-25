import 'package:cloud_firestore/cloud_firestore.dart';

import '../cell_layout_presets/cell_layout_preset.dart';
import '../firebase/firestore_paths.dart';
import 'firestore_timestamp_adapter.dart';
import 'firestore_version_conflict.dart';

/// N7.1 §2/§4 — persistence for `cellLayoutPresets/{id}`, global/reusable
/// config (§3). Same shape as [LayoutTemplateRepository]: no caching, no
/// `watchXxx()` stream (§5) — admin-only, one-shot reads.
class CellLayoutPresetRepository {
  const CellLayoutPresetRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  static const List<String> _timestampFields = ['createdAt', 'updatedAt'];

  Future<List<CellLayoutPreset>> fetchAll() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(FirestorePaths.cellLayoutPresetsCollection())
        .get();
    return _parseSnapshot(snapshot);
  }

  Future<CellLayoutPreset?> fetchOne(String presetId) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await firestore
        .doc(FirestorePaths.cellLayoutPresetDoc(presetId))
        .get();
    if (!snapshot.exists) return null;
    return _parseDoc(snapshot.data() ?? <String, Object?>{});
  }

  Future<void> create(CellLayoutPreset preset) async {
    final String path = FirestorePaths.cellLayoutPresetDoc(preset.id);
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      path,
    );
    final DocumentSnapshot<Map<String, dynamic>> existing = await reference
        .get();
    if (existing.exists) {
      throw StateError('Ya existe un CellLayoutPreset con id "${preset.id}".');
    }
    await reference.set(<String, Object?>{
      ...preset.toMap(),
      'presetVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<int> save({
    required CellLayoutPreset preset,
    required int expectedVersion,
  }) {
    final String path = FirestorePaths.cellLayoutPresetDoc(preset.id);
    return firestore.runTransaction<int>((Transaction transaction) async {
      final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
        path,
      );
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);
      if (!snapshot.exists) {
        throw StateError('CellLayoutPreset remoto inexistente: ${preset.id}');
      }
      final int actualVersion =
          (snapshot.data()?['presetVersion'] as int?) ?? 0;
      if (actualVersion != expectedVersion) {
        throw FirestoreVersionConflict(
          entityType: 'cellLayoutPreset',
          entityId: preset.id,
          expectedVersion: expectedVersion,
          actualVersion: actualVersion,
        );
      }
      final int nextVersion = expectedVersion + 1;
      transaction.set(reference, <String, Object?>{
        ...preset.toMap(),
        'presetVersion': nextVersion,
        'createdAt':
            snapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return nextVersion;
    });
  }

  Future<void> setEnabled(String presetId, bool enabled) async {
    await firestore.doc(FirestorePaths.cellLayoutPresetDoc(presetId)).set(
      <String, Object?>{
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  List<CellLayoutPreset> _parseSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final List<CellLayoutPreset> results = <CellLayoutPreset>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final CellLayoutPreset? parsed = _tryParse(doc.data());
      if (parsed != null) results.add(parsed);
    }
    return results;
  }

  CellLayoutPreset? _tryParse(Map<String, Object?> raw) {
    try {
      return _parseDoc(raw);
    } catch (_) {
      return null;
    }
  }

  CellLayoutPreset _parseDoc(Map<String, Object?> raw) =>
      CellLayoutPreset.fromMap(
        normalizeFirestoreTimestamps(raw, timestampFields: _timestampFields),
      );
}
