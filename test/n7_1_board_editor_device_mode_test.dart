// N7.1 §20 "BoardEditorMode.device: cargar; editar; dirty; guardar;
// recargar" — controller-level unit tests (plain `test()`, `ChangeNotifier`
// needs no widget pump) plus one full widget-level test driving
// `BoardEditorPage` end to end with a fake `onSave` closure (no
// `DeviceBoardConfigRepository`/Firestore anywhere — `onSave` is just the
// `Future<int> Function(BoardContentLayout, int)` callback
// `BoardEditorDeviceContext` already declares).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_preview/board_editor_controller.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/services/firestore_version_conflict.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

BoardContentLayout _sampleLayout({int layoutVersion = 1}) => BoardContentLayout(
  deviceId: 'device-1',
  layoutTemplateId: 'grid_6x4',
  layoutVersion: layoutVersion,
  capabilityProfileId: 'sala_a',
  sourceBoardPresetId: 'preset_a',
  sourceBoardPresetVersion: 2,
  items: [
    BoardContentItem(
      id: 'metric-0',
      placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 2),
      content: MetricBoardContent(metricKey: 'tempInterior'),
    ),
  ],
);

void main() {
  group(
    'N7.1 §13/§14 — BoardEditorController.forDevice: cargar/editar/dirty',
    () {
      test('loads the layout with mode=device and loadedLayoutVersion set', () {
        final controller = BoardEditorController.forDevice(
          tenantId: 'tenant-a',
          layout: _sampleLayout(layoutVersion: 4),
          catalog: emptyDeviceMetricCatalog,
        );
        expect(controller.mode, BoardEditorMode.device);
        expect(controller.tenantId, 'tenant-a');
        expect(controller.deviceId, 'device-1');
        expect(controller.loadedLayoutVersion, 4);
        expect(controller.sourceBoardPresetId, 'preset_a');
        expect(controller.sourceBoardPresetVersion, 2);
        expect(controller.dirty, isFalse);
        expect(controller.items, hasLength(1));
      });

      test('editing (e.g. moving the selected item) sets dirty', () {
        final controller = BoardEditorController.forDevice(
          tenantId: 'tenant-a',
          layout: _sampleLayout(),
          catalog: emptyDeviceMetricCatalog,
        );
        controller.selectItem('metric-0');
        controller.moveSelectedBy(1, 0);
        expect(controller.dirty, isTrue);
      });

      test('board getter carries capabilityProfileId/sourceBoardPresetId/'
          'sourceBoardPresetVersion forward unchanged after an edit', () {
        final controller = BoardEditorController.forDevice(
          tenantId: 'tenant-a',
          layout: _sampleLayout(),
          catalog: emptyDeviceMetricCatalog,
          profileId: 'sala_a',
        );
        controller.selectItem('metric-0');
        controller.moveSelectedBy(1, 1);
        final board = controller.board;
        expect(board.capabilityProfileId, 'sala_a');
        expect(board.sourceBoardPresetId, 'preset_a');
        expect(board.sourceBoardPresetVersion, 2);
      });

      test('reset() restores the pristine device layout and clears dirty', () {
        final controller = BoardEditorController.forDevice(
          tenantId: 'tenant-a',
          layout: _sampleLayout(),
          catalog: emptyDeviceMetricCatalog,
        );
        controller.selectItem('metric-0');
        controller.moveSelectedBy(2, 2);
        expect(controller.dirty, isTrue);
        controller.reset();
        expect(controller.dirty, isFalse);
        expect(controller.items.first.placement.x, 0);
      });
    },
  );

  group(
    'N7.1 §14 — save-state machine (draftDirty/saving/saved/saveError)',
    () {
      test(
        'markSaving/markSaved transitions and updates loadedLayoutVersion',
        () {
          final controller = BoardEditorController.forDevice(
            tenantId: 'tenant-a',
            layout: _sampleLayout(layoutVersion: 1),
            catalog: emptyDeviceMetricCatalog,
          );
          controller.selectItem('metric-0');
          controller.moveSelectedBy(1, 0);
          expect(controller.dirty, isTrue);

          controller.markSaving();
          expect(controller.saveStatus, BoardSaveStatus.saving);

          controller.markSaved(2);
          expect(controller.saveStatus, BoardSaveStatus.saved);
          expect(controller.dirty, isFalse);
          expect(controller.loadedLayoutVersion, 2);
        },
      );

      test('markSaveError leaves dirty untouched — "no pisar silenciosamente" '
          '(N7.1 §15)', () {
        final controller = BoardEditorController.forDevice(
          tenantId: 'tenant-a',
          layout: _sampleLayout(),
          catalog: emptyDeviceMetricCatalog,
        );
        controller.selectItem('metric-0');
        controller.moveSelectedBy(1, 0);
        controller.markSaving();
        controller.markSaveError('configuration_conflict');
        expect(controller.saveStatus, BoardSaveStatus.error);
        expect(controller.saveError, 'configuration_conflict');
        expect(controller.dirty, isTrue, reason: 'edits must not be discarded');
      });
    },
  );

  group('N7.1 §13/§14 — BoardEditorPage end to end in device mode', () {
    testWidgets('load → select+move (dirty) → Guardar → saved, version bumps', (
      tester,
    ) async {
      BoardContentLayout? savedLayout;
      int? savedExpectedVersion;
      await pump(
        tester,
        BoardEditorPage(
          isOwner: true,
          deviceContext: BoardEditorDeviceContext(
            tenantId: 'tenant-a',
            deviceId: 'device-1',
            initialLayout: _sampleLayout(),
            profile: null,
            profileId: null,
            onSave: (layout, expectedVersion) async {
              savedLayout = layout;
              savedExpectedVersion = expectedVersion;
              return expectedVersion + 1;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sin cambios · v1'), findsOneWidget);
      final saveButton = find.byKey(const ValueKey('editor-device-save'));
      expect(
        (tester.widget(saveButton) as FilledButton).onPressed,
        isNull,
        reason: 'nothing to save yet',
      );

      // Select the metric item (same interaction existing preset/fixture
      // tests already use — `edit-placement-<item.id>`) then move it.
      await tester.tap(find.byKey(const ValueKey('edit-placement-metric-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-move-right')));
      await tester.pumpAndSettle();

      expect(find.text('Cambios sin guardar'), findsOneWidget);
      expect(
        (tester.widget(saveButton) as FilledButton).onPressed,
        isNotNull,
        reason: 'dirty must enable Guardar',
      );

      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(savedExpectedVersion, 1);
      expect(savedLayout, isNotNull);
      expect(savedLayout!.items.first.placement.x, 1);
      expect(find.textContaining('Guardado · v2'), findsOneWidget);
      expect(
        (tester.widget(saveButton) as FilledButton).onPressed,
        isNull,
        reason: 'nothing left to save right after a successful save',
      );
    });

    testWidgets(
      'a FirestoreVersionConflict from onSave shows the error and keeps '
      'dirty true (N7.1 §15 — no pisar silenciosamente)',
      (tester) async {
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            deviceContext: BoardEditorDeviceContext(
              tenantId: 'tenant-a',
              deviceId: 'device-1',
              initialLayout: _sampleLayout(),
              profile: null,
              profileId: null,
              onSave: (layout, expectedVersion) async {
                throw const FirestoreVersionConflict(
                  entityType: 'deviceBoardConfig',
                  entityId: 'tenant-a/device-1',
                  expectedVersion: 1,
                  actualVersion: 2,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('edit-placement-metric-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-move-right')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('editor-device-save')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Error al guardar'), findsOneWidget);
        expect(find.textContaining('FirestoreVersionConflict'), findsOneWidget);
        // Still enabled — the edit is still there, unsaved.
        expect(
          (tester.widget(find.byKey(const ValueKey('editor-device-save')))
                  as FilledButton)
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'recargar: reopening with the freshly-saved layout reflects the '
      'persisted change and resets dirty/save status',
      (tester) async {
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            deviceContext: BoardEditorDeviceContext(
              tenantId: 'tenant-a',
              deviceId: 'device-1',
              initialLayout: _sampleLayout(layoutVersion: 2),
              profile: null,
              profileId: null,
              onSave: (layout, expectedVersion) async => expectedVersion + 1,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sin cambios · v2'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('edit-placement-metric-0')),
          findsOneWidget,
        );
      },
    );
  });
}
