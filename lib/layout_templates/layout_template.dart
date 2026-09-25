import 'layout_template_validator.dart';

/// Reusable external board geometry. [name] labels this geometry in a catalog;
/// it is never the title of a device card.
class LayoutTemplate {
  LayoutTemplate({
    required this.id,
    required this.name,
    required this.columns,
    required this.rows,
    this.schemaVersion = LayoutTemplateValidator.supportedSchemaVersion,
    this.templateVersion = 1,
    this.enabled = true,
    this.createdAt,
    this.updatedAt,
    this.internalUnitsPerCellX =
        LayoutTemplateValidator.defaultInternalUnitsPerCell,
    this.internalUnitsPerCellY =
        LayoutTemplateValidator.defaultInternalUnitsPerCell,
  }) {
    LayoutTemplateValidator.text(id, 'id');
    LayoutTemplateValidator.text(name, 'name');
    LayoutTemplateValidator.dimensions(columns, rows);
    if (schemaVersion != LayoutTemplateValidator.supportedSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Unsupported schema',
      );
    }
    if (templateVersion < 1) {
      throw ArgumentError.value(
        templateVersion,
        'templateVersion',
        'Must be positive',
      );
    }
    LayoutTemplateValidator.integerRange(
      internalUnitsPerCellX,
      'internalUnitsPerCellX',
      1,
      LayoutTemplateValidator.maxInternalUnitsPerCell,
    );
    LayoutTemplateValidator.integerRange(
      internalUnitsPerCellY,
      'internalUnitsPerCellY',
      1,
      LayoutTemplateValidator.maxInternalUnitsPerCell,
    );
  }

  /// Version and resolution are required on the wire: never reinterpret saved
  /// data using defaults from a newer release. Unknown extra fields are ignored.
  factory LayoutTemplate.fromMap(Map<String, Object?> map) {
    return LayoutTemplate(
      id: _string(map, 'id'),
      name: _string(map, 'name'),
      columns: _int(map, 'columns'),
      rows: _int(map, 'rows'),
      schemaVersion: _int(map, 'schemaVersion'),
      templateVersion: _int(map, 'templateVersion'),
      enabled: _bool(map, 'enabled'),
      internalUnitsPerCellX: _int(map, 'internalUnitsPerCellX'),
      internalUnitsPerCellY: _int(map, 'internalUnitsPerCellY'),
      createdAt: _date(map, 'createdAt'),
      updatedAt: _date(map, 'updatedAt'),
    );
  }

  final String id;
  final String name;
  final int columns;
  final int rows;
  final int schemaVersion;
  final int templateVersion;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int internalUnitsPerCellX;
  final int internalUnitsPerCellY;

  /// JSON-compatible UTC timestamps. A future Firestore adapter must convert
  /// SDK Timestamp values at the persistence boundary, outside this model.
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'columns': columns,
    'rows': rows,
    'schemaVersion': schemaVersion,
    'templateVersion': templateVersion,
    'enabled': enabled,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'internalUnitsPerCellX': internalUnitsPerCellX,
    'internalUnitsPerCellY': internalUnitsPerCellY,
  };
}

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String) return value;
  throw ArgumentError.value(value, key, 'Required string');
}

int _int(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is int) return value;
  throw ArgumentError.value(value, key, 'Required integer; no coercion');
}

bool _bool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is bool) return value;
  throw ArgumentError.value(value, key, 'Required boolean');
}

DateTime? _date(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    // Canonical UTC representation also rejects normalized invalid dates.
    if (parsed != null && parsed.isUtc && parsed.toIso8601String() == value) {
      return parsed;
    }
  }
  throw ArgumentError.value(
    value,
    key,
    'Expected canonical UTC ISO-8601 or DateTime',
  );
}
