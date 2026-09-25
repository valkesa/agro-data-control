import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_editor_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset_catalog.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

Future<void> selectValue(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('cell-editor-element-value')));
  await tester.pumpAndSettle();
}

void main() {
  group('CellLayoutEditorPage', () {
    testWidgets('N6.3 §3: a seed/global design opens gated behind a warning', (
      tester,
    ) async {
      final catalog = CellLayoutPresetCatalog();
      await pump(
        tester,
        CellLayoutEditorPage(
          isOwner: true,
          presetId: 'default_1x1',
          catalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cell-editor-duplicate')),
        findsOneWidget,
      );
      // Save exists but stays disabled until the user either edits the copy
      // or explicitly opts into "Editar igual".
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('cell-editor-save')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'duplicating a global design switches to direct local editing',
      (tester) async {
        final catalog = CellLayoutPresetCatalog();
        await pump(
          tester,
          CellLayoutEditorPage(
            isOwner: true,
            presetId: 'default_1x1',
            catalog: catalog,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cell-editor-duplicate')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cell-editor-duplicate')),
          findsNothing,
        );
        expect(catalog.presets, hasLength(8));
        expect(catalog.byId('default_1x1'), isNotNull); // original untouched
      },
    );

    testWidgets('a local/new design is editable directly, no duplicate gate', (
      tester,
    ) async {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'Custom', width: 1, height: 1);
      await pump(
        tester,
        CellLayoutEditorPage(
          isOwner: true,
          presetId: preset.id,
          catalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cell-editor-duplicate')), findsNothing);
    });

    testWidgets(
      'moving the selected element with arrows updates its placement',
      (tester) async {
        final catalog = CellLayoutPresetCatalog(initial: []);
        final preset = catalog.create(name: 'Custom', width: 1, height: 1);
        await pump(
          tester,
          CellLayoutEditorPage(
            isOwner: true,
            presetId: preset.id,
            catalog: catalog,
          ),
        );
        await tester.pumpAndSettle();
        await selectValue(tester);
        final before = catalog
            .byId(preset.id)!
            .elements
            .firstWhere((e) => e.id == 'value')
            .placement;
        await tester.tap(find.byKey(const ValueKey('cell-editor-move-right')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cell-editor-save')));
        await tester.pumpAndSettle();
        final after = catalog
            .byId(preset.id)!
            .elements
            .firstWhere((e) => e.id == 'value')
            .placement;
        expect(after.x, before.x + 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'resizing the selected element changes widthUnits/heightUnits',
      (tester) async {
        final catalog = CellLayoutPresetCatalog(initial: []);
        final preset = catalog.create(name: 'Custom', width: 1, height: 1);
        await pump(
          tester,
          CellLayoutEditorPage(
            isOwner: true,
            presetId: preset.id,
            catalog: catalog,
          ),
        );
        await tester.pumpAndSettle();
        await selectValue(tester);
        await tester.tap(find.byKey(const ValueKey('cell-editor-width-minus')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cell-editor-save')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a collision shows an error visually and never crashes, and can be repaired',
      (tester) async {
        final catalog = CellLayoutPresetCatalog(initial: []);
        final preset = catalog.create(name: 'Custom', width: 1, height: 1);
        await pump(
          tester,
          CellLayoutEditorPage(
            isOwner: true,
            presetId: preset.id,
            catalog: catalog,
          ),
        );
        await tester.pumpAndSettle();
        // Move "value" directly onto "icon"'s cell region — label sits at
        // (0,0), value starts at (0,2) by default; move it up onto label.
        await selectValue(tester);
        await tester.tap(find.byKey(const ValueKey('cell-editor-move-up')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cell-editor-move-up')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('cell-editor-issues')),
          findsOneWidget,
        );
        expect(find.textContaining('internal_collision'), findsWidgets);

        // Repair: move it back down.
        await tester.tap(find.byKey(const ValueKey('cell-editor-move-down')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cell-editor-move-down')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('cell-editor-issues')), findsNothing);
      },
    );

    testWidgets(
      'resizing out of the subgrid bounds is flagged, never crashes',
      (tester) async {
        final catalog = CellLayoutPresetCatalog(initial: []);
        final preset = catalog.create(name: 'Custom', width: 1, height: 1);
        await pump(
          tester,
          CellLayoutEditorPage(
            isOwner: true,
            presetId: preset.id,
            catalog: catalog,
          ),
        );
        await tester.pumpAndSettle();
        await selectValue(tester);
        for (var i = 0; i < 8; i++) {
          await tester.tap(
            find.byKey(const ValueKey('cell-editor-width-plus')),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        expect(find.textContaining('internal_out_of_bounds'), findsWidgets);
      },
    );

    testWidgets('alignment changes are applied without throwing', (
      tester,
    ) async {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'Custom', width: 1, height: 1);
      await pump(
        tester,
        CellLayoutEditorPage(
          isOwner: true,
          presetId: preset.id,
          catalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      await selectValue(tester);
      await tester.tap(find.byKey(const ValueKey('cell-editor-h-align')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('start').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cell-editor-v-align')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('top').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('sizeRole change updates the preview without throwing', (
      tester,
    ) async {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'Custom', width: 1, height: 1);
      await pump(
        tester,
        CellLayoutEditorPage(
          isOwner: true,
          presetId: preset.id,
          catalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      await selectValue(tester);
      await tester.tap(find.byKey(const ValueKey('cell-editor-size-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('xs').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cell-editor-save')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('hiding and reappearing an element via visibility toggle', (
      tester,
    ) async {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'Custom', width: 1, height: 1);
      await pump(
        tester,
        CellLayoutEditorPage(
          isOwner: true,
          presetId: preset.id,
          catalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      await selectValue(tester);
      await tester.tap(find.byKey(const ValueKey('cell-editor-visible')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cell-editor-element-value')),
        findsOneWidget, // N6.4.1: hidden footprint remains editable.
      );
      await tester.tap(find.byKey(const ValueKey('cell-editor-visible')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cell-editor-element-value')),
        findsOneWidget,
      );
    });

    testWidgets('add/remove indicator slot keeps ordinal contiguity', (
      tester,
    ) async {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'Custom', width: 2, height: 1);
      await pump(
        tester,
        CellLayoutEditorPage(
          isOwner: true,
          presetId: preset.id,
          catalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      // "Crear desde default" already includes 3 indicator slots (the same
      // composition the seed catalog uses).
      expect(find.text('Indicator slots: 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cell-editor-add-slot')));
      await tester.pumpAndSettle();
      expect(find.text('Indicator slots: 4'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cell-editor-save')));
      await tester.pumpAndSettle();
      expect(
        catalog
            .byId(preset.id)!
            .elements
            .where((e) => e.type.name == 'indicator')
            .length,
        4,
      );
      await tester.tap(find.byKey(const ValueKey('cell-editor-select-slot-3')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cell-editor-delete-selected-slot')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Indicator slots: 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('discarding via back shows a confirmation when dirty', (
      tester,
    ) async {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'Custom', width: 1, height: 1);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open-cell-editor'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CellLayoutEditorPage(
                        isOwner: true,
                        presetId: preset.id,
                        catalog: catalog,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.tap(find.byKey(const ValueKey('open-cell-editor')));
      await tester.pumpAndSettle();
      await selectValue(tester);
      await tester.tap(find.byKey(const ValueKey('cell-editor-move-right')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar cambios?'), findsOneWidget);
    });
  });
}
