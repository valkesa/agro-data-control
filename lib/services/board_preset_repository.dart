import 'package:cloud_firestore/cloud_firestore.dart';

import '../board_presets/board_preset.dart';
import '../firebase/firestore_paths.dart';
import 'firestore_timestamp_adapter.dart';
import 'firestore_version_conflict.dart';

/// N7.1 §2/§4/§7/§10 — persistence for `boardPresets/{id}`, global/reusable
/// config (§3). [BoardPreset] already carries its own `enabled`/
/// `presetVersion`/`createdAt`/`updatedAt` (added directly to the model for
/// N7.1 — see `lib/board_presets/board_preset.dart`), so no separate Record
/// envelope is needed: the domain object is the persisted shape directly.
///
/// Unlike every other N7.1 global collection, a [BoardPreset] can actually
/// be [delete]d (§10) — deleting it never touches an already-applied
/// [DeviceBoardConfigRepository] document: that's a deep, independent copy
/// (N7.1 §9), never a live reference to this collection.
class BoardPresetRepository {
  const BoardPresetRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  static const List<String> _timestampFields = ['createdAt', 'updatedAt'];

  Future<List<BoardPreset>> fetchAll() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(FirestorePaths.boardPresetsCollection())
        .get();
    final List<BoardPreset> results = <BoardPreset>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final BoardPreset? parsed = _tryParse(doc.data());
      if (parsed != null) results.add(parsed);
    }
    return results;
  }

  Future<BoardPreset?> fetchOne(String presetId) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await firestore
        .doc(FirestorePaths.boardPresetDoc(presetId))
        .get();
    if (!snapshot.exists) return null;
    return _tryParse(snapshot.data() ?? <String, Object?>{});
  }

  Future<void> create(BoardPreset preset) async {
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.boardPresetDoc(preset.id),
    );
    final created = await firestore.runTransaction<bool>((transaction) async {
      if ((await transaction.get(reference)).exists) return false;
      transaction.set(reference, <String, Object?>{
        ...preset.toMap(),
        'presetVersion': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!created) {
      throw FirestoreAlreadyExists(
        entityType: 'boardPreset',
        entityId: preset.id,
      );
    }
  }

  /// Versioned update (§15) — every edit (rename, add/remove item, change
  /// profile, ...) goes through this, never a raw `.set()`. `presetVersion`
  /// is what [DeviceBoardConfigRepository.applyPreset] snapshots into
  /// `sourceBoardPresetVersion` (§6/§9) — trazability only, never re-read
  /// live afterwards.
  Future<int> save({
    required BoardPreset preset,
    required int expectedVersion,
  }) async {
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.boardPresetDoc(preset.id),
    );
    final outcome = await firestore.runTransaction<Object>((
      Transaction transaction,
    ) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);
      if (!snapshot.exists) {
        throw StateError('BoardPreset remoto inexistente: ${preset.id}');
      }
      final int actualVersion =
          (snapshot.data()?['presetVersion'] as int?) ?? 1;
      if (actualVersion != expectedVersion) {
        return FirestoreVersionMismatchResult(actualVersion);
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
    if (outcome is FirestoreVersionMismatchResult) {
      throw FirestoreVersionConflict(
        entityType: 'boardPreset',
        entityId: preset.id,
        expectedVersion: expectedVersion,
        actualVersion: outcome.actualVersion,
      );
    }
    return outcome as int;
  }

  /// N7.1 §10 — real, physical delete (the one exception among N7.1's
  /// global collections). No cascade of any kind: any Device that already
  /// applied this preset keeps its `DeviceBoardConfigRepository` document
  /// completely untouched, with `sourceBoardPresetId` surviving purely as
  /// historical trazability (its target may no longer exist — callers must
  /// never re-resolve it as a live reference).
  Future<int> countDeviceUsages(String presetId) async {
    final result = await firestore
        .collectionGroup('settings')
        .where('sourceBoardPresetId', isEqualTo: presetId)
        .count()
        .get();
    return result.count ?? 0;
  }

  Future<void> delete(String presetId, {int? expectedVersion}) async {
    final reference = firestore.doc(FirestorePaths.boardPresetDoc(presetId));
    final outcome = await firestore.runTransaction<Object>((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) return const _DeleteMissing();
      final actual = (snapshot.data()?['presetVersion'] as int?) ?? 1;
      if (expectedVersion != null && actual != expectedVersion) {
        return _DeleteConflict(actual);
      }
      transaction.delete(reference);
      return true;
    });
    if (outcome is _DeleteMissing) {
      throw StateError('BoardPreset remoto inexistente: $presetId');
    }
    if (outcome is _DeleteConflict) {
      throw FirestoreVersionConflict(
        entityType: 'boardPreset',
        entityId: presetId,
        expectedVersion: expectedVersion!,
        actualVersion: outcome.actualVersion,
      );
    }
  }

  BoardPreset? _tryParse(Map<String, Object?> raw) {
    try {
      return BoardPreset.fromMap(
        normalizeFirestoreTimestamps(raw, timestampFields: _timestampFields),
      );
    } catch (_) {
      return null;
    }
  }
}

class _DeleteMissing {
  const _DeleteMissing();
}

class _DeleteConflict {
  const _DeleteConflict(this.actualVersion);
  final int actualVersion;
}
