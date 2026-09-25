import 'capability_validation.dart';

/// N6.5.2 §2 — a reusable *semantic* indicator concept ("Calefacción etapa
/// 1"), independent of any Device wiring or of a specific metric. No
/// `sourceField`, no `condition` — those depend on which Device type exposes
/// it and how, so they live on [IndicatorBinding] instead (N6.5.2 §5). Never
/// pinned to a `metricKey`: which metrics a Device *offers* it under is a
/// [DeviceCapabilityProfile] concern (`indicatorKeys` + optionally
/// `suggestedIndicatorsByMetric`), not a property of the indicator itself.
class CapabilityIndicatorDefinition {
  CapabilityIndicatorDefinition({
    required this.key,
    required this.label,
    required this.defaultIcon,
  }) {
    CapabilityValidation.key(key, 'key');
    CapabilityValidation.string(label, 'label');
    CapabilityValidation.string(defaultIcon, 'defaultIcon');
  }

  final String key;
  final String label;
  final String defaultIcon;

  CapabilityIndicatorDefinition copyWith({
    String? label,
    String? defaultIcon,
  }) => CapabilityIndicatorDefinition(
    key: key,
    label: label ?? this.label,
    defaultIcon: defaultIcon ?? this.defaultIcon,
  );

  /// N7.1 §2 — see [CapabilityMetricDefinition.fromMap]: same rationale,
  /// persistence lifecycle metadata lives in [CapabilityIndicatorRecord].
  factory CapabilityIndicatorDefinition.fromMap(Map<String, Object?> map) =>
      CapabilityIndicatorDefinition(
        key: map['key'] as String,
        label: map['label'] as String,
        defaultIcon: map['defaultIcon'] as String,
      );

  Map<String, Object?> toMap() => {
    'key': key,
    'label': label,
    'defaultIcon': defaultIcon,
  };
}
