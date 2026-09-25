import '../device_board_layouts/board_parsing.dart';
import '../device_board_layouts/device_board_layout.dart';
import '../layout_templates/layout_template_validator.dart';
import 'cell_layout_preset.dart';

class CellLayoutCatalog {
  CellLayoutCatalog(
    Iterable<CellLayoutPreset> presets, {
    Map<String, String> defaults = const {},
  }) : presets = List.unmodifiable(presets),
       defaults = Map.unmodifiable(defaults) {
    final ids = <String>{};
    for (final preset in this.presets) {
      if (!ids.add(preset.id)) {
        BoardParsing.fail(
          'duplicate_preset_id',
          'Duplicate preset ${preset.id}',
        );
      }
    }
    for (final entry in this.defaults.entries) {
      final preset = byId(entry.value);
      if (preset == null ||
          '${preset.widthCells}x${preset.heightCells}' != entry.key ||
          !preset.enabled) {
        BoardParsing.fail(
          'invalid_default_preset',
          'Default must reference an enabled preset of matching span',
        );
      }
    }
  }
  final List<CellLayoutPreset> presets;
  final Map<String, String> defaults;
  CellLayoutPreset? byId(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  CellLayoutPreset? defaultForSpan(int width, int height) {
    final id = defaults['${width}x$height'];
    return id == null ? null : byId(id);
  }

  /// No fallback for an explicit unknown ID: a `cellLayoutPresetId` that was
  /// set and no longer resolves is a real error, never silently patched.
  /// `(default por span)` (`cellLayoutPresetId == null`), however, must
  /// resolve for *any* valid span (N6.3.1 §2) — a seeded [defaultForSpan]
  /// entry is preferred when one exists (kept curated/hand-tuned), and
  /// [resolveDefaultCellLayoutForSpan] is the generic fallback for every
  /// other span, so "default por span" can never produce
  /// `cell_preset_not_found`.
  CellLayoutPreset resolve(DeviceBoardLayoutItem item) {
    if (item.cellLayoutPresetId == null) {
      return defaultForSpan(
            item.placement.widthCells,
            item.placement.heightCells,
          ) ??
          resolveDefaultCellLayoutForSpan(
            item.placement.widthCells,
            item.placement.heightCells,
          );
    }
    final result = byId(item.cellLayoutPresetId!);
    if (result == null) {
      BoardParsing.fail(
        'cell_preset_not_found',
        'No preset configured for item ${item.id}',
      );
    }
    return result;
  }
}

/// Generic "default por span" resolution (N6.3.1 §2/§3): builds an
/// ephemeral, never-persisted [CellLayoutPreset] compatible with any valid
/// `widthCells`×`heightCells`, reusing the exact same element composition
/// the seed catalog itself is built from — no per-span hardcoded table, no
/// dependency on the metric being rendered. Never added to any catalog by
/// this function; turning it into a real, editable, catalog-backed preset
/// is a separate explicit action (N6.3.1 §5, "Crear diseño desde este
/// default").
CellLayoutPreset resolveDefaultCellLayoutForSpan(int width, int height) =>
    CellLayoutPreset(
      id: 'auto_default_${width}x$height',
      name: 'Default automático $width × $height',
      widthCells: width,
      heightCells: height,
      elements: buildDefaultCellLayoutElements(width, height),
    );

/// Same default composition the seed catalog below is built from — public
/// so "Crear diseño de celda" (N6.3 §22, "Crear desde default") reuses it
/// instead of duplicating the layout geometry.
List<CellLayoutElement> buildDefaultCellLayoutElements(
  int width,
  int height, {
  bool icon = false,
}) {
  final columns = width * LayoutTemplateValidator.defaultInternalUnitsPerCell;
  final rows = height * LayoutTemplateValidator.defaultInternalUnitsPerCell;
  final wide = width > 1 && height == 1;
  CellLayoutElement element(
    String id,
    CellElementType type,
    int x,
    int y,
    int w,
    int h, {
    int? slot,
    CellFontRole? role,
    CellSizeRole size = CellSizeRole.md,
  }) => CellLayoutElement(
    id: id,
    type: type,
    placement: InternalGridPlacement(x: x, y: y, widthUnits: w, heightUnits: h),
    indicatorSlot: slot,
    sizeRole: size,
    horizontalAlignment: CellHorizontalAlignment.center,
    verticalAlignment: CellVerticalAlignment.center,
    textStyle: role == null
        ? null
        : CellTextStyle(
            fontRole: role,
            weight: type == CellElementType.value
                ? CellFontWeight.bold
                : CellFontWeight.normal,
          ),
  );
  return [
    if (icon) element('icon', CellElementType.icon, 0, 0, 2, 2),
    element(
      'label',
      CellElementType.label,
      icon ? 2 : 0,
      0,
      columns - (icon ? 4 : 2),
      2,
      role: CellFontRole.label,
      size: width == 2 && height == 2 ? CellSizeRole.md : CellSizeRole.sm,
    ),
    element(
      'value',
      CellElementType.value,
      0,
      2,
      wide ? columns - 6 : columns - 2,
      wide ? rows - 2 : rows - 4,
      role: CellFontRole.primaryValue,
      size: width >= 2 ? CellSizeRole.xxl : CellSizeRole.xl,
    ),
    element(
      'unit',
      CellElementType.unit,
      wide ? columns - 6 : 0,
      wide ? 4 : rows - 2,
      wide ? 4 : columns - 2,
      2,
      role: CellFontRole.unit,
      size: CellSizeRole.sm,
    ),
    for (var slot = 0; slot < 3; slot++)
      element(
        'indicator-$slot',
        CellElementType.indicator,
        columns - 2,
        height == 2 ? 3 + slot * 3 : slot * 2,
        2,
        2,
        slot: slot,
      ),
  ];
}

CellLayoutPreset _preset(int width, int height, {bool icon = false}) =>
    CellLayoutPreset(
      id: '${icon ? 'icon_value' : 'default'}_${width}x$height',
      name:
          '${icon ? 'Icono y valor' : 'Valor e indicadores'} $width × $height',
      presetVersion: 2,
      widthCells: width,
      heightCells: height,
      elements: buildDefaultCellLayoutElements(width, height, icon: icon),
    );

final CellLayoutCatalog initialCellLayoutCatalog = CellLayoutCatalog(
  [
    for (final span in [(1, 1), (2, 1), (1, 2), (2, 2), (3, 1)])
      _preset(span.$1, span.$2),
    _preset(1, 1, icon: true),
    _preset(2, 1, icon: true),
  ],
  defaults: {
    for (final span in [(1, 1), (2, 1), (1, 2), (2, 2), (3, 1)])
      '${span.$1}x${span.$2}': 'default_${span.$1}x${span.$2}',
  },
);
