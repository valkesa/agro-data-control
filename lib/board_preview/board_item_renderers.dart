import 'package:flutter/material.dart';
import '../board_content/board_content_config.dart';
import '../board_content/board_content_layout.dart';
import '../cell_layout_presets/cell_content_resolver.dart';
import '../cell_layout_presets/cell_layout_catalog.dart';
import '../cell_layout_presets/cell_layout_preset.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../layout_templates/layout_template.dart';
import '../board_runtime/configurable_board_visual_state.dart';
import '../ui_templates/board/template_icon_resolver.dart';
import 'board_content_renderer.dart';
import 'board_render_config.dart';
import 'cell_layout_canvas.dart';
import 'preview_board_data.dart';

class BoardItemRenderContext {
  const BoardItemRenderContext({
    required this.item,
    required this.template,
    required this.catalog,
    required this.presets,
    required this.data,
    this.showGrid = false,
  });
  final BoardContentItem item;
  final LayoutTemplate template;
  final DeviceMetricCatalog catalog;
  final CellLayoutCatalog presets;
  final PreviewBoardDataProvider data;
  final bool showGrid;
}

typedef BoardItemBuilder = Widget Function(BoardItemRenderContext);
final Map<BoardContentType, BoardItemBuilder> boardRendererRegistry =
    Map.unmodifiable({
      BoardContentType.metric: (c) => MetricBoardRenderer(c),
      BoardContentType.image: (c) => ImageBoardRenderer(c),
      BoardContentType.latestEvent: (c) => LatestEventBoardRenderer(c),
      BoardContentType.dataTable: (c) => DataTableBoardRenderer(c),
      BoardContentType.status: (c) => StatusBoardRenderer(c),
      BoardContentType.text: (c) => TextBoardRenderer(c),
      BoardContentType.chart: (c) => ChartBoardRenderer(c),
      BoardContentType.icon: (c) => IconBoardRenderer(c),
      BoardContentType.placeholder: (c) => PlaceholderBoardRenderer(c),
    });
Widget _missing(BoardItemRenderContext c) => PreviewDiagnostic(
  issues: [
    LayoutValidationIssue(
      code: 'data_source_missing',
      message: 'Fuente local ausente o con formato incompatible',
      itemId: c.item.id,
    ),
  ],
);
Widget _fit(Widget child, {Alignment alignment = Alignment.center}) =>
    FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);

/// N6.4 §8/§14: for an intentionally-unbound item, `_missing()`'s red
/// diagnostic would read as an error when nothing is actually broken — this
/// is a calmer, neutral "not linked yet" indicator instead.
Widget _unbound(String message) => Center(
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: _fit(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off, color: Color(0xFF64748B), size: 22),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  ),
);

Alignment _cellAlignmentOf(
  CellHorizontalAlignment h,
  CellVerticalAlignment v,
) => Alignment(
  switch (h) {
    CellHorizontalAlignment.start => -1,
    CellHorizontalAlignment.end => 1,
    CellHorizontalAlignment.center => 0,
  },
  switch (v) {
    CellVerticalAlignment.top => -1,
    CellVerticalAlignment.bottom => 1,
    CellVerticalAlignment.center => 0,
  },
);

Color _placeholderStyleColor(BoardPlaceholderStyle style) => switch (style) {
  BoardPlaceholderStyle.neutral => const Color(0xFF94A3B8),
  BoardPlaceholderStyle.info => const Color(0xFF7DD3FC),
  BoardPlaceholderStyle.success => const Color(0xFF34D399),
  BoardPlaceholderStyle.warning => const Color(0xFFFBBF24),
};

/// N6.4 §4: an icon as its own board item — no `MetricDefinition`, no data
/// dependency at all.
class IconBoardRenderer extends StatelessWidget {
  const IconBoardRenderer(this.c, {super.key});
  final BoardItemRenderContext c;
  @override
  Widget build(BuildContext context) {
    final config = c.item.content as IconBoardContent;
    // Fills the item's own box, then relies on `_fit`'s scale-down so a
    // `hero` icon never overflows a small span — same mechanism
    // `CellLayoutCanvas` already uses for cell-internal icons (N6.3.2 §4).
    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = constraints.biggest.shortestSide;
        final size = BoardRenderConfig.elementSize(config.sizeRole, unit);
        return Padding(
          padding: const EdgeInsets.all(8),
          child: _fit(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  resolveTemplateIcon(config.iconKey),
                  color: const Color(0xFF7DD3FC),
                  size: size,
                ),
                if (config.label != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    config.label!,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            alignment: _cellAlignmentOf(
              config.horizontalAlignment,
              config.verticalAlignment,
            ),
          ),
        );
      },
    );
  }
}

/// N6.4 §5/§6/§17: a design stub — label/mockValue/unit/icon, no
/// `CellLayoutPreset` composition (see the class doc on
/// [PlaceholderBoardContent] for why not), just a small fixed layout that
/// reads as "not real data" at a glance (§11).
class PlaceholderBoardRenderer extends StatelessWidget {
  const PlaceholderBoardRenderer(this.c, {super.key});
  final BoardItemRenderContext c;
  @override
  Widget build(BuildContext context) {
    final config = c.item.content as PlaceholderBoardContent;
    final color = _placeholderStyleColor(config.style);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: _fit(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (config.iconKey != null) ...[
              Icon(
                resolveTemplateIcon(config.iconKey!),
                color: color,
                size: 22,
              ),
              const SizedBox(height: 4),
            ],
            Text(
              config.label,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  config.mockValue ?? '--',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                  ),
                ),
                if (config.unit != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    config.unit!,
                    style: TextStyle(color: color, fontSize: 13),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MetricBoardRenderer extends StatelessWidget {
  const MetricBoardRenderer(this.c, {super.key});
  final BoardItemRenderContext c;
  @override
  Widget build(BuildContext context) {
    final item = c.item.toMetricItem();
    final metric = c.catalog.metricByKey(item.metricKey)!;
    // N6.3.1 (B1/B2): resolving a preset or its content can fail for
    // reasons entirely outside this widget's control — an explicit preset
    // id that no longer exists, a span mismatch, colliding internal
    // elements. None of that should ever crash the board being previewed;
    // it should read the same as any other unresolved content (compare
    // `_missing()` above for images) instead of taking down the whole
    // render tree.
    try {
      // N7.1.1 §3 — a snapshot on the item itself (independent of the
      // global catalog) always wins over a live lookup; only an item saved
      // before this stage (no snapshot yet) falls back to resolving
      // `cellLayoutPresetId` against the current global catalog.
      final snapshot =
          (c.item.content as MetricBoardContent).cellLayoutSnapshot;
      final preset = snapshot ?? c.presets.resolve(item);
      final resolved = CellContentResolver.resolve(
        metric,
        item,
        preset,
        template: c.template,
      );
      final visualState = resolveConfigurableBoardMetricVisualState(
        metric: metric,
        deviceData: c.data.metricData,
        rangeSettings: c.data.rangeSettings,
      );
      return CellLayoutCanvas(
        columns: preset.internalColumns(c.template),
        rows: preset.internalRows(c.template),
        resolved: resolved,
        catalog: c.catalog,
        data: c.data,
        metric: metric,
        itemIdForKeys: item.id,
        labelOverride: (c.item.content as MetricBoardContent).labelOverride,
        unitOverride: (c.item.content as MetricBoardContent).unitOverride,
        showGrid: c.showGrid,
        visualState: visualState,
      );
    } on LayoutValidationException catch (error) {
      return PreviewDiagnostic(
        issues: [
          for (final issue in error.issues)
            LayoutValidationIssue(
              code: issue.code,
              message: issue.message,
              itemId: item.id,
            ),
        ],
      );
    }
  }
}

class ImageBoardRenderer extends StatelessWidget {
  const ImageBoardRenderer(this.c, {super.key});
  final BoardItemRenderContext c;
  @override
  Widget build(BuildContext context) {
    final config = c.item.content as ImageBoardContent;
    final fit = switch (config.fit) {
      BoardImageFit.contain => BoxFit.contain,
      BoardImageFit.cover => BoxFit.cover,
      BoardImageFit.fill => BoxFit.fill,
    };
    // Even URL configs are resolved only through this local provider in preview.
    final image = c.data.media[config.sourceRef];
    if (image != null) {
      return Image(
        image: image,
        fit: fit,
        semanticLabel: config.altText,
        errorBuilder: (context, error, stack) => _missing(c),
      );
    }
    return Semantics(
      label: config.altText ?? 'Imagen de preview',
      child: Container(
        color: const Color(0xFF172B43),
        child: FittedBox(
          fit: fit,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.image_outlined,
                  size: 100,
                  color: Color(0xFF7DD3FC),
                ),
                Text(
                  config.altText ?? 'Imagen',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 12),
                const Text(
                  'PREVIEW · imagen de referencia',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatField(Object? value, BoardFieldFormat format) {
  if (value == null) return 'Sin datos';
  if (format == BoardFieldFormat.dateTime && value is DateTime) {
    String n(int v) => v.toString().padLeft(2, '0');
    return '${n(value.day)}/${n(value.month)} ${n(value.hour)}:${n(value.minute)}';
  }
  if (format == BoardFieldFormat.boolean && value is bool) {
    return value ? 'Sí' : 'No';
  }
  return value.toString();
}

class LatestEventBoardRenderer extends StatelessWidget {
  const LatestEventBoardRenderer(this.c, {super.key});
  final BoardItemRenderContext c;
  @override
  Widget build(BuildContext context) {
    final config = c.item.content as LatestEventBoardContent;
    // N6.4 §14: bound resolves exactly as before N6.4 (unchanged behavior/
    // tests); unbound/demo never touch `c.data.sources` at all — the design
    // is previewable purely from `demoValues` (empty for unbound, which
    // `_formatField` already renders as "Sin datos" per field).
    final Map<String, Object?> value;
    if (config.eventSourceId != null) {
      final bound = c.data.sources[config.eventSourceId];
      if (bound is! Map<String, Object?>) return _missing(c);
      value = bound;
    } else {
      value = config.demoValues ?? const {};
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (final field in config.fields)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: _fit(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (field.icon != null)
                        Icon(resolveTemplateIcon(field.icon!), size: 16),
                      Text(
                        field.label,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatField(value[field.key], field.format),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DataTableBoardRenderer extends StatelessWidget {
  const DataTableBoardRenderer(this.c, {super.key});
  final BoardItemRenderContext c;
  @override
  Widget build(BuildContext context) {
    final config = c.item.content as DataTableBoardContent;
    // N6.4 §14: same bound/unbound-or-demo split as latestEvent above.
    final List<Object?> rows;
    if (config.dataSourceId != null) {
      final bound = c.data.sources[config.dataSourceId];
      if (bound is! List || bound.any((r) => r is! Map<String, Object?>)) {
        return _missing(c);
      }
      rows = bound;
    } else {
      rows = config.demoRows ?? const [];
    }
    Widget row(Map<String, Object?>? data) => SizedBox(
      height: 30,
      child: Row(
        children: [
          for (final col in config.columns)
            Expanded(
              flex: col.flex,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _fit(
                  Text(
                    data == null
                        ? col.field.label
                        : _formatField(data[col.field.key], col.field.format),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      color: data == null
                          ? const Color(0xFF7DD3FC)
                          : const Color(0xFFE5E7EB),
                      fontWeight: data == null
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          if (config.showHeader) row(null),
          for (final data in rows.take(config.maxRows))
            row(data as Map<String, Object?>),
          if (rows.isEmpty) const Text('Sin registros'),
        ],
      ),
    );
  }
}

class StatusBoardRenderer extends StatelessWidget {
  const StatusBoardRenderer(this.c, {super.key});
  final BoardItemRenderContext c;
  static Color severityColor(PreviewSeverity severity) => switch (severity) {
    PreviewSeverity.ok => const Color(0xFF34D399),
    PreviewSeverity.warning => const Color(0xFFFBBF24),
    PreviewSeverity.critical => const Color(0xFFF87171),
    PreviewSeverity.neutral => const Color(0xFF94A3B8),
  };
  @override
  Widget build(BuildContext context) {
    final config = c.item.content as StatusBoardContent;
    if (config.dataSourceId == null) {
      // N6.4 §14: demo shows the configured preview label in a neutral
      // color (severity is a real-data concept, never fabricated here);
      // unbound shows the calm "not linked yet" indicator, never the red
      // `_missing()` diagnostic reserved for a genuinely broken bound item.
      if (config.demoLabel == null) {
        return _unbound('Sin vincular');
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: _fit(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, size: 12, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Text(
                config.demoLabel!,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final value = c.data.sources[config.dataSourceId];
    if (value is! PreviewStatus) return _missing(c);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: _fit(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 12, color: severityColor(value.severity)),
            const SizedBox(width: 8),
            Text(
              value.label,
              style: TextStyle(
                color: severityColor(value.severity),
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TextBoardRenderer extends StatelessWidget {
  const TextBoardRenderer(this.c, {super.key});
  final BoardItemRenderContext c;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: Text(
      (c.item.content as TextBoardContent).text,
      style: const TextStyle(color: Color(0xFFE5E7EB)),
    ),
  );
}

class ChartBoardRenderer extends StatelessWidget {
  const ChartBoardRenderer(this.c, {super.key});
  final BoardItemRenderContext c;
  @override
  Widget build(BuildContext context) {
    final config = c.item.content as ChartBoardContent;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: _fit(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.show_chart, color: Color(0xFF7DD3FC), size: 32),
            Text(
              'Gráfico ${config.chartType.name} · preview',
              style: const TextStyle(color: Colors.white),
            ),
            Text(
              config.series.map((s) => s.label).join(' · '),
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
            const Text(
              'Visualización pendiente',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
