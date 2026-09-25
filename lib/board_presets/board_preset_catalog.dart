import 'package:flutter/foundation.dart';
import '../board_content/board_content_layout.dart';
import '../board_content/reference_content_boards.dart';
import '../device_board_layouts/reference_board_layouts.dart';
import '../layout_templates/layout_template.dart';
import '../layout_templates/layout_template_catalog.dart';
import 'board_preset.dart';

/// Reconstructs a [LayoutTemplate] purely from its `grid_<cols>x<rows>` id
/// convention — every template in this codebase (catalog or fixture) follows
/// it. Lets a [BoardPreset] reference *any* geometry (including a fixture's,
/// like Arco's `grid_6x7`, or a dynamic one like `grid_8x4`) while staying a
/// plain string on disk, with a single resolution path (N6.2 §2/§15).
LayoutTemplate resolveLayoutTemplateId(String id) {
  for (final template in initialLayoutTemplateCatalog.templates) {
    if (template.id == id) return template;
  }
  final match = RegExp(r'^grid_(\d+)x(\d+)$').firstMatch(id);
  if (match != null) {
    final columns = int.parse(match.group(1)!);
    final rows = int.parse(match.group(2)!);
    return LayoutTemplate(
      id: id,
      name: '$columns × $rows',
      columns: columns,
      rows: rows,
    );
  }
  throw StateError('BoardPreset references unknown LayoutTemplate "$id"');
}

/// Builds a [LayoutTemplate] for an arbitrary column/row count, reusing a
/// catalog entry when one already matches so ids stay stable and shared
/// across presets (N6.2 §15 — "layout dinámico: soportar 6x4, 8x4, etc.").
LayoutTemplate buildLayoutTemplate(int columns, int rows) {
  final id = 'grid_${columns}x$rows';
  return resolveLayoutTemplateId(id);
}

/// Seed presets (N6.2 §8): the visual content of the three demo fixtures
/// (Sala/Laboratorio/Arco), migrated into standalone [BoardPreset]s that are
/// explicitly *not* those fixtures — no [PreviewBoardDataProvider], no demo
/// device name, no dependency on `preview_board_data.dart`. The fixtures
/// keep existing unchanged as "Casos demo" for the read-only/editor
/// playground (N6.2 §7); BoardPreset is the separate, Tenant/Site/Device-
/// agnostic concept N6.2 introduces. Migrating the *items* is a one-time
/// convenience so the catalog isn't empty on first use, not a coupling: a
/// [BoardPreset] here never reads from `preview_board_data.dart` again after
/// construction.
List<BoardPreset> _seedPresets() => [
  BoardPreset(
    id: 'preset-sala-clima-estandar',
    name: 'Sala clima estándar',
    description:
        'Temperatura/humedad interior y exterior, ventilación, presión '
        'diferencial, puertas, cerdas, NH3 y agua — geometría de referencia '
        'para una sala climatizada típica.',
    layoutTemplateId: roomContentExample.template.id,
    items: roomContentExample.board.items,
    // N6.5.2: corrected to the real metricKeys — `humInterior`/`presionDiferencial`/
    // `humExterior` were the *sourceFields*, not the metricKeys
    // (`humedadInterior`/`presion`/`humedadExterior`); harmless before this
    // pass since nothing validates `requiredMetricKeys`/`optionalMetricKeys`,
    // fixed while already touching this block.
    requiredMetricKeys: const ['tempInterior', 'humedadInterior'],
    optionalMetricKeys: const [
      'fan',
      'presion',
      'nh3',
      'tempExterior',
      'humedadExterior',
    ],
    // N6.5 §30/§25, renamed in N6.5.2 §17: the profile this preset's actual
    // content was extracted from (see reference_board_layouts.dart) —
    // matches the pre-N6.5 hardcoded fallback exactly, so this is a no-op
    // for this preset.
    capabilityProfileId: 'environment_room_v1',
  ),
  BoardPreset(
    id: 'preset-laboratorio-estandar',
    name: 'Laboratorio estándar',
    description: 'Temperatura y humedad de laboratorio, geometría mínima.',
    layoutTemplateId: referenceBoardLayouts[1].template.id,
    items: referenceBoardLayouts[1].board.items.map(
      BoardContentItem.fromLegacy,
    ),
    requiredMetricKeys: const ['tempInterior'],
    // N6.5.2: corrected `humInterior` (a sourceField) to the real metricKey.
    optionalMetricKeys: const ['humedadInterior'],
    // N6.5 §30: fixes a latent gap — before N6.5 this preset was always
    // opened against `environment_room_v1` (the old hardcoded fallback),
    // which happens to share the same metric *keys* but not the same
    // MetricDefinition instances (different label/unit/icon) as its actual
    // source profile, `laboratory_v1`.
    capabilityProfileId: 'laboratory_v1',
  ),
  BoardPreset(
    id: 'preset-arco-estandar',
    name: 'Arco estándar',
    description:
        'Imagen del dispositivo, contadores de desinfección, estado '
        'operativo, último evento y tabla de registros recientes.',
    layoutTemplateId: disinfectionContentExample.template.id,
    items: disinfectionContentExample.board.items,
    // N6.5.2: corrected to the real metricKeys (`disinfected`/`vehicles`/
    // `level` were never actual keys in any catalog/profile).
    requiredMetricKeys: const [
      'vehiclesDisinfectedDaily',
      'vehiclesTotalDaily',
      'disinfectantLevel',
    ],
    // N6.5 §30: fixes a real pre-N6.5 bug — `vehiclesDisinfectedDaily`/
    // `vehiclesTotalDaily`/`disinfectantLevel` never existed in the old
    // hardcoded fallback catalog (`environment_room_v1`) at all, so opening
    // this preset always produced three `metric_not_found` issues.
    capabilityProfileId: 'disinfection_arch_v1',
  ),
];

/// Single in-memory instance shared by the presets list page and any editor
/// route pushed from it, so a preset created/duplicated/edited in one visit
/// is still there when the user navigates back to the list — for the
/// lifetime of the app session only (N6.2 §8: "sin Firestore todavía").
final BoardPresetCatalog sharedBoardPresetCatalog = BoardPresetCatalog();

/// Local/in-memory catalog of [BoardPreset]s (N6.2 §8) — no Firestore, no
/// persistence across app restarts. A [ChangeNotifier] so the presets list
/// UI and any editor bound to a preset id can react to create/duplicate/
/// rename/content updates without a separate stream.
/// Sentinel distinguishing "not passed, leave as-is" from "explicitly clear
/// to null" for [BoardPresetCatalog.updateContent]'s optional
/// `capabilityProfileId` — a plain `null` default can't tell those apart.
const Object _unchanged = Object();

class BoardPresetCatalog extends ChangeNotifier {
  BoardPresetCatalog({List<BoardPreset>? initial})
    : _presets = List.of(initial ?? _seedPresets());

  List<BoardPreset> _presets;
  int _nextSeq = 0;

  List<BoardPreset> get presets => List.unmodifiable(_presets);

  BoardPreset? byId(String id) {
    for (final preset in _presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  String _freshId(String base) {
    final used = _presets.map((p) => p.id).toSet();
    var candidate = '$base-${_nextSeq++}';
    while (used.contains(candidate)) {
      candidate = '$base-${_nextSeq++}';
    }
    return candidate;
  }

  /// Creates an empty preset with the given [layout] (N6.2 §9). Always
  /// starts with `items: []` — content is added afterwards via the editor.
  ///
  /// [capabilityProfileId] defaults to `null` ("Sin perfil", N6.5.1 §1/§3,
  /// renamed in N6.5.2 §17/§18): before N6.5.1 this silently fell back to
  /// the reference environment catalog, so a preset could end up bound to a
  /// profile the user never picked. Callers that need a real profile (the
  /// UI creation dialog, or a test exercising profile-dependent behavior)
  /// now always pass it explicitly.
  BoardPreset create({
    required String name,
    String description = '',
    required LayoutTemplate layout,
    String? capabilityProfileId,
  }) {
    final preset = BoardPreset(
      id: _freshId('preset-new'),
      name: name,
      description: description,
      layoutTemplateId: layout.id,
      items: const [],
      capabilityProfileId: capabilityProfileId,
    );
    _presets = [..._presets, preset];
    notifyListeners();
    return preset;
  }

  /// Creates a structurally-independent copy under a new id (N6.2 §10):
  /// [BoardPreset.items] is already an unmodifiable *copy* of the original
  /// list (built in its constructor), so no later edit to either preset can
  /// ever reach into the other's item list or vice versa.
  BoardPreset duplicate(String id) {
    final original = byId(id);
    if (original == null) {
      throw ArgumentError('Unknown BoardPreset id "$id"');
    }
    final copy = original.copyWith(
      id: _freshId('${original.id}-copy'),
      name: '${original.name} (copia)',
      presetVersion: 1,
    );
    _presets = [..._presets, copy];
    notifyListeners();
    return copy;
  }

  /// Renames/redescribes a preset without touching its technical id (N6.2
  /// §10 — "No permitir cambiar ID técnico tras creación").
  void rename(String id, {String? name, String? description}) {
    _replace(
      id,
      (preset) => preset.copyWith(name: name, description: description),
    );
  }

  /// Live-commits the editor's current content back into the catalog entry
  /// (N6.2 §12 preset mode: editing *is* saving, in-memory, no separate
  /// publish step). Bumps [BoardPreset.presetVersion] so it is visible that
  /// the preset changed since creation/duplication.
  void updateContent(
    String id, {
    required LayoutTemplate layout,
    required Iterable<BoardContentItem> items,
    required bool showTitle,
    String? titleOverride,
    bool clearTitleOverride = false,
    Object? capabilityProfileId = _unchanged,
  }) {
    _replace(
      id,
      (preset) => preset.copyWith(
        layoutTemplateId: layout.id,
        items: items,
        showTitleDefault: showTitle,
        titleOverride: titleOverride,
        clearTitleOverride: clearTitleOverride,
        capabilityProfileId: identical(capabilityProfileId, _unchanged)
            ? preset.capabilityProfileId
            : capabilityProfileId as String?,
        clearCapabilityProfileId:
            !identical(capabilityProfileId, _unchanged) &&
            capabilityProfileId == null,
        presetVersion: preset.presetVersion + 1,
      ),
    );
  }

  void _replace(String id, BoardPreset Function(BoardPreset current) update) {
    final index = _presets.indexWhere((p) => p.id == id);
    if (index == -1) return;
    final next = [..._presets];
    next[index] = update(next[index]);
    _presets = next;
    notifyListeners();
  }
}
