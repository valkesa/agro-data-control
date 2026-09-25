import '../device_metric_catalogs/reference_metric_catalogs.dart';
import 'capability_indicator_definition.dart';
import 'capability_library_store.dart';
import 'capability_metric_definition.dart';
import 'device_capability_profile.dart';
import 'device_capability_profile_store.dart';
import 'indicator_binding.dart';
import 'metric_binding.dart';

/// N6.5.2 §16 — migrates the pre-N6.5.2 `referenceMetricCatalogs` (N6.5's 3
/// seed catalogs, `environment_room_v1`/`laboratory_v1`/`disinfection_arch_v1`,
/// still derived from the legacy `agro_ui_templates.dart` templates)
/// *programmatically* into the new global metric library / global indicator
/// library / capability profiles, instead of hand-transcribing every field —
/// guarantees the exact same labels/units/icons/sourceFields/transforms
/// survive the split (§16 "sin perder comportamiento").
///
/// A metric key repeated across catalogs (`tempInterior`, `humedadInterior`
/// — same key, same label/unit/icon/displayType/decimals in both
/// `environment_room_v1` and `laboratory_v1`) collapses into ONE global
/// [CapabilityMetricDefinition] the first time it's seen; later catalogs
/// reusing that key only add their own [MetricBinding] to their own
/// profile — never a duplicate global entry (§16's explicit acceptance
/// check). [metrics]/[indicators] are mutated in place (`upsert`); the
/// returned list is the 3 profiles ready to seed
/// [DeviceCapabilityProfileStore].
List<DeviceCapabilityProfile> seedCapabilityLibrariesAndProfiles({
  required MetricLibraryStore metrics,
  required IndicatorLibraryStore indicators,
}) {
  final profiles = <DeviceCapabilityProfile>[];
  for (final catalog in referenceMetricCatalogs) {
    var profile = DeviceCapabilityProfile(
      id: catalog.id,
      name: catalog.name,
      description: catalog.description,
      enabled: catalog.enabled,
    );
    for (final metric in catalog.metrics) {
      if (metrics.byKey(metric.key) == null) {
        metrics.upsert(
          CapabilityMetricDefinition(
            key: metric.key,
            label: metric.label,
            shortLabel: metric.shortLabel,
            defaultUnit: metric.unit,
            icon: metric.icon,
            displayType: metric.displayType,
            decimals: metric.decimals,
            statusBehavior: metric.statusBehavior,
          ),
        );
      }
      profile = profile.withOverrides(
        addMetricKeys: [metric.key],
        metricBindingUpserts: {
          metric.key: MetricBinding(
            sourceField: metric.sourceField,
            transform: metric.transform,
            valueLabelSourceField: metric.valueLabelSourceField,
          ),
        },
      );
    }
    for (final indicator in catalog.indicators) {
      if (indicators.byKey(indicator.key) == null) {
        indicators.upsert(
          CapabilityIndicatorDefinition(
            key: indicator.key,
            label: _referenceIndicatorLabel(indicator.key),
            defaultIcon: indicator.icon,
          ),
        );
      }
      profile = profile.withOverrides(
        addIndicatorKeys: [indicator.key],
        indicatorBindingUpserts: {
          indicator.key: IndicatorBinding(
            sourceField: indicator.sourceField,
            condition: indicator.condition,
          ),
        },
      );
    }
    if (catalog.availableIndicators.isNotEmpty) {
      // N6.5's `availableIndicators` was a hard per-metric restriction;
      // here it becomes exactly what it always conceptually was for these 3
      // reference profiles — an initial suggestion, never a restriction
      // (§8/§16 "sin perder comportamiento" refers to what's *offered*, and
      // §7/§9 already make the restriction disappear for every profile).
      profile = profile.withOverrides(
        suggestedIndicatorsUpserts: catalog.availableIndicators,
      );
    }
    profiles.add(profile);
  }
  return profiles;
}

/// `MetricIndicatorDefinition` never had a `label` (N6.5's admin UI showed
/// the bare key instead) — the 3 reference indicators get a real one here
/// since the global library now requires it (§2); anything outside this
/// fixed set falls back to the bare key rather than guessing a translation.
String _referenceIndicatorLabel(String key) =>
    const {
      'calefaccionEtapa1': 'Calefacción etapa 1',
      'calefaccionEtapa2': 'Calefacción etapa 2',
      'humidificacion': 'Humidificación',
    }[key] ??
    key;

/// Constructs the three shared stores together, in the only order that
/// guarantees none of them is ever observed empty-but-should-be-seeded: if
/// `sharedMetricLibraryStore`/`sharedIndicatorLibraryStore` were instead
/// plain top-level `final MetricLibraryStore sharedX = MetricLibraryStore();`
/// declarations, Dart's lazy top-level init means whichever one a caller
/// touches *first* — independent of `sharedDeviceCapabilityProfileStore` —
/// would come back empty until something else happened to seed it.
/// Wrapping all three in one eagerly-constructed holder removes that
/// access-order dependency entirely.
class _SeededCapabilities {
  _SeededCapabilities()
    : metrics = MetricLibraryStore(),
      indicators = IndicatorLibraryStore() {
    profiles = DeviceCapabilityProfileStore(
      initial: seedCapabilityLibrariesAndProfiles(
        metrics: metrics,
        indicators: indicators,
      ),
    );
  }

  final MetricLibraryStore metrics;
  final IndicatorLibraryStore indicators;
  late final DeviceCapabilityProfileStore profiles;
}

final _seeded = _SeededCapabilities();

/// Single in-memory instances shared by the admin page, the BoardPreset
/// Editor's profile selector, and any test/tool that needs them — same
/// session-lifetime contract as every other shared N6.x store, pre-seeded
/// with the migrated N6.5 reference data (§16).
final MetricLibraryStore sharedMetricLibraryStore = _seeded.metrics;
final IndicatorLibraryStore sharedIndicatorLibraryStore = _seeded.indicators;
final DeviceCapabilityProfileStore sharedDeviceCapabilityProfileStore =
    _seeded.profiles;

/// The `environment_room_v1` profile — used as the fallback for a
/// [BoardPreset.capabilityProfileId] that doesn't resolve to a known store
/// entry (an id typo, or a profile deleted after the preset referenced it),
/// mirroring `board_preset_catalog.dart`'s pre-N6.5.2 `referenceMetricCatalog`
/// fallback exactly.
DeviceCapabilityProfile get referenceCapabilityProfile =>
    sharedDeviceCapabilityProfileStore.byId('environment_room_v1')!;
