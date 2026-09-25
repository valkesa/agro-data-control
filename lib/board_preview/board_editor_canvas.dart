import 'package:flutter/material.dart';
import '../cell_layout_presets/cell_layout_catalog.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import 'board_canvas_layout.dart';
import 'board_content_renderer.dart';
import 'board_editor_controller.dart';
import 'board_item_renderers.dart';
import 'board_preview_card.dart';
import 'board_render_config.dart';
import 'preview_board_data.dart';

/// A pending placement, shown as a translucent ghost before the user
/// confirms adding a new item. Purely a UI affordance; never persisted.
class PendingPlacement {
  const PendingPlacement({
    required this.x,
    required this.y,
    required this.widthCells,
    required this.heightCells,
  });
  final int x;
  final int y;
  final int widthCells;
  final int heightCells;
}

/// Interactive board canvas for N6. Built entirely on [BoardCanvasLayout],
/// the same geometry [BoardContentRenderer] uses for the read-only preview
/// — no parallel geometry, no pixel-based movement, only grid coordinates.
class BoardEditorCanvas extends StatelessWidget {
  const BoardEditorCanvas({
    super.key,
    required this.controller,
    required this.renderConfig,
    required this.presets,
    required this.data,
    required this.deviceName,
    this.issues = const [],
    this.pending,
    this.onCellTap,
  });

  final BoardEditorController controller;
  final BoardRenderConfig renderConfig;
  final CellLayoutCatalog presets;
  final PreviewBoardDataProvider data;
  final String deviceName;
  final List<LayoutValidationIssue> issues;
  final PendingPlacement? pending;
  final void Function(int x, int y)? onCellTap;

  @override
  Widget build(BuildContext context) {
    final template = controller.template;
    final catalog = controller.catalog;
    final board = controller.board;
    final showHelpers = controller.editMode;
    final title = board.resolveTitle(deviceName);
    final invalidIds = <String>{
      for (final issue in issues) ...[
        if (issue.itemId != null) issue.itemId!,
        if (issue.relatedItemId != null) issue.relatedItemId!,
      ],
    };
    return BoardCanvasLayout(
      template: template,
      renderConfig: renderConfig,
      title: title == null
          ? null
          : Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE5E7EB),
              ),
            ),
      debugLabelBuilder: showHelpers
          ? (scale) =>
                'baseCellSize=${renderConfig.baseCellSize.toStringAsFixed(0)} · '
                'columns=${template.columns} × rows=${template.rows} · '
                'scale=${scale.toStringAsFixed(3)}'
          : null,
      stackChildren: (cw, ch) => [
        if (onCellTap != null && showHelpers)
          Positioned.fill(
            child: _CellTapGrid(
              columns: template.columns,
              rows: template.rows,
              cellWidth: cw,
              cellHeight: ch,
              onTap: onCellTap!,
            ),
          ),
        for (final item in board.items)
          Positioned(
            key: ValueKey('edit-placement-${item.id}'),
            left: item.placement.x * cw,
            top: item.placement.y * ch,
            width: item.placement.widthCells * cw,
            height: item.placement.heightCells * ch,
            child: BoardPreviewCard(
              gap: renderConfig.cardGap,
              selected: showHelpers && item.id == controller.selectedItemId,
              invalid: showHelpers && invalidIds.contains(item.id),
              onTap: () => controller.selectItem(item.id),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Content renderers (metric in particular) assume a
                  // validated board and throw on incompatible geometry —
                  // correct for the read-only preview, but the editor must
                  // keep the card selectable/movable while mid-edit instead
                  // of crashing. The real issue text lives in the panel.
                  if (invalidIds.contains(item.id))
                    const _InvalidItemPlaceholder()
                  else
                    boardRendererRegistry[item.type]!(
                      BoardItemRenderContext(
                        item: item,
                        template: template,
                        catalog: catalog,
                        presets: presets,
                        data: data,
                        showGrid: false,
                      ),
                    ),
                  if (showHelpers)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: IgnorePointer(
                        child: Container(
                          color: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
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
        if (pending != null)
          Positioned(
            key: const ValueKey('pending-placement'),
            left: pending!.x * cw,
            top: pending!.y * ch,
            width: pending!.widthCells * cw,
            height: pending!.heightCells * ch,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x5563D3FA),
                  border: Border.all(color: const Color(0xFF63D3FA), width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        if (showHelpers)
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
}

class _InvalidItemPlaceholder extends StatelessWidget {
  const _InvalidItemPlaceholder();
  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(Icons.error_outline, color: Color(0xFFF87171), size: 20),
  );
}

class _CellTapGrid extends StatelessWidget {
  const _CellTapGrid({
    required this.columns,
    required this.rows,
    required this.cellWidth,
    required this.cellHeight,
    required this.onTap,
  });
  final int columns;
  final int rows;
  final double cellWidth;
  final double cellHeight;
  final void Function(int x, int y) onTap;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (var y = 0; y < rows; y++)
        for (var x = 0; x < columns; x++)
          Positioned(
            key: ValueKey('cell-tap-$x-$y'),
            left: x * cellWidth,
            top: y * cellHeight,
            width: cellWidth,
            height: cellHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(x, y),
            ),
          ),
    ],
  );
}
