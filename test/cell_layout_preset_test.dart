import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_validator.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/cell_layout_presets/cell_content_resolver.dart';
import 'package:agro_data_control/device_board_layouts/device_board_layout.dart';
import 'package:agro_data_control/device_board_layouts/layout_validation_issue.dart';
import 'package:agro_data_control/device_metric_catalogs/reference_metric_catalogs.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';
import 'package:agro_data_control/ui_templates/models/metric_definition.dart';
import 'package:agro_data_control/ui_templates/enums/metric_display_type.dart';

LayoutTemplate get template =>
    LayoutTemplate(id: 'grid_10x5', name: 'Grid', columns: 10, rows: 5);
DeviceBoardLayoutItem item({
  int w = 1,
  int h = 1,
  String? preset,
  List<String> keys = const [],
  String metric = 'tempInterior',
}) => DeviceBoardLayoutItem(
  id: 'metric',
  metricKey: metric,
  placement: GridPlacement(x: 0, y: 0, widthCells: w, heightCells: h),
  indicatorKeys: keys,
  cellLayoutPresetId: preset,
);
CellLayoutElement element({
  String id = 'value',
  int x = 0,
  int y = 0,
  int w = 2,
  int h = 2,
  CellElementType type = CellElementType.value,
  int? slot,
}) => CellLayoutElement(
  id: id,
  type: type,
  placement: InternalGridPlacement(x: x, y: y, widthUnits: w, heightUnits: h),
  indicatorSlot: slot,
);
CellLayoutPreset preset({
  List<CellLayoutElement>? elements,
  int w = 1,
  int h = 1,
}) => CellLayoutPreset(
  id: 'custom',
  name: 'Custom',
  widthCells: w,
  heightCells: h,
  elements: elements ?? [element()],
);
Map<String, Object?> clone(Map<String, Object?> map) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(map)) as Map);
List<String> codes(CellLayoutPreset p, {DeviceBoardLayoutItem? cell}) =>
    CellLayoutValidator.validate(
      p,
      cell ?? item(),
      template,
    ).map((i) => i.code).toList();
Matcher throwsCode(String code) => throwsA(
  isA<LayoutValidationException>().having(
    (e) => e.issues.single.code,
    'code',
    code,
  ),
);

void main() {
  for (final shape in [
    (1, 1, 8, 8),
    (2, 1, 16, 8),
    (1, 2, 8, 16),
    (2, 2, 16, 16),
  ]) {
    test('geometry and default ${shape.$1}x${shape.$2}', () {
      final p = initialCellLayoutCatalog.defaultForSpan(shape.$1, shape.$2)!;
      expect(p.internalColumns(template), shape.$3);
      expect(p.internalRows(template), shape.$4);
      expect(
        codes(
          p,
          cell: item(w: shape.$1, h: shape.$2),
        ),
        isEmpty,
      );
    });
  }
  test('custom N1 resolution is honored, geometry never scaled silently', () {
    final t = LayoutTemplate(
      id: 'grid',
      name: 'Grid',
      columns: 10,
      rows: 5,
      internalUnitsPerCellX: 12,
      internalUnitsPerCellY: 10,
    );
    expect(preset(w: 2, h: 2).internalColumns(t), 24);
    expect(preset(w: 2, h: 2).internalRows(t), 20);
    final small = LayoutTemplate(
      id: 'grid',
      name: 'Grid',
      columns: 10,
      rows: 5,
      internalUnitsPerCellX: 4,
      internalUnitsPerCellY: 4,
    );
    expect(
      CellLayoutValidator.validate(
        initialCellLayoutCatalog.byId('default_1x1')!,
        item(),
        small,
      ).map((i) => i.code),
      contains('internal_out_of_bounds'),
    );
  });
  test('bounds and exact edge', () {
    expect(codes(preset(elements: [element(x: 6, y: 6)])), isEmpty);
    expect(
      codes(preset(elements: [element(x: 7, y: 6)])),
      contains('internal_out_of_bounds'),
    );
    expect(
      codes(preset(elements: [element(x: 6, y: 7)])),
      contains('internal_out_of_bounds'),
    );
  });
  for (final field in ['x', 'y', 'widthUnits', 'heightUnits']) {
    test('strict placement $field', () {
      for (final invalid in [null, '1', 1.5, -1]) {
        final map = clone(element().placement.toMap())..[field] = invalid;
        expect(() => InternalGridPlacement.fromMap(map), throwsArgumentError);
      }
      if (field.contains('Units')) {
        expect(
          () => InternalGridPlacement.fromMap(
            clone(element().placement.toMap())..[field] = 0,
          ),
          throwsArgumentError,
        );
      }
    });
  }
  for (final pair in [
    [element(w: 4), element(id: 'b', x: 2, w: 4)],
    [element(), element(id: 'b')],
    [element(w: 6, h: 6), element(id: 'b', x: 2, y: 2)],
  ]) {
    test(
      'collision ${pair.first.placement.widthUnits}/${pair.last.placement.x}',
      () {
        final issues = CellLayoutValidator.collisions(pair);
        expect(issues.single.code, 'internal_collision');
        expect(issues.single.relatedItemId, 'b');
        expect(codes(preset(elements: pair)), contains('internal_collision'));
      },
    );
  }
  test('horizontal, vertical and corner adjacency are valid', () {
    expect(
      codes(
        preset(
          elements: [
            element(),
            element(id: 'b', x: 2),
            element(id: 'c', y: 2),
            element(id: 'd', x: 2, y: 2),
          ],
        ),
      ),
      isEmpty,
    );
  });
  test('duplicate IDs rejected; repeated content types allowed', () {
    expect(
      () => preset(elements: [element(), element(x: 2)]),
      throwsCode('duplicate_element_id'),
    );
    expect(
      codes(
        preset(
          elements: [
            element(),
            element(id: 'repeated-value', x: 2),
          ],
        ),
      ),
      isEmpty,
    );
  });
  test('slots must be unique, contiguous and indicator-only', () {
    expect(
      () => element(type: CellElementType.indicator),
      throwsCode('invalid_indicator_slot'),
    );
    expect(
      () => element(type: CellElementType.indicator, slot: -1),
      throwsCode('invalid_indicator_slot'),
    );
    expect(() => element(slot: 0), throwsCode('unexpected_indicator_slot'));
    expect(
      () =>
          preset(elements: [element(type: CellElementType.indicator, slot: 1)]),
      throwsCode('noncontiguous_indicator_slots'),
    );
    expect(
      () => preset(
        elements: [
          element(type: CellElementType.indicator, slot: 0),
          element(id: 'other', type: CellElementType.indicator, slot: 0, x: 2),
        ],
      ),
      throwsCode('duplicate_indicator_slot'),
    );
  });
  test('sufficient, excess and fewer indicators', () {
    final p = initialCellLayoutCatalog.byId('default_1x1')!;
    expect(codes(p, cell: item(keys: ['a', 'b', 'c'])), isEmpty);
    expect(codes(p, cell: item(keys: ['a'])), isEmpty);
    expect(
      codes(p, cell: item(keys: ['a', 'b', 'c', 'd'])),
      contains('insufficient_indicator_slots'),
    );
  });
  test('span, explicit ID, enabled and external bounds', () {
    expect(codes(preset(), cell: item(w: 2)), contains('cell_span_mismatch'));
    expect(codes(preset(w: 2), cell: item(w: 2)), isEmpty);
    expect(
      codes(preset(), cell: item(preset: 'other')),
      contains('cell_preset_mismatch'),
    );
    expect(
      codes(CellLayoutPreset.fromMap(preset().toMap()..['enabled'] = false)),
      contains('cell_preset_disabled'),
    );
    expect(
      codes(preset(w: 11), cell: item(w: 11)),
      containsAll(['preset_out_of_bounds', 'placement_out_of_bounds']),
    );
  });
  test('catalog IDs, defaults and immutable snapshots', () {
    final list = [preset()];
    final defaults = {'1x1': 'custom'};
    final catalog = CellLayoutCatalog(list, defaults: defaults);
    list.clear();
    defaults.clear();
    expect(catalog.resolve(item()).id, 'custom');
    expect(catalog.byId('unknown'), isNull);
    expect(() => catalog.presets.clear(), throwsUnsupportedError);
    expect(() => catalog.defaults.clear(), throwsUnsupportedError);
    expect(
      () => CellLayoutCatalog([preset(), preset()]),
      throwsCode('duplicate_preset_id'),
    );
    expect(
      () => CellLayoutCatalog([preset()], defaults: {'2x1': 'custom'}),
      throwsCode('invalid_default_preset'),
    );
    expect(
      () => CellLayoutCatalog([preset()], defaults: {'1x1': 'missing'}),
      throwsCode('invalid_default_preset'),
    );
    expect(
      () => catalog.resolve(item(preset: 'unknown')),
      throwsCode('cell_preset_not_found'),
    );
    // N6.3.1 (B1): "(default por span)" (cellLayoutPresetId == null) must
    // resolve for any valid span, even one with no seeded default entry —
    // it falls back to resolveDefaultCellLayoutForSpan instead of throwing
    // cell_preset_not_found. Only an *explicit* unresolvable id (above)
    // still fails.
    final generic = catalog.resolve(item(w: 3));
    expect(generic.widthCells, 3);
    expect(generic.heightCells, 1);
    expect(generic.id, resolveDefaultCellLayoutForSpan(3, 1).id);
  });
  test('all initial variants valid, including explicit selection', () {
    expect(initialCellLayoutCatalog.presets, hasLength(7));
    for (final p in initialCellLayoutCatalog.presets) {
      final cell = item(w: p.widthCells, h: p.heightCells, preset: p.id);
      expect(initialCellLayoutCatalog.resolve(cell), same(p));
      expect(codes(p, cell: cell), isEmpty);
    }
  });
  test('future 3x2 preset supported with no metric/device branches', () {
    final p = CellLayoutPreset(
      id: 'wide_future_v1',
      name: 'Future',
      widthCells: 3,
      heightCells: 2,
      elements: [element(w: 24, h: 16)],
    );
    final catalog = CellLayoutCatalog([p], defaults: {'3x2': p.id});
    expect(catalog.resolve(item(w: 3, h: 2)), same(p));
    expect(codes(p, cell: item(w: 3, h: 2)), isEmpty);
    expect(p.internalColumns(template), 24);
  });
  test('pure resolver handles all five element types and vacant slots', () {
    final metric = referenceMetricCatalogById(
      'environment_room_v1',
    )!.metricByKey('tempInterior')!;
    final p = initialCellLayoutCatalog.byId('icon_value_1x1')!;
    final cell = item(keys: ['calefaccionEtapa1', 'calefaccionEtapa2']);
    final resolved = CellContentResolver.resolve(
      metric,
      cell,
      p,
      template: template,
    );
    expect(
      resolved.firstWhere((e) => e.element.type == CellElementType.label).text,
      metric.label,
    );
    expect(
      resolved.firstWhere((e) => e.element.type == CellElementType.unit).text,
      metric.unit,
    );
    expect(
      resolved
          .firstWhere((e) => e.element.type == CellElementType.icon)
          .iconRef,
      metric.icon,
    );
    expect(
      resolved
          .firstWhere((e) => e.element.type == CellElementType.value)
          .valuePending,
      isTrue,
    );
    final indicators = resolved
        .where((e) => e.element.type == CellElementType.indicator)
        .toList();
    expect(indicators.map((e) => e.indicatorKey), [
      'calefaccionEtapa1',
      'calefaccionEtapa2',
      null,
    ]);
    expect(indicators.last.emptyIndicator, isTrue);
    expect(() => resolved.clear(), throwsUnsupportedError);
    expect(
      () => CellContentResolver.resolve(
        metric,
        item(metric: 'missing'),
        p,
        template: template,
      ),
      throwsCode('metric_mismatch'),
    );
    expect(
      () => CellContentResolver.resolve(
        metric,
        item(w: 2),
        p,
        template: template,
      ),
      throwsCode('cell_span_mismatch'),
    );
  });
  test('future energy metric resolves same semantic preset', () {
    final metric = MetricDefinition(
      key: 'energyConsumption',
      label: 'Energy',
      unit: 'kWh',
      icon: 'energy',
      sourceField: 'computed.energy',
      displayType: MetricDisplayType.number,
      decimals: 2,
    );
    final result = CellContentResolver.resolve(
      metric,
      item(metric: metric.key),
      initialCellLayoutCatalog.byId('default_1x1')!,
      template: template,
    );
    expect(
      result.firstWhere((e) => e.element.type == CellElementType.label).text,
      'Energy',
    );
  });
  test('nested Map and JSON round trips preserve all presentation fields', () {
    final map = clone(initialCellLayoutCatalog.byId('icon_value_1x1')!.toMap())
      ..['presetVersion'] = 4
      ..['createdAt'] = '2026-09-11T10:00:00.000Z'
      ..['updatedAt'] = '2026-09-11T11:00:00.000Z';
    expect(CellLayoutPreset.fromMap(map).toMap(), map);
    final elements = [element()];
    final p = preset(elements: elements);
    elements.clear();
    expect(p.elements, hasLength(1));
    expect(() => p.elements.clear(), throwsUnsupportedError);
    (p.toMap()['elements'] as List).clear();
    expect(p.elements, hasLength(1));
  });
  for (final entry in <String, List<Object?>>{
    'id': ['', null, 1],
    'name': ['', false],
    'widthCells': [0, -1, 1.5, '1'],
    'heightCells': [0, -1],
    'schemaVersion': [0, 3, '1'],
    'presetVersion': [0, -1, 1.5],
    'enabled': [null, 'true', 1],
    'elements': [
      null,
      {},
      [1],
    ],
    'createdAt': ['bad', '2026-02-31T00:00:00.000Z', 1],
  }.entries) {
    test('invalid preset ${entry.key}', () {
      for (final value in entry.value) {
        expect(
          () => CellLayoutPreset.fromMap(
            clone(preset().toMap())..[entry.key] = value,
          ),
          throwsArgumentError,
        );
      }
    });
  }
  test('required fields and optional dates', () {
    for (final key in [
      'id',
      'name',
      'widthCells',
      'heightCells',
      'schemaVersion',
      'presetVersion',
      'enabled',
      'elements',
    ]) {
      expect(
        () => CellLayoutPreset.fromMap(preset().toMap()..remove(key)),
        throwsArgumentError,
      );
    }
    expect(
      CellLayoutPreset.fromMap(
        preset().toMap()
          ..remove('createdAt')
          ..remove('updatedAt'),
      ).createdAt,
      isNull,
    );
  });
  test('invalid type, alignment, text style and slots rejected', () {
    for (final entry in {
      'type': 'futureTrend',
      'horizontalAlignment': 'left',
      'verticalAlignment': 'end',
      'indicatorSlot': 1,
    }.entries) {
      expect(
        () => CellLayoutElement.fromMap(
          element().toMap()..[entry.key] = entry.value,
        ),
        throwsArgumentError,
      );
    }
    expect(() => CellTextStyle(maxLines: 0), throwsArgumentError);
    for (final entry in {
      'fontRole': 'custom',
      'weight': 'heavy',
      'maxLines': 1.5,
    }.entries) {
      expect(
        () => CellTextStyle.fromMap(
          CellTextStyle().toMap()..[entry.key] = entry.value,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => CellLayoutElement(
        id: 'icon',
        type: CellElementType.icon,
        placement: element().placement,
        textStyle: CellTextStyle(),
      ),
      throwsArgumentError,
    );
  });
  for (final field in [
    'metricKey',
    'sourceField',
    'deviceId',
    'tenantId',
    'image',
    'table',
    'latestEvent',
    'fontSize',
    'paddingLeft',
    'internalColumns',
    'internalRows',
    'sourceRef',
  ]) {
    test('rejects foreign or redundant $field', () {
      expect(
        () => CellLayoutPreset.fromMap(preset().toMap()..[field] = 1),
        throwsArgumentError,
      );
      expect(
        () => CellLayoutElement.fromMap(element().toMap()..[field] = 1),
        throwsArgumentError,
      );
      expect(
        () => InternalGridPlacement.fromMap(
          element().placement.toMap()..[field] = 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => CellTextStyle.fromMap(CellTextStyle().toMap()..[field] = 1),
        throwsArgumentError,
      );
    });
  }
}
