import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_content/board_content_validator.dart';
import 'package:agro_data_control/board_content/reference_content_boards.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_validator.dart';
import 'package:agro_data_control/cell_layout_presets/cell_content_resolver.dart';
import 'package:agro_data_control/device_board_layouts/device_board_layout.dart';
import 'package:agro_data_control/device_board_layouts/reference_board_layouts.dart';
import 'package:agro_data_control/device_board_layouts/layout_validation_issue.dart';
import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';
import 'package:agro_data_control/device_metric_catalogs/reference_metric_catalogs.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';

BoardDataField field([String key = 'time']) =>
    BoardDataField(key: key, label: key, format: BoardFieldFormat.dateTime);
List<BoardContentConfig> samples() => [
  MetricBoardContent(
    metricKey: 'tempInterior',
    indicatorKeys: ['calefaccionEtapa1'],
  ),
  ImageBoardContent(
    sourceType: BoardImageSourceType.asset,
    sourceRef: 'assets/example.png',
    altText: 'Example',
  ),
  LatestEventBoardContent(eventSourceId: 'events.latest', fields: [field()]),
  DataTableBoardContent(
    dataSourceId: 'events.recent',
    columns: [BoardTableColumn(field: field(), flex: 2)],
  ),
  StatusBoardContent(dataSourceId: 'device.state'),
  TextBoardContent(text: 'Información'),
  ChartBoardContent(
    dataSourceId: 'history',
    chartType: BoardChartType.line,
    series: [BoardChartSeries(key: 'value', label: 'Value')],
  ),
];
BoardContentItem item(
  BoardContentConfig config, {
  String id = 'item',
  int x = 0,
  int y = 0,
  int w = 1,
  int h = 1,
}) => BoardContentItem(
  id: id,
  placement: GridPlacement(x: x, y: y, widthCells: w, heightCells: h),
  content: config,
);
BoardContentLayout board(
  List<BoardContentItem> items, {
  String templateId = 'grid_8x4',
}) => BoardContentLayout(
  deviceId: 'example',
  layoutTemplateId: templateId,
  items: items,
);
LayoutTemplate grid({int columns = 8, int rows = 4}) => LayoutTemplate(
  id: 'grid_${columns}x$rows',
  name: 'Grid',
  columns: columns,
  rows: rows,
);
DeviceMetricCatalog get catalog =>
    referenceMetricCatalogById('environment_room_v1')!;
List<String> validate(
  BoardContentLayout b, {
  DeviceMetricCatalog? metrics,
  LayoutTemplate? template,
}) => BoardContentValidator.validate(
  b,
  template ?? grid(),
  metrics ?? catalog,
  initialCellLayoutCatalog,
).map((e) => e.code).toList();
Map<String, Object?> clone(Map<String, Object?> map) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(map)) as Map);
Matcher throwsCode(String code) => throwsA(
  isA<LayoutValidationException>().having(
    (e) => e.issues.single.code,
    'code',
    code,
  ),
);

void main() {
  for (final content in samples()) {
    test('${content.type.name}: typed Map/JSON round trip and validity', () {
      final value = board([item(content)]);
      expect(validate(value), isEmpty);
      final copy = BoardContentLayout.fromMap(clone(value.toMap()));
      expect(copy.toMap(), value.toMap());
      expect(copy.items.single.content.runtimeType, content.runtimeType);
    });
    test('${content.type.name}: bounds and mixed collision', () {
      expect(
        validate(board([item(content, x: 8)])),
        contains('placement_out_of_bounds'),
      );
      expect(
        validate(
          board([
            item(content),
            item(TextBoardContent(text: 'Note'), id: 'other'),
          ]),
        ),
        contains('placement_collision'),
      );
      expect(
        validate(
          board([
            item(content),
            item(TextBoardContent(text: 'Note'), id: 'other', x: 1),
          ]),
        ),
        isEmpty,
      );
    });
    test('${content.type.name}: strict content keys', () {
      expect(
        () => BoardContentConfig.fromMap(
          content.type.name,
          content.toMap()..['unknown'] = 1,
        ),
        throwsCode('invalid_content_config'),
      );
    });
  }
  test('unknown type including unregistered customWidget is rejected', () {
    for (final type in ['unknown', 'customWidget', 'ArcoDashboard']) {
      expect(
        () => BoardContentConfig.fromMap(type, {}),
        throwsCode('unsupported_content_type'),
      );
    }
  });
  test('schema migration preserves all N3 fixtures and metadata', () {
    for (final fixture in referenceBoardLayouts) {
      final migrated = BoardContentLayout.fromMap(clone(fixture.board.toMap()));
      expect(migrated.schemaVersion, 2);
      expect(migrated.toLegacy().toMap(), fixture.board.toMap());
      expect(
        BoardContentValidator.validate(
          migrated,
          fixture.template,
          fixture.catalog,
          initialCellLayoutCatalog,
        ),
        isEmpty,
      );
    }
    final original = DeviceBoardLayout(
      deviceId: 'device',
      layoutTemplateId: 'grid_8x4',
      showTitle: false,
      titleOverride: 'Título',
      layoutVersion: 7,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 9),
      items: [
        DeviceBoardLayoutItem(
          id: 'metric',
          metricKey: 'tempInterior',
          placement: GridPlacement(x: 0, y: 0, widthCells: 1, heightCells: 1),
          cellLayoutPresetId: 'default_1x1',
          indicatorKeys: ['calefaccionEtapa1'],
        ),
      ],
    );
    final migrated = BoardContentLayout.fromLegacy(original);
    expect(migrated.toLegacy().toMap(), original.toMap());
    expect(
      BoardContentLayout.fromMap(clone(migrated.toMap())).toMap(),
      migrated.toMap(),
    );
    expect(migrated.resolveTitle('current'), isNull);
    expect(
      () => board([item(TextBoardContent(text: 'note'))]).toLegacy(),
      throwsCode('non_metric_content'),
    );
  });
  test('N2 metrics, indicators and N4 presets remain validated', () {
    expect(
      validate(board([item(MetricBoardContent(metricKey: 'missing'))])),
      contains('metric_not_found'),
    );
    expect(
      validate(
        board([
          item(
            MetricBoardContent(
              metricKey: 'tempInterior',
              indicatorKeys: ['missing'],
            ),
          ),
        ]),
      ),
      contains('indicator_not_available'),
    );
    expect(
      validate(
        board([
          item(
            MetricBoardContent(
              metricKey: 'humedadInterior',
              indicatorKeys: ['calefaccionEtapa1'],
            ),
          ),
        ]),
      ),
      contains('indicator_not_available'),
    );
    expect(
      validate(
        board([
          item(
            MetricBoardContent(
              metricKey: 'tempInterior',
              indicatorKeys: ['calefaccionEtapa1', 'calefaccionEtapa1'],
            ),
          ),
        ]),
      ),
      contains('duplicate_indicator_key'),
    );
    expect(
      validate(
        board([
          item(
            MetricBoardContent(
              metricKey: 'tempInterior',
              cellLayoutPresetId: 'missing',
            ),
          ),
        ]),
      ),
      contains('cell_preset_not_found'),
    );
    expect(
      validate(
        board([
          item(
            MetricBoardContent(
              metricKey: 'tempInterior',
              cellLayoutPresetId: 'default_2x1',
            ),
          ),
        ]),
      ),
      contains('cell_span_mismatch'),
    );
    final b = board([item(MetricBoardContent(metricKey: 'tempInterior'))]);
    final before = b.toMap();
    expect(
      validate(
        b,
        metrics: catalog.withOverrides(removedKeys: ['tempInterior']),
      ),
      contains('metric_not_found'),
    );
    expect(b.toMap(), before);
  });
  test('duplicate IDs across types; repeated metric keys retain meaning', () {
    expect(
      validate(
        board([
          item(samples().first),
          item(TextBoardContent(text: 'Note'), x: 1),
        ]),
      ),
      contains('duplicate_item_id'),
    );
    expect(
      validate(
        board([
          item(samples().first),
          item(samples().first, id: 'second', x: 1),
        ]),
      ),
      isEmpty,
    );
  });
  for (final size in [(6, 4), (8, 4), (10, 5)]) {
    test('all content kinds on ${size.$1}x${size.$2}', () {
      final t = grid(columns: size.$1, rows: size.$2);
      final configs = samples();
      final items = <BoardContentItem>[];
      for (var i = 0; i < configs.length; i++) {
        items.add(
          item(configs[i], id: 'item-$i', x: i % size.$1, y: i ~/ size.$1),
        );
      }
      expect(validate(board(items, templateId: t.id), template: t), isEmpty);
    });
  }
  test('all four image source contracts', () {
    for (final type in BoardImageSourceType.values) {
      final value = ImageBoardContent(
        sourceType: type,
        sourceRef: type == BoardImageSourceType.url
            ? 'https://example.com/image.png'
            : 'images/hero',
      );
      expect(ImageBoardContent.fromMap(value.toMap()).toMap(), value.toMap());
    }
  });
  test('invalid image references and enum values', () {
    for (final url in [
      'javascript:alert(1)',
      'file:///tmp/image',
      'https://',
      'https://user:pass@example.com/a',
      'https://example.com/a b',
    ]) {
      expect(
        () => ImageBoardContent(
          sourceType: BoardImageSourceType.url,
          sourceRef: url,
        ),
        throwsArgumentError,
      );
    }
    for (final ref in ['', '../a', '/absolute', 'a/../b', 'a b']) {
      expect(
        () => ImageBoardContent(
          sourceType: BoardImageSourceType.asset,
          sourceRef: ref,
        ),
        throwsArgumentError,
      );
    }
    final map = samples()[1].toMap();
    expect(
      () => ImageBoardContent.fromMap({...map, 'sourceType': 'ftp'}),
      throwsArgumentError,
    );
    expect(
      () => ImageBoardContent.fromMap({...map, 'fit': 'pixels'}),
      throwsArgumentError,
    );
  });
  test('event fields and table columns validate unique keys', () {
    expect(
      () => LatestEventBoardContent(
        eventSourceId: 'events',
        fields: [field(), field()],
      ),
      throwsCode('duplicate_field_key'),
    );
    expect(
      () => DataTableBoardContent(
        dataSourceId: 'records',
        columns: [
          BoardTableColumn(field: field()),
          BoardTableColumn(field: field()),
        ],
      ),
      throwsCode('duplicate_column_key'),
    );
    expect(
      () => LatestEventBoardContent(eventSourceId: 'events', fields: []),
      throwsArgumentError,
    );
    expect(
      () => DataTableBoardContent(dataSourceId: 'records', columns: []),
      throwsArgumentError,
    );
  });
  test('nonmetric data source IDs required without consulting providers', () {
    for (final invalid in ['', 'invalid source']) {
      expect(
        () =>
            LatestEventBoardContent(eventSourceId: invalid, fields: [field()]),
        throwsCode('data_source_missing'),
      );
      expect(
        () => DataTableBoardContent(
          dataSourceId: invalid,
          columns: [BoardTableColumn(field: field())],
        ),
        throwsCode('data_source_missing'),
      );
      expect(
        () => StatusBoardContent(dataSourceId: invalid),
        throwsCode('data_source_missing'),
      );
      expect(
        () => ChartBoardContent(
          dataSourceId: invalid,
          chartType: BoardChartType.line,
          series: [BoardChartSeries(key: 'v', label: 'V')],
        ),
        throwsCode('data_source_missing'),
      );
    }
  });
  test('table technical budgets, booleans and field formats', () {
    for (final n in [0, -1, 1001]) {
      expect(
        () => DataTableBoardContent(
          dataSourceId: 'data',
          columns: [BoardTableColumn(field: field())],
          maxRows: n,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => BoardTableColumn(field: field(), flex: 0),
      throwsArgumentError,
    );
    expect(
      () => BoardDataField.fromMap(field().toMap()..['format'] = 'html'),
      throwsArgumentError,
    );
    final map = samples()[3].toMap();
    expect(
      () => DataTableBoardContent.fromMap({...map, 'showHeader': 'true'}),
      throwsArgumentError,
    );
    expect(
      () => DataTableBoardContent.fromMap({...map, 'maxRows': 1.5}),
      throwsArgumentError,
    );
  });
  test('text is plain text; chart series are typed and unique', () {
    for (final text in ['', '<script>alert(1)</script>', '<b>label</b>']) {
      expect(() => TextBoardContent(text: text), throwsArgumentError);
    }
    expect(TextBoardContent(text: 'Value < 10').text, 'Value < 10');
    expect(
      () => ChartBoardContent(
        dataSourceId: 'history',
        chartType: BoardChartType.line,
        series: [],
      ),
      throwsArgumentError,
    );
    expect(
      () => ChartBoardContent(
        dataSourceId: 'history',
        chartType: BoardChartType.line,
        series: [
          BoardChartSeries(key: 'v', label: 'A'),
          BoardChartSeries(key: 'v', label: 'B'),
        ],
      ),
      throwsCode('duplicate_series_key'),
    );
    expect(
      () => ChartBoardContent.fromMap(
        samples().last.toMap()..['chartType'] = 'engineClass',
      ),
      throwsArgumentError,
    );
  });
  test('nested lists, board items and output maps cannot mutate domain', () {
    final keys = ['calefaccionEtapa1'];
    final metric = MetricBoardContent(
      metricKey: 'tempInterior',
      indicatorKeys: keys,
    );
    keys.clear();
    expect(metric.indicatorKeys, hasLength(1));
    final fields = [field()];
    final event = LatestEventBoardContent(
      eventSourceId: 'latest',
      fields: fields,
    );
    fields.clear();
    expect(event.fields, hasLength(1));
    final columns = [BoardTableColumn(field: field())];
    final table = DataTableBoardContent(
      dataSourceId: 'records',
      columns: columns,
    );
    columns.clear();
    expect(table.columns, hasLength(1));
    final series = [BoardChartSeries(key: 'v', label: 'V')];
    final chart = ChartBoardContent(
      dataSourceId: 'history',
      chartType: BoardChartType.bar,
      series: series,
    );
    series.clear();
    expect(chart.series, hasLength(1));
    final cells = [item(event)];
    final b = board(cells);
    cells.clear();
    expect(b.items, hasLength(1));
    expect(() => b.items.clear(), throwsUnsupportedError);
    expect(() => event.fields.clear(), throwsUnsupportedError);
    expect(() => metric.indicatorKeys.clear(), throwsUnsupportedError);
    expect(() => table.columns.clear(), throwsUnsupportedError);
    expect(() => chart.series.clear(), throwsUnsupportedError);
    (event.toMap()['fields'] as List).clear();
    expect(event.fields, hasLength(1));
  });
  test('strict board, item, placement and nested field serialization', () {
    final base = board([item(samples().first)]).toMap();
    for (final version in [0, 3, '2', 2.5]) {
      expect(
        () => BoardContentLayout.fromMap({...base, 'schemaVersion': version}),
        throwsArgumentError,
      );
    }
    for (final key in ['items', 'deviceId', 'schemaVersion', 'layoutVersion']) {
      expect(
        () => BoardContentLayout.fromMap({...base}..remove(key)),
        throwsArgumentError,
      );
    }
    expect(
      () => BoardContentLayout.fromMap({...base, 'legacy': true}),
      throwsArgumentError,
    );
    expect(
      () => BoardContentItem.fromMap(
        item(samples().first).toMap()..['metricKey'] = 'mixed',
      ),
      throwsArgumentError,
    );
    expect(
      () => BoardDataField.fromMap(field().toMap()..['widthPixels'] = 10),
      throwsArgumentError,
    );
    final bad = item(samples().first).toMap();
    bad['placement'] = {'x': 0, 'y': 0, 'widthCells': 1.5, 'heightCells': 1};
    expect(() => BoardContentItem.fromMap(bad), throwsArgumentError);
  });
  test('Arco reference is mixed and valid without real data', () {
    final f = disinfectionContentExample;
    expect(
      BoardContentValidator.validate(
        f.board,
        f.template,
        f.catalog,
        initialCellLayoutCatalog,
      ),
      isEmpty,
    );
    expect(
      f.board.items.map((i) => i.type).toSet(),
      containsAll([
        BoardContentType.metric,
        BoardContentType.image,
        BoardContentType.latestEvent,
        BoardContentType.dataTable,
        BoardContentType.status,
      ]),
    );
    expect(
      BoardContentLayout.fromMap(clone(f.board.toMap())).toMap(),
      f.board.toMap(),
    );
  });
  test('Sala reference stays metric-only', () {
    final f = roomContentExample;
    expect(
      f.board.items.every((i) => i.type == BoardContentType.metric),
      isTrue,
    );
    expect(
      BoardContentValidator.validate(
        f.board,
        f.template,
        f.catalog,
        initialCellLayoutCatalog,
      ),
      isEmpty,
    );
  });
  test('3x1 default closes unchanged Laboratory fixture gap', () {
    final f = referenceBoardLayouts[1];
    final p = initialCellLayoutCatalog.byId('default_3x1')!;
    expect(p.internalColumns(f.template), 24);
    expect(p.internalRows(f.template), 8);
    expect(initialCellLayoutCatalog.defaultForSpan(3, 1), same(p));
    for (final item in f.board.items) {
      expect(item.placement.widthCells, 3);
      expect(initialCellLayoutCatalog.resolve(item), same(p));
      expect(CellLayoutValidator.validate(p, item, f.template), isEmpty);
      expect(
        CellContentResolver.resolve(
          f.catalog.metricByKey(item.metricKey)!,
          item,
          p,
          template: f.template,
        ),
        isNotEmpty,
      );
    }
  });
}
