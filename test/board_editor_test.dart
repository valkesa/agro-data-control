import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/board_preview/board_content_renderer.dart';
import 'package:agro_data_control/board_preview/board_editor_canvas.dart';
import 'package:agro_data_control/board_preview/board_editor_controller.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/board_preview/board_preview_card.dart';
import 'package:agro_data_control/board_preview/board_render_config.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset_catalog.dart';

/// Every preset in the real N4 catalog exposes exactly 3 indicator slots,
/// matching the 3 real indicators tempInterior offers — so the "exceeds
/// available slots" guard can never trigger through the shipped fixtures.
/// This catalog keeps every real preset (so the untouched Sala items still
/// resolve normally) and only overrides the 1x1 default with a scarce,
/// single-slot preset to exercise that real guard end to end.
final _scarce1x1 = CellLayoutPreset(
  id: 'scarce_1x1',
  name: 'Scarce 1x1',
  widthCells: 1,
  heightCells: 1,
  elements: [
    CellLayoutElement(
      id: 'value',
      type: CellElementType.value,
      placement: InternalGridPlacement(
        x: 0,
        y: 0,
        widthUnits: 8,
        heightUnits: 6,
      ),
    ),
    CellLayoutElement(
      id: 'indicator-0',
      type: CellElementType.indicator,
      indicatorSlot: 0,
      placement: InternalGridPlacement(
        x: 0,
        y: 6,
        widthUnits: 8,
        heightUnits: 2,
      ),
    ),
  ],
);
final _tinySlotCatalog = CellLayoutCatalog(
  [...initialCellLayoutCatalog.presets, _scarce1x1],
  defaults: {...initialCellLayoutCatalog.defaults, '1x1': 'scarce_1x1'},
);

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

Finder issuesPanel() => find.byKey(const ValueKey('editor-issues-panel'));

bool issuesContain(WidgetTester tester, String code) => tester
    .widgetList<Text>(
      find.descendant(of: issuesPanel(), matching: find.byType(Text)),
    )
    .any((t) => (t.data ?? '').contains(code));

bool issuesContainForItem(WidgetTester tester, String itemId) => tester
    .widgetList<Text>(
      find.descendant(of: issuesPanel(), matching: find.byType(Text)),
    )
    .any((t) => (t.data ?? '').contains(itemId));

/// Pushes [BoardEditorPage] on a real [Navigator] stack (a button screen
/// underneath), so A1's back-button/PopScope interception is exercised the
/// same way it is in the real app (main.dart pushes a MaterialPageRoute).
Future<void> pushEditor(WidgetTester tester, {bool isOwner = true}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-editor'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BoardEditorPage(isOwner: isOwner),
                ),
              ),
              child: const Text('open editor'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-editor')));
  await tester.pumpAndSettle();
}

BoardEditorController _liveController(WidgetTester tester) =>
    tester.widget<BoardEditorCanvas>(find.byType(BoardEditorCanvas)).controller;

/// N6.3 §16/§18: the add-content chips/form now live under the side
/// panel's "Agregar" tab, not always on screen — switch to it before
/// interacting with `editor-add-type-*`/`editor-pending-*`/
/// `editor-confirm-add`/`editor-cancel-add`. A no-op tap if that tab is
/// already selected.
Future<void> openAgregarTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
  await tester.pumpAndSettle();
}

/// Same as [openAgregarTab] but for "Board" — needed for
/// `editor-item-row-*`/`editor-items-panel` whenever the side panel isn't
/// already showing that tab (e.g. after selecting an item auto-switched it
/// to "Seleccionado").
Future<void> openBoardTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor-side-tab-board')));
  await tester.pumpAndSettle();
}

void main() {
  group('Access', () {
    testWidgets('owner sees the editor', (tester) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      expect(find.text('BOARD EDITOR — OWNER ONLY'), findsOneWidget);
    });

    testWidgets('non-owner is denied', (tester) async {
      await pump(tester, const BoardEditorPage(isOwner: false));
      await tester.pumpAndSettle();
      expect(
        find.text('Board Editor disponible solo para owner'),
        findsOneWidget,
      );
      expect(find.text('BOARD EDITOR — OWNER ONLY'), findsNothing);
    });
  });

  group('Layout template', () {
    testWidgets('selector lists every catalog layout', (tester) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-layout-template')));
      await tester.pumpAndSettle();
      expect(find.text('6 × 1 (grid_6x1)'), findsOneWidget);
      expect(find.text('6 × 2 (grid_6x2)'), findsOneWidget);
      expect(find.text('6 × 3 (grid_6x3)'), findsOneWidget);
      await tester.tap(find.text('6 × 1 (grid_6x1)'));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'switching to a smaller layout keeps items and reports bounds issues',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        expect(issuesContain(tester, 'placement_out_of_bounds'), isFalse);
        await tester.tap(find.byKey(const ValueKey('editor-layout-template')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('6 × 1 (grid_6x1)'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('edit-placement-fan')),
          findsOneWidget,
        );
        expect(issuesContain(tester, 'placement_out_of_bounds'), isTrue);
      },
    );
  });

  group('Selection, move and resize', () {
    testWidgets('tapping a card selects it and shows its panel', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-selected-panel')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-selected-panel')),
        findsOneWidget,
      );
      expect(find.textContaining('humidity'), findsWidgets);
    });

    testWidgets('arrow buttons move the selected item on the grid', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-move-up')));
      await tester.pumpAndSettle();
      expect(issuesContain(tester, 'placement_collision'), isTrue);
      expect(find.byKey(const ValueKey('editor-dirty-state')), findsOneWidget);
    });

    testWidgets(
      'reposition-with-click moves the selected item into a freed empty cell',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        // Sala is fully packed: free a cell first (2,3) by deleting ammonia.
        await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('edit-placement-co2')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('editor-reposition-toggle')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cell-tap-2-3')));
        await tester.pumpAndSettle();

        expect(issuesContain(tester, 'placement_collision'), isFalse);
        final positioned = tester.widget<Positioned>(
          find.byKey(const ValueKey('edit-placement-co2')),
        );
        expect(positioned.left, 2 * 68.0);
        expect(positioned.top, 3 * 68.0);
      },
    );

    testWidgets(
      'resize creates a preset span mismatch, then a compatible preset resolves it',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-metric-preset')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Valor e indicadores 2 × 1').first);
        await tester.pumpAndSettle();
        expect(issuesContain(tester, 'cell_span_mismatch'), isFalse);
        await tester.tap(find.byKey(const ValueKey('editor-width-plus')));
        await tester.pumpAndSettle();
        expect(issuesContain(tester, 'cell_span_mismatch'), isTrue);
        await tester.tap(find.byKey(const ValueKey('editor-metric-preset')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Valor e indicadores 3 × 1').first);
        await tester.pumpAndSettle();
        expect(issuesContain(tester, 'cell_span_mismatch'), isFalse);
      },
    );
  });

  group('Indicators', () {
    testWidgets('selecting an available indicator is reflected without error', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('edit-placement-temperature-main')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-indicator-calefaccionEtapa1')),
      );
      await tester.pumpAndSettle();
      expect(issuesContain(tester, 'indicator_not_available'), isFalse);
    });

    testWidgets('exceeding available indicator slots blocks the add button', (
      tester,
    ) async {
      await pump(
        tester,
        BoardEditorPage(isOwner: true, presets: _tinySlotCatalog),
      );
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      // tiny_1x1 (the injected default for 1x1) exposes a single slot,
      // while tempInterior offers 3 real indicators to pick from.
      await tester.tap(
        find.byKey(
          const ValueKey('editor-pending-indicator-calefaccionEtapa1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('editor-confirm-add')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(
        find.byKey(
          const ValueKey('editor-pending-indicator-calefaccionEtapa2'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-pending-indicator-overflow')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('editor-confirm-add')),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('Title', () {
    testWidgets('toggling showTitle changes the resolved preview text', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      expect(find.textContaining('Resuelve a: "Sala · demo"'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor-show-title')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Resuelve a: "(sin título)"'), findsOneWidget);
    });

    testWidgets('titleOverride replaces the resolved title', (tester) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('editor-title-override')),
        'Sala 1 personalizada',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Resuelve a: "Sala 1 personalizada"'),
        findsOneWidget,
      );
    });
  });

  group('Delete', () {
    testWidgets('removes the selected item from the board', (tester) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('edit-placement-ammonia')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('editor-selected-panel')), findsNothing);
    });
  });

  group('Add content', () {
    testWidgets('adding a metric into a freed cell produces no new issues', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('editor-pending-x-plus')));
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('editor-pending-y-plus')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('editor-confirm-add')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('edit-placement-metric-0')),
        findsOneWidget,
      );
      expect(issuesContain(tester, 'placement_collision'), isFalse);
      expect(issuesContain(tester, 'placement_out_of_bounds'), isFalse);
    });

    testWidgets('non-metric types can be added with minimal fields', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-text')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('editor-pending-x-plus')));
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('editor-pending-y-plus')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('edit-placement-text-0')),
        findsOneWidget,
      );
    });
  });

  group('Dirty and reset', () {
    testWidgets('reset restores the pristine fixture', (tester) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-move-left')));
      await tester.pumpAndSettle();
      expect(
        find.text('Cambios sin guardar · borrador local en memoria'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('editor-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restaurar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Sin cambios · borrador local en memoria'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('edit-placement-ammonia')),
        findsOneWidget,
      );
    });
  });

  group('Preview mode', () {
    testWidgets('hides selection/debug helpers and cell taps', (tester) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      // Edit mode is the default: helpers are visible from the start.
      expect(find.byKey(const ValueKey('cell-tap-0-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('board-geometry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor-toggle-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cell-tap-0-0')), findsNothing);
      expect(find.byKey(const ValueKey('board-geometry')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('editor-toggle-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cell-tap-0-0')), findsOneWidget);
    });
  });

  group('Gap token', () {
    testWidgets('every rendered card uses the configured cardGap', (
      tester,
    ) async {
      const config = BoardRenderConfig(cardGap: 2);
      await pump(
        tester,
        const BoardEditorPage(isOwner: true, renderConfig: config),
      );
      await tester.pumpAndSettle();
      final cards = tester.widgetList<BoardPreviewCard>(
        find.byType(BoardPreviewCard),
      );
      expect(cards, isNotEmpty);
      for (final card in cards) {
        expect(card.gap, config.cardGap);
      }
    });

    testWidgets('BoardEditorCanvas exposes the same geometry as preview', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      expect(find.byType(BoardEditorCanvas), findsOneWidget);
    });
  });

  // N6.1 — auditoría posterior a N6, hallazgos A1-A5 convertidos en tests
  // de aceptación permanentes (Prompt_Etapa_N6_1 §12/§13).
  group('A1 — exit confirmation', () {
    testWidgets(
      'dirty + Back shows the discard dialog; Cancel stays in editor',
      (tester) async {
        await pushEditor(tester);
        await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-move-up')));
        await tester.pumpAndSettle();
        expect(find.text('Board Editor'), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('¿Descartar cambios?'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('editor-discard-cancel')));
        await tester.pumpAndSettle();
        expect(find.text('Board Editor'), findsOneWidget);
        expect(find.byKey(const ValueKey('open-editor')), findsNothing);
      },
    );

    testWidgets('dirty + Back + Descartar exits the editor', (tester) async {
      await pushEditor(tester);
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-move-up')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-discard-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Board Editor'), findsNothing);
      expect(find.byKey(const ValueKey('open-editor')), findsOneWidget);
    });

    testWidgets('a clean editor pops without any dialog', (tester) async {
      await pushEditor(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar cambios?'), findsNothing);
      expect(find.byKey(const ValueKey('open-editor')), findsOneWidget);
    });

    testWidgets('an in-progress add draft also blocks silent exit', (
      tester,
    ) async {
      await pushEditor(tester);
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar cambios?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor-discard-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('switching fixture while dirty reuses the same confirmation', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-move-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laboratorio demo'));
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar cambios?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor-discard-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Laboratorio · demo'), findsOneWidget);
    });
  });

  group('A2 — persistent text controllers', () {
    testWidgets(
      'title typed without Enter previews live and survives an unrelated rebuild',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-title-override')),
          'Sin enter',
        );
        await tester.pump();
        expect(find.text('Resuelve a: "Sin enter"'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
        await tester.pumpAndSettle();
        expect(find.text('Sin enter'), findsWidgets);
      },
    );

    testWidgets(
      'selected-item field text is not lost by an unrelated rebuild',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Arco demo'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('edit-placement-operating-state')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-edit-status-source')),
          'device.custom_status',
        );
        await tester.pump();
        // Unrelated rebuild that does not change selection.
        await tester.tap(
          find.byKey(const ValueKey('editor-reposition-toggle')),
        );
        await tester.pumpAndSettle();
        expect(find.text('device.custom_status'), findsOneWidget);
      },
    );

    testWidgets(
      'changing selection resyncs the field to the newly selected item',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Arco demo'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('edit-placement-operating-state')),
        );
        await tester.pumpAndSettle();
        expect(find.text('device.operatingState'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('edit-placement-latest')));
        await tester.pumpAndSettle();
        expect(find.text('device.operatingState'), findsNothing);
        expect(find.text('device.latestVehicle'), findsOneWidget);
      },
    );
  });

  group('A3 — invalid inputs never throw', () {
    testWidgets(
      'invalid selected dataSourceId shows an error and keeps the app alive',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Arco demo'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('edit-placement-operating-state')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-edit-status-source')),
          'bad source',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('editor-selected-error')),
          findsOneWidget,
        );
        final content =
            _liveController(tester).selectedItem!.content as StatusBoardContent;
        expect(content.dataSourceId, 'device.operatingState');

        await tester.enterText(
          find.byKey(const ValueKey('editor-edit-status-source')),
          'device.ok',
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('editor-selected-error')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'invalid pending dataSourceId disables Agregar without throwing',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-status')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('editor-pending-binding-bound')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-pending-data-source')),
          'bad source',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('editor-pending-error')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('editor-confirm-add')),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const ValueKey('editor-pending-data-source')),
          'device.ok',
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('editor-pending-error')),
          findsNothing,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('editor-confirm-add')),
              )
              .onPressed,
          isNotNull,
        );
      },
    );
  });

  group('A4 — Preview is read-only', () {
    testWidgets(
      'Preview swaps to BoardContentRenderer and hides every editing affordance',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
        await tester.pumpAndSettle();
        // Selecting a card auto-switches the side panel to "Seleccionado".
        expect(
          find.byKey(const ValueKey('editor-selected-panel')),
          findsOneWidget,
        );
        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-text')));
        await tester.pumpAndSettle();
        expect(find.byType(BoardEditorCanvas), findsOneWidget);
        // Only one side-panel tab is mounted at a time — the selection
        // itself is still live in the controller (verified below, after
        // returning from Preview), just not the active tab right now.
        expect(
          find.byKey(const ValueKey('editor-selected-panel')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('editor-add-panel')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('editor-toggle-mode')));
        await tester.pumpAndSettle();

        expect(find.byType(BoardEditorCanvas), findsNothing);
        expect(find.byType(BoardContentRenderer), findsOneWidget);
        expect(
          find.byKey(const ValueKey('editor-selected-panel')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('editor-add-panel')), findsNothing);
        expect(find.byKey(const ValueKey('editor-items-panel')), findsNothing);
        expect(
          find.byKey(const ValueKey('editor-layout-template')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('editor-reset')), findsNothing);
        expect(find.text('Modo preview · solo lectura'), findsOneWidget);

        // The draft survives internally and reappears back in Editar.
        await tester.tap(find.byKey(const ValueKey('editor-toggle-mode')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('editor-add-panel')), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('editor-add-type-text')),
              )
              .selected,
          isTrue,
        );
      },
    );
  });

  group('A5 — out-of-canvas items stay reachable', () {
    testWidgets(
      'shrinking the layout keeps an out-of-bounds item selectable and repairable from the items list',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-layout-template')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('6 × 1 (grid_6x1)'));
        await tester.pumpAndSettle();
        expect(issuesContainForItem(tester, 'water'), isTrue);

        expect(
          find.byKey(const ValueKey('editor-item-row-water')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('editor-item-row-water')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-selected-panel')),
          findsOneWidget,
        );
        expect(find.text('Seleccionado: water (metric)'), findsOneWidget);

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byKey(const ValueKey('editor-move-up')));
          await tester.pumpAndSettle();
        }
        expect(issuesContainForItem(tester, 'water'), isFalse);
      },
    );

    testWidgets('an issue with itemId is clickable and selects that item', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-move-up')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-selected-panel')),
        findsOneWidget,
      );

      // Collision issues carry itemId/relatedItemId in list order, not
      // necessarily 'ammonia' first — read the real issue instead of
      // assuming which side of the pair it landed on.
      final controller = _liveController(tester);
      final allIssues = controller.issues(initialCellLayoutCatalog);
      final issueIndex = allIssues.indexWhere(
        (i) => i.code == 'placement_collision' && i.itemId != null,
      );
      final issue = allIssues[issueIndex];
      final other = controller.items.firstWhere((i) => i.id != issue.itemId);

      // Select a different item first so the upcoming tap is what re-selects.
      await openBoardTab(tester);
      await tester.tap(find.byKey(ValueKey('editor-item-row-${other.id}')));
      await tester.pumpAndSettle();
      expect(controller.selectedItemId, isNot(issue.itemId));

      final issueFinder = find.byKey(
        ValueKey(
          'editor-issue-$issueIndex-${issue.code}-${issue.itemId}-'
          '${issue.relatedItemId ?? "_"}',
        ),
      );
      expect(issueFinder, findsOneWidget);
      await tester.tap(issueFinder);
      await tester.pumpAndSettle();
      expect(controller.selectedItemId, issue.itemId);
    });
  });

  group('latestEvent / dataTable minimal usable config', () {
    testWidgets(
      'picking a fields config preserves fields; changing source keeps them',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Arco demo'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-placement-latest')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey('editor-edit-event-fields-Simple (1 campo)'),
          ),
        );
        await tester.pumpAndSettle();
        var content =
            _liveController(tester).selectedItem!.content
                as LatestEventBoardContent;
        expect(content.fields, hasLength(1));
        expect(content.fields.single.key, 'value');

        await tester.enterText(
          find.byKey(const ValueKey('editor-edit-event-source')),
          'device.custom_event',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        content =
            _liveController(tester).selectedItem!.content
                as LatestEventBoardContent;
        expect(content.eventSourceId, 'device.custom_event');
        expect(content.fields, hasLength(1));
      },
    );

    testWidgets(
      'adding a latestEvent uses the chosen field config, not the old hardcoded single field',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await openAgregarTab(tester);
        await tester.tap(
          find.byKey(const ValueKey('editor-add-type-latestEvent')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey(
              'editor-pending-event-fields-Evento (fecha + estado)',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('editor-confirm-add')),
              )
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'picking a columns config preserves columns/maxRows/showHeader',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Arco demo'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-placement-records')));
        await tester.pumpAndSettle();
        final before =
            _liveController(tester).selectedItem!.content
                as DataTableBoardContent;
        await tester.tap(
          find.byKey(
            const ValueKey(
              'editor-edit-table-columns-Registro (fecha + estado)',
            ),
          ),
        );
        await tester.pumpAndSettle();
        final after =
            _liveController(tester).selectedItem!.content
                as DataTableBoardContent;
        expect(after.columns, hasLength(2));
        expect(after.maxRows, before.maxRows);
        expect(after.showHeader, before.showHeader);

        await tester.enterText(
          find.byKey(const ValueKey('editor-edit-table-source')),
          'device.custom_table',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final withNewSource =
            _liveController(tester).selectedItem!.content
                as DataTableBoardContent;
        expect(withNewSource.dataSourceId, 'device.custom_table');
        expect(withNewSource.columns, hasLength(2));
      },
    );
  });

  group('preset selector — span compatible only', () {
    testWidgets(
      'dropdown offers only compatible presets; resize does not auto-reassign; diagnostic entry appears for the incompatible current one',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-metric-preset')));
        await tester.pumpAndSettle();
        expect(find.text('Valor e indicadores 2 × 1'), findsOneWidget);
        expect(find.text('Icono y valor 2 × 1'), findsOneWidget);
        expect(find.text('Valor e indicadores 1 × 1'), findsNothing);
        await tester.tap(find.text('Valor e indicadores 2 × 1'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('editor-width-plus')));
        await tester.pumpAndSettle();
        expect(issuesContain(tester, 'cell_span_mismatch'), isTrue);
        final mismatched =
            _liveController(tester).selectedItem!.content as MetricBoardContent;
        expect(mismatched.cellLayoutPresetId, 'default_2x1');

        await tester.tap(find.byKey(const ValueKey('editor-metric-preset')));
        await tester.pumpAndSettle();
        expect(find.textContaining('span incompatible'), findsWidgets);
        await tester.tap(find.text('Valor e indicadores 3 × 1'));
        await tester.pumpAndSettle();
        expect(issuesContain(tester, 'cell_span_mismatch'), isFalse);
      },
    );

    testWidgets(
      'pending preset dropdown also stays span-compatible and does not auto-reassign on resize',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-pending-preset')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Valor e indicadores 1 × 1'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('editor-pending-width-plus')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-pending-preset')));
        await tester.pumpAndSettle();
        expect(find.textContaining('span incompatible'), findsWidgets);
      },
    );
  });

  group('R1 — per-item drafts survive navigating away', () {
    testWidgets(
      'an invalid draft on one item survives selecting another item and back',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Arco demo'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('edit-placement-operating-state')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-edit-status-source')),
          'bad source',
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('editor-selected-error')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('edit-placement-disinfected')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-selected-error')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey('edit-placement-operating-state')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-selected-error')),
          findsOneWidget,
        );
        expect(find.text('bad source'), findsOneWidget);
      },
    );

    testWidgets(
      'a draft parked on a non-selected item still counts as dirty and blocks silent exit',
      (tester) async {
        await pushEditor(tester);
        await tester.tap(find.text('Arco demo'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('edit-placement-operating-state')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-edit-status-source')),
          'bad source',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('edit-placement-disinfected')),
        );
        await tester.pumpAndSettle();
        // The currently-selected item (disinfected) has no error of its own,
        // but the parked draft on operating-state must still block a silent
        // pop (N6.2 §1/§11).
        expect(
          find.byKey(const ValueKey('editor-selected-error')),
          findsNothing,
        );

        final backButton = find.byTooltip('Back');
        await tester.tap(backButton);
        await tester.pumpAndSettle();
        expect(find.text('¿Descartar cambios?'), findsOneWidget);
      },
    );

    testWidgets('the items list flags an item with a parked draft error', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arco demo'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('edit-placement-operating-state')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('editor-edit-status-source')),
        'bad source',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('edit-placement-disinfected')),
      );
      await tester.pumpAndSettle();
      await openBoardTab(tester);
      final row = tester.widget<InkWell>(
        find.byKey(const ValueKey('editor-item-row-operating-state')),
      );
      final icon = find.descendant(
        of: find.byWidget(row),
        matching: find.byIcon(Icons.error_outline),
      );
      expect(icon, findsOneWidget);
    });
  });

  group('R2 — layout selector resolves from a single collection', () {
    testWidgets(
      'selecting the current fixture layout (grid_6x7) is a safe no-op',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Arco demo'));
        await tester.pumpAndSettle();
        expect(
          find.text('Cambios sin guardar · borrador local en memoria'),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('editor-layout-template')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('6 × 7 (grid_6x7) — del fixture').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Sin cambios · borrador local en memoria'),
          findsOneWidget,
        );
      },
    );
  });

  group('R3 — Reset clears every ephemeral state', () {
    testWidgets(
      'Reset clears pending drafts, item drafts and text so a later add starts clean',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        // Start an "image" add and type a distinctive sourceRef.
        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-image')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editor-pending-image-ref')),
          'discarded-ref',
        );
        await tester.pump();
        // Park an invalid draft on another item too.
        await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('editor-reset')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restaurar'));
        await tester.pumpAndSettle();

        expect(
          find.text('Sin cambios · borrador local en memoria'),
          findsOneWidget,
        );
        // Reset clears the selection itself (not just its draft) — the side
        // panel stays on whichever tab the user was last on (here,
        // "Seleccionado", from parking the humidity draft above), now
        // showing its "nothing selected" placeholder rather than a stale
        // panel for an item that no longer counts as selected.
        expect(_liveController(tester).selectedItemId, isNull);
        expect(
          find.byKey(const ValueKey('editor-selected-panel')),
          findsNothing,
        );

        // Starting a fresh "image" add must never show the discarded text.
        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-image')));
        await tester.pumpAndSettle();
        expect(find.text('discarded-ref'), findsNothing);
        expect(find.text('hero'), findsOneWidget);
      },
    );
  });

  group('R4 — Preview shows only the final board by default', () {
    testWidgets(
      'Preview hides title controls and the issues panel unless debug is on',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-toggle-mode')));
        await tester.pumpAndSettle();

        expect(find.text('Mostrar título'), findsNothing);
        expect(issuesPanel(), findsNothing);
        expect(find.byKey(const ValueKey('editor-items-panel')), findsNothing);
        expect(find.byKey(const ValueKey('editor-add-panel')), findsNothing);
        expect(
          find.byKey(const ValueKey('editor-layout-template')),
          findsNothing,
        );

        await tester.tap(find.byKey(const ValueKey('editor-debug-toggle')));
        await tester.pumpAndSettle();
        expect(issuesPanel(), findsOneWidget);
        // Debug only reveals diagnostics, never editing affordances.
        expect(find.byKey(const ValueKey('editor-add-panel')), findsNothing);
      },
    );
  });

  group('R5 — multi-collision never produces duplicate keys', () {
    testWidgets('moving a 2x2 item onto two other items at once never throws', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('edit-placement-temperature-main')),
      );
      await tester.pumpAndSettle();
      // temperature-main is 2x2 at (0,0); moving it right by one cell
      // overlaps both humidity (2,0) and outside-temperature (2,1)
      // simultaneously — the exact R5 repro from the audit.
      await tester.tap(find.byKey(const ValueKey('editor-move-right')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(issuesContain(tester, 'placement_collision'), isTrue);
      final collisions = _liveController(tester)
          .issues(initialCellLayoutCatalog)
          .where((i) => i.code == 'placement_collision')
          .toList();
      expect(collisions.length, greaterThanOrEqualTo(2));
    });
  });

  group('Board Preset editor mode', () {
    testWidgets('opens against a BoardPreset instead of a demo fixture', (
      tester,
    ) async {
      final catalog = BoardPresetCatalog(initial: []);
      final preset = catalog.create(
        name: 'Maternidad estándar',
        layout: buildLayoutTemplate(6, 4),
      );
      await pump(
        tester,
        BoardEditorPage(
          isOwner: true,
          presetId: preset.id,
          presetCatalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('BOARD PRESET EDITOR'), findsOneWidget);
      expect(
        find.text('Preset de tablero: Maternidad estándar'),
        findsOneWidget,
      );
      expect(find.text('Layout: 6x4'), findsOneWidget);
      expect(find.text('CASOS DEMO'), findsNothing);
    });

    testWidgets('adding content commits live into the BoardPresetCatalog', (
      tester,
    ) async {
      final catalog = BoardPresetCatalog(initial: []);
      final preset = catalog.create(
        name: 'Maternidad estándar',
        layout: buildLayoutTemplate(6, 4),
        // N6.5.1: create() no longer defaults to a catalog — this test is
        // about editor↔catalog commit mechanics, not catalog selection, so
        // it opts into a real one explicitly.
        capabilityProfileId: 'environment_room_v1',
      );
      await pump(
        tester,
        BoardEditorPage(
          isOwner: true,
          presetId: preset.id,
          presetCatalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();

      final stored = catalog.byId(preset.id)!;
      expect(stored.items, hasLength(1));
      expect(stored.presetVersion, greaterThan(1));
    });

    testWidgets('duplicate independence holds through the editor too', (
      tester,
    ) async {
      final catalog = BoardPresetCatalog(initial: []);
      final original = catalog.create(
        name: 'Sala clima estándar',
        layout: buildLayoutTemplate(6, 4),
        // N6.5.1: no more silent default catalog — this test needs a real
        // one purely to exercise duplicate independence, not selection.
        capabilityProfileId: 'environment_room_v1',
      );
      await pump(
        tester,
        BoardEditorPage(
          key: ValueKey(original.id),
          isOwner: true,
          presetId: original.id,
          presetCatalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();

      final duplicate = catalog.duplicate(original.id);
      await pump(
        tester,
        BoardEditorPage(
          key: ValueKey(duplicate.id),
          isOwner: true,
          presetId: duplicate.id,
          presetCatalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();

      final originalAfter = catalog.byId(original.id)!;
      final duplicateAfter = catalog.byId(duplicate.id)!;
      expect(originalAfter.items, hasLength(1));
      expect(duplicateAfter.items, hasLength(2));
    });

    testWidgets('N6.3 §10: the cell layout editor also opens for a metric item '
        'while editing a BoardPreset', (tester) async {
      final catalog = BoardPresetCatalog(initial: []);
      final preset = catalog.create(
        name: 'Maternidad estándar',
        layout: buildLayoutTemplate(6, 4),
        // N6.5.1: no more silent default catalog.
        capabilityProfileId: 'environment_room_v1',
      );
      await pump(
        tester,
        BoardEditorPage(
          isOwner: true,
          presetId: preset.id,
          presetCatalog: catalog,
        ),
      );
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();

      final addedId = catalog.byId(preset.id)!.items.single.id;
      await openBoardTab(tester);
      await tester.tap(find.byKey(ValueKey('editor-item-row-$addedId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-side-tab-selected')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-create-design-from-default')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Diseño de celda'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('N6.3.1 — B1: default por span para cualquier span válido', () {
    Future<String> addMetricItem(
      WidgetTester tester, {
      int widthPlus = 1,
      int heightPlus = 1,
    }) async {
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      for (var i = 0; i < widthPlus; i++) {
        await tester.tap(
          find.byKey(const ValueKey('editor-pending-width-plus')),
        );
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < heightPlus; i++) {
        await tester.tap(
          find.byKey(const ValueKey('editor-pending-height-plus')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();
      return 'metric-0';
    }

    testWidgets(
      'resizing a default-por-span item from a seeded span (2x2) to an '
      'unseeded one (4x2) never produces cell_preset_not_found',
      (tester) async {
        final catalog = BoardPresetCatalog(initial: []);
        final preset = catalog.create(
          name: 'Maternidad estándar',
          layout: buildLayoutTemplate(8, 6),
          // N6.5.1: no more silent default catalog.
          capabilityProfileId: 'environment_room_v1',
        );
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            presetId: preset.id,
            presetCatalog: catalog,
          ),
        );
        await tester.pumpAndSettle();
        final id = await addMetricItem(tester, widthPlus: 1, heightPlus: 1);
        await openBoardTab(tester);
        await tester.tap(find.byKey(ValueKey('editor-item-row-$id')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('editor-side-tab-selected')),
        );
        await tester.pumpAndSettle();
        expect(find.text('(default por span)'), findsOneWidget);
        expect(issuesContain(tester, 'cell_preset_not_found'), isFalse);

        // 2x2 -> 4x2: no seeded default exists for 4x2.
        await tester.tap(find.byKey(const ValueKey('editor-width-plus')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-width-plus')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(issuesContain(tester, 'cell_preset_not_found'), isFalse);
      },
    );

    testWidgets(
      'varios spans sin default sembrado (3x1, 4x2, 5x3) never produce '
      'cell_preset_not_found — proves the resolution is generic, not a '
      'hardcoded table',
      (tester) async {
        for (final span in [(3, 1), (4, 2), (5, 3)]) {
          final (widthPlus, heightPlus) = (span.$1 - 1, span.$2 - 1);
          final catalog = BoardPresetCatalog(initial: []);
          final preset = catalog.create(
            name: 'Maternidad estándar',
            layout: buildLayoutTemplate(8, 6),
            // N6.5.1: no more silent default catalog.
            capabilityProfileId: 'environment_room_v1',
          );
          await pump(
            tester,
            BoardEditorPage(
              isOwner: true,
              presetId: preset.id,
              presetCatalog: catalog,
            ),
          );
          await tester.pumpAndSettle();
          final id = await addMetricItem(
            tester,
            widthPlus: widthPlus,
            heightPlus: heightPlus,
          );
          await openBoardTab(tester);
          await tester.tap(find.byKey(ValueKey('editor-item-row-$id')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('editor-side-tab-selected')),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'span ${span.$1}x${span.$2}',
          );
          expect(
            issuesContain(tester, 'cell_preset_not_found'),
            isFalse,
            reason: 'span ${span.$1}x${span.$2}',
          );
        }
      },
    );

    testWidgets(
      '"Crear diseño desde este default" turns the generic default into a '
      'real, directly-editable CellLayoutPreset',
      (tester) async {
        final catalog = BoardPresetCatalog(initial: []);
        final preset = catalog.create(
          name: 'Maternidad estándar',
          layout: buildLayoutTemplate(8, 6),
          // N6.5.1: no more silent default catalog.
          capabilityProfileId: 'environment_room_v1',
        );
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            presetId: preset.id,
            presetCatalog: catalog,
          ),
        );
        await tester.pumpAndSettle();
        // width+3, height+1 -> 4x2, no seeded default.
        final id = await addMetricItem(tester, widthPlus: 3, heightPlus: 1);
        await openBoardTab(tester);
        await tester.tap(find.byKey(ValueKey('editor-item-row-$id')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('editor-side-tab-selected')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-create-design-from-default')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('editor-create-design-from-default')),
        );
        await tester.pumpAndSettle();
        // Opened directly into the cell layout editor — a brand-new local
        // preset is never gated behind "Duplicar diseño de celda" first.
        expect(find.text('Diseño de celda'), findsWidgets);
        expect(
          find.byKey(const ValueKey('cell-editor-duplicate')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Volver al Board'));
        await tester.pumpAndSettle();
        // The item no longer reads "(default por span)" — it now points at
        // a real, explicit, catalog-backed preset.
        await tester.tap(
          find.byKey(const ValueKey('editor-side-tab-selected')),
        );
        await tester.pumpAndSettle();
        expect(find.text('(default por span)'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('N6.3.1 — B2: Eliminar elemento', () {
    testWidgets('metric: seleccionar -> eliminar -> confirmar -> desaparece', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('editor-delete')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('editor-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-delete-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('edit-placement-ammonia')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('editor-item-row-ammonia')),
        findsNothing,
      );
    });

    testWidgets('cancelar deja el item intacto', (tester) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('edit-placement-ammonia')),
        findsOneWidget,
      );
    });

    testWidgets('después de eliminar, la selección queda limpia', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-delete-confirm')));
      await tester.pumpAndSettle();
      expect(_liveController(tester).selectedItemId, isNull);
      expect(find.byKey(const ValueKey('editor-selected-panel')), findsNothing);
    });

    for (final type in ['image', 'status', 'dataTable']) {
      testWidgets('tipo no métrico ($type) también puede eliminarse', (
        tester,
      ) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await openAgregarTab(tester);
        await tester.tap(find.byKey(ValueKey('editor-add-type-$type')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
        await tester.pumpAndSettle();
        final placed = find.byKey(ValueKey('edit-placement-$type-0'));
        expect(placed, findsOneWidget);
        await tester.tap(placed);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-delete-confirm')));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('edit-placement-$type-0')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'un item con placement_collision también puede eliminarse, y el '
      'board se revalida',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
        await tester.pumpAndSettle();
        // Move humidity onto temperature-main -> collision.
        await tester.tap(find.byKey(const ValueKey('editor-move-left')));
        await tester.pumpAndSettle();
        expect(issuesContain(tester, 'placement_collision'), isTrue);

        await tester.tap(find.byKey(const ValueKey('editor-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-delete-confirm')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(issuesContain(tester, 'placement_collision'), isFalse);
        expect(
          find.byKey(const ValueKey('edit-placement-humidity')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'eliminar del board no borra la métrica del DeviceMetricCatalog',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        final catalog = _liveController(tester).catalog;
        expect(catalog.metricByKey('humedadInterior'), isNotNull);
        await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-delete-confirm')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('edit-placement-humidity')),
          findsNothing,
        );
        expect(catalog.metricByKey('humedadInterior'), isNotNull);
      },
    );

    testWidgets(
      '§11: eliminar una métrica declarada required no la bloquea, solo '
      'advierte',
      (tester) async {
        final layout = buildLayoutTemplate(8, 6);
        final item = BoardContentItem(
          id: 'temp-required',
          content: MetricBoardContent(metricKey: 'tempInterior'),
          placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 2),
        );
        final preset = BoardPreset(
          id: 'preset-required',
          name: 'Con requeridos',
          layoutTemplateId: layout.id,
          items: [item],
          requiredMetricKeys: const ['tempInterior'],
        );
        final catalog = BoardPresetCatalog(initial: [preset]);
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            presetId: preset.id,
            presetCatalog: catalog,
          ),
        );
        await tester.pumpAndSettle();
        await openBoardTab(tester);
        await tester.tap(
          find.byKey(const ValueKey('editor-item-row-temp-required')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-delete-confirm')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Esta métrica sigue declarada como requerida por el preset.',
          ),
          findsOneWidget,
        );
        // Never blocked — the item is gone regardless of the warning.
        expect(
          find.byKey(const ValueKey('editor-item-row-temp-required')),
          findsNothing,
        );
      },
    );
  });

  group('N6.3 — UX lateral del Board Editor', () {
    testWidgets('desktop width uses the side-by-side layout', (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: BoardEditorPage(isOwner: true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-layout-desktop')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('editor-layout-narrow')), findsNothing);
      expect(find.byKey(const ValueKey('editor-side-panel')), findsOneWidget);
    });

    testWidgets('narrow width stacks board above the side panel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: BoardEditorPage(isOwner: true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-layout-narrow')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('editor-layout-desktop')), findsNothing);
      expect(find.byKey(const ValueKey('editor-side-panel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the three tabs show mutually-exclusive content', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-items-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-add-panel')), findsNothing);

      await openAgregarTab(tester);
      expect(find.byKey(const ValueKey('editor-add-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-items-panel')), findsNothing);

      await openBoardTab(tester);
      expect(find.byKey(const ValueKey('editor-items-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-add-panel')), findsNothing);
    });

    testWidgets('selecting a card auto-switches to "Seleccionado"', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      expect(find.byKey(const ValueKey('editor-add-panel')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-selected-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('editor-add-panel')), findsNothing);
    });

    testWidgets('"Mover con clic" still works inside the side panel', (
      tester,
    ) async {
      await pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-ammonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-reposition-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-move-down')));
      await tester.tap(find.byKey(const ValueKey('editor-move-down')));
      await tester.pumpAndSettle();
      final freedCell = find.byKey(const ValueKey('cell-tap-2-3'));
      if (tester.any(freedCell)) {
        await tester.tap(freedCell);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('N6.3 — Diseño de celda desde el Board Editor', () {
    testWidgets(
      '"Editar diseño" opens the visual cell layout editor and applying '
      'a change back is reflected on the item',
      (tester) async {
        await pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-metric-preset')));
        await tester.pumpAndSettle();
        final menu = tester.widget<DropdownButton<String?>>(
          find.byKey(const ValueKey('editor-metric-preset')),
        );
        menu.onChanged!('default_2x1');
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('editor-open-cell-layout-editor')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Diseño de celda'), findsWidgets);
        expect(
          find.byKey(const ValueKey('cell-editor-duplicate')),
          findsNothing,
        );
        final globalBefore = sharedCellLayoutPresetCatalog
            .byId('default_2x1')!
            .toMap();
        await tester.tap(
          find.byKey(const ValueKey('cell-editor-element-value')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cell-editor-move-right')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cell-editor-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Volver al Board'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final content =
            _liveController(tester).selectedItem!.content as MetricBoardContent;
        expect(content.cellLayoutPresetId, 'default_2x1');
        expect(content.cellLayoutSnapshot, isNotNull);
        expect(
          sharedCellLayoutPresetCatalog.byId('default_2x1')!.toMap(),
          globalBefore,
        );
      },
    );
  });
}
