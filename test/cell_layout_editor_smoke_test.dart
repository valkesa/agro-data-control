import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_editor_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset_catalog.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

void main() {
  testWidgets('smoke: renders default_1x1 without throwing', (tester) async {
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
    expect(tester.takeException(), isNull);
    expect(find.text('Diseño de celda'), findsWidgets);
    expect(
      find.byKey(const ValueKey('cell-editor-canvas-panel')),
      findsOneWidget,
    );
  });

  testWidgets('selecting the value element shows its properties', (
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
    await tester.tap(find.byKey(const ValueKey('cell-editor-element-value')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Seleccionado: value (value)'), findsOneWidget);
  });
}
