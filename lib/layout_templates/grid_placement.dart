import 'layout_template.dart';
import 'layout_template_validator.dart';

/// Zero-based external cell span; contains no content or metric references.
class GridPlacement {
  GridPlacement({
    required this.x,
    required this.y,
    required this.widthCells,
    required this.heightCells,
  }) {
    LayoutTemplateValidator.integerRange(
      x,
      'x',
      0,
      LayoutTemplateValidator.maxAxisCells - 1,
    );
    LayoutTemplateValidator.integerRange(
      y,
      'y',
      0,
      LayoutTemplateValidator.maxAxisCells - 1,
    );
    LayoutTemplateValidator.dimensions(widthCells, heightCells);
  }

  final int x;
  final int y;
  final int widthCells;
  final int heightCells;

  bool fitsWithin(LayoutTemplate layout) =>
      x + widthCells <= layout.columns && y + heightCells <= layout.rows;

  void validateWithin(LayoutTemplate layout) {
    if (!fitsWithin(layout)) {
      throw ArgumentError('Placement exceeds layout ${layout.id} bounds');
    }
  }

  int internalColumns(LayoutTemplate layout) {
    validateWithin(layout);
    return widthCells * layout.internalUnitsPerCellX;
  }

  int internalRows(LayoutTemplate layout) {
    validateWithin(layout);
    return heightCells * layout.internalUnitsPerCellY;
  }
}
