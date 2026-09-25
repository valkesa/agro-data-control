import '../ui_templates/enums/metric_display_type.dart';
import '../ui_templates/enums/metric_status_behavior.dart';
import 'capability_validation.dart';

/// N6.5.2 §1 — a reusable *semantic* metric concept ("Temperatura interior"),
/// independent of any Device wiring. Deliberately narrower than the legacy
/// `ui_templates.MetricDefinition` it gets resolved into (via
/// `DeviceCapabilityProfile.resolve`): no `sourceField`, no
/// `valueLabelSourceField`, no `transform` — those depend on which Device
/// type is exposing this metric and how, so they live on [MetricBinding]
/// instead (N6.5.2 §5). Never references indicators; that association moved
/// to [DeviceCapabilityProfile] entirely (N6.5.2 §1 — "NO debe definir qué
/// indicators están asociados a esa métrica").
class CapabilityMetricDefinition {
  CapabilityMetricDefinition({
    required this.key,
    required this.label,
    this.shortLabel,
    required this.defaultUnit,
    required this.icon,
    required this.displayType,
    required this.decimals,
    this.statusBehavior = MetricStatusBehavior.none,
  }) {
    CapabilityValidation.key(key, 'key');
    CapabilityValidation.string(label, 'label');
    if (shortLabel != null) {
      CapabilityValidation.string(shortLabel!, 'shortLabel');
    }
    CapabilityValidation.string(icon, 'icon');
    CapabilityValidation.integer(
      decimals,
      'decimals',
      min: 0,
      max: CapabilityValidation.maxDecimals,
    );
  }

  final String key;
  final String label;
  final String? shortLabel;
  final String defaultUnit;
  final String icon;
  final MetricDisplayType displayType;
  final int decimals;
  final MetricStatusBehavior statusBehavior;

  static const _unset = Object();

  CapabilityMetricDefinition copyWith({
    String? label,
    Object? shortLabel = _unset,
    String? defaultUnit,
    String? icon,
    MetricDisplayType? displayType,
    int? decimals,
    MetricStatusBehavior? statusBehavior,
  }) => CapabilityMetricDefinition(
    key: key,
    label: label ?? this.label,
    shortLabel: identical(shortLabel, _unset)
        ? this.shortLabel
        : shortLabel as String?,
    defaultUnit: defaultUnit ?? this.defaultUnit,
    icon: icon ?? this.icon,
    displayType: displayType ?? this.displayType,
    decimals: decimals ?? this.decimals,
    statusBehavior: statusBehavior ?? this.statusBehavior,
  );

  /// N7.1 §2 — pure structural round-trip; persistence lifecycle metadata
  /// (schemaVersion/enabled/timestamps) lives one layer up in
  /// [CapabilityMetricRecord], mirroring [DeviceTemplateRecord] wrapping
  /// [DeviceTemplate] — this class stays exactly the domain object it
  /// already was.
  factory CapabilityMetricDefinition.fromMap(Map<String, Object?> map) =>
      CapabilityMetricDefinition(
        key: map['key'] as String,
        label: map['label'] as String,
        shortLabel: map['shortLabel'] as String?,
        defaultUnit: map['defaultUnit'] as String,
        icon: map['icon'] as String,
        displayType: MetricDisplayType.fromWireName(
          map['displayType'] as String,
        ),
        decimals: map['decimals'] as int,
        statusBehavior: MetricStatusBehavior.fromWireName(
          map['statusBehavior'] as String,
        ),
      );

  Map<String, Object?> toMap() => {
    'key': key,
    'label': label,
    if (shortLabel != null) 'shortLabel': shortLabel,
    'defaultUnit': defaultUnit,
    'icon': icon,
    'displayType': displayType.wireName,
    'decimals': decimals,
    'statusBehavior': statusBehavior.wireName,
  };
}
