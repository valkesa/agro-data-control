import '../enums/metric_display_type.dart';
import '../enums/metric_status_behavior.dart';
import '../enums/metric_transform.dart';
import '_parsing.dart';

class MetricDefinition {
  MetricDefinition({
    required this.key,
    required this.label,
    this.shortLabel,
    required this.unit,
    required this.icon,
    required this.sourceField,
    this.valueLabelSourceField,
    required this.displayType,
    required this.decimals,
    this.transform = MetricTransform.none,
    this.statusBehavior = MetricStatusBehavior.none,
  }) {
    requireNonEmpty(key, 'key');
    requireNonEmpty(label, 'label');
    if (shortLabel != null) {
      requireNonEmpty(shortLabel!, 'shortLabel');
    }
    requireNonEmpty(icon, 'icon');
    requireNonEmpty(sourceField, 'sourceField');
    if (valueLabelSourceField != null) {
      requireNonEmpty(valueLabelSourceField!, 'valueLabelSourceField');
    }
    requireNonNegative(decimals, 'decimals');
  }

  factory MetricDefinition.fromMap(Map<String, Object?> map) {
    return MetricDefinition(
      key: readRequiredString(map, 'key'),
      label: readRequiredString(map, 'label'),
      shortLabel: readString(map['shortLabel']).trim().isEmpty
          ? null
          : readString(map['shortLabel']).trim(),
      unit: readString(map['unit']),
      icon: readRequiredString(map, 'icon'),
      sourceField: readRequiredString(map, 'sourceField'),
      valueLabelSourceField:
          readString(map['valueLabelSourceField']).trim().isEmpty
          ? null
          : readString(map['valueLabelSourceField']).trim(),
      displayType: MetricDisplayType.fromWireName(
        readRequiredString(map, 'displayType'),
      ),
      decimals: readNonNegativeInt(map, 'decimals'),
      transform: MetricTransform.fromWireName(
        readString(map['transform']).trim().isEmpty
            ? MetricTransform.none.wireName
            : readString(map['transform']).trim(),
      ),
      statusBehavior: MetricStatusBehavior.fromWireName(
        readString(map['statusBehavior']).trim().isEmpty
            ? MetricStatusBehavior.none.wireName
            : readString(map['statusBehavior']).trim(),
      ),
    );
  }

  final String key;
  final String label;
  final String? shortLabel;
  final String unit;
  final String icon;
  final String sourceField;
  final String? valueLabelSourceField;
  final MetricDisplayType displayType;
  final int decimals;
  final MetricTransform transform;
  final MetricStatusBehavior statusBehavior;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'key': key,
      'label': label,
      if (shortLabel != null) 'shortLabel': shortLabel,
      'unit': unit,
      'icon': icon,
      'sourceField': sourceField,
      if (valueLabelSourceField != null)
        'valueLabelSourceField': valueLabelSourceField,
      'displayType': displayType.wireName,
      'decimals': decimals,
      'transform': transform.wireName,
      'statusBehavior': statusBehavior.wireName,
    };
  }
}
