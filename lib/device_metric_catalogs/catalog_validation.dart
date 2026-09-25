import '../ui_templates/enums/metric_display_type.dart';
import '../ui_templates/enums/metric_status_behavior.dart';
import '../ui_templates/enums/metric_transform.dart';
import '../ui_templates/models/metric_definition.dart';

/// Strict N2 boundary. Legacy parsers retain their existing behavior.
abstract final class CatalogValidation {
  static const schemaVersion = 1;
  // Matches the numeric formatter's toStringAsFixed contract, not a UI preset.
  static const maxDecimals = 20;
  static final _path = RegExp(
    r'^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$',
  );
  static const metricFields = {
    'key',
    'label',
    'shortLabel',
    'unit',
    'icon',
    'sourceField',
    'valueLabelSourceField',
    'displayType',
    'decimals',
    'transform',
    'statusBehavior',
  };

  static void fields(Map<String, Object?> map, Set<String> allowed) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        throw ArgumentError.value(key, 'field', 'Unknown field in N2 schema');
      }
    }
  }

  static String string(Object? value, String field, {bool allowEmpty = false}) {
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      throw ArgumentError.value(value, field, 'Expected valid string');
    }
    return value;
  }

  static void key(String value, String field) {
    string(value, field);
    if (value != value.trim()) {
      throw ArgumentError.value(
        value,
        field,
        'Surrounding whitespace is not allowed',
      );
    }
  }

  /// Flat aliases and dotted keys are opaque lookups, not nested traversal.
  /// Prefixes are extensible; no list of known metric names is imposed.
  static void source(String value) {
    if (!_path.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'sourceField',
        'Expected alias or dotted source key',
      );
    }
  }

  static int integer(Object? value, String field, {int min = 1, int? max}) {
    if (value is! int || value < min || (max != null && value > max)) {
      throw ArgumentError.value(value, field, 'Invalid integer');
    }
    return value;
  }

  static Map<String, Object?> map(Object? value, String field) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw ArgumentError.value(value, field, 'Expected string-keyed map');
    }
    return Map<String, Object?>.from(value);
  }

  static List<Object?> list(Object? value, String field) {
    if (value is! List) {
      throw ArgumentError.value(value, field, 'Expected list');
    }
    return List<Object?>.from(value);
  }

  static void metric(MetricDefinition value) {
    key(value.key, 'key');
    string(value.label, 'label');
    if (value.shortLabel != null) string(value.shortLabel, 'shortLabel');
    string(value.icon, 'icon');
    source(value.sourceField);
    if (value.valueLabelSourceField != null) {
      source(value.valueLabelSourceField!);
    }
    integer(value.decimals, 'decimals', min: 0, max: maxDecimals);
  }

  static MetricDefinition readMetric(Object? value) {
    final data = map(value, 'metric');
    fields(data, metricFields);
    for (final field in [
      'key',
      'label',
      'icon',
      'sourceField',
      'displayType',
      'transform',
      'statusBehavior',
    ]) {
      string(data[field], field);
    }
    string(data['unit'], 'unit', allowEmpty: true);
    for (final field in ['shortLabel', 'valueLabelSourceField']) {
      if (data.containsKey(field)) string(data[field], field);
    }
    integer(data['decimals'], 'decimals', min: 0, max: maxDecimals);
    // Reuse the existing model and enum readers; do not recreate formatting.
    final result = MetricDefinition(
      key: data['key']! as String,
      label: data['label']! as String,
      shortLabel: data['shortLabel'] as String?,
      unit: data['unit']! as String,
      icon: data['icon']! as String,
      sourceField: data['sourceField']! as String,
      valueLabelSourceField: data['valueLabelSourceField'] as String?,
      displayType: MetricDisplayType.fromWireName(
        data['displayType']! as String,
      ),
      decimals: data['decimals']! as int,
      transform: MetricTransform.fromWireName(data['transform']! as String),
      statusBehavior: MetricStatusBehavior.fromWireName(
        data['statusBehavior']! as String,
      ),
    );
    // Prevent legacy trimming/coercion from silently changing persisted keys.
    key(data['key']! as String, 'key');
    source(data['sourceField']! as String);
    if (data.containsKey('valueLabelSourceField')) {
      source(data['valueLabelSourceField']! as String);
    }
    metric(result);
    return result;
  }
}
