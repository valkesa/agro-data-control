import 'package:flutter/foundation.dart';
import 'capability_indicator_definition.dart';
import 'capability_metric_definition.dart';

/// N6.5.2 §11 — in-memory admin registry of [CapabilityMetricDefinition]s,
/// the "biblioteca global de métricas". No Firestore, no persistence across
/// restarts — same session-only contract every N6.5.x store already uses.
/// Deliberately separate from [IndicatorLibraryStore] (§2: two distinct
/// libraries, not one merged registry) and from
/// [DeviceCapabilityProfileStore] (a profile only *references* entries here
/// by key — see N6.5.2 §4).
class MetricLibraryStore extends ChangeNotifier {
  MetricLibraryStore({List<CapabilityMetricDefinition>? initial})
    : _metrics = List.of(initial ?? const []);

  List<CapabilityMetricDefinition> _metrics;

  List<CapabilityMetricDefinition> get metrics => List.unmodifiable(_metrics);

  void replaceAll(Iterable<CapabilityMetricDefinition> metrics) {
    _metrics = List.of(metrics);
    notifyListeners();
  }

  CapabilityMetricDefinition? byKey(String key) {
    for (final metric in _metrics) {
      if (metric.key == key) return metric;
    }
    return null;
  }

  /// Inserts a brand-new definition, or replaces the existing one with the
  /// same `key` in place (an edit, never a duplicate entry).
  void upsert(CapabilityMetricDefinition metric) {
    final index = _metrics.indexWhere((m) => m.key == metric.key);
    if (index == -1) {
      _metrics = [..._metrics, metric];
    } else {
      final next = [..._metrics];
      next[index] = metric;
      _metrics = next;
    }
    notifyListeners();
  }

  /// Caller is responsible for checking references first (same contract as
  /// every other N6.5.x store's `delete` — this method never checks on the
  /// caller's behalf, see N6.5.2 §20 "no borrar silenciosamente").
  void remove(String key) {
    _metrics = _metrics.where((m) => m.key != key).toList();
    notifyListeners();
  }

  CapabilityMetricDefinition duplicate(String key, {required String newKey}) {
    final original = byKey(key);
    if (original == null) throw ArgumentError('Unknown metric key "$key"');
    if (byKey(newKey) != null) {
      throw ArgumentError('metricKey "$newKey" already exists');
    }
    final copy = CapabilityMetricDefinition(
      key: newKey,
      label: '${original.label} (copia)',
      shortLabel: original.shortLabel,
      defaultUnit: original.defaultUnit,
      icon: original.icon,
      displayType: original.displayType,
      decimals: original.decimals,
      statusBehavior: original.statusBehavior,
    );
    _metrics = [..._metrics, copy];
    notifyListeners();
    return copy;
  }
}

/// N6.5.2 §12 — in-memory admin registry of [CapabilityIndicatorDefinition]s,
/// the "biblioteca global de indicators". Same contract as
/// [MetricLibraryStore]; kept as a distinct class/instance because the two
/// libraries are conceptually and administratively independent (§10).
class IndicatorLibraryStore extends ChangeNotifier {
  IndicatorLibraryStore({List<CapabilityIndicatorDefinition>? initial})
    : _indicators = List.of(initial ?? const []);

  List<CapabilityIndicatorDefinition> _indicators;

  List<CapabilityIndicatorDefinition> get indicators =>
      List.unmodifiable(_indicators);

  void replaceAll(Iterable<CapabilityIndicatorDefinition> indicators) {
    _indicators = List.of(indicators);
    notifyListeners();
  }

  CapabilityIndicatorDefinition? byKey(String key) {
    for (final indicator in _indicators) {
      if (indicator.key == key) return indicator;
    }
    return null;
  }

  void upsert(CapabilityIndicatorDefinition indicator) {
    final index = _indicators.indexWhere((i) => i.key == indicator.key);
    if (index == -1) {
      _indicators = [..._indicators, indicator];
    } else {
      final next = [..._indicators];
      next[index] = indicator;
      _indicators = next;
    }
    notifyListeners();
  }

  void remove(String key) {
    _indicators = _indicators.where((i) => i.key != key).toList();
    notifyListeners();
  }

  CapabilityIndicatorDefinition duplicate(
    String key, {
    required String newKey,
  }) {
    final original = byKey(key);
    if (original == null) throw ArgumentError('Unknown indicator key "$key"');
    if (byKey(newKey) != null) {
      throw ArgumentError('indicatorKey "$newKey" already exists');
    }
    final copy = CapabilityIndicatorDefinition(
      key: newKey,
      label: '${original.label} (copia)',
      defaultIcon: original.defaultIcon,
    );
    _indicators = [..._indicators, copy];
    notifyListeners();
    return copy;
  }
}

// Shared, pre-seeded instances (`sharedMetricLibraryStore`/
// `sharedIndicatorLibraryStore`) live in `reference_capability_seeds.dart`,
// not here — they must come into existence already seeded together with
// `sharedDeviceCapabilityProfileStore`, never empty (see that file's
// `_SeededCapabilities` for why a plain top-level `final` per store here
// would risk an access-order-dependent empty library).
