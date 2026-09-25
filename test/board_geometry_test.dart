import 'package:flutter/gestures.dart';
import 'package:agro_data_control/board_preview/board_preview_page.dart';
import 'package:agro_data_control/board_preview/board_preview_card.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_preview/board_render_config.dart';
import 'package:agro_data_control/board_preview/board_content_renderer.dart';
import 'package:agro_data_control/board_preview/preview_board_data.dart';
import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/device_metric_catalogs/reference_metric_catalogs.dart';
import 'board_preview_test.dart' as f;

Rect painted(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

void main() {
  for (final span in [(1, 1), (2, 1), (1, 2), (2, 2), (3, 1)]) {
    testWidgets('square external and internal units ${span.$1}x${span.$2}', (
      tester,
    ) async {
      await f.pump(
        tester,
        f.render(
          f.board([
            f.cell(
              MetricBoardContent(metricKey: 'tempInterior'),
              w: span.$1,
              h: span.$2,
            ),
          ]),
        ),
      );
      final external = tester.widget<Positioned>(
        find.byKey(const ValueKey('placement-cell')),
      );
      expect(external.width! / span.$1, external.height! / span.$2);
      final internal = painted(
        tester,
        find.byKey(const ValueKey('cell-internal-grid')),
      );
      expect(
        internal.width / (8 * span.$1),
        closeTo(internal.height / (8 * span.$2), 1e-8),
      );
      expect(
        internal.width / internal.height,
        closeTo(span.$1 / span.$2, 1e-8),
      );
    });
  }
  testWidgets(
    'fixed left-aligned desktop, whole board uniform narrow scaling',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [1440.0, 1100.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1200);
        await f.pump(
          tester,
          f.render(
            f.board([
              f.cell(MetricBoardContent(metricKey: 'tempInterior'), w: 2, h: 2),
            ], showTitle: false),
          ),
          width: width,
        );
        final r = painted(tester, find.byKey(const ValueKey('board-grid')));
        final scale = width < 408 ? width / 408 : 1.0;
        expect(r.width, closeTo(408 * scale, 1e-6));
        expect(r.height, closeTo(272 * scale, 1e-6));
        expect(r.left, closeTo(0, 1e-6));
        final text = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey('metric-cell-value')),
        );
        final transform = text.getTransformTo(null);
        expect(transform.entry(0, 0), closeTo(scale, 1e-6));
        expect(transform.entry(1, 1), closeTo(scale, 1e-6));
        expect(tester.takeException(), isNull);
      }
    },
  );
  test('v1 migration and strict v2 visual roundtrip', () {
    final map = initialCellLayoutCatalog.byId('default_2x2')!.toMap();
    map['schemaVersion'] = 1;
    for (final e in map['elements']! as List) {
      (e as Map).remove('visibility');
      e.remove('sizeRole');
    }
    final migrated = CellLayoutPreset.fromMap(map);
    expect(migrated.schemaVersion, 2);
    expect(
      migrated.elements.every((e) => e.visibility == CellVisibility.visible),
      isTrue,
    );
    expect(
      CellLayoutPreset.fromMap(migrated.toMap()).toMap(),
      migrated.toMap(),
    );
    for (final field in ['visibility', 'sizeRole']) {
      final element = migrated.elements.first.toMap();
      expect(
        () => CellLayoutElement.fromMap(element..[field] = 'unknown'),
        throwsArgumentError,
      );
      expect(
        () => CellLayoutElement.fromMap(element..remove(field)),
        throwsArgumentError,
      );
    }
  });
  testWidgets('all element kinds obey visual roles visibility and alignment', (
    tester,
  ) async {
    final original = initialCellLayoutCatalog.byId('icon_value_2x1')!;
    for (final hidden in [false, true]) {
      final map = original.toMap();
      for (final e in map['elements']! as List) {
        (e as Map)['visibility'] = hidden ? 'hidden' : 'visible';
        e['sizeRole'] = 'sm';
        e['horizontalAlignment'] = 'end';
        e['verticalAlignment'] = 'bottom';
        if (e['textStyle'] != null) {
          (e['textStyle'] as Map)['weight'] = 'medium';
          (e['textStyle'] as Map)['maxLines'] = 2;
        }
      }
      final preset = CellLayoutPreset.fromMap(map);
      await f.pump(
        tester,
        BoardContentRenderer(
          board: f.board([
            f.cell(
              MetricBoardContent(
                metricKey: 'tempInterior',
                cellLayoutPresetId: preset.id,
                indicatorKeys: ['calefaccionEtapa1', 'calefaccionEtapa2'],
              ),
              w: 2,
            ),
          ]),
          template: f.grid(),
          catalog: referenceMetricCatalogById('environment_room_v1')!,
          data: samplePreviewData,
          deviceName: 'Example',
          presets: CellLayoutCatalog([preset]),
        ),
      );
      for (final element in preset.elements) {
        final finder = find.byKey(ValueKey('cell-element-${element.id}'));
        expect(finder, hidden ? findsNothing : findsOneWidget);
        if (hidden || element.indicatorSlot == 2) continue;
        final fit = tester.widget<OverflowBox>(
          find.descendant(of: finder, matching: find.byType(OverflowBox)).first,
        );
        expect(fit.alignment, Alignment.bottomRight);
      }
      if (!hidden) {
        for (final kind in ['label', 'value', 'unit']) {
          final text = tester.widget<Text>(
            find.byKey(ValueKey('metric-cell-$kind')),
          );
          expect(text.style!.fontSize, 6.375);
          expect(text.style!.fontWeight, FontWeight.w500);
          expect(text.maxLines, 2);
          expect(text.textAlign, TextAlign.end);
        }
        final icons = tester.widgetList<Icon>(find.byType(Icon));
        expect(icons.every((i) => i.size == 6.375), isTrue);
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('runtime design width and invalid geometry diagnostic', (
    tester,
  ) async {
    for (final width in [72.0, 0.0, double.nan]) {
      await f.pump(
        tester,
        BoardContentRenderer(
          board: f.board([]),
          template: f.grid(),
          catalog: referenceMetricCatalogById('environment_room_v1')!,
          data: samplePreviewData,
          deviceName: 'Example',
          renderConfig: BoardRenderConfig(baseCellSize: width),
        ),
      );
      if (width == 72) {
        expect(
          tester.getSize(find.byKey(const ValueKey('board-grid'))).width,
          432,
        );
      } else {
        expect(
          find.byKey(const ValueKey('preview-diagnostic')),
          findsOneWidget,
        );
      }
    }
  });
  test('natural size grows by columns and rows, never by available width', () {
    for (final cell in [64.0, 68.0, 72.0, 76.0]) {
      final config = BoardRenderConfig(baseCellSize: cell);
      expect(config.naturalBoardWidth(6), 6 * cell);
      expect(config.naturalBoardWidth(10), 10 * cell);
      expect(config.naturalBoardHeight(4), 4 * cell);
      expect(config.scaleFor(1100, 6), 1);
      expect(config.scaleFor(1440, 6), 1);
      expect(config.scaleFor(320, 6), closeTo(320 / (6 * cell), 1e-8));
    }
  });
  testWidgets(
    'preview page keeps board at content left edge in every viewport',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [1440.0, 1100.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(
          const MaterialApp(
            home: BoardPreviewPage(isOwner: true, initialGrid: true),
          ),
        );
        await tester.pumpAndSettle();
        final rect = painted(tester, find.byKey(const ValueKey('board-grid')));
        expect(rect.left, closeTo(16, 1e-6));
        expect(rect.right, lessThanOrEqualTo(width - 16 + 1e-6));
        expect(find.textContaining('baseCellSize='), findsOneWidget);
        expect(find.textContaining('naturalBoardWidth='), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
  final contents = <BoardContentConfig>[
    MetricBoardContent(metricKey: 'tempInterior'),
    ImageBoardContent(
      sourceType: BoardImageSourceType.asset,
      sourceRef: 'test',
    ),
    LatestEventBoardContent(
      eventSourceId: 'event',
      fields: [BoardDataField(key: 'x', label: 'X')],
    ),
    DataTableBoardContent(
      dataSourceId: 'rows',
      columns: [
        BoardTableColumn(
          field: BoardDataField(key: 'x', label: 'X'),
        ),
      ],
    ),
    StatusBoardContent(dataSourceId: 'state'),
    TextBoardContent(text: 'Example'),
    ChartBoardContent(
      dataSourceId: 'chart',
      chartType: BoardChartType.line,
      series: [BoardChartSeries(key: 'x', label: 'X')],
    ),
  ];
  for (final content in contents) {
    testWidgets('common border and hover for ${content.type.name}', (
      tester,
    ) async {
      await f.pump(tester, f.render(f.board([f.cell(content)])));
      final shell = find.byType(BoardPreviewCard);
      expect(shell, findsOneWidget);
      Border border() =>
          (tester
                          .widget<DecoratedBox>(
                            find
                                .descendant(
                                  of: shell,
                                  matching: find.byType(DecoratedBox),
                                )
                                .last,
                          )
                          .decoration
                      as BoxDecoration)
                  .border!
              as Border;
      expect(border().top.color, BoardCardTokens.boardCardBorder);
      final before = painted(tester, shell);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(shell));
      await tester.pump();
      expect(border().top.color, BoardCardTokens.boardCardBorderHover);
      expect(border().top.width, BoardCardTokens.borderWidth);
      expect(painted(tester, shell), before);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(border().top.color, BoardCardTokens.boardCardBorder);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    });
  }

  test('renderer has no business-specific composition branches', () {
    final source = File(
      'lib/board_preview/board_item_renderers.dart',
    ).readAsStringSync();
    final metric = source
        .split('class MetricBoardRenderer')[1]
        .split('class ImageBoardRenderer')[0];
    expect(
      RegExp(
        r'(if|switch)\s*\([^)]*(metricKey|deviceId|tenant|widthCells|heightCells)',
      ).hasMatch(metric),
      isFalse,
    );
    for (final businessKey in [
      'tempInterior',
      'calefaccionEtapa1',
      'environment_room',
      'laboratorio',
    ]) {
      expect(metric, isNot(contains(businessKey)));
    }
  });
}
