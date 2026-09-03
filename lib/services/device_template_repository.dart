import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../ui_templates/models/device_template.dart';
import '../ui_templates/models/device_template_record.dart';

/// Persistence for `deviceTemplates/{id}` — pure Firestore access, no
/// caching and no fallback-to-local logic (that lives in
/// `DeviceTemplateRegistry`, which is the only intended caller of
/// [watchTemplates]). Kept separate from the resolver/registry per Etapa
/// 6A's separation of concerns: resolver → identity, repository →
/// persistence, registry → runtime cache.
class DeviceTemplateRepository {
  const DeviceTemplateRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  /// One listener over the whole collection — never per-template, never
  /// per-card. The collection is small (today: 3 docs), so a full-snapshot
  /// stream is the simplest strategy that still satisfies "1 lectura/cache
  /// de templates -> múltiples devices" (Etapa 6A §12-14).
  Stream<List<DeviceTemplateRecord>> watchTemplates() {
    debugPrint(
      '[TEMPLATE_REGISTRY] watching collection '
      'path=${FirestorePaths.deviceTemplatesCollection()}',
    );
    return firestore
        .collection(FirestorePaths.deviceTemplatesCollection())
        .snapshots()
        .map(_parseSnapshot);
  }

  Future<List<DeviceTemplateRecord>> fetchTemplates() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(FirestorePaths.deviceTemplatesCollection())
        .get();
    return _parseSnapshot(snapshot);
  }

  Future<DeviceTemplateRecord?> fetchTemplate(String templateId) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await firestore
        .doc(FirestorePaths.deviceTemplateDoc(templateId))
        .get();
    if (!snapshot.exists) {
      return null;
    }
    return DeviceTemplateRecord.fromMap(snapshot.data() ?? <String, Object?>{});
  }

  Future<void> updateTemplateMetadata({
    required String templateId,
    required bool enabled,
    String? description,
    List<String> tags = const <String>[],
  }) async {
    final String path = FirestorePaths.deviceTemplateDoc(templateId);
    await firestore.doc(path).set(<String, Object?>{
      'enabled': enabled,
      'description': _nullableNonEmpty(description) ?? FieldValue.delete(),
      'tags': _normalizeTags(tags),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> resetTemplateToLocal({
    required DeviceTemplate template,
    bool enabled = true,
    String? description,
    List<String> tags = const <String>[],
  }) async {
    final DeviceTemplateRecord? existing = await fetchTemplate(template.id);
    final int nextTemplateVersion = (existing?.templateVersion ?? 0) + 1;
    final String path = FirestorePaths.deviceTemplateDoc(template.id);
    await firestore.doc(path).set(<String, Object?>{
      ...template.toMap(),
      'schemaVersion': supportedDeviceTemplateSchemaVersion,
      'templateVersion': nextTemplateVersion,
      'enabled': enabled,
      'createdAt': existing?.createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (_nullableNonEmpty(description) case final String value)
        'description': value,
      'tags': _normalizeTags(tags),
    });
  }

  /// A single malformed doc is logged and skipped — never lets one bad
  /// template break the whole collection read (Etapa 6A §8, defensive
  /// parsing).
  List<DeviceTemplateRecord> _parseSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final List<DeviceTemplateRecord> records = <DeviceTemplateRecord>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final DeviceTemplateRecord? record = DeviceTemplateRecord.fromMap(
        doc.data(),
      );
      if (record != null) {
        records.add(record);
      }
    }
    return records;
  }
}

String? _nullableNonEmpty(String? value) {
  final String trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _normalizeTags(List<String> tags) {
  final Set<String> normalized = <String>{};
  for (final String tag in tags) {
    final String value = tag.trim();
    if (value.isNotEmpty) {
      normalized.add(value);
    }
  }
  return List<String>.unmodifiable(normalized);
}
