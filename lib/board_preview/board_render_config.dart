import 'dart:math' as math;
import '../cell_layout_presets/cell_layout_preset.dart';

/// Runtime design-system settings. Never serialized into board/preset documents.
class BoardRenderConfig {
  const BoardRenderConfig({this.baseCellSize = 68, this.cardGap = 2});
  final double baseCellSize;

  /// Single source for the inset between adjacent Cards (N6 §1). Previously
  /// a constant 3 inside BoardPreviewCard; chosen after comparing 3/2/1.
  final double cardGap;
  bool get isValid =>
      baseCellSize.isFinite &&
      baseCellSize > 0 &&
      cardGap.isFinite &&
      cardGap >= 0;
  double naturalBoardWidth(int columns) => columns * baseCellSize;
  double naturalBoardHeight(int rows) => rows * baseCellSize;
  double scaleFor(double availableWidth, int columns) =>
      math.min(1.0, math.max(0.0, availableWidth / naturalBoardWidth(columns)));

  static double elementSize(CellSizeRole role, double unit) =>
      unit *
      switch (role) {
        CellSizeRole.xs => 0.6,
        CellSizeRole.sm => 0.75,
        CellSizeRole.md => 1.0,
        CellSizeRole.lg => 1.5,
        CellSizeRole.xl => 2.0,
        CellSizeRole.xxl => 3.0,
        CellSizeRole.hero => 4.0,
      };
}
