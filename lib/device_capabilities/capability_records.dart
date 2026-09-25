import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'capability_indicator_definition.dart';
import 'capability_metric_definition.dart';

/// N7.1 §2/§6 — current contract version of a `capabilityMetrics/{key}` /
/// `capabilityIndicators/{key}` Firestore document. A doc whose
/// `schemaVersion` exceeds this constant is not even attempted to parse —
/// same defensive convention as [DeviceTemplateRecord].
const int supportedCapabilityRecordSchemaVersion = 1;

/// Firestore persistence envelope around a [CapabilityMetricDefinition]:
/// adds versioning/lifecycle metadata without touching the pure domain
/// object itself — mirrors [DeviceTemplateRecord] wrapping [DeviceTemplate]
/// exactly (resolver/registry → identity, repository → persistence).
class CapabilityMetricRecord {
  const CapabilityMetricRecord({
    required this.metric,
    required this.schemaVersion,
    required this.enabled,
    this.recordVersion = 1,
    this.createdAt,
    this.updatedAt,
  });

  final CapabilityMetricDefinition metric;
  final int schemaVersion;
  final bool enabled;

  /// N7.1 §15 — optimistic-concurrency counter, bumped on every
  /// [CapabilityMetricRepository.save]. Independent of [schemaVersion]
  /// (document shape) and of [CapabilityMetricDefinition] itself (which has
  /// no versioning concept of its own).
  final int recordVersion;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Defensive parse: `null` (never throws) for a malformed document or one
  /// declaring a newer `schemaVersion` than this build supports — callers
  /// skip it rather than let one bad doc break a whole collection read.
  static CapabilityMetricRecord? fromMap(Map<String, Object?> map) {
    final int schemaVersion = _readInt(map['schemaVersion'], defaultValue: 0);
    if (schemaVersion <= 0 ||
        schemaVersion > supportedCapabilityRecordSchemaVersion) {
      debugPrint(
        '[CAPABILITY_REPOSITORY] unsupported schemaVersion=$schemaVersion '
        'key=${map['key']} (supported=$supportedCapabilityRecordSchemaVersion) '
        '-> skipped',
      );
      return null;
    }
    final CapabilityMetricDefinition metric;
    try {
      metric = CapabilityMetricDefinition.fromMap(map);
    } catch (error) {
      debugPrint(
        '[CAPABILITY_REPOSITORY] invalid metric key=${map['key']} '
        'error=$error -> skipped',
      );
      return null;
    }
    return CapabilityMetricRecord(
      metric: metric,
      schemaVersion: schemaVersion,
      enabled: map['enabled'] is bool ? map['enabled']! as bool : true,
      recordVersion: _readInt(map['recordVersion'], defaultValue: 1),
      createdAt: _readTimestamp(map['createdAt']),
      updatedAt: _readTimestamp(map['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    ...metric.toMap(),
    'schemaVersion': schemaVersion,
    'enabled': enabled,
    'recordVersion': recordVersion,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

/// Same rationale as [CapabilityMetricRecord], wrapping
/// [CapabilityIndicatorDefinition] instead.
class CapabilityIndicatorRecord {
  const CapabilityIndicatorRecord({
    required this.indicator,
    required this.schemaVersion,
    required this.enabled,
    this.recordVersion = 1,
    this.createdAt,
    this.updatedAt,
  });

  final CapabilityIndicatorDefinition indicator;
  final int schemaVersion;
  final bool enabled;
  final int recordVersion;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static CapabilityIndicatorRecord? fromMap(Map<String, Object?> map) {
    final int schemaVersion = _readInt(map['schemaVersion'], defaultValue: 0);
    if (schemaVersion <= 0 ||
        schemaVersion > supportedCapabilityRecordSchemaVersion) {
      debugPrint(
        '[CAPABILITY_REPOSITORY] unsupported schemaVersion=$schemaVersion '
        'key=${map['key']} (supported=$supportedCapabilityRecordSchemaVersion) '
        '-> skipped',
      );
      return null;
    }
    final CapabilityIndicatorDefinition indicator;
    try {
      indicator = CapabilityIndicatorDefinition.fromMap(map);
    } catch (error) {
      debugPrint(
        '[CAPABILITY_REPOSITORY] invalid indicator key=${map['key']} '
        'error=$error -> skipped',
      );
      return null;
    }
    return CapabilityIndicatorRecord(
      indicator: indicator,
      schemaVersion: schemaVersion,
      enabled: map['enabled'] is bool ? map['enabled']! as bool : true,
      recordVersion: _readInt(map['recordVersion'], defaultValue: 1),
      createdAt: _readTimestamp(map['createdAt']),
      updatedAt: _readTimestamp(map['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    ...indicator.toMap(),
    'schemaVersion': schemaVersion,
    'recordVersion': recordVersion,
    'enabled': enabled,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

int _readInt(Object? value, {required int defaultValue}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return defaultValue;
}

/// Same Timestamp/DateTime/ISO-string tolerance as [DeviceTemplateRecord]
/// (`Timestamp.toDate()` returns local time by default — normalize to UTC).
DateTime? _readTimestamp(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}
