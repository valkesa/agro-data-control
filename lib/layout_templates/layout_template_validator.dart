/// Technical guardrails, not product presets. Bounds keep accidental grids
/// from causing excessive allocation in future editors/renderers.
abstract final class LayoutTemplateValidator {
  static const int supportedSchemaVersion = 1;
  static const int defaultInternalUnitsPerCell = 8;
  static const int maxAxisCells = 1024;
  static const int maxTotalCells = 65536;
  static const int maxInternalUnitsPerCell = 1024;

  static void text(String value, String field) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, field, 'Must not be empty');
    }
  }

  static void integerRange(int value, String field, int min, int max) {
    if (value < min || value > max) {
      throw ArgumentError.value(value, field, 'Expected $min..$max');
    }
  }

  static void dimensions(int columns, int rows) {
    integerRange(columns, 'columns', 1, maxAxisCells);
    integerRange(rows, 'rows', 1, maxAxisCells);
    if (columns * rows > maxTotalCells) {
      throw ArgumentError(
        'Grid exceeds technical budget of $maxTotalCells cells',
      );
    }
  }

  static void uniqueIds(Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      text(id, 'id');
      if (!seen.add(id.trim())) {
        throw ArgumentError.value(id, 'id', 'Duplicate layout template ID');
      }
    }
  }
}
