import 'package:flutter/foundation.dart';
import 'device_capability_profile.dart';
import 'indicator_binding.dart';
import 'metric_binding.dart';

/// N6.5.2 §13 — a stable, readable id derived from a display name, same
/// contract as `slugifyCatalogId` (N6.5 §7) it replaces for this store.
String slugifyProfileId(String name) {
  const accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ñ': 'n',
    'ü': 'u',
  };
  var result = name.toLowerCase();
  accents.forEach(
    (accented, plain) => result = result.replaceAll(accented, plain),
  );
  result = result.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  result = result.replaceAll(RegExp(r'_+'), '_');
  result = result.replaceAll(RegExp(r'^_|_$'), '');
  return result.isEmpty ? 'profile' : result;
}

/// N6.5.2 §13 — in-memory admin registry of [DeviceCapabilityProfile]s. No
/// Firestore, no persistence across restarts — same session-only contract
/// every N6.5.x store uses.
class DeviceCapabilityProfileStore extends ChangeNotifier {
  DeviceCapabilityProfileStore({List<DeviceCapabilityProfile>? initial})
    : _profiles = List.of(initial ?? const []);

  List<DeviceCapabilityProfile> _profiles;
  int _nextSeq = 0;

  List<DeviceCapabilityProfile> get profiles => List.unmodifiable(_profiles);

  DeviceCapabilityProfile? byId(String id) {
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  String _freshId(String base) {
    final used = _profiles.map((p) => p.id).toSet();
    if (!used.contains(base)) return base;
    var candidate = '$base-${++_nextSeq}';
    while (used.contains(candidate)) {
      candidate = '$base-${++_nextSeq}';
    }
    return candidate;
  }

  // --- Profile CRUD --------------------------------------------------------

  DeviceCapabilityProfile create({
    required String name,
    String description = '',
  }) {
    final profile = DeviceCapabilityProfile(
      id: _freshId(slugifyProfileId(name)),
      name: name,
      description: description,
    );
    _profiles = [..._profiles, profile];
    notifyListeners();
    return profile;
  }

  /// Deep copy (same contract as `DeviceMetricCatalogStore.duplicate`): new
  /// id/name, same capability membership/bindings/suggestions — safe without
  /// cloning each binding because everything here is immutable.
  DeviceCapabilityProfile duplicate(String id) {
    final original = byId(id);
    if (original == null) throw ArgumentError('Unknown profile id "$id"');
    final copy = DeviceCapabilityProfile(
      id: _freshId('${original.id}-copy'),
      name: '${original.name} (copia)',
      description: original.description,
      enabled: original.enabled,
      metricKeys: original.metricKeys,
      indicatorKeys: original.indicatorKeys,
      metricBindings: original.metricBindings,
      indicatorBindings: original.indicatorBindings,
      suggestedIndicatorsByMetric: original.suggestedIndicatorsByMetric,
    );
    _profiles = [..._profiles, copy];
    notifyListeners();
    return copy;
  }

  void rename(String id, {String? name, String? description}) {
    _replace(id, (p) => p.copyWith(name: name, description: description));
  }

  void setEnabled(String id, bool enabled) {
    _replace(id, (p) => p.copyWith(enabled: enabled));
  }

  /// Caller is responsible for checking references first (N6.5.2 §20 — "no
  /// borrar silenciosamente"), same contract as every other N6.x store.
  void delete(String id) {
    _profiles = _profiles.where((p) => p.id != id).toList();
    notifyListeners();
  }

  // --- Metric membership (§13/§14) -----------------------------------------

  void addMetric(String profileId, String metricKey, MetricBinding binding) {
    _replace(
      profileId,
      (p) => p.withOverrides(
        addMetricKeys: [metricKey],
        metricBindingUpserts: {metricKey: binding},
      ),
    );
  }

  void removeMetric(String profileId, String metricKey) {
    _replace(profileId, (p) => p.withOverrides(removeMetricKeys: [metricKey]));
  }

  void setMetricBinding(
    String profileId,
    String metricKey,
    MetricBinding binding,
  ) {
    _replace(
      profileId,
      (p) => p.withOverrides(metricBindingUpserts: {metricKey: binding}),
    );
  }

  // --- Indicator membership (§13/§14) --------------------------------------

  void addIndicator(
    String profileId,
    String indicatorKey,
    IndicatorBinding binding,
  ) {
    _replace(
      profileId,
      (p) => p.withOverrides(
        addIndicatorKeys: [indicatorKey],
        indicatorBindingUpserts: {indicatorKey: binding},
      ),
    );
  }

  void removeIndicator(String profileId, String indicatorKey) {
    _replace(
      profileId,
      (p) => p.withOverrides(removeIndicatorKeys: [indicatorKey]),
    );
  }

  void setIndicatorBinding(
    String profileId,
    String indicatorKey,
    IndicatorBinding binding,
  ) {
    _replace(
      profileId,
      (p) => p.withOverrides(indicatorBindingUpserts: {indicatorKey: binding}),
    );
  }

  // --- Suggestions (§8) ------------------------------------------------------

  /// Sets/replaces the suggested indicators for [metricKey] — a prefill
  /// hint for the board editor (§8), never a restriction: the user can still
  /// pick any of `profile.indicatorKeys` regardless of what's suggested.
  void setSuggestedIndicators(
    String profileId,
    String metricKey,
    List<String> indicatorKeys,
  ) {
    _replace(
      profileId,
      (p) => p.withOverrides(
        suggestedIndicatorsUpserts: {metricKey: indicatorKeys},
      ),
    );
  }

  void _replace(
    String id,
    DeviceCapabilityProfile Function(DeviceCapabilityProfile current) update,
  ) {
    final index = _profiles.indexWhere((p) => p.id == id);
    if (index == -1) return;
    final next = [..._profiles];
    next[index] = update(next[index]);
    _profiles = next;
    notifyListeners();
  }
}

// The shared, pre-seeded `sharedDeviceCapabilityProfileStore` instance lives
// in `reference_capability_seeds.dart` — see that file's `_SeededCapabilities`
// for why it must be constructed together with the two library stores.
