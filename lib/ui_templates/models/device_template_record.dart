import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'device_template.dart';

/// Current contract version of a `deviceTemplates/{id}` Firestore document —
/// distinct from [DeviceTemplateRecord.templateVersion], which is the
/// template's own functional/content version (bumped when its metrics/
/// slots/columns change, unrelated to the document's shape). A doc whose
/// `schemaVersion` exceeds this constant is not even attempted to parse —
/// see [DeviceTemplateRecord.fromMap].
const int supportedDeviceTemplateSchemaVersion = 1;

/// Firestore persistence envelope around a [DeviceTemplate]: adds
/// versioning/lifecycle metadata (`schemaVersion`, `templateVersion`,
/// `enabled`, timestamps, optional `description`/`tags`) without touching
/// `DeviceTemplate` itself, which stays the pure visual-contract model
/// shared by TABLERO/TABLA and the local catalog
/// (`lib/ui_templates/catalog/agro_ui_templates.dart`).
///
/// `DeviceTemplate.toMap()`/`fromMap()` already cover the full structural
/// shape (metrics/indicators/boardSlots/tableColumns/enums) plus
/// constructor-time validation (duplicate keys, dangling references,
/// unknown enum values, non-serializable indicator conditions, ...) — this
/// class reuses that validation as-is rather than re-implementing it.
class DeviceTemplateRecord {
  const DeviceTemplateRecord({
    required this.template,
    required this.schemaVersion,
    required this.templateVersion,
    required this.enabled,
    this.createdAt,
    this.updatedAt,
    this.description,
    this.tags = const <String>[],
  });

  final DeviceTemplate template;
  final int schemaVersion;
  final int templateVersion;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? description;
  final List<String> tags;

  /// Defensive parse: returns `null` (never throws) for a document that is
  /// malformed, has an unrecognized field, or declares a `schemaVersion`
  /// newer than this build supports. Callers (`DeviceTemplateRepository`,
  /// `DeviceTemplateRegistry`) treat `null` the same as "no remote template
  /// for this id" — the local catalog fallback takes over.
  static DeviceTemplateRecord? fromMap(Map<String, Object?> map) {
    final int schemaVersion = _readInt(map['schemaVersion'], defaultValue: 0);
    if (schemaVersion <= 0 ||
        schemaVersion > supportedDeviceTemplateSchemaVersion) {
      debugPrint(
        '[TEMPLATE_REGISTRY] unsupported schemaVersion=$schemaVersion '
        'id=${map['id']} (supported=$supportedDeviceTemplateSchemaVersion) '
        '-> local fallback',
      );
      return null;
    }

    final DeviceTemplate template;
    try {
      template = DeviceTemplate.fromMap(map);
    } catch (error) {
      debugPrint(
        '[TEMPLATE_REGISTRY] invalid remote template id=${map['id']} '
        'error=$error -> local fallback',
      );
      return null;
    }

    return DeviceTemplateRecord(
      template: template,
      schemaVersion: schemaVersion,
      templateVersion: _readInt(map['templateVersion'], defaultValue: 1),
      enabled: map['enabled'] is bool ? map['enabled']! as bool : true,
      createdAt: _readTimestamp(map['createdAt']),
      updatedAt: _readTimestamp(map['updatedAt']),
      description: (map['description'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['description'] as String).trim(),
      tags: map['tags'] is Iterable
          ? List<String>.unmodifiable(
              (map['tags']! as Iterable).map((Object? e) => e.toString()),
            )
          : const <String>[],
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      ...template.toMap(),
      'schemaVersion': schemaVersion,
      'templateVersion': templateVersion,
      'enabled': enabled,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (description != null) 'description': description,
      'tags': tags,
    };
  }

  static int _readInt(Object? value, {required int defaultValue}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return defaultValue;
  }

  /// `createdAt`/`updatedAt` arrive as a Firestore `Timestamp` from a live
  /// read, but may be a plain `DateTime` (tests) or ISO string (defensive) —
  /// accept all three rather than assuming one shape.
  static DateTime? _readTimestamp(Object? value) {
    // `Timestamp.toDate()` returns local time by default (a well-known
    // cloud_firestore quirk) — normalize to UTC so this doesn't depend on
    // the runtime's timezone, in tests or in production.
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }
}
