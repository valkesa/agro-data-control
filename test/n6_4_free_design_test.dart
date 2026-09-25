import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/board_preview/board_editor_canvas.dart';
import 'package:agro_data_control/board_preview/board_editor_controller.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset_catalog.dart';
import 'package:agro_data_control/device_capabilities/reference_capability_seeds.dart';
import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

BoardEditorController _liveController(WidgetTester tester) =>
    tester.widget<BoardEditorCanvas>(find.byType(BoardEditorCanvas)).controller;

Future<void> openAgregarTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
  await tester.pumpAndSettle();
}

Future<void> openBoardTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor-side-tab-board')));
  await tester.pumpAndSettle();
}

Future<void> openSelectedTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor-side-tab-selected')));
  await tester.pumpAndSettle();
}

/// N6.4 §21 "Sin catálogo": a real, empty capability catalog — never a
/// fabricated one hiding behind a nonempty one.
final emptyMetricCatalog = DeviceMetricCatalog(
  id: 'empty',
  name: 'Vacío',
  metrics: [],
);

BoardEditorPage freePreset({
  required BoardPresetCatalog catalog,
  required String presetId,
  DeviceMetricCatalog? metricCatalog,
}) => BoardEditorPage(
  isOwner: true,
  presetId: presetId,
  presetCatalog: catalog,
  metricCatalog: metricCatalog ?? emptyMetricCatalog,
);

(BoardPresetCatalog, BoardPreset) newFreePreset({String name = 'Libre'}) {
  final catalog = BoardPresetCatalog(initial: []);
  final preset = catalog.create(name: name, layout: buildLayoutTemplate(6, 7));
  return (catalog, preset);
}

void main() {
  group('N6.4 §21 — Placeholder', () {
    testWidgets('crear sin metricKey, renderiza, mover, resize, eliminar', (
      tester,
    ) async {
      final (catalog, preset) = newFreePreset();
      await pump(tester, freePreset(catalog: catalog, presetId: preset.id));
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(
        find.byKey(const ValueKey('editor-add-type-placeholder')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('editor-pending-placeholder-label')),
        'Vehículos hoy',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final item = catalog.byId(preset.id)!.items.single;
      expect(item.content, isA<PlaceholderBoardContent>());
      expect((item.content as PlaceholderBoardContent).label, 'Vehículos hoy');
      expect(find.text('Vehículos hoy'), findsWidgets);

      // Move.
      await openBoardTab(tester);
      await tester.tap(find.byKey(ValueKey('editor-item-row-${item.id}')));
      await tester.pumpAndSettle();
      await openSelectedTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-move-right')));
      await tester.pumpAndSettle();
      expect(_liveController(tester).selectedItem!.placement.x, 1);
      expect(tester.takeException(), isNull);

      // Resize.
      await tester.tap(find.byKey(const ValueKey('editor-width-plus')));
      await tester.pumpAndSettle();
      expect(_liveController(tester).selectedItem!.placement.widthCells, 2);
      expect(tester.takeException(), isNull);

      // Delete.
      await tester.tap(find.byKey(const ValueKey('editor-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-delete-confirm')));
      await tester.pumpAndSettle();
      expect(catalog.byId(preset.id)!.items, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mockValue/unit/icon se editan y renderizan sin crash', (
      tester,
    ) async {
      final (catalog, preset) = newFreePreset();
      await pump(tester, freePreset(catalog: catalog, presetId: preset.id));
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(
        find.byKey(const ValueKey('editor-add-type-placeholder')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('editor-pending-placeholder-mock')),
        '12',
      );
      await tester.enterText(
        find.byKey(const ValueKey('editor-pending-placeholder-unit')),
        'u',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();
      final content =
          catalog.byId(preset.id)!.items.single.content
              as PlaceholderBoardContent;
      expect(content.mockValue, '12');
      expect(content.unit, 'u');
      expect(find.text('12'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('N6.4 §21 — Icon', () {
    testWidgets('crear sin metric, renderiza, sizeRole hero, alignment', (
      tester,
    ) async {
      final (catalog, preset) = newFreePreset();
      await pump(tester, freePreset(catalog: catalog, presetId: preset.id));
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-icon')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-pending-icon-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('hero').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-pending-icon-h-align')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('end').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final content =
          catalog.byId(preset.id)!.items.single.content as IconBoardContent;
      expect(content.sizeRole.name, 'hero');
      expect(content.horizontalAlignment.name, 'end');
    });
  });

  group('N6.4 §21 — Text', () {
    testWidgets('crear/editar, hero, maxLines', (tester) async {
      final (catalog, preset) = newFreePreset();
      await pump(tester, freePreset(catalog: catalog, presetId: preset.id));
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-text')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('editor-pending-text')),
        'Arco de desinfección',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-pending-text-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('hero').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-pending-text-maxlines-plus')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final content =
          catalog.byId(preset.id)!.items.single.content as TextBoardContent;
      expect(content.text, 'Arco de desinfección');
      expect(content.sizeRole.name, 'hero');
      expect(content.maxLines, 4);

      // Editing after the fact also works.
      await openBoardTab(tester);
      final id = catalog.byId(preset.id)!.items.single.id;
      await tester.tap(find.byKey(ValueKey('editor-item-row-$id')));
      await tester.pumpAndSettle();
      await openSelectedTab(tester);
      await tester.enterText(
        find.byKey(const ValueKey('editor-edit-text')),
        'Editado',
      );
      await tester.pumpAndSettle();
      expect(
        (catalog.byId(preset.id)!.items.single.content as TextBoardContent)
            .text,
        'Editado',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('N6.4 §21/§23 — Conversión placeholder -> metric', () {
    testWidgets('preserva placement/span (id, x, y, width, height)', (
      tester,
    ) async {
      final (catalog, preset) = newFreePreset();
      final referenceCatalog = referenceCapabilityProfile.resolve(
        sharedMetricLibraryStore,
        sharedIndicatorLibraryStore,
      );
      await pump(
        tester,
        freePreset(
          catalog: catalog,
          presetId: preset.id,
          metricCatalog: referenceCatalog,
        ),
      );
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(
        find.byKey(const ValueKey('editor-add-type-placeholder')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-pending-x-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-pending-x-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-pending-y-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-pending-width-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();

      final before = catalog.byId(preset.id)!.items.single;
      expect(before.placement.x, 2);
      expect(before.placement.y, 1);
      expect(before.placement.widthCells, 2);
      expect(before.placement.heightCells, 1);

      await openBoardTab(tester);
      await tester.tap(find.byKey(ValueKey('editor-item-row-${before.id}')));
      await tester.pumpAndSettle();
      await openSelectedTab(tester);
      await tester.tap(
        find.byKey(const ValueKey('editor-convert-placeholder-to-metric')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-convert-confirm')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final after = catalog.byId(preset.id)!.items.single;
      expect(after.id, before.id);
      expect(after.placement.x, before.placement.x);
      expect(after.placement.y, before.placement.y);
      expect(after.placement.widthCells, before.placement.widthCells);
      expect(after.placement.heightCells, before.placement.heightCells);
      expect(after.content, isA<MetricBoardContent>());
    });

    testWidgets('placeholder sin binding es válido (no exige metricKey)', (
      tester,
    ) async {
      final content = PlaceholderBoardContent(label: 'Estado');
      expect(content.mockValue, isNull);
      expect(content.unit, isNull);
      expect(content.iconKey, isNull);
    });

    testWidgets(
      'catálogo vacío: Convertir a métrica no ofrece nada, no crashea, '
      'conserva el placeholder',
      (tester) async {
        final (catalog, preset) = newFreePreset();
        await pump(tester, freePreset(catalog: catalog, presetId: preset.id));
        await tester.pumpAndSettle();
        await openAgregarTab(tester);
        await tester.tap(
          find.byKey(const ValueKey('editor-add-type-placeholder')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
        await tester.pumpAndSettle();

        await openBoardTab(tester);
        final id = catalog.byId(preset.id)!.items.single.id;
        await tester.tap(find.byKey(ValueKey('editor-item-row-$id')));
        await tester.pumpAndSettle();
        await openSelectedTab(tester);
        await tester.tap(
          find.byKey(const ValueKey('editor-convert-placeholder-to-metric')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('No hay métricas disponibles en el perfil actual.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('editor-convert-confirm')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          catalog.byId(preset.id)!.items.single.content,
          isA<PlaceholderBoardContent>(),
        );
      },
    );
  });

  group('N6.4 §21 — Sin catálogo de métricas', () {
    testWidgets('BoardPreset con 0 métricas disponibles igual permite agregar '
        'text/icon/image/placeholder', (tester) async {
      final (catalog, preset) = newFreePreset();
      await pump(tester, freePreset(catalog: catalog, presetId: preset.id));
      await tester.pumpAndSettle();
      expect(_liveController(tester).catalog.metrics, isEmpty);

      for (final type in ['text', 'icon', 'image', 'placeholder']) {
        await openAgregarTab(tester);
        await tester.tap(find.byKey(ValueKey('editor-add-type-$type')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: type);
      }
      expect(catalog.byId(preset.id)!.items, hasLength(4));
    });
  });

  group('N6.4 §22 — Arco demo libre (sin DeviceMetricCatalog real)', () {
    testWidgets(
      'hero image + 2 placeholders KPI + status/latestEvent/dataTable '
      'demo-unbound, cero crash, cero metricKey obligatorio',
      (tester) async {
        final catalog = BoardPresetCatalog(initial: []);
        final preset = catalog.create(
          name: 'Arco demo libre',
          layout: buildLayoutTemplate(6, 7),
        );
        await pump(tester, freePreset(catalog: catalog, presetId: preset.id));
        await tester.pumpAndSettle();

        Future<void> add(String type, {VoidCallback? configure}) async {
          await openAgregarTab(tester);
          await tester.tap(find.byKey(ValueKey('editor-add-type-$type')));
          await tester.pumpAndSettle();
          if (configure != null) configure();
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: type);
        }

        // Hero image.
        await add('image');
        // KPI 1.
        await add('placeholder');
        // KPI 2.
        await add('placeholder');
        // status demo/unbound stays unbound by default.
        await add('status');
        // latestEvent: switch to demo before confirming.
        await openAgregarTab(tester);
        await tester.tap(
          find.byKey(const ValueKey('editor-add-type-latestEvent')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('editor-pending-binding-demo')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // dataTable stays unbound.
        await add('dataTable');

        final items = catalog.byId(preset.id)!.items;
        expect(items, hasLength(6));
        expect(
          items.where((i) => i.content is ImageBoardContent),
          hasLength(1),
        );
        expect(
          items.where((i) => i.content is PlaceholderBoardContent),
          hasLength(2),
        );
        final status =
            items.firstWhere((i) => i.content is StatusBoardContent).content
                as StatusBoardContent;
        expect(status.bindingMode, BoardBindingMode.unbound);
        final event =
            items
                    .firstWhere((i) => i.content is LatestEventBoardContent)
                    .content
                as LatestEventBoardContent;
        expect(event.bindingMode, BoardBindingMode.demo);
        final table =
            items.firstWhere((i) => i.content is DataTableBoardContent).content
                as DataTableBoardContent;
        expect(table.bindingMode, BoardBindingMode.unbound);

        // Preview never crashes with zero real metrics/sources bound.
        await tester.tap(find.byKey(const ValueKey('editor-toggle-mode')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('N6.4 §24 — referencia compartida de CellLayoutPreset', () {
    testWidgets(
      'itemA y itemB comparten presetLocalX: Editar diseño desde itemA '
      'detecta que itemB también lo usa',
      (tester) async {
        final shared = sharedCellLayoutPresetCatalog.create(
          name: 'Compartido N6.4',
          width: 1,
          height: 1,
        );
        final layout = buildLayoutTemplate(4, 4);
        final itemA = BoardContentItem(
          id: 'itemA',
          content: MetricBoardContent(
            metricKey: 'tempInterior',
            cellLayoutPresetId: shared.id,
          ),
          placement: GridPlacement(x: 0, y: 0, widthCells: 1, heightCells: 1),
        );
        final itemB = BoardContentItem(
          id: 'itemB',
          content: MetricBoardContent(
            metricKey: 'humedadInterior',
            cellLayoutPresetId: shared.id,
          ),
          placement: GridPlacement(x: 1, y: 0, widthCells: 1, heightCells: 1),
        );
        final preset = BoardPreset(
          id: 'preset-shared-n64',
          name: 'Con hermanos',
          layoutTemplateId: layout.id,
          items: [itemA, itemB],
        );
        final catalog = BoardPresetCatalog(initial: [preset]);
        await pump(
          tester,
          freePreset(
            catalog: catalog,
            presetId: preset.id,
            metricCatalog: referenceCapabilityProfile.resolve(
              sharedMetricLibraryStore,
              sharedIndicatorLibraryStore,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await openBoardTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-item-row-itemA')));
        await tester.pumpAndSettle();
        await openSelectedTab(tester);
        await tester.tap(
          find.byKey(const ValueKey('editor-open-cell-layout-editor')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cell-editor-duplicate')),
          findsOneWidget,
          reason:
              'itemB still uses the same design, so editing itemA must warn',
        );
      },
    );
  });
}
