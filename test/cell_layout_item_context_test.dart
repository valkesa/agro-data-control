import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_editor_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset_catalog.dart';
import 'package:agro_data_control/device_capabilities/global_capability_catalog.dart';
import 'package:agro_data_control/device_capabilities/reference_capability_seeds.dart';
import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
  await tester.pumpAndSettle();
}

DeviceMetricCatalog _globalCatalog() => buildGlobalCapabilityCatalog(
  metrics: sharedMetricLibraryStore,
  indicators: sharedIndicatorLibraryStore,
);

CellLayoutPreset _layout() => CellLayoutPreset(
  id: 'water-layout-4x2',
  name: 'Agua 4 × 2',
  widthCells: 4,
  heightCells: 2,
  elements: buildDefaultCellLayoutElements(4, 2),
);

CellLayoutItemContext _context({List<String> indicators = const []}) {
  final catalog = _globalCatalog();
  final metric = catalog.metricByKey('agua')!;
  return CellLayoutItemContext(
    itemId: 'water-item',
    content: MetricBoardContent(
      metricKey: 'agua',
      cellLayoutPresetId: 'water-layout-4x2',
      indicatorKeys: indicators,
    ),
    metric: metric,
    catalog: catalog,
    effectiveLayout: _layout(),
    widthCells: 4,
    heightCells: 2,
  );
}

void main() {
  testWidgets('A/B — muestra Agua y solo humidificacion, nunca temperatura', (
    tester,
  ) async {
    final catalog = CellLayoutPresetCatalog(initial: [_layout()]);
    await _pump(
      tester,
      CellLayoutEditorPage(
        isOwner: true,
        presetId: _layout().id,
        catalog: catalog,
        itemContext: _context(indicators: const ['humidificacion']),
        onItemSnapshotSaved: (_) {},
      ),
    );

    expect(find.text('Editando diseño del item: Agua'), findsOneWidget);
    expect(find.text('Span externo: 4 × 2'), findsOneWidget);
    expect(find.text('Indicators activos: humidificacion'), findsOneWidget);
    expect(
      find.textContaining('Preview contextual: Agua · 123'),
      findsOneWidget,
    );
    expect(find.byTooltip('humidificacion: activo'), findsOneWidget);
    expect(find.textContaining('Temperatura interior'), findsNothing);
    expect(find.byTooltip('calefaccionEtapa1: activo'), findsNothing);
    expect(find.byTooltip('calefaccionEtapa2: activo'), findsNothing);
  });

  testWidgets('C — sin indicators no inventa activos en slots disponibles', (
    tester,
  ) async {
    final catalog = CellLayoutPresetCatalog(initial: [_layout()]);
    await _pump(
      tester,
      CellLayoutEditorPage(
        isOwner: true,
        presetId: _layout().id,
        catalog: catalog,
        itemContext: _context(),
        onItemSnapshotSaved: (_) {},
      ),
    );

    expect(find.text('Indicators activos: ninguno'), findsOneWidget);
    expect(find.text('Slots disponibles en el diseño: 3'), findsOneWidget);
    expect(find.byTooltip('humidificacion: activo'), findsNothing);
  });

  testWidgets(
    'D/E — editar A guarda snapshot, no muta global/B y persiste al reabrir',
    (tester) async {
      final cellCatalog = CellLayoutPresetCatalog(initial: [_layout()]);
      final globalBefore = cellCatalog.byId(_layout().id)!.toMap();
      final template = buildLayoutTemplate(8, 4);
      final itemA = BoardContentItem(
        id: 'water-a',
        placement: GridPlacement(x: 0, y: 0, widthCells: 4, heightCells: 2),
        content: MetricBoardContent(
          metricKey: 'agua',
          cellLayoutPresetId: _layout().id,
          indicatorKeys: const ['humidificacion'],
        ),
      );
      final itemB = BoardContentItem(
        id: 'water-b',
        placement: GridPlacement(x: 4, y: 0, widthCells: 4, heightCells: 2),
        content: MetricBoardContent(
          metricKey: 'agua',
          cellLayoutPresetId: _layout().id,
        ),
      );
      final preset = BoardPreset(
        id: 'water-board',
        name: 'Agua contextual',
        layoutTemplateId: template.id,
        items: [itemA, itemB],
      );
      final boards = BoardPresetCatalog(initial: [preset]);
      await _pump(
        tester,
        BoardEditorPage(
          isOwner: true,
          presetId: preset.id,
          presetCatalog: boards,
          presets: CellLayoutCatalog([_layout()]),
          cellLayoutPresetCatalog: cellCatalog,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('editor-item-row-water-a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-open-cell-layout-editor')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cell-editor-element-value')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cell-editor-size-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajustar a la celda').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cell-editor-element-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cell-editor-move-right')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cell-editor-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volver al Board'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-preset-save')));
      await tester.pumpAndSettle();

      final saved = boards.byId(preset.id)!;
      final savedA = saved.items.first.content as MetricBoardContent;
      final savedB = saved.items.last.content as MetricBoardContent;
      expect(savedA.cellLayoutSnapshot, isNotNull);
      expect(
        savedA.cellLayoutSnapshot!.elements
            .firstWhere((element) => element.id == 'value')
            .sizeRole,
        CellSizeRole.fit,
      );
      expect(savedB.cellLayoutSnapshot, isNull);
      expect(saved.items.last.toMap(), itemB.toMap());
      expect(cellCatalog.byId(_layout().id)!.toMap(), globalBefore);
      final movedX = savedA.cellLayoutSnapshot!.elements
          .firstWhere((element) => element.id == 'unit')
          .placement
          .x;

      final restored = BoardPreset.fromMap(saved.toMap());
      await tester.pumpWidget(const SizedBox());
      final reopened = BoardPresetCatalog(initial: [restored]);
      await _pump(
        tester,
        BoardEditorPage(
          isOwner: true,
          presetId: restored.id,
          presetCatalog: reopened,
          presets: CellLayoutCatalog([_layout()]),
          cellLayoutPresetCatalog: cellCatalog,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('editor-item-row-water-a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-open-cell-layout-editor')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Editando diseño del item: Agua'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cell-editor-element-value')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<CellSizeRole>>(
              find.byKey(const ValueKey('cell-editor-size-role')),
            )
            .value,
        CellSizeRole.fit,
      );
      final reopenedContent =
          reopened.presets.single.items.first.content as MetricBoardContent;
      expect(
        reopenedContent.cellLayoutSnapshot!.elements
            .firstWhere((element) => element.id == 'unit')
            .placement
            .x,
        movedX,
      );
    },
  );

  testWidgets('F — modo global identifica el preview como ficticio', (
    tester,
  ) async {
    final catalog = CellLayoutPresetCatalog(initial: [_layout()]);
    await _pump(
      tester,
      CellLayoutEditorPage(
        isOwner: true,
        presetId: _layout().id,
        catalog: catalog,
      ),
    );
    expect(
      find.text('Modo globalPreset · preview ficticio de referencia'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Preview ficticio de referencia'),
      findsOneWidget,
    );
  });

  test('previewValueFor no usa temperatura como mock universal', () {
    final agua = _globalCatalog().metricByKey('agua')!;
    final temperatura = _globalCatalog().metricByKey('tempInterior')!;
    expect(previewValueFor(agua), 123);
    expect(previewValueFor(temperatura), 24.6);
  });
}
