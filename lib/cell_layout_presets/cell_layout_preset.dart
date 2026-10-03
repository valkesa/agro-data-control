import '../device_board_layouts/board_parsing.dart';
import '../layout_templates/grid_placement.dart';
import '../layout_templates/layout_template.dart';

enum CellElementType { label, value, unit, icon, indicator }

enum CellHorizontalAlignment { start, center, end }

enum CellVerticalAlignment { top, center, bottom }

enum CellFontRole { label, primaryValue, unit, secondary }

enum CellVisibility { visible, hidden }

enum CellSizeRole { xs, sm, md, lg, xl, xxl, hero, fit }

enum CellFontWeight { normal, medium, bold }

T readCellEnum<T extends Enum>(Object? value, List<T> values, String field) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  BoardParsing.fail('unsupported_enum', 'Unsupported $field: $value');
}

class CellTextStyle {
  CellTextStyle({
    this.fontRole = CellFontRole.primaryValue,
    this.weight = CellFontWeight.normal,
    this.maxLines = 1,
  }) {
    if (maxLines < 1) {
      BoardParsing.fail('invalid_max_lines', 'maxLines must be positive');
    }
  }
  factory CellTextStyle.fromMap(Map<String, Object?> map) {
    BoardParsing.fields(map, {'fontRole', 'weight', 'maxLines'});
    return CellTextStyle(
      fontRole: readCellEnum(map['fontRole'], CellFontRole.values, 'fontRole'),
      weight: readCellEnum(map['weight'], CellFontWeight.values, 'weight'),
      maxLines: BoardParsing.integer(map['maxLines'], 'maxLines'),
    );
  }
  final CellFontRole fontRole;
  final CellFontWeight weight;
  final int maxLines;
  Map<String, Object?> toMap() => {
    'fontRole': fontRole.name,
    'weight': weight.name,
    'maxLines': maxLines,
  };
}

/// Internal units, not external cells or pixels. Bounds depend on N1 context.
class InternalGridPlacement {
  InternalGridPlacement({
    required this.x,
    required this.y,
    required this.widthUnits,
    required this.heightUnits,
  }) {
    if (x < 0 || y < 0 || widthUnits < 1 || heightUnits < 1) {
      BoardParsing.fail(
        'invalid_internal_placement',
        'Coordinates must be nonnegative and dimensions positive',
      );
    }
  }
  factory InternalGridPlacement.fromMap(Map<String, Object?> map) {
    BoardParsing.fields(map, {'x', 'y', 'widthUnits', 'heightUnits'});
    return InternalGridPlacement(
      x: BoardParsing.integer(map['x'], 'x'),
      y: BoardParsing.integer(map['y'], 'y'),
      widthUnits: BoardParsing.integer(map['widthUnits'], 'widthUnits'),
      heightUnits: BoardParsing.integer(map['heightUnits'], 'heightUnits'),
    );
  }
  final int x;
  final int y;
  final int widthUnits;
  final int heightUnits;
  bool fitsWithin(int columns, int rows) =>
      x + widthUnits <= columns && y + heightUnits <= rows;
  Map<String, Object?> toMap() => {
    'x': x,
    'y': y,
    'widthUnits': widthUnits,
    'heightUnits': heightUnits,
  };
}

/// Type itself is the semantic source reference; no metric/business IDs or
/// arbitrary sourceField strings are allowed. Indicators use ordinal slots.
class CellLayoutElement {
  CellLayoutElement({
    required this.id,
    required this.type,
    required this.placement,
    this.indicatorSlot,
    this.horizontalAlignment,
    this.verticalAlignment,
    this.textStyle,
    this.visibility = CellVisibility.visible,
    this.sizeRole = CellSizeRole.md,
  }) {
    BoardParsing.string(id, 'element id');
    if (type == CellElementType.indicator) {
      if (indicatorSlot == null || indicatorSlot! < 0) {
        BoardParsing.fail(
          'invalid_indicator_slot',
          'Indicator requires nonnegative slot',
        );
      }
    } else if (indicatorSlot != null) {
      BoardParsing.fail(
        'unexpected_indicator_slot',
        'Only indicators have slots',
      );
    }
    if (textStyle != null &&
        (type == CellElementType.icon || type == CellElementType.indicator)) {
      BoardParsing.fail(
        'invalid_text_style',
        'Text style applies only to text elements',
      );
    }
    if (sizeRole == CellSizeRole.fit && type != CellElementType.value) {
      BoardParsing.fail(
        'invalid_fit_target',
        'Fit size is currently supported only for value elements',
      );
    }
  }
  factory CellLayoutElement.fromMap(
    Map<String, Object?> map, {
    int schemaVersion = 2,
  }) {
    BoardParsing.fields(map, {
      'id',
      'type',
      'placement',
      'indicatorSlot',
      'horizontalAlignment',
      'verticalAlignment',
      'textStyle',
      if (schemaVersion == 2) 'visibility',
      if (schemaVersion == 2) 'sizeRole',
    });
    return CellLayoutElement(
      visibility: schemaVersion == 1
          ? CellVisibility.visible
          : readCellEnum(
              map['visibility'],
              CellVisibility.values,
              'visibility',
            ),
      sizeRole: schemaVersion == 1
          ? _legacySize(map)
          : readCellEnum(map['sizeRole'], CellSizeRole.values, 'sizeRole'),
      id: BoardParsing.string(map['id'], 'id'),
      type: readCellEnum(map['type'], CellElementType.values, 'type'),
      placement: InternalGridPlacement.fromMap(
        BoardParsing.map(map['placement'], 'placement'),
      ),
      indicatorSlot: map['indicatorSlot'] == null
          ? null
          : BoardParsing.integer(map['indicatorSlot'], 'indicatorSlot'),
      horizontalAlignment: map['horizontalAlignment'] == null
          ? null
          : readCellEnum(
              map['horizontalAlignment'],
              CellHorizontalAlignment.values,
              'horizontalAlignment',
            ),
      verticalAlignment: map['verticalAlignment'] == null
          ? null
          : readCellEnum(
              map['verticalAlignment'],
              CellVerticalAlignment.values,
              'verticalAlignment',
            ),
      textStyle: map['textStyle'] == null
          ? null
          : CellTextStyle.fromMap(
              BoardParsing.map(map['textStyle'], 'textStyle'),
            ),
    );
  }
  final String id;
  final CellElementType type;
  final InternalGridPlacement placement;
  final int? indicatorSlot;
  final CellHorizontalAlignment? horizontalAlignment;
  final CellVerticalAlignment? verticalAlignment;
  final CellTextStyle? textStyle;
  final CellVisibility visibility;
  final CellSizeRole sizeRole;

  // Schema 1 had implicit sizes. Upgrade explicitly without changing placements.
  static CellSizeRole _legacySize(Map<String, Object?> map) {
    if (map['type'] == 'icon') return CellSizeRole.lg;
    if (map['type'] == 'indicator') return CellSizeRole.md;
    final style = map['textStyle'];
    final role = style is Map ? style['fontRole'] : null;
    return switch (role) {
      'primaryValue' => CellSizeRole.xl,
      'label' => CellSizeRole.sm,
      'unit' => CellSizeRole.xs,
      _ => CellSizeRole.md,
    };
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.name,
    'placement': placement.toMap(),
    'indicatorSlot': indicatorSlot,
    'horizontalAlignment': horizontalAlignment?.name,
    'verticalAlignment': verticalAlignment?.name,
    'textStyle': textStyle?.toMap(),
    'visibility': visibility.name,
    'sizeRole': sizeRole.name,
  };
}

class CellLayoutPreset {
  CellLayoutPreset({
    required this.id,
    required this.name,
    required this.widthCells,
    required this.heightCells,
    this.schemaVersion = 2,
    this.presetVersion = 1,
    this.enabled = true,
    required Iterable<CellLayoutElement> elements,
    this.createdAt,
    this.updatedAt,
  }) : elements = List.unmodifiable(elements) {
    BoardParsing.string(id, 'id');
    BoardParsing.string(name, 'name');
    GridPlacement(x: 0, y: 0, widthCells: widthCells, heightCells: heightCells);
    if (schemaVersion != 2) {
      BoardParsing.fail(
        'unsupported_schema_version',
        'Unsupported cell preset schema',
      );
    }
    if (presetVersion < 1) {
      BoardParsing.fail(
        'invalid_preset_version',
        'presetVersion must be positive',
      );
    }
    final ids = <String>{};
    final slots = <int>{};
    for (final element in this.elements) {
      if (!ids.add(element.id)) {
        BoardParsing.fail(
          'duplicate_element_id',
          'Duplicate element ${element.id}',
        );
      }
      if (element.indicatorSlot != null && !slots.add(element.indicatorSlot!)) {
        BoardParsing.fail(
          'duplicate_indicator_slot',
          'Duplicate indicator slot',
        );
      }
    }
    // Continuous ordinal slots prevent a mere count from hiding mapping gaps.
    for (var index = 0; index < slots.length; index++) {
      if (!slots.contains(index)) {
        BoardParsing.fail(
          'noncontiguous_indicator_slots',
          'Slots must be continuous from zero',
        );
      }
    }
  }
  factory CellLayoutPreset.fromMap(Map<String, Object?> map) {
    BoardParsing.fields(map, {
      'id',
      'name',
      'widthCells',
      'heightCells',
      'schemaVersion',
      'presetVersion',
      'enabled',
      'elements',
      'createdAt',
      'updatedAt',
    });
    final sourceVersion = BoardParsing.integer(
      map['schemaVersion'],
      'schemaVersion',
    );
    if (sourceVersion != 1 && sourceVersion != 2) {
      BoardParsing.fail(
        'unsupported_schema_version',
        'Unsupported cell preset schema',
      );
    }
    return CellLayoutPreset(
      id: BoardParsing.string(map['id'], 'id'),
      name: BoardParsing.string(map['name'], 'name'),
      widthCells: BoardParsing.integer(map['widthCells'], 'widthCells'),
      heightCells: BoardParsing.integer(map['heightCells'], 'heightCells'),
      schemaVersion: 2,
      presetVersion: BoardParsing.integer(
        map['presetVersion'],
        'presetVersion',
      ),
      enabled: BoardParsing.boolean(map['enabled'], 'enabled'),
      elements: BoardParsing.list(map['elements'], 'elements').map(
        (e) => CellLayoutElement.fromMap(
          BoardParsing.map(e, 'element'),
          schemaVersion: sourceVersion,
        ),
      ),
      createdAt: BoardParsing.date(map['createdAt'], 'createdAt'),
      updatedAt: BoardParsing.date(map['updatedAt'], 'updatedAt'),
    );
  }
  final String id;
  final String name;
  final int widthCells;
  final int heightCells;
  final int schemaVersion;
  final int presetVersion;
  final bool enabled;
  final List<CellLayoutElement> elements;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  GridPlacement get _span => GridPlacement(
    x: 0,
    y: 0,
    widthCells: widthCells,
    heightCells: heightCells,
  );
  int internalColumns(LayoutTemplate template) =>
      _span.internalColumns(template);
  int internalRows(LayoutTemplate template) => _span.internalRows(template);
  int get indicatorSlotCount =>
      elements.where((e) => e.type == CellElementType.indicator).length;
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'widthCells': widthCells,
    'heightCells': heightCells,
    'schemaVersion': schemaVersion,
    'presetVersion': presetVersion,
    'enabled': enabled,
    'elements': elements.map((e) => e.toMap()).toList(),
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };
}
