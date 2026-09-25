import 'device_capability_profile_store.dart';

/// N6.5.2 §20 — one place a global metricKey/indicatorKey is referenced
/// FROM (a [DeviceCapabilityProfile], not a BoardPreset item — see
/// `board_preset_metric_references.dart` for the board-level references).
class CapabilityLibraryReference {
  const CapabilityLibraryReference({
    required this.profileId,
    required this.profileName,
  });
  final String profileId;
  final String profileName;
}

/// Reusable reference-lookup utilities (N6.5.2 §20) over a
/// [DeviceCapabilityProfileStore] — read-only, never mutates a profile.
/// Mirrors `BoardPresetMetricReferences` exactly, one layer up: those find
/// which BoardPreset items use a metric/indicator; these find which
/// profiles *offer* it.
extension DeviceCapabilityProfileReferences on DeviceCapabilityProfileStore {
  /// Every profile that references [metricKey] in `metricKeys` — used by
  /// the metric library admin to block deleting a metric still offered by a
  /// profile (§11 "eliminar si no está referenciada").
  List<CapabilityLibraryReference> findMetricKeyReferences(String metricKey) {
    final refs = <CapabilityLibraryReference>[];
    for (final profile in profiles) {
      if (profile.metricKeys.contains(metricKey)) {
        refs.add(
          CapabilityLibraryReference(
            profileId: profile.id,
            profileName: profile.name,
          ),
        );
      }
    }
    return refs;
  }

  /// Every profile that references [indicatorKey] in `indicatorKeys` — same
  /// purpose as [findMetricKeyReferences], for the indicator library (§12).
  List<CapabilityLibraryReference> findIndicatorKeyReferences(
    String indicatorKey,
  ) {
    final refs = <CapabilityLibraryReference>[];
    for (final profile in profiles) {
      if (profile.indicatorKeys.contains(indicatorKey)) {
        refs.add(
          CapabilityLibraryReference(
            profileId: profile.id,
            profileName: profile.name,
          ),
        );
      }
    }
    return refs;
  }
}
