import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../cell_layout_presets/cell_content_resolver.dart';
import '../cell_layout_presets/cell_layout_preset.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../ui_templates/board/template_data_resolver.dart';
import '../ui_templates/board/template_icon_resolver.dart';
import '../ui_templates/board/template_value_formatter.dart';
import '../ui_templates/models/metric_definition.dart';
import 'board_canvas_layout.dart';
import 'cell_editor_tokens.dart';
import 'board_render_config.dart';
import 'preview_board_data.dart';

/// Keep the natural semantic size. Only the enclosing Board may scale.
Widget cellClip(Widget child, {Alignment alignment = Alignment.center}) =>
    ClipRect(
      child: OverflowBox(
        alignment: alignment,
        minWidth: 0,
        maxWidth: double.infinity,
        minHeight: 0,
        maxHeight: double.infinity,
        child: child,
      ),
    );

/// The single geometry the internal subgrid of a [CellLayoutPreset] ever
/// uses — extracted from `MetricBoardRenderer` (N6.3 §15/§1: "no crear
/// preview falso", "no duplicar geometría respecto del renderer real").
/// Consumed both by the real board renderer (through [resolved], content
/// pre-resolved via [CellContentResolver]) and by the N6.3 visual cell
/// editor (through [rawElements], no metric/data context required — a mid-
/// edit draft can be invalid and must never crash).
///
/// Formula (unchanged from the pre-N6.3 inline version):
/// `unit = min(availableWidth / columns, availableHeight / rows)`, every
/// element's pixel rect is `placement.{x,y,widthUnits,heightUnits} * unit`.
/// Never pixels as a source of truth — always [InternalGridPlacement] units.
class CellLayoutCanvas extends StatelessWidget {
  const CellLayoutCanvas({
    super.key,
    required this.columns,
    required this.rows,
    this.resolved,
    this.rawElements,
    this.catalog,
    this.data,
    this.metric,
    this.itemIdForKeys = 'cell',
    this.showGrid = false,
    this.editorMode = false,
    this.labelOverride,
    this.unitOverride,
    this.selectedElementId,
    this.invalidElementIds = const {},
    this.onElementTap,
    this.onUnitResolved,
    this.underlayBuilder,
  }) : assert(
         (resolved != null) != (rawElements != null),
         'Provide exactly one of resolved (valid content) or rawElements '
         '(geometry-only, for an unresolvable/mid-edit draft).',
       ),
       assert(
         resolved == null ||
             (catalog != null && data != null && metric != null),
         'catalog/data/metric are required to render resolved content.',
       );

  final int columns;
  final int rows;

  /// Real content, pre-resolved by [CellContentResolver] — used by the
  /// production board renderer and by the cell editor whenever the current
  /// draft is valid.
  final List<ResolvedCellElement>? resolved;

  /// Geometry-only fallback (element id/type/placement/sizeRole/visibility,
  /// no text/icon/indicator content) — used by the cell editor when the
  /// draft currently has validation issues (out of bounds / collision) and
  /// [CellContentResolver.resolve] would throw. Still real geometry, never a
  /// fabricated layout.
  final List<CellLayoutElement>? rawElements;

  final DeviceMetricCatalog? catalog;
  final PreviewBoardDataProvider? data;
  final MetricDefinition? metric;
  final String itemIdForKeys;
  final bool showGrid;
  final bool editorMode;
  final String? labelOverride;
  final String? unitOverride;
  final String? selectedElementId;
  final Set<String> invalidElementIds;
  final void Function(String elementId)? onElementTap;

  /// Reports the resolved `unit` (pixels per internal grid unit) back to the
  /// caller once layout is known — lets an interactive editor convert a tap
  /// position into an [InternalGridPlacement] cell.
  final void Function(double unit)? onUnitResolved;

  /// Extra content rendered *below* every element (so an occupied cell's own
  /// element always wins hit-testing, same ordering `BoardEditorCanvas` uses
  /// for its cell-tap grid) — the N6.3 cell editor's "Mover con clic" grid.
  final Widget Function(double unit)? underlayBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, limits) {
        final unit = math.min(
          limits.maxWidth / columns,
          limits.maxHeight / rows,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onUnitResolved?.call(unit);
        });
        final elements = resolved != null
            ? resolved!.map((r) => r.element).toList()
            : rawElements!;
        return Center(
          child: SizedBox(
            key: ValueKey('$itemIdForKeys-internal-grid'),
            width: unit * columns,
            height: unit * rows,
            child: Stack(
              children: [
                if (underlayBuilder != null) underlayBuilder!(unit),
                for (var i = 0; i < elements.length; i++)
                  if (editorMode ||
                      elements[i].visibility == CellVisibility.visible)
                    Positioned(
                      key: ValueKey('$itemIdForKeys-element-${elements[i].id}'),
                      left: elements[i].placement.x * unit,
                      top: elements[i].placement.y * unit,
                      width: elements[i].placement.widthUnits * unit,
                      height: elements[i].placement.heightUnits * unit,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onElementTap == null
                            ? null
                            : () => onElementTap!(elements[i].id),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: !editorMode
                                  ? Colors.transparent
                                  : invalidElementIds.contains(elements[i].id)
                                  ? const Color(0xFFF87171)
                                  : elements[i].id == selectedElementId
                                  ? cellEditorElementBorderSelected
                                  : elements[i].visibility ==
                                        CellVisibility.hidden
                                  ? cellEditorElementBorderHidden
                                  : cellEditorElementBorder,
                              width:
                                  editorMode &&
                                      elements[i].id == selectedElementId
                                  ? 2
                                  : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Opacity(
                              opacity:
                                  elements[i].visibility ==
                                      CellVisibility.hidden
                                  ? 0.35
                                  : 1,
                              child: resolved != null
                                  ? _resolvedElement(resolved![i], unit)
                                  : _rawElement(elements[i], unit),
                            ),
                          ),
                        ),
                      ),
                    ),
                if (showGrid)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: PreviewGridPainter(columns, rows),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _resolvedElement(ResolvedCellElement part, double unit) {
    if (part.emptyIndicator) return const SizedBox.shrink();
    final e = part.element;
    final size = BoardRenderConfig.elementSize(e.sizeRole, unit);
    final alignment = _alignmentOf(e);
    if (e.type == CellElementType.icon) {
      return cellClip(
        Icon(
          resolveTemplateIcon(part.iconRef!),
          color: const Color(0xFF7DD3FC),
          size: size,
        ),
        alignment: alignment,
      );
    }
    if (e.type == CellElementType.indicator) {
      final indicator = catalog!.indicatorByKey(part.indicatorKey!)!;
      const resolver = TemplateDataResolver();
      final value = resolver.resolveSourceField(
        indicator.sourceField,
        data!.metricData,
      );
      final active = value == indicator.condition;
      return Tooltip(
        message: '${indicator.key}: ${active ? 'activo' : 'inactivo'}',
        child: cellClip(
          Icon(
            resolveTemplateIcon(indicator.icon),
            key: ValueKey('indicator-$itemIdForKeys-${e.indicatorSlot}'),
            color: active ? const Color(0xFFFBBF24) : const Color(0xFF64748B),
            size: size,
          ),
          alignment: alignment,
        ),
      );
    }
    const resolver = TemplateDataResolver();
    final raw = resolver.resolveMetric(metric!, data!.metricData);
    final text = e.type == CellElementType.value
        ? formatTemplateMetricValue(metric!, raw)
        : e.type == CellElementType.unit
        ? unitOverride ?? metric!.unit
        : labelOverride ?? part.text ?? '';
    return _textElement(e, text, size, alignment);
  }

  /// Same geometry/sizeRole/alignment as [_resolvedElement], but with
  /// placeholder content (type name, no metric/data dependency) — used when
  /// the draft cannot be safely resolved (N6.3 §9: "mostrar error visual, no
  /// crashear, permitir reparar").
  Widget _rawElement(CellLayoutElement e, double unit) {
    final size = BoardRenderConfig.elementSize(e.sizeRole, unit);
    final alignment = _alignmentOf(e);
    if (e.type == CellElementType.icon) {
      return cellClip(
        Icon(Icons.image_outlined, color: const Color(0xFF7DD3FC), size: size),
        alignment: alignment,
      );
    }
    if (e.type == CellElementType.indicator) {
      return cellClip(
        Icon(Icons.circle_outlined, color: const Color(0xFF64748B), size: size),
        alignment: alignment,
      );
    }
    final label = switch (e.type) {
      CellElementType.label => 'label',
      CellElementType.value => 'value',
      CellElementType.unit => 'unit',
      _ => e.type.name,
    };
    return _textElement(e, label, size, alignment);
  }

  Widget _textElement(
    CellLayoutElement e,
    String text,
    double size,
    Alignment alignment,
  ) {
    final weight = switch (e.textStyle?.weight) {
      CellFontWeight.bold => FontWeight.w800,
      CellFontWeight.medium => FontWeight.w500,
      _ => FontWeight.w400,
    };
    final textWidget = Text(
      text,
      // Preserved verbatim from the pre-N6.3 inline renderer: existing
      // widget tests key off 'metric-$itemId-$typeName' (not the element
      // id) for the real board-rendering path.
      key: ValueKey('metric-$itemIdForKeys-${e.type.name}'),
      maxLines: e.textStyle?.maxLines ?? 1,
      textAlign: switch (e.horizontalAlignment) {
        CellHorizontalAlignment.start => TextAlign.start,
        CellHorizontalAlignment.end => TextAlign.end,
        _ => TextAlign.center,
      },
      style: TextStyle(
        color: e.textStyle?.fontRole == CellFontRole.primaryValue
            ? const Color(0xFFE5E7EB)
            : const Color(0xFF94A3B8),
        fontSize: size,
        fontWeight: weight,
      ),
    );
    if ((e.textStyle?.maxLines ?? 1) == 1) {
      return cellClip(textWidget, alignment: alignment);
    }
    return LayoutBuilder(
      builder: (context, constraints) => cellClip(
        SizedBox(width: constraints.maxWidth, child: textWidget),
        alignment: alignment,
      ),
    );
  }

  static Alignment _alignmentOf(CellLayoutElement e) => Alignment(
    switch (e.horizontalAlignment) {
      CellHorizontalAlignment.start => -1,
      CellHorizontalAlignment.end => 1,
      _ => 0,
    },
    switch (e.verticalAlignment) {
      CellVerticalAlignment.top => -1,
      CellVerticalAlignment.bottom => 1,
      _ => 0,
    },
  );
}
