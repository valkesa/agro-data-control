import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_preview/board_content_renderer.dart';
import 'package:agro_data_control/board_preview/board_item_renderers.dart';
import 'package:agro_data_control/board_preview/board_preview_page.dart';
import 'package:agro_data_control/board_preview/preview_board_data.dart';
import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/device_metric_catalogs/reference_metric_catalogs.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';

BoardContentItem cell(
  BoardContentConfig config, {
  String id = 'cell',
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
  String template = 'grid_6x4',
  bool showTitle = true,
  String? title,
}) => BoardContentLayout(
  deviceId: 'example',
  layoutTemplateId: template,
  items: items,
  showTitle: showTitle,
  titleOverride: title,
);
LayoutTemplate grid({int columns = 6, int rows = 4}) => LayoutTemplate(
  id: 'grid_${columns}x$rows',
  name: 'NOT A DEVICE TITLE',
  columns: columns,
  rows: rows,
);
Widget render(
  BoardContentLayout b, {
  LayoutTemplate? template,
  PreviewBoardDataProvider? data,
  bool debug = false,
}) => BoardContentRenderer(
  board: b,
  template: template ?? grid(),
  catalog: referenceMetricCatalogById('environment_room_v1')!,
  data: data ?? samplePreviewData,
  deviceName: 'Device actual',
  showGrid: debug,
);
Future<void> pump(
  WidgetTester tester,
  Widget child, {
  double width = 600,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final dimensions in [(6, 4), (6, 7), (8, 4), (10, 5)]) {
    testWidgets('dynamic geometry ${dimensions.$1}x${dimensions.$2}', (
      tester,
    ) async {
      final t = grid(columns: dimensions.$1, rows: dimensions.$2);
      await pump(
        tester,
        render(
          board([
            cell(TextBoardContent(text: 'span'), x: 1, y: 1, w: 2, h: 2),
          ], template: t.id),
          template: t,
        ),
      );
      final positioned = tester.widget<Positioned>(
        find.byKey(const ValueKey('placement-cell')),
      );
      expect(positioned.left, 68.0);
      expect(positioned.width, 136.0);
      expect(positioned.top, closeTo(68.0, 0.001));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('title current name, override and hidden', (tester) async {
    await pump(tester, render(board([])));
    expect(find.text('Device actual'), findsOneWidget);
    expect(find.text('NOT A DEVICE TITLE'), findsNothing);
    await pump(tester, render(board([], title: 'Custom')));
    expect(find.text('Custom'), findsOneWidget);
    await pump(tester, render(board([], showTitle: false)));
    expect(find.byKey(const ValueKey('board-title')), findsNothing);
  });
  testWidgets('metric default values, unit, label and indicator slot mapping', (
    tester,
  ) async {
    await pump(
      tester,
      render(
        board([
          cell(
            MetricBoardContent(
              metricKey: 'tempInterior',
              indicatorKeys: ['calefaccionEtapa1', 'calefaccionEtapa2'],
            ),
          ),
        ]),
      ),
    );
    expect(find.text('24.6'), findsOneWidget);
    expect(find.text('°C'), findsOneWidget);
    expect(find.text('Temperatura interior'), findsOneWidget);
    final active = tester.widget<Icon>(
      find.byKey(const ValueKey('indicator-cell-0')),
    );
    final inactive = tester.widget<Icon>(
      find.byKey(const ValueKey('indicator-cell-1')),
    );
    expect(active.color, isNot(inactive.color));
    expect(find.byKey(const ValueKey('indicator-cell-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('explicit icon preset and 3x1 internal placement', (
    tester,
  ) async {
    await pump(
      tester,
      render(
        board([
          cell(
            MetricBoardContent(
              metricKey: 'tempInterior',
              cellLayoutPresetId: 'icon_value_1x1',
            ),
          ),
        ]),
      ),
    );
    expect(find.byIcon(Icons.thermostat), findsOneWidget);
    await pump(
      tester,
      render(
        board([cell(MetricBoardContent(metricKey: 'tempInterior'), w: 3)]),
      ),
    );
    final external = tester.widget<Positioned>(
      find.byKey(const ValueKey('placement-cell')),
    );
    final value = tester.widget<Positioned>(
      find.byKey(const ValueKey('cell-element-value')),
    );
    // Full logical canvas: gutters are decoration, never grid padding.
    expect(value.width, closeTo(external.width! * 18 / 24, 0.001));
    expect(find.text('24.6'), findsOneWidget);
  });
  for (final fit in BoardImageFit.values) {
    testWidgets('image ${fit.name}', (tester) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1sAAAAASUVORK5CYII=',
      );
      await pump(
        tester,
        render(
          board([
            cell(
              ImageBoardContent(
                sourceType: BoardImageSourceType.deviceMediaRef,
                sourceRef: 'local',
                fit: fit,
              ),
            ),
          ]),
          data: PreviewBoardDataProvider(media: {'local': MemoryImage(bytes)}),
        ),
      );
      final widget = tester.widget<Image>(find.byType(Image));
      expect(widget.fit, switch (fit) {
        BoardImageFit.contain => BoxFit.contain,
        BoardImageFit.cover => BoxFit.cover,
        BoardImageFit.fill => BoxFit.fill,
      });
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('latest event fields from configuration', (tester) async {
    final config = LatestEventBoardContent(
      eventSourceId: 'event',
      fields: [
        BoardDataField(key: 'custom', label: 'Custom field'),
        BoardDataField(
          key: 'at',
          label: 'Hora',
          format: BoardFieldFormat.dateTime,
        ),
      ],
    );
    await pump(
      tester,
      render(
        board([cell(config, w: 6)]),
        data: PreviewBoardDataProvider(
          sources: {
            'event': {'custom': 'Value', 'at': DateTime(2026, 9, 12, 10, 5)},
          },
        ),
      ),
    );
    expect(find.text('Custom field'), findsOneWidget);
    expect(find.text('Value'), findsOneWidget);
    expect(find.text('12/09 10:05'), findsOneWidget);
  });
  testWidgets('embedded table header maxRows and column flex', (tester) async {
    DataTableBoardContent config(bool header) => DataTableBoardContent(
      dataSourceId: 'rows',
      columns: [
        BoardTableColumn(
          field: BoardDataField(key: 'a', label: 'A'),
          flex: 1,
        ),
        BoardTableColumn(
          field: BoardDataField(key: 'b', label: 'B'),
          flex: 3,
        ),
      ],
      maxRows: 2,
      showHeader: header,
    );
    final data = PreviewBoardDataProvider(
      sources: {
        'rows': [
          {'a': 'first', 'b': 'one'},
          {'a': 'second', 'b': 'two'},
          {'a': 'third', 'b': 'three'},
        ],
      },
    );
    await pump(
      tester,
      render(board([cell(config(true), w: 6, h: 2)]), data: data),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('third'), findsNothing);
    final flexes = tester
        .widgetList<Expanded>(
          find.descendant(
            of: find.byType(DataTableBoardRenderer),
            matching: find.byType(Expanded),
          ),
        )
        .map((e) => e.flex)
        .toList();
    expect(flexes, [1, 3, 1, 3, 1, 3]);
    await pump(
      tester,
      render(board([cell(config(false), w: 6, h: 2)]), data: data),
    );
    expect(find.text('A'), findsNothing);
  });
  for (final severity in PreviewSeverity.values) {
    testWidgets('status ${severity.name}', (tester) async {
      await pump(
        tester,
        render(
          board([cell(StatusBoardContent(dataSourceId: 'state'), w: 2)]),
          data: PreviewBoardDataProvider(
            sources: {'state': PreviewStatus('state', 'State label', severity)},
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('State label')).style!.color,
        StatusBoardRenderer.severityColor(severity),
      );
    });
  }
  testWidgets('text and chart placeholder dispatch', (tester) async {
    await pump(
      tester,
      render(
        board([
          cell(TextBoardContent(text: 'Plain text')),
          cell(
            ChartBoardContent(
              dataSourceId: 'chart',
              chartType: BoardChartType.line,
              series: [BoardChartSeries(key: 'a', label: 'Serie')],
            ),
            id: 'chart',
            x: 1,
            w: 3,
          ),
        ]),
      ),
    );
    expect(find.text('Plain text'), findsOneWidget);
    expect(find.text('Visualización pendiente'), findsOneWidget);
    expect(boardRendererRegistry.length, 9);
  });
  for (final scenario in [
    'metric_not_found',
    'cell_preset_not_found',
    'placement_collision',
    'placement_out_of_bounds',
    'indicator_not_available',
  ]) {
    testWidgets('diagnostic $scenario', (tester) async {
      final items = switch (scenario) {
        'metric_not_found' => [cell(MetricBoardContent(metricKey: 'missing'))],
        'cell_preset_not_found' => [
          cell(
            MetricBoardContent(
              metricKey: 'tempInterior',
              cellLayoutPresetId: 'missing',
            ),
          ),
        ],
        'placement_collision' => [
          cell(TextBoardContent(text: 'a')),
          cell(TextBoardContent(text: 'b'), id: 'second'),
        ],
        'placement_out_of_bounds' => [cell(TextBoardContent(text: 'a'), x: 6)],
        _ => [
          cell(
            MetricBoardContent(
              metricKey: 'tempInterior',
              indicatorKeys: ['missing'],
            ),
          ),
        ],
      };
      await pump(tester, render(board(items)));
      expect(find.textContaining(scenario), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'missing provider and unsupported serialized type are diagnostics',
    (tester) async {
      await pump(
        tester,
        render(board([cell(StatusBoardContent(dataSourceId: 'missing'))])),
      );
      expect(find.textContaining('data_source_missing'), findsOneWidget);
      final map = board([cell(TextBoardContent(text: 'a'))]).toMap();
      ((map['items'] as List).first as Map)['type'] = 'unknown';
      await pump(
        tester,
        BoardContentRenderer.fromMap(
          map: map,
          template: grid(),
          catalog: referenceMetricCatalogById('environment_room_v1')!,
          data: samplePreviewData,
          deviceName: 'Demo',
        ),
      );
      expect(find.textContaining('unsupported_content_type'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 1100.0]) {
    for (var i = 0; i < 3; i++) {
      testWidgets('fixture $i at width $width', (tester) async {
        tester.view.physicalSize = Size(width, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: BoardPreviewPage(isOwner: true, initialIndex: i),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BoardContentRenderer), findsOneWidget);
        expect(find.byType(PreviewDiagnostic), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('owner guard selector and debug default off', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BoardPreviewPage(isOwner: false)),
    );
    expect(find.text('Preview disponible solo para owner'), findsOneWidget);
    expect(find.byType(BoardContentRenderer), findsNothing);
    await tester.pumpWidget(
      const MaterialApp(home: BoardPreviewPage(isOwner: true)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BoardContentRenderer>(find.byType(BoardContentRenderer))
          .showGrid,
      isFalse,
    );
    await tester.tap(find.text('Laboratorio'));
    await tester.pumpAndSettle();
    expect(find.text('Laboratorio · demo'), findsOneWidget);
    await tester.tap(find.text('Mostrar grilla'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BoardContentRenderer>(find.byType(BoardContentRenderer))
          .showGrid,
      isTrue,
    );
    await tester.tap(find.text('Arco'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageBoardRenderer), findsOneWidget);
    expect(find.byType(DataTableBoardRenderer), findsOneWidget);
  });
}
