import '../board_content/board_content_config.dart';
import 'board_preset_catalog.dart';

/// One place a `metricKey`/`indicatorKey` is used from (N6.5 §24). Never a
/// full [BoardPreset] snapshot — the admin UI only needs enough to point the
/// user at the right preset/item, not to render it.
class MetricCatalogReference {
  const MetricCatalogReference({
    required this.presetId,
    required this.presetName,
    required this.itemId,
  });
  final String presetId;
  final String presetName;
  final String itemId;
}

/// Reusable reference-lookup utilities (N6.5 §24) over a [BoardPresetCatalog]
/// — deliberately not baked into [BoardPresetCatalog] itself, since only the
/// metric-catalog admin UI needs them. Read-only: never mutates a preset.
extension BoardPresetMetricReferences on BoardPresetCatalog {
  /// Every board item, across every preset, whose content is bound to
  /// [metricKey] — regardless of which `metricCatalogId` that preset
  /// currently uses (a metric can be referenced by key even after a preset
  /// switches to a catalog that no longer defines it; that mismatch is what
  /// produces the `metric_not_found` issue, not an absence of reference).
  List<MetricCatalogReference> findMetricReferences(String metricKey) {
    final refs = <MetricCatalogReference>[];
    for (final preset in presets) {
      for (final item in preset.items) {
        final content = item.content;
        if (content is MetricBoardContent && content.metricKey == metricKey) {
          refs.add(
            MetricCatalogReference(
              presetId: preset.id,
              presetName: preset.name,
              itemId: item.id,
            ),
          );
        }
      }
    }
    return refs;
  }

  /// Every board item whose selected `indicatorKeys` includes
  /// [indicatorKey] for [metricKey] specifically — an indicator is scoped to
  /// one metric (N6.5 §17), so a bare indicator key is not enough to find
  /// its references on its own.
  List<MetricCatalogReference> findIndicatorReferences(
    String metricKey,
    String indicatorKey,
  ) {
    final refs = <MetricCatalogReference>[];
    for (final preset in presets) {
      for (final item in preset.items) {
        final content = item.content;
        if (content is MetricBoardContent &&
            content.metricKey == metricKey &&
            content.indicatorKeys.contains(indicatorKey)) {
          refs.add(
            MetricCatalogReference(
              presetId: preset.id,
              presetName: preset.name,
              itemId: item.id,
            ),
          );
        }
      }
    }
    return refs;
  }

  /// Presets currently designed against [profileId] (N6.5 §1 / N6.5.2 §20 —
  /// "eliminar perfil si no está referenciado"). Renamed from N6.5's
  /// `findCatalogReferences` — same purpose, now over
  /// `BoardPreset.capabilityProfileId` instead of the retired
  /// `metricCatalogId`.
  List<MetricCatalogReference> findProfileReferences(String profileId) {
    final refs = <MetricCatalogReference>[];
    for (final preset in presets) {
      if (preset.capabilityProfileId == profileId) {
        refs.add(
          MetricCatalogReference(
            presetId: preset.id,
            presetName: preset.name,
            itemId: '',
          ),
        );
      }
    }
    return refs;
  }

  /// Every board item, across every preset, whose selected `indicatorKeys`
  /// includes [indicatorKey] — regardless of which metric it's attached to
  /// (N6.5.2 §20). Unlike [findIndicatorReferences], this is metric-agnostic
  /// on purpose: since N6.5.2 an indicator is no longer scoped to one fixed
  /// metric (§7/§9), so the global indicator library's delete-check needs
  /// "is this indicator used anywhere", not "is it used by this one metric".
  List<MetricCatalogReference> findIndicatorKeyReferences(String indicatorKey) {
    final refs = <MetricCatalogReference>[];
    for (final preset in presets) {
      for (final item in preset.items) {
        final content = item.content;
        if (content is MetricBoardContent &&
            content.indicatorKeys.contains(indicatorKey)) {
          refs.add(
            MetricCatalogReference(
              presetId: preset.id,
              presetName: preset.name,
              itemId: item.id,
            ),
          );
        }
      }
    }
    return refs;
  }
}
