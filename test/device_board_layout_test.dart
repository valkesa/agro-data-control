import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/device_board_layouts/device_board_layout.dart';
import 'package:agro_data_control/device_board_layouts/device_board_layout_validator.dart';
import 'package:agro_data_control/device_board_layouts/layout_validation_issue.dart';
import 'package:agro_data_control/device_board_layouts/reference_board_layouts.dart';
import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';
import 'package:agro_data_control/device_metric_catalogs/reference_metric_catalogs.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';

DeviceBoardLayoutItem item({
  String id = 'main',
  String metric = 'tempInterior',
  int x = 0,
  int y = 0,
  int w = 1,
  int h = 1,
  List<String> indicators = const [],
  String? preset,
}) => DeviceBoardLayoutItem(
  id: id,
  metricKey: metric,
  placement: GridPlacement(x: x, y: y, widthCells: w, heightCells: h),
  indicatorKeys: indicators,
  cellLayoutPresetId: preset,
);
DeviceBoardLayout board({
  List<DeviceBoardLayoutItem>? items,
  String template = 'grid_6x4',
  bool showTitle = true,
  String? title,
  int schema = 1,
  int version = 1,
}) => DeviceBoardLayout(
  deviceId: 'example',
  layoutTemplateId: template,
  items: items ?? [item()],
  showTitle: showTitle,
  titleOverride: title,
  schemaVersion: schema,
  layoutVersion: version,
);
LayoutTemplate grid({int columns = 6, int rows = 4, bool enabled = true}) =>
    LayoutTemplate(
      id: 'grid_${columns}x$rows',
      name: 'Grid',
      columns: columns,
      rows: rows,
      enabled: enabled,
    );
DeviceMetricCatalog get catalog =>
    referenceMetricCatalogById('environment_room_v1')!;
List<LayoutValidationIssue> validate(
  DeviceBoardLayout value, {
  LayoutTemplate? template,
  DeviceMetricCatalog? metrics,
}) => DeviceBoardLayoutValidator.validate(
  value,
  template ?? grid(),
  metrics ?? catalog,
);
Matcher issueException(String code) => isA<LayoutValidationException>().having(
  (e) => e.issues.single.code,
  'code',
  code,
);

void main() {
  test('valid layout and structured issues are immutable', () {
    expect(validate(board()), isEmpty);
    final issues = validate(board(items: [item(metric: 'missing')]));
    expect(issues.single.code, 'metric_not_found');
    expect(issues.single.itemId, 'main');
    expect(issues.single.metricKey, 'missing');
    expect(issues.single.message, isNotEmpty);
    expect(() => issues.clear(), throwsUnsupportedError);
  });
  test('list snapshots are deeply immutable', () {
    final keys = ['calefaccionEtapa1'];
    final cells = [item(indicators: keys)];
    final value = board(items: cells);
    keys.clear();
    cells.clear();
    expect(value.items, hasLength(1));
    expect(value.items.single.indicatorKeys, ['calefaccionEtapa1']);
    expect(() => value.items.clear(), throwsUnsupportedError);
    expect(
      () => value.items.single.indicatorKeys.clear(),
      throwsUnsupportedError,
    );
    final map = value.toMap();
    (((map['items'] as List).single as Map)['indicatorKeys'] as List).clear();
    expect(value.items.single.indicatorKeys, hasLength(1));
  });
  test('Map and JSON round trip preserves all fields', () {
    final value = DeviceBoardLayout(
      deviceId: 'example',
      layoutTemplateId: 'grid_6x4',
      showTitle: false,
      titleOverride: 'Detalle',
      layoutVersion: 3,
      createdAt: DateTime.parse('2026-09-11T10:00:00-03:00'),
      updatedAt: DateTime.utc(2026, 9, 11, 14),
      items: [
        item(
          w: 2,
          h: 2,
          preset: 'future_custom_v1',
          indicators: ['calefaccionEtapa1'],
        ),
      ],
    );
    final decoded = DeviceBoardLayout.fromMap(
      Map<String, Object?>.from(jsonDecode(jsonEncode(value.toMap())) as Map),
    );
    expect(decoded.toMap(), value.toMap());
    expect(decoded.createdAt!.isAtSameMomentAs(value.createdAt!), isTrue);
    expect(validate(decoded), isEmpty);
    expect(DeviceBoardLayout.fromMap(board().toMap()).toMap(), board().toMap());
  });
  test('optional fields can be omitted', () {
    final map = board().toMap()
      ..remove('createdAt')
      ..remove('updatedAt')
      ..remove('titleOverride');
    ((map['items'] as List).single as Map).remove('cellLayoutPresetId');
    expect(DeviceBoardLayout.fromMap(map).titleOverride, isNull);
  });
  for (final spec in [(6, 4), (8, 4), (10, 5)]) {
    test(
      'dynamic ${spec.$1}x${spec.$2} exact boundary and repeated metric',
      () {
        final template = grid(columns: spec.$1, rows: spec.$2);
        final value = board(
          template: template.id,
          items: [
            item(),
            item(id: 'second', x: spec.$1 - 1, y: spec.$2 - 1),
          ],
        );
        expect(validate(value, template: template), isEmpty);
        expect(DeviceBoardLayout.fromMap(value.toMap()).toMap(), value.toMap());
      },
    );
  }
  test('mismatched template and disabled template detected', () {
    expect(
      validate(board(template: 'other')).map((e) => e.code),
      contains('layout_template_mismatch'),
    );
    expect(
      validate(board(), template: grid(enabled: false)).single.code,
      'layout_template_disabled',
    );
  });
  for (final cell in [
    item(x: 5, w: 2),
    item(y: 3, h: 2),
    item(x: 6),
    item(y: 4),
  ]) {
    test('out of bounds ${cell.placement.x},${cell.placement.y}', () {
      expect(
        validate(board(items: [cell])).single.code,
        'placement_out_of_bounds',
      );
    });
  }
  for (final span in [
    (1, 1, 8, 8),
    (2, 1, 16, 8),
    (1, 2, 8, 16),
    (2, 2, 16, 16),
    (3, 2, 24, 16),
  ]) {
    test('derived subgrid ${span.$1}x${span.$2}', () {
      final cell = item(w: span.$1, h: span.$2);
      expect(cell.internalColumns(grid()), span.$3);
      expect(cell.internalRows(grid()), span.$4);
      expect(cell.toMap(), isNot(contains('internalColumns')));
    });
  }
  test('subgrid honors persisted N1 resolution', () {
    final template = LayoutTemplate(
      id: 'grid',
      name: 'Grid',
      columns: 8,
      rows: 4,
      internalUnitsPerCellX: 12,
      internalUnitsPerCellY: 10,
    );
    expect(item(w: 2, h: 2).internalColumns(template), 24);
    expect(item(w: 2, h: 2).internalRows(template), 20);
  });
  for (final pair in [
    [item(w: 2), item(id: 'b', x: 1, w: 2)],
    [item(w: 2, h: 2), item(id: 'b', w: 2, h: 2)],
    [item(w: 3, h: 3), item(id: 'b', x: 1, y: 1)],
    [item(w: 2, h: 2), item(id: 'b', x: 1, y: 1, w: 2, h: 2)],
  ]) {
    test(
      'partial, complete or contained collision ${pair.last.placement.x}/${pair.last.placement.y}/${pair.first.placement.widthCells}',
      () {
        final issues = validate(board(items: pair));
        expect(issues.single.code, 'placement_collision');
        expect(issues.single.itemId, 'main');
        expect(issues.single.relatedItemId, 'b');
      },
    );
  }
  test('horizontal, vertical and corner adjacency valid', () {
    expect(
      validate(
        board(
          items: [
            item(w: 2, h: 2),
            item(id: 'b', x: 2, w: 1, h: 2),
            item(id: 'c', y: 2, w: 2),
            item(id: 'd', x: 2, y: 2),
          ],
        ),
      ),
      isEmpty,
    );
  });
  test('every colliding pair reported once', () {
    final issues = DeviceBoardLayoutValidator.collisions([
      item(),
      item(id: 'b'),
      item(id: 'c'),
    ]);
    expect(issues, hasLength(3));
  });
  test('duplicate item IDs rejected even when placements differ', () {
    expect(
      validate(board(items: [item(), item(x: 1)])).single.code,
      'duplicate_item_id',
    );
  });
  test('indicator selection requires semantic availability', () {
    expect(
      validate(
        board(
          items: [
            item(indicators: ['calefaccionEtapa1', 'humidificacion']),
          ],
        ),
      ),
      isEmpty,
    );
    expect(
      validate(
        board(
          items: [
            item(indicators: ['missing']),
          ],
        ),
      ).single.code,
      'indicator_not_available',
    );
    expect(
      validate(
        board(
          items: [
            item(metric: 'humedadInterior', indicators: ['calefaccionEtapa1']),
          ],
        ),
      ).single.code,
      'indicator_not_available',
    );
    expect(
      validate(
        board(
          items: [
            item(indicators: ['calefaccionEtapa1', 'calefaccionEtapa1']),
          ],
        ),
      ).single.code,
      'duplicate_indicator_key',
    );
  });
  test('catalog removals are detected without deleting saved items', () {
    final value = board();
    final before = value.toMap();
    final effective = catalog.withOverrides(removedKeys: ['tempInterior']);
    expect(validate(value, metrics: effective).single.code, 'metric_not_found');
    expect(value.toMap(), before);
  });
  test('title derives current name, override or hidden state', () {
    expect(board().resolveTitle('Sala1'), 'Sala1');
    expect(board().resolveTitle('Nuevo nombre'), 'Nuevo nombre');
    expect(
      board(title: 'Personalizado').resolveTitle('Sala1'),
      'Personalizado',
    );
    expect(
      board(showTitle: false, title: 'Personalizado').resolveTitle('Sala1'),
      isNull,
    );
    expect(board().toMap(), isNot(contains('deviceName')));
    for (final value in ['', '   ']) {
      expect(
        () => board(title: value),
        throwsA(issueException('invalid_title_override')),
      );
      expect(
        () => DeviceBoardLayout.fromMap(
          board().toMap()..['titleOverride'] = value,
        ),
        throwsA(issueException('invalid_title_override')),
      );
    }
  });
  test('invalid versions rejected with structured codes', () {
    for (final value in [0, 2, -1]) {
      expect(
        () => board(schema: value),
        throwsA(issueException('unsupported_schema_version')),
      );
    }
    expect(
      () => board(version: 0),
      throwsA(issueException('invalid_layout_version')),
    );
    expect(board(version: 10).layoutVersion, 10);
  });
  for (final field in [
    'deviceId',
    'layoutTemplateId',
    'showTitle',
    'schemaVersion',
    'layoutVersion',
    'items',
  ]) {
    test('requires $field in persisted board', () {
      expect(
        () => DeviceBoardLayout.fromMap(board().toMap()..remove(field)),
        throwsArgumentError,
      );
    });
  }
  for (final entry in <String, List<Object?>>{
    'deviceId': ['', 1],
    'layoutTemplateId': ['', true],
    'showTitle': ['true', 1, null],
    'titleOverride': [1, false],
    'schemaVersion': [2, 1.5, '1'],
    'layoutVersion': [0, -1, 1.5, '1'],
    'items': [
      null,
      {},
      [1],
    ],
    'createdAt': ['bad', '2026-02-31T00:00:00.000Z', '2026-09-11', 1],
    'updatedAt': ['bad', false],
  }.entries) {
    test('rejects invalid board ${entry.key}', () {
      for (final value in entry.value) {
        expect(
          () => DeviceBoardLayout.fromMap(board().toMap()..[entry.key] = value),
          throwsArgumentError,
        );
      }
    });
  }
  for (final field in ['x', 'y', 'widthCells', 'heightCells']) {
    test('placement strict integer $field', () {
      for (final value in [null, '1', 1.5, -1]) {
        final map = item().toMap();
        map['placement'] = Map<String, Object?>.from(map['placement'] as Map)
          ..[field] = value;
        expect(() => DeviceBoardLayoutItem.fromMap(map), throwsArgumentError);
      }
      if (field.contains('Cells')) {
        final map = item().toMap();
        (map['placement'] as Map)[field] = 0;
        expect(() => DeviceBoardLayoutItem.fromMap(map), throwsArgumentError);
      }
    });
  }
  for (final field in [
    'label',
    'unit',
    'sourceField',
    'decimals',
    'displayType',
    'transform',
    'statusBehavior',
    'boardSlots',
    'tableColumns',
    'columns',
    'rows',
    'position',
    'internalColumns',
    'deviceName',
  ]) {
    test('rejects legacy and redundant field $field at every level', () {
      expect(
        () => DeviceBoardLayout.fromMap(board().toMap()..[field] = 1),
        throwsArgumentError,
      );
      expect(
        () => DeviceBoardLayoutItem.fromMap(item().toMap()..[field] = 1),
        throwsArgumentError,
      );
      final map = item().toMap();
      (map['placement'] as Map)[field] = 1;
      expect(() => DeviceBoardLayoutItem.fromMap(map), throwsArgumentError);
    });
  }
  test('item fields are defensive and preset IDs are open strings', () {
    for (final field in ['id', 'metricKey', 'placement', 'indicatorKeys']) {
      expect(
        () => DeviceBoardLayoutItem.fromMap(item().toMap()..remove(field)),
        throwsArgumentError,
      );
    }
    expect(() => item(preset: ' '), throwsArgumentError);
    expect(() => item(indicators: ['']), throwsArgumentError);
    expect(
      item(preset: 'future_any_span_v99').cellLayoutPresetId,
      'future_any_span_v99',
    );
    expect(item().cellLayoutPresetId, isNull);
  });
  test('reference Sala/Laboratorio/Arco configurations validate', () {
    expect(referenceBoardLayouts, hasLength(3));
    expect(() => referenceBoardLayouts.clear(), throwsUnsupportedError);
    for (final example in referenceBoardLayouts) {
      expect(
        DeviceBoardLayoutValidator.validate(
          example.board,
          example.template,
          example.catalog,
        ),
        isEmpty,
        reason: example.label,
      );
      expect(
        DeviceBoardLayout.fromMap(example.board.toMap()).toMap(),
        example.board.toMap(),
      );
    }
  });
}
