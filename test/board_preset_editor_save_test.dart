import 'dart:async';

import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/board_preview/board_editor_canvas.dart';
import 'package:agro_data_control/board_preview/board_editor_controller.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/services/firestore_version_conflict.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
  await tester.pumpAndSettle();
}

BoardEditorController _controller(WidgetTester tester) =>
    tester.widget<BoardEditorCanvas>(find.byType(BoardEditorCanvas)).controller;

Future<void> _addMetric(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
  await tester.pumpAndSettle();
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('editor-preset-save')),
);

({BoardPresetCatalog catalog, BoardPreset preset}) _fixture({
  List<BoardContentItem> items = const [],
}) {
  final preset = BoardPreset(
    id: 'save-test',
    name: 'Guardado explícito',
    layoutTemplateId: 'grid_6x4',
    items: items,
    capabilityProfileId: 'environment_room_v1',
    presetVersion: 4,
  );
  return (catalog: BoardPresetCatalog(initial: [preset]), preset: preset);
}

void main() {
  testWidgets('A/B — dirty habilita Guardar y éxito actualiza baseline', (
    tester,
  ) async {
    final fixture = _fixture();
    BoardPreset? persisted;
    int? expected;
    await _pump(
      tester,
      BoardEditorPage(
        isOwner: true,
        presetId: fixture.preset.id,
        presetCatalog: fixture.catalog,
        onPresetSave: (draft, version) async {
          persisted = draft;
          expected = version;
          return 5;
        },
      ),
    );

    expect(_saveButton(tester).onPressed, isNull);
    await _addMetric(tester);
    expect(find.text('Cambios sin guardar'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('editor-preset-save')));
    await tester.pumpAndSettle();
    expect(expected, 4);
    expect(persisted!.items, hasLength(1));
    expect(_controller(tester).dirty, isFalse);
    expect(fixture.catalog.byId(fixture.preset.id)!.presetVersion, 5);
    expect(find.text('BoardPreset guardado'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('C — layout inválido mantiene Guardar deshabilitado', (
    tester,
  ) async {
    final invalid = BoardContentItem(
      id: 'outside',
      placement: GridPlacement(x: 99, y: 0, widthCells: 1, heightCells: 1),
      content: TextBoardContent(text: 'Fuera'),
    );
    final fixture = _fixture(items: [invalid]);
    await _pump(
      tester,
      BoardEditorPage(
        isOwner: true,
        presetId: fixture.preset.id,
        presetCatalog: fixture.catalog,
      ),
    );
    _controller(tester).setShowTitle(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('No se puede guardar'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('D — error de repository conserva dirty y el draft', (
    tester,
  ) async {
    final fixture = _fixture();
    await _pump(
      tester,
      BoardEditorPage(
        isOwner: true,
        presetId: fixture.preset.id,
        presetCatalog: fixture.catalog,
        onPresetSave: (_, _) async => throw StateError('fallo remoto'),
      ),
    );
    await _addMetric(tester);
    await tester.tap(find.byKey(const ValueKey('editor-preset-save')));
    await tester.pumpAndSettle();
    expect(_controller(tester).dirty, isTrue);
    expect(_controller(tester).items, hasLength(1));
    expect(find.textContaining('No se pudo guardar'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('conflicto versionado no pisa remoto y conserva el draft', (
    tester,
  ) async {
    final fixture = _fixture();
    await _pump(
      tester,
      BoardEditorPage(
        isOwner: true,
        presetId: fixture.preset.id,
        presetCatalog: fixture.catalog,
        onPresetSave: (_, _) async => throw FirestoreVersionConflict(
          entityType: 'boardPreset',
          entityId: fixture.preset.id,
          expectedVersion: 4,
          actualVersion: 5,
        ),
      ),
    );
    await _addMetric(tester);
    await tester.tap(find.byKey(const ValueKey('editor-preset-save')));
    await tester.pumpAndSettle();
    expect(_controller(tester).dirty, isTrue);
    expect(find.textContaining('Conflicto de versión'), findsOneWidget);
  });

  testWidgets('Reset restaura el último baseline guardado', (tester) async {
    final fixture = _fixture();
    await _pump(
      tester,
      BoardEditorPage(
        isOwner: true,
        presetId: fixture.preset.id,
        presetCatalog: fixture.catalog,
        onPresetSave: (_, version) async => version + 1,
      ),
    );
    await _addMetric(tester);
    await tester.tap(find.byKey(const ValueKey('editor-preset-save')));
    await tester.pumpAndSettle();
    _controller(tester).setShowTitle(false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-reset')));
    await tester.pumpAndSettle();
    expect(find.text('Restaurar último BoardPreset guardado'), findsOneWidget);
    await tester.tap(find.text('Restaurar'));
    await tester.pumpAndSettle();
    expect(_controller(tester).showTitle, isTrue);
    expect(_controller(tester).items, hasLength(1));
    expect(_controller(tester).dirty, isFalse);
  });

  testWidgets('E/G — guardar, volver limpio y reabrir conserva la métrica', (
    tester,
  ) async {
    final fixture = _fixture();
    BoardPreset remote = fixture.preset;
    await _pump(
      tester,
      _PresetHost(
        catalog: fixture.catalog,
        presetId: fixture.preset.id,
        save: (draft, version) async {
          remote = BoardPreset.fromMap(
            draft.toMap(),
          ).copyWith(presetVersion: version + 1);
          return remote.presetVersion;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-preset-editor')));
    await tester.pumpAndSettle();
    await _addMetric(tester);
    await tester.tap(find.byKey(const ValueKey('editor-preset-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar cambios?'), findsNothing);
    expect(find.byKey(const ValueKey('open-preset-editor')), findsOneWidget);
    expect(remote.items, hasLength(1));

    fixture.catalog.replaceAll([remote]);
    await tester.tap(find.byKey(const ValueKey('open-preset-editor')));
    await tester.pumpAndSettle();
    expect(_controller(tester).items, hasLength(1));
  });

  testWidgets('F — volver dirty mantiene el diálogo de descarte', (
    tester,
  ) async {
    final fixture = _fixture();
    await _pump(
      tester,
      _PresetHost(
        catalog: fixture.catalog,
        presetId: fixture.preset.id,
        save: (_, version) async => version + 1,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-preset-editor')));
    await tester.pumpAndSettle();
    await _addMetric(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar cambios?'), findsOneWidget);
  });

  testWidgets('saving bloquea acciones hasta completar el repository', (
    tester,
  ) async {
    final fixture = _fixture();
    final completer = Completer<int>();
    await _pump(
      tester,
      BoardEditorPage(
        isOwner: true,
        presetId: fixture.preset.id,
        presetCatalog: fixture.catalog,
        onPresetSave: (_, _) => completer.future,
      ),
    );
    await _addMetric(tester);
    await tester.tap(find.byKey(const ValueKey('editor-preset-save')));
    await tester.pump();
    expect(find.text('Guardando…'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    completer.complete(5);
    await tester.pumpAndSettle();
    expect(find.textContaining('BoardPreset guardado'), findsWidgets);
  });
}

class _PresetHost extends StatelessWidget {
  const _PresetHost({
    required this.catalog,
    required this.presetId,
    required this.save,
  });

  final BoardPresetCatalog catalog;
  final String presetId;
  final Future<int> Function(BoardPreset, int) save;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        key: const ValueKey('open-preset-editor'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BoardEditorPage(
              isOwner: true,
              presetId: presetId,
              presetCatalog: catalog,
              onPresetSave: save,
            ),
          ),
        ),
        child: const Text('Abrir'),
      ),
    ),
  );
}
