import 'package:agro_data_control/board_preview/board_render_config.dart';
import 'package:agro_data_control/board_preview/cell_layout_canvas.dart';
import 'package:agro_data_control/board_preview/preview_board_data.dart';
import 'package:agro_data_control/cell_layout_presets/cell_content_resolver.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_editor_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset_catalog.dart';
import 'package:agro_data_control/device_capabilities/global_capability_catalog.dart';
import 'package:agro_data_control/device_capabilities/reference_capability_seeds.dart';
import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';
import 'package:agro_data_control/ui_templates/models/template_data_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceMetricCatalog _catalog() => buildGlobalCapabilityCatalog(
  metrics: sharedMetricLibraryStore,
  indicators: sharedIndicatorLibraryStore,
);

CellLayoutElement _value(CellSizeRole role) => CellLayoutElement(
  id: 'value',
  type: CellElementType.value,
  placement: InternalGridPlacement(x: 0, y: 0, widthUnits: 32, heightUnits: 16),
  sizeRole: role,
  textStyle: CellTextStyle(
    fontRole: CellFontRole.primaryValue,
    weight: CellFontWeight.bold,
  ),
);

Widget _canvas({
  required double width,
  required double height,
  required String text,
  required CellSizeRole role,
  String id = 'fit',
}) {
  final catalog = _catalog();
  final metric = catalog.metricByKey('tempInterior')!;
  final element = _value(role);
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: CellLayoutCanvas(
            columns: 32,
            rows: 16,
            resolved: [ResolvedCellElement(element: element)],
            catalog: catalog,
            data: PreviewBoardDataProvider(
              metricData: TemplateDataContext(
                source: {metric.sourceField: text},
              ),
            ),
            metric: metric,
            itemIdForKeys: id,
          ),
        ),
      ),
    ),
  );
}

double _renderedFont(WidgetTester tester, String id) => tester
    .widget<Text>(find.byKey(ValueKey('metric-$id-value')))
    .style!
    .fontSize!;

void main() {
  testWidgets('A — fit usa más espacio que hero en una celda grande', (
    tester,
  ) async {
    await tester.pumpWidget(
      _canvas(
        width: 400,
        height: 200,
        text: '24.6',
        role: CellSizeRole.hero,
        id: 'hero',
      ),
    );
    await tester.pumpAndSettle();
    final hero = _renderedFont(tester, 'hero');

    await tester.pumpWidget(
      _canvas(
        width: 400,
        height: 200,
        text: '24.6',
        role: CellSizeRole.fit,
        id: 'fit',
      ),
    );
    await tester.pumpAndSettle();
    final fit = _renderedFont(tester, 'fit');
    expect(fit, greaterThan(hero));
    expect(fit, lessThanOrEqualTo(cellFitMaxFontSize));
    expect(find.byType(OverflowBox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('A2 — reducir sólo el alto libre no achica antes de tocar el glifo', () {
    final tall = fittedCellFontSize(
      text: '24.6',
      maxWidth: 240,
      maxHeight: 180,
      fontWeight: FontWeight.w800,
    );
    final shorter = fittedCellFontSize(
      text: '24.6',
      maxWidth: 240,
      maxHeight: 100,
      fontWeight: FontWeight.w800,
    );
    final tooShort = fittedCellFontSize(
      text: '24.6',
      maxWidth: 240,
      maxHeight: 30,
      fontWeight: FontWeight.w800,
    );

    expect(shorter, tall);
    expect(tooShort, lessThan(shorter));
  });

  testWidgets('B — texto largo reduce automáticamente sin overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _canvas(
        width: 400,
        height: 200,
        text: '24.6',
        role: CellSizeRole.fit,
        id: 'short',
      ),
    );
    await tester.pumpAndSettle();
    final short = _renderedFont(tester, 'short');

    await tester.pumpWidget(
      _canvas(
        width: 400,
        height: 200,
        text: '12345678901234567890',
        role: CellSizeRole.fit,
        id: 'long',
      ),
    );
    await tester.pumpAndSettle();
    expect(_renderedFont(tester, 'long'), lessThan(short));
    expect(find.byType(OverflowBox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C — el mismo contenido crece de span 2×1 a 4×2', (tester) async {
    await tester.pumpWidget(
      _canvas(
        width: 200,
        height: 100,
        text: '24.6',
        role: CellSizeRole.fit,
        id: 'small-span',
      ),
    );
    await tester.pumpAndSettle();
    final small = _renderedFont(tester, 'small-span');

    await tester.pumpWidget(
      _canvas(
        width: 400,
        height: 200,
        text: '24.6',
        role: CellSizeRole.fit,
        id: 'large-span',
      ),
    );
    await tester.pumpAndSettle();
    expect(_renderedFont(tester, 'large-span'), greaterThan(small));
  });

  testWidgets('D/F — selector, guardado, serialización y reapertura', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = CellLayoutPresetCatalog(initial: const []);
    final preset = catalog.create(name: 'Fit 4 × 2', width: 4, height: 2);

    Future<void> open(CellLayoutPresetCatalog source) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: CellLayoutEditorPage(
            key: UniqueKey(),
            isOwner: true,
            presetId: preset.id,
            catalog: source,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cell-editor-element-value')));
      await tester.pumpAndSettle();
    }

    await open(catalog);
    await tester.tap(find.byKey(const ValueKey('cell-editor-size-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajustar a la celda').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cell-editor-fit-help')), findsOneWidget);
    expect(find.byType(OverflowBox), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('cell-editor-save')));
    await tester.pumpAndSettle();

    final serialized = catalog.byId(preset.id)!.toMap();
    final restoredPreset = CellLayoutPreset.fromMap(serialized);
    expect(
      restoredPreset.elements.firstWhere((e) => e.id == 'value').sizeRole,
      CellSizeRole.fit,
    );
    final restored = CellLayoutPresetCatalog(initial: [restoredPreset]);
    await open(restored);
    expect(
      tester
          .widget<DropdownButton<CellSizeRole>>(
            find.byKey(const ValueKey('cell-editor-size-role')),
          )
          .value,
      CellSizeRole.fit,
    );
    expect(find.byKey(const ValueKey('cell-editor-fit-help')), findsOneWidget);
  });

  test('E — tamaños fijos conservan sus factores y documentos viejos', () {
    expect(BoardRenderConfig.elementSize(CellSizeRole.sm, 8), 6);
    expect(BoardRenderConfig.elementSize(CellSizeRole.md, 8), 8);
    expect(BoardRenderConfig.elementSize(CellSizeRole.lg, 8), 12);
    expect(BoardRenderConfig.elementSize(CellSizeRole.hero, 8), 32);

    final old = CellLayoutPreset(
      id: 'old',
      name: 'Viejo',
      widthCells: 1,
      heightCells: 1,
      elements: [_value(CellSizeRole.hero)],
    );
    expect(
      CellLayoutPreset.fromMap(old.toMap()).elements.single.sizeRole,
      CellSizeRole.hero,
    );
  });

  test('fit sólo es válido para el elemento principal value', () {
    expect(
      () => CellLayoutElement(
        id: 'unit',
        type: CellElementType.unit,
        placement: InternalGridPlacement(
          x: 0,
          y: 0,
          widthUnits: 1,
          heightUnits: 1,
        ),
        sizeRole: CellSizeRole.fit,
      ),
      throwsA(anything),
    );
  });
}
