import '../ui_templates/enums/metric_transform.dart';
import 'capability_validation.dart';

/// N6.5.2 §5/§14 — the Device-type-specific wiring for one metric within a
/// single [DeviceCapabilityProfile]. `sourceField` is the whole reason this
/// class exists: the same global metric (`tempInterior`) can read from
/// `room1.temp` in Profile A and `plc.temperature` in Profile B, so it is
/// never universal (§5) — always a per-profile binding, never a field on
/// [CapabilityMetricDefinition]. `transform`/`unitOverride`/
/// `valueLabelSourceField` are likewise binding-only per the exact field
/// list in §14's example.
class MetricBinding {
  MetricBinding({
    required this.sourceField,
    this.transform = MetricTransform.none,
    this.unitOverride,
    this.valueLabelSourceField,
  }) {
    CapabilityValidation.source(sourceField);
    if (valueLabelSourceField != null) {
      CapabilityValidation.source(valueLabelSourceField!);
    }
  }

  final String sourceField;
  final MetricTransform transform;
  final String? unitOverride;
  final String? valueLabelSourceField;

  static const _unset = Object();

  MetricBinding copyWith({
    String? sourceField,
    MetricTransform? transform,
    Object? unitOverride = _unset,
    Object? valueLabelSourceField = _unset,
  }) => MetricBinding(
    sourceField: sourceField ?? this.sourceField,
    transform: transform ?? this.transform,
    unitOverride: identical(unitOverride, _unset)
        ? this.unitOverride
        : unitOverride as String?,
    valueLabelSourceField: identical(valueLabelSourceField, _unset)
        ? this.valueLabelSourceField
        : valueLabelSourceField as String?,
  );

  /// N7.1 §7 — a profile's bindings are part of what gets persisted to
  /// Firestore; kept a plain `Map<String, Object?>` round-trip (no
  /// Firestore types leak into this model) so [DeviceCapabilityProfile]
  /// stays testable without any Firestore dependency.
  factory MetricBinding.fromMap(Map<String, Object?> map) => MetricBinding(
    sourceField: map['sourceField'] as String,
    transform: MetricTransform.fromWireName(map['transform'] as String),
    unitOverride: map['unitOverride'] as String?,
    valueLabelSourceField: map['valueLabelSourceField'] as String?,
  );

  Map<String, Object?> toMap() => {
    'sourceField': sourceField,
    'transform': transform.wireName,
    if (unitOverride != null) 'unitOverride': unitOverride,
    if (valueLabelSourceField != null)
      'valueLabelSourceField': valueLabelSourceField,
  };
}
