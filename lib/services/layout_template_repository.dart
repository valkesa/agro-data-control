import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firestore_paths.dart';
import '../layout_templates/layout_template.dart';
import 'firestore_timestamp_adapter.dart';
import 'firestore_version_conflict.dart';

/// N7.1 §2/§4 — persistence for `layoutTemplates/{id}`, global/reusable
/// config (§3). Pure Firestore access, no caching (an admin-only,
/// low-frequency collection — no runtime registry needed on top, unlike
/// `deviceTemplates`). Deliberately no `watchXxx()` stream: nothing in this
/// app consumes layout templates continuously, so a permanent listener
/// would violate N7.1 §5 ("cero streams permanentes innecesarios") for no
/// benefit — every read here is one-shot, refreshed explicitly by the
/// caller after a write.
class LayoutTemplateRepository {
  const LayoutTemplateRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  static const List<String> _timestampFields = ['createdAt', 'updatedAt'];

  Future<List<LayoutTemplate>> fetchAll() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(FirestorePaths.layoutTemplatesCollection())
        .get();
    return _parseSnapshot(snapshot);
  }

  Future<LayoutTemplate?> fetchOne(String templateId) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await firestore
        .doc(FirestorePaths.layoutTemplateDoc(templateId))
        .get();
    if (!snapshot.exists) return null;
    return _parseDoc(snapshot.data() ?? <String, Object?>{});
  }

  /// First-time persistence of a new template. Rejects an id that already
  /// exists (pre-check for a friendly error; Firestore rules are the real
  /// enforcement — same documented approach as `AgroSiteService.create`).
  Future<void> create(LayoutTemplate template) async {
    final String path = FirestorePaths.layoutTemplateDoc(template.id);
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      path,
    );
    final created = await firestore.runTransaction<bool>((transaction) async {
      if ((await transaction.get(reference)).exists) return false;
      transaction.set(reference, <String, Object?>{
        ...template.toMap(),
        'templateVersion': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!created) {
      throw FirestoreAlreadyExists(
        entityType: 'layoutTemplate',
        entityId: template.id,
      );
    }
  }

  /// Versioned update — N7.1 §15: throws [FirestoreVersionConflict] rather
  /// than overwriting silently if `expectedVersion` no longer matches what
  /// is stored.
  Future<int> save({
    required LayoutTemplate template,
    required int expectedVersion,
  }) async {
    final String path = FirestorePaths.layoutTemplateDoc(template.id);
    final outcome = await firestore.runTransaction<Object>((
      Transaction transaction,
    ) async {
      final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
        path,
      );
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);
      if (!snapshot.exists) {
        throw StateError('LayoutTemplate remoto inexistente: ${template.id}');
      }
      final int actualVersion =
          (snapshot.data()?['templateVersion'] as int?) ?? 0;
      if (actualVersion != expectedVersion) {
        return FirestoreVersionMismatchResult(actualVersion);
      }
      final int nextVersion = expectedVersion + 1;
      transaction.set(reference, <String, Object?>{
        ...template.toMap(),
        'templateVersion': nextVersion,
        'createdAt':
            snapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return nextVersion;
    });
    if (outcome is FirestoreVersionMismatchResult) {
      throw FirestoreVersionConflict(
        entityType: 'layoutTemplate',
        entityId: template.id,
        expectedVersion: expectedVersion,
        actualVersion: outcome.actualVersion,
      );
    }
    return outcome as int;
  }

  /// Soft-disable only — same "never physically deleted" convention as
  /// `deviceTemplates` (N7.1 keeps every global config collection
  /// consistent unless the prompt explicitly calls out hard delete, which
  /// it only does for `BoardPreset` — see `BoardPresetRepository.delete`).
  Future<void> setEnabled(String templateId, bool enabled) async {
    await firestore.doc(FirestorePaths.layoutTemplateDoc(templateId)).set(
      <String, Object?>{
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  List<LayoutTemplate> _parseSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final List<LayoutTemplate> results = <LayoutTemplate>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final LayoutTemplate? parsed = _tryParse(doc.data());
      if (parsed != null) results.add(parsed);
    }
    return results;
  }

  LayoutTemplate? _tryParse(Map<String, Object?> raw) {
    try {
      return _parseDoc(raw);
    } catch (_) {
      // A single malformed doc is skipped, never breaks the whole read —
      // same defensive convention as `DeviceTemplateRepository`.
      return null;
    }
  }

  LayoutTemplate _parseDoc(Map<String, Object?> raw) => LayoutTemplate.fromMap(
    normalizeFirestoreTimestamps(raw, timestampFields: _timestampFields),
  );
}
