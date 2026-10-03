import 'package:flutter/material.dart';
import '../board_content/board_content_config.dart';
import '../board_content/board_content_layout.dart';
import '../board_content/board_content_validator.dart';
import '../cell_layout_presets/cell_layout_catalog.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../board_runtime/configurable_board_visual_state.dart';
import '../layout_templates/layout_template.dart';
import 'preview_board_data.dart';
import 'board_render_config.dart';
import 'board_canvas_layout.dart';
import 'board_preview_card.dart';
import 'board_item_renderers.dart';

export 'board_canvas_layout.dart' show PreviewGridPainter;

class PreviewDiagnostic extends StatelessWidget {
  const PreviewDiagnostic({super.key, required this.issues});
  final List<LayoutValidationIssue> issues;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('preview-diagnostic'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF351F28),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.orange),
    ),
    child: SingleChildScrollView(
      child: Text(
        issues
            .map(
              (i) =>
                  '${i.code}${i.itemId == null ? '' : ' · ${i.itemId}'}: ${i.message}',
            )
            .join('\n'),
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    ),
  );
}

class BoardContentRenderer extends StatelessWidget {
  const BoardContentRenderer({
    super.key,
    required this.board,
    required this.template,
    required this.catalog,
    required this.data,
    required this.deviceName,
    this.presets,
    this.showGrid = false,
    this.renderConfig = const BoardRenderConfig(),
  });
  final BoardContentLayout board;
  final LayoutTemplate template;
  final DeviceMetricCatalog catalog;
  final PreviewBoardDataProvider data;
  final String deviceName;
  final CellLayoutCatalog? presets;
  final bool showGrid;
  final BoardRenderConfig renderConfig;

  /// Safe boundary for future file/JSON previews, including unsupported types.
  static Widget fromMap({
    required Map<String, Object?> map,
    required LayoutTemplate template,
    required DeviceMetricCatalog catalog,
    required PreviewBoardDataProvider data,
    required String deviceName,
  }) {
    try {
      return BoardContentRenderer(
        board: BoardContentLayout.fromMap(map),
        template: template,
        catalog: catalog,
        data: data,
        deviceName: deviceName,
      );
    } on LayoutValidationException catch (e) {
      return PreviewDiagnostic(issues: e.issues);
    } on ArgumentError catch (e) {
      return PreviewDiagnostic(
        issues: [
          LayoutValidationIssue(
            code: 'invalid_content_config',
            message: e.message.toString(),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = presets ?? initialCellLayoutCatalog;
    var issues = BoardContentValidator.validate(
      board,
      template,
      catalog,
      registry,
    );
    if (!renderConfig.isValid) {
      issues = <LayoutValidationIssue>[
        ...issues,
        const LayoutValidationIssue(
          code: 'invalid_geometry',
          message: 'Base cell size must be finite and positive',
        ),
      ];
    }
    if (issues.isNotEmpty) return PreviewDiagnostic(issues: issues);
    final title = board.resolveTitle(deviceName);
    return BoardCanvasLayout(
      template: template,
      renderConfig: renderConfig,
      title: title == null
          ? null
          : Text(
              title,
              key: const ValueKey('board-title'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE5E7EB),
              ),
            ),
      debugLabelBuilder: showGrid
          ? (scale) =>
                'baseCellSize=${renderConfig.baseCellSize.toStringAsFixed(0)} · '
                'naturalBoardWidth=${renderConfig.naturalBoardWidth(template.columns).toStringAsFixed(0)} · '
                'scale=${scale.toStringAsFixed(3)}'
          : null,
      unboundedWidth: () => const PreviewDiagnostic(
        issues: [
          LayoutValidationIssue(
            code: 'invalid_geometry',
            message: 'Preview requires bounded width',
          ),
        ],
      ),
      stackChildren: (cw, ch) => [
        for (final item in board.items)
          Positioned(
            key: ValueKey('placement-${item.id}'),
            left: item.placement.x * cw,
            top: item.placement.y * ch,
            width: item.placement.widthCells * cw,
            height: item.placement.heightCells * ch,
            child: BoardPreviewCard(
              gap: renderConfig.cardGap,
              semanticBorderColor: _visualStateFor(item)?.borderColor,
              semanticBorderWidth: _visualStateFor(item)?.borderWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  boardRendererRegistry[item.type]!(
                    BoardItemRenderContext(
                      item: item,
                      template: template,
                      catalog: catalog,
                      presets: registry,
                      data: data,
                      showGrid: showGrid,
                    ),
                  ),
                  if (showGrid)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: IgnorePointer(
                        child: Container(
                          color: Colors.black87,
                          child: Text(
                            '${item.id} · ${item.placement.widthCells}×${item.placement.heightCells}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (showGrid)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PreviewGridPainter(template.columns, template.rows),
              ),
            ),
          ),
      ],
    );
  }

  ConfigurableBoardMetricVisualState? _visualStateFor(BoardContentItem item) {
    if (item.type != BoardContentType.metric) return null;
    final metric = catalog.metricByKey(item.toMetricItem().metricKey);
    if (metric == null) return null;
    return resolveConfigurableBoardMetricVisualState(
      metric: metric,
      deviceData: data.metricData,
      rangeSettings: data.rangeSettings,
    );
  }
}
