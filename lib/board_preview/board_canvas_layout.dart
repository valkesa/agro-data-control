import 'package:flutter/material.dart';
import '../layout_templates/layout_template.dart';
import 'board_render_config.dart';

/// Single source of the board geometry approved in N5.2: fixed square
/// [BoardRenderConfig.baseCellSize], scale-down only, top-left anchored.
/// Both [BoardContentRenderer] (read-only preview) and the N6 editor canvas
/// build on this widget so neither can drift into a parallel geometry.
class BoardCanvasLayout extends StatelessWidget {
  const BoardCanvasLayout({
    super.key,
    required this.template,
    required this.renderConfig,
    required this.stackChildren,
    this.title,
    this.debugLabelBuilder,
    this.unboundedWidth,
  });

  final LayoutTemplate template;
  final BoardRenderConfig renderConfig;

  /// Builds the Stack children for the grid area given the resolved cell
  /// size in logical pixels (cw == ch, guaranteed square by construction).
  final List<Widget> Function(double cellWidth, double cellHeight)
  stackChildren;
  final Widget? title;

  /// Receives the scale actually resolved for the current constraints, so
  /// the debug text never reports a stale/guessed value.
  final String Function(double scale)? debugLabelBuilder;
  final Widget Function()? unboundedWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return unboundedWidth?.call() ??
              const SizedBox.shrink(key: ValueKey('board-unbounded'));
        }
        final scale = renderConfig.scaleFor(
          constraints.maxWidth,
          template.columns,
        );
        final cw = renderConfig.baseCellSize;
        final ch = cw;
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: renderConfig.naturalBoardWidth(template.columns) * scale,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: renderConfig.naturalBoardWidth(template.columns),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: title,
                      ),
                    if (debugLabelBuilder != null)
                      Text(
                        debugLabelBuilder!(scale),
                        key: const ValueKey('board-geometry'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.amber,
                        ),
                      ),
                    SizedBox(
                      key: const ValueKey('board-grid'),
                      height: ch * template.rows,
                      child: Stack(children: stackChildren(cw, ch)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PreviewGridPainter extends CustomPainter {
  const PreviewGridPainter(this.columns, this.rows);
  final int columns;
  final int rows;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x557DD3FC)
      ..strokeWidth = 0.7;
    for (var x = 0; x <= columns; x++) {
      canvas.drawLine(
        Offset(size.width * x / columns, 0),
        Offset(size.width * x / columns, size.height),
        paint,
      );
    }
    for (var y = 0; y <= rows; y++) {
      canvas.drawLine(
        Offset(0, size.height * y / rows),
        Offset(size.width, size.height * y / rows),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PreviewGridPainter old) =>
      columns != old.columns || rows != old.rows;
}
