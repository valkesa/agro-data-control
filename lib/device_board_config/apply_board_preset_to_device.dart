import '../board_content/board_content_config.dart';
import '../board_content/board_content_layout.dart';
import '../board_content/board_content_validator.dart';
import '../board_presets/board_preset.dart';
import '../board_presets/board_preset_catalog.dart'
    show resolveLayoutTemplateId;
import '../cell_layout_presets/cell_layout_catalog.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import '../device_capabilities/capability_library_store.dart';
import '../device_capabilities/device_capability_profile.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';

/// N7.1 §8/§11 — result of attempting to apply a [BoardPreset] to a Device.
/// Exactly one of [layout]/[issues] is meaningful: a non-null [layout] means
/// every check passed and it is safe to persist; a non-empty [issues] means
/// the apply was refused — "Nunca reparar/borrar silenciosamente" (§11), so
/// there is no partial/best-effort result to fall back to.
class BoardPresetApplicationResult {
  const BoardPresetApplicationResult.success(this.layout) : issues = const [];
  const BoardPresetApplicationResult.blocked(this.issues) : layout = null;

  final BoardContentLayout? layout;
  final List<LayoutValidationIssue> issues;
  bool get isBlocked => layout == null;
}

/// N7.1 §8/§9/§11 — the pure "Aplicar BoardPreset a Device" use case, kept
/// entirely Firestore-free (like `AgroSiteService`'s standalone payload
/// builders) so it is unit-testable without any repository/emulator:
///
/// 1. validar preset (structurally, via [BoardPreset] itself — already
///    guaranteed by its constructor);
/// 2. validar perfil (an explicit `null` [profile] is a valid "Sin perfil"
///    apply, exactly like the Board Editor already allows in preset mode —
///    it just means every metric/indicator the preset references is
///    reported missing, see step 3);
/// 3. validar métricas/indicators — resolves [profile] into a
///    [DeviceMetricCatalog] (or [emptyDeviceMetricCatalog] when `profile`
///    is `null`) and runs the *exact same* [BoardContentValidator] every
///    other board already goes through; any `metric_not_found`/
///    `indicator_not_available`/`indicator_not_found` issue blocks the
///    apply (§11 "faltan métricas/indicators → bloquear y mostrar issues");
/// 4. copiar BoardPreset → DeviceBoardLayout — [preset.items] are written
///    by *value* (their own `toMap()`/`fromMap()` round-trip, never a
///    pointer back to the preset document) into the returned
///    [BoardContentLayout], which is the actual deep-copy guarantee (§9):
///    nothing here is a live reference to the source [BoardPreset] or to
///    its Firestore document;
/// 5-7. persisting the result, the Device's `capabilityProfileId`, and the
///    trazability fields is [DeviceBoardConfigRepository.applyPreset]'s
///    job, one layer up — this function never touches Firestore.
///
/// N7.1.1 §3 — every [preset.items] entry referencing a [cellLayoutPresetId]
/// gets its composition resolved against [cellLayoutCatalog] *once, here*,
/// and snapshotted by value onto the returned item's
/// [MetricBoardContent.cellLayoutSnapshot] — never re-resolved live
/// afterwards. This supersedes N7.1's original "shared presentation, live
/// reference is fine" design (kept only as the historical rationale below):
/// an independent audit (`informe_etapa_n7_1_..._2026-09-19.html` §20.1,
/// finding A2) found real Devices whose rendering *did* change when a
/// global `CellLayoutPreset` was edited — the deep-copy guarantee N7.1
/// claimed never actually covered cell-level composition. [cellLayoutPresetId]
/// itself is kept on the item purely as trazability (§3: "puede conservarse
/// SOLO como trazabilidad"), never resolved live once a snapshot exists —
/// see `board_item_renderers.dart`/`board_content_validator.dart`.
List<BoardContentItem> materializeCellLayoutSnapshots(
  List<BoardContentItem> items,
  CellLayoutCatalog cellLayoutCatalog, {
  bool refreshExisting = false,
}) => [
  for (final item in items)
    if (item.content case final MetricBoardContent content
        when content.cellLayoutPresetId != null &&
            (refreshExisting || content.cellLayoutSnapshot == null))
      BoardContentItem(
        id: item.id,
        placement: item.placement,
        content: content.copyWith(
          cellLayoutSnapshot: cellLayoutCatalog.byId(
            content.cellLayoutPresetId!,
          ),
          sourceCellLayoutPresetVersion: cellLayoutCatalog
              .byId(content.cellLayoutPresetId!)
              ?.presetVersion,
        ),
      )
    else
      item,
];

BoardPresetApplicationResult applyBoardPresetToDevice({
  required String deviceId,
  required BoardPreset preset,
  required DeviceCapabilityProfile? profile,
  required MetricLibraryStore metricsLibrary,
  required IndicatorLibraryStore indicatorsLibrary,
  required CellLayoutCatalog cellLayoutCatalog,
  required int nextLayoutVersion,
  String? capabilityProfileId,
}) {
  final DeviceMetricCatalog catalog = profile == null
      ? emptyDeviceMetricCatalog
      : profile.resolve(metricsLibrary, indicatorsLibrary);

  final BoardContentLayout candidate = BoardContentLayout(
    deviceId: deviceId,
    layoutTemplateId: preset.layoutTemplateId,
    showTitle: preset.showTitleDefault,
    titleOverride: preset.titleOverride,
    layoutVersion: nextLayoutVersion,
    capabilityProfileId: capabilityProfileId,
    sourceBoardPresetId: preset.id,
    sourceBoardPresetVersion: preset.presetVersion,
    items: materializeCellLayoutSnapshots(
      preset.items,
      cellLayoutCatalog,
      refreshExisting: true,
    ),
  );

  final issues = missingCapabilityIssues(preset: preset, profile: profile);
  if (issues.isNotEmpty) {
    return BoardPresetApplicationResult.blocked(issues);
  }

  final structuralIssues = _validate(candidate, cellLayoutCatalog, catalog);
  if (structuralIssues.isNotEmpty) {
    return BoardPresetApplicationResult.blocked(structuralIssues);
  }

  return BoardPresetApplicationResult.success(candidate);
}

/// N7.1 §11 — "mismo perfil → OK; otro perfil compatible → validar keys":
/// every `metricKey`/`indicatorKey` the preset actually references (its
/// items' content, plus its declarative [BoardPreset.requiredMetricKeys])
/// must exist in [profile]. `null` profile ("Sin perfil") is reported as
/// every referenced key missing, matching how an unbound Board Editor
/// already treats "Sin perfil" (N6.5.2).
List<LayoutValidationIssue> missingCapabilityIssues({
  required BoardPreset preset,
  required DeviceCapabilityProfile? profile,
}) {
  final Set<String> availableMetrics = profile?.metricKeys.toSet() ?? const {};
  final Set<String> availableIndicators =
      profile?.indicatorKeys.toSet() ?? const {};

  final Set<String> requiredMetrics = {
    ...preset.requiredMetricKeys,
    for (final item in preset.items)
      if (item.content is MetricBoardContent)
        (item.content as MetricBoardContent).metricKey,
  };
  final Set<String> requiredIndicators = {
    for (final item in preset.items)
      if (item.content is MetricBoardContent)
        ...(item.content as MetricBoardContent).indicatorKeys,
  };

  final issues = <LayoutValidationIssue>[];
  for (final metricKey in requiredMetrics) {
    if (!availableMetrics.contains(metricKey)) {
      issues.add(
        LayoutValidationIssue(
          code: 'metric_not_found',
          message: 'El perfil no expone la métrica "$metricKey"',
          metricKey: metricKey,
        ),
      );
    }
  }
  for (final indicatorKey in requiredIndicators) {
    if (!availableIndicators.contains(indicatorKey)) {
      issues.add(
        LayoutValidationIssue(
          code: 'indicator_not_available',
          message: 'El perfil no expone el indicator "$indicatorKey"',
        ),
      );
    }
  }
  return issues;
}

List<LayoutValidationIssue> _validate(
  BoardContentLayout board,
  CellLayoutCatalog presets,
  DeviceMetricCatalog catalog,
) {
  final template = resolveLayoutTemplateId(board.layoutTemplateId);
  return BoardContentValidator.validate(board, template, catalog, presets);
}
