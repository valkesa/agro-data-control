import 'capability_validation.dart';

/// N6.5.2 §5/§14 — the Device-type-specific wiring for one indicator within
/// a single [DeviceCapabilityProfile]. Same rationale as [MetricBinding]:
/// the same global indicator (`heater`) can read `calefaccionEtapa1` in
/// Profile A and `heaterOn` in Profile B (or not exist at all in Profile C),
/// so `sourceField`/`condition` are never part of
/// [CapabilityIndicatorDefinition] — always per-profile.
class IndicatorBinding {
  IndicatorBinding({required this.sourceField, this.condition = true}) {
    CapabilityValidation.source(sourceField);
    if (!(condition == null ||
        condition is String ||
        condition is bool ||
        (condition is num && (condition as num).isFinite))) {
      throw ArgumentError.value(
        condition,
        'condition',
        'Expected finite JSON scalar',
      );
    }
  }

  final String sourceField;
  final Object? condition;

  static const _unset = Object();

  IndicatorBinding copyWith({
    String? sourceField,
    Object? condition = _unset,
  }) => IndicatorBinding(
    sourceField: sourceField ?? this.sourceField,
    condition: identical(condition, _unset) ? this.condition : condition,
  );

  /// N7.1 §7 — see [MetricBinding.fromMap]: same rationale, no Firestore
  /// types in this model.
  factory IndicatorBinding.fromMap(Map<String, Object?> map) =>
      IndicatorBinding(
        sourceField: map['sourceField'] as String,
        condition: map['condition'],
      );

  Map<String, Object?> toMap() => {
    'sourceField': sourceField,
    'condition': condition,
  };
}
