import '../device_metric_catalogs/device_metric_catalog.dart';
import '../device_metric_catalogs/metric_indicator_definition.dart';
import '../ui_templates/models/metric_definition.dart';
import 'capability_library_store.dart';
import 'capability_validation.dart';
import 'indicator_binding.dart';
import 'metric_binding.dart';

/// N6.5.2 §3/§13 — "Perfil de capacidades" in the UI: declares what a
/// Device *type* can expose, by referencing global [CapabilityMetricDefinition]/
/// [CapabilityIndicatorDefinition] entries by key (§4 — never copying them)
/// plus the Device-type-specific wiring for each (§5/§14).
///
/// [suggestedIndicatorsByMetric] is deliberately just a UI prefill (§8): the
/// board editor still lets any metric pick from the *entire*
/// [indicatorKeys] list (§7/§9), never only its suggested subset — that
/// restriction is exactly what N6.5.2 removes.
class DeviceCapabilityProfile {
  DeviceCapabilityProfile({
    required this.id,
    required this.name,
    this.description = '',
    this.enabled = true,
    Iterable<String> metricKeys = const [],
    Iterable<String> indicatorKeys = const [],
    Map<String, MetricBinding> metricBindings = const {},
    Map<String, IndicatorBinding> indicatorBindings = const {},
    Map<String, List<String>> suggestedIndicatorsByMetric = const {},
    this.profileVersion = 1,
  }) : metricKeys = List.unmodifiable(metricKeys),
       indicatorKeys = List.unmodifiable(indicatorKeys),
       metricBindings = Map.unmodifiable(metricBindings),
       indicatorBindings = Map.unmodifiable(indicatorBindings),
       suggestedIndicatorsByMetric = Map.unmodifiable({
         for (final entry in suggestedIndicatorsByMetric.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }) {
    CapabilityValidation.key(id, 'id');
    CapabilityValidation.string(name, 'name');
    final metricKeySet = this.metricKeys.toSet();
    if (metricKeySet.length != this.metricKeys.length) {
      throw ArgumentError('Duplicate metricKey in profile "$id"');
    }
    final indicatorKeySet = this.indicatorKeys.toSet();
    if (indicatorKeySet.length != this.indicatorKeys.length) {
      throw ArgumentError('Duplicate indicatorKey in profile "$id"');
    }
    // Every referenced metric/indicator must carry a binding (§5: sourceField
    // is required, always per-profile) — a key with no binding could never
    // resolve to a valid legacy MetricDefinition/MetricIndicatorDefinition.
    for (final key in this.metricKeys) {
      if (!this.metricBindings.containsKey(key)) {
        throw ArgumentError('Missing metricBinding for "$key"');
      }
    }
    for (final key in this.metricBindings.keys) {
      if (!metricKeySet.contains(key)) {
        throw ArgumentError('metricBinding for unknown metric "$key"');
      }
    }
    for (final key in this.indicatorKeys) {
      if (!this.indicatorBindings.containsKey(key)) {
        throw ArgumentError('Missing indicatorBinding for "$key"');
      }
    }
    for (final key in this.indicatorBindings.keys) {
      if (!indicatorKeySet.contains(key)) {
        throw ArgumentError('indicatorBinding for unknown indicator "$key"');
      }
    }
    // Suggestions are a subset of what the profile actually offers (§9 — a
    // suggestion can never point at a capability the profile doesn't have).
    for (final entry in this.suggestedIndicatorsByMetric.entries) {
      if (!metricKeySet.contains(entry.key)) {
        throw ArgumentError(
          'suggestedIndicatorsByMetric for unknown metric "${entry.key}"',
        );
      }
      final seen = <String>{};
      for (final key in entry.value) {
        if (!indicatorKeySet.contains(key) || !seen.add(key)) {
          throw ArgumentError(
            'Unknown or repeated suggested indicator "$key" for "${entry.key}"',
          );
        }
      }
    }
  }

  final String id;
  final String name;
  final String description;
  final bool enabled;
  final List<String> metricKeys;
  final List<String> indicatorKeys;
  final Map<String, MetricBinding> metricBindings;
  final Map<String, IndicatorBinding> indicatorBindings;
  final Map<String, List<String>> suggestedIndicatorsByMetric;
  final int profileVersion;

  /// Administration-only fields (mirrors [DeviceMetricCatalog.copyWith]):
  /// never touches capability membership/bindings — use `withOverrides` for
  /// those. `id` is intentionally not settable: it is the stable key
  /// [BoardPreset.capabilityProfileId] references.
  DeviceCapabilityProfile copyWith({
    String? name,
    String? description,
    bool? enabled,
    int? profileVersion,
  }) => DeviceCapabilityProfile(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    enabled: enabled ?? this.enabled,
    metricKeys: metricKeys,
    indicatorKeys: indicatorKeys,
    metricBindings: metricBindings,
    indicatorBindings: indicatorBindings,
    suggestedIndicatorsByMetric: suggestedIndicatorsByMetric,
    profileVersion: profileVersion ?? this.profileVersion,
  );

  /// Rebuilds capability membership/bindings/suggestions — never mutates in
  /// place, exactly like [DeviceMetricCatalog.withOverrides]. Removing a
  /// metric/indicator also strips its binding and any suggestion entries
  /// that reference it, so the invariants the constructor enforces always
  /// hold on the result.
  DeviceCapabilityProfile withOverrides({
    Iterable<String> addMetricKeys = const [],
    Iterable<String> removeMetricKeys = const [],
    Map<String, MetricBinding> metricBindingUpserts = const {},
    Iterable<String> addIndicatorKeys = const [],
    Iterable<String> removeIndicatorKeys = const [],
    Map<String, IndicatorBinding> indicatorBindingUpserts = const {},
    Map<String, List<String>> suggestedIndicatorsUpserts = const {},
  }) {
    final nextMetricKeys = {...metricKeys}
      ..removeAll(removeMetricKeys)
      ..addAll(addMetricKeys);
    final nextIndicatorKeys = {...indicatorKeys}
      ..removeAll(removeIndicatorKeys)
      ..addAll(addIndicatorKeys);
    final nextMetricBindings = {
      for (final entry in metricBindings.entries)
        if (nextMetricKeys.contains(entry.key)) entry.key: entry.value,
      ...metricBindingUpserts,
    };
    final nextIndicatorBindings = {
      for (final entry in indicatorBindings.entries)
        if (nextIndicatorKeys.contains(entry.key)) entry.key: entry.value,
      ...indicatorBindingUpserts,
    };
    final nextSuggested = {
      for (final entry in suggestedIndicatorsByMetric.entries)
        if (nextMetricKeys.contains(entry.key))
          entry.key: entry.value.where(nextIndicatorKeys.contains).toList(),
      for (final entry in suggestedIndicatorsUpserts.entries)
        entry.key: entry.value,
    };
    return DeviceCapabilityProfile(
      id: id,
      name: name,
      description: description,
      enabled: enabled,
      metricKeys: nextMetricKeys,
      indicatorKeys: nextIndicatorKeys,
      metricBindings: nextMetricBindings,
      indicatorBindings: nextIndicatorBindings,
      suggestedIndicatorsByMetric: nextSuggested,
      profileVersion: profileVersion,
    );
  }

  /// N6.5.2 §4/§7/§9 — the bridge back to the shape every existing
  /// validator/renderer/editor already consumes: resolves each referenced
  /// global definition + its binding into a legacy [MetricDefinition]/
  /// [MetricIndicatorDefinition], and — this is the actual behavioral change
  /// N6.5.2 makes — maps *every* resolved metric to the profile's *entire*
  /// indicator list in [DeviceMetricCatalog.availableIndicators], never a
  /// per-metric subset. A key missing from [metricsLibrary]/
  /// [indicatorsLibrary] (a dangling reference) is silently skipped here;
  /// any board item still pointing at it surfaces as the existing
  /// `metric_not_found`/`indicator_not_available` issue downstream, never a
  /// crash.
  DeviceMetricCatalog resolve(
    MetricLibraryStore metricsLibrary,
    IndicatorLibraryStore indicatorsLibrary,
  ) {
    final resolvedMetrics = <MetricDefinition>[];
    for (final key in metricKeys) {
      final global = metricsLibrary.byKey(key);
      final binding = metricBindings[key];
      if (global == null || binding == null) continue;
      resolvedMetrics.add(
        MetricDefinition(
          key: global.key,
          label: global.label,
          shortLabel: global.shortLabel,
          unit: binding.unitOverride ?? global.defaultUnit,
          icon: global.icon,
          sourceField: binding.sourceField,
          valueLabelSourceField: binding.valueLabelSourceField,
          displayType: global.displayType,
          decimals: global.decimals,
          transform: binding.transform,
          statusBehavior: global.statusBehavior,
        ),
      );
    }
    final resolvedIndicators = <MetricIndicatorDefinition>[];
    for (final key in indicatorKeys) {
      final global = indicatorsLibrary.byKey(key);
      final binding = indicatorBindings[key];
      if (global == null || binding == null) continue;
      resolvedIndicators.add(
        MetricIndicatorDefinition(
          key: global.key,
          sourceField: binding.sourceField,
          icon: global.defaultIcon,
          condition: binding.condition,
        ),
      );
    }
    final flatIndicatorKeys = resolvedIndicators.map((i) => i.key).toList();
    return DeviceMetricCatalog(
      id: id,
      name: name,
      description: description,
      enabled: enabled,
      metrics: resolvedMetrics,
      indicators: resolvedIndicators,
      availableIndicators: {
        for (final metric in resolvedMetrics) metric.key: flatIndicatorKeys,
      },
    );
  }

  /// N7.1 §2/§7 — persistence round-trip for `capabilityProfiles/{id}`.
  /// Deliberately references global metrics/indicators only by key (§4):
  /// never embeds a [CapabilityMetricDefinition]/[CapabilityIndicatorDefinition]
  /// here, only its own [metricBindings]/[indicatorBindings] (§5/§14).
  factory DeviceCapabilityProfile.fromMap(Map<String, Object?> map) {
    final metricBindingsMap = (map['metricBindings'] as Map?) ?? const {};
    final indicatorBindingsMap = (map['indicatorBindings'] as Map?) ?? const {};
    final suggestedMap =
        (map['suggestedIndicatorsByMetric'] as Map?) ?? const {};
    return DeviceCapabilityProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      description: (map['description'] as String?) ?? '',
      enabled: (map['enabled'] as bool?) ?? true,
      metricKeys: (map['metricKeys'] as List?)?.cast<String>() ?? const [],
      indicatorKeys:
          (map['indicatorKeys'] as List?)?.cast<String>() ?? const [],
      metricBindings: {
        for (final entry in metricBindingsMap.entries)
          entry.key as String: MetricBinding.fromMap(
            (entry.value as Map).cast<String, Object?>(),
          ),
      },
      indicatorBindings: {
        for (final entry in indicatorBindingsMap.entries)
          entry.key as String: IndicatorBinding.fromMap(
            (entry.value as Map).cast<String, Object?>(),
          ),
      },
      suggestedIndicatorsByMetric: {
        for (final entry in suggestedMap.entries)
          entry.key as String: (entry.value as List).cast<String>(),
      },
      profileVersion: (map['profileVersion'] as int?) ?? 1,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'enabled': enabled,
    'metricKeys': metricKeys,
    'indicatorKeys': indicatorKeys,
    'metricBindings': {
      for (final entry in metricBindings.entries)
        entry.key: entry.value.toMap(),
    },
    'indicatorBindings': {
      for (final entry in indicatorBindings.entries)
        entry.key: entry.value.toMap(),
    },
    'suggestedIndicatorsByMetric': suggestedIndicatorsByMetric,
    'profileVersion': profileVersion,
  };
}
