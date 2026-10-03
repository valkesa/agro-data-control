import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

void main() {
  group('E. UI — Fuente de datos (Etapa DataSourceBinding 1 §7)', () {
    testWidgets('item sin binding muestra "Sin configurar"', (tester) async {
      await _pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-data-source-unset')),
        findsOneWidget,
      );
      expect(find.text('Sin configurar'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-data-source-tenant')),
        findsNothing,
      );
    });

    testWidgets(
      'botón QA (§8) aplica un binding de ejemplo y la UI muestra tenant/site/device/métrica',
      (tester) async {
        await _pump(tester, const BoardEditorPage(isOwner: true));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('edit-placement-humidity')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-data-source-qa-sample')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('editor-data-source-qa-sample')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('editor-data-source-unset')),
          findsNothing,
        );
        expect(find.textContaining('Tenant: qa-tenant'), findsOneWidget);
        expect(find.textContaining('Site: qa-site'), findsOneWidget);
        expect(find.textContaining('Device: qa-device'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('editor-data-source-metric')),
          findsOneWidget,
        );
      },
    );

    testWidgets('el binding sobrevive editar un campo no relacionado (etiqueta visible)', (
      tester,
    ) async {
      await _pump(tester, const BoardEditorPage(isOwner: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-placement-humidity')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-data-source-qa-sample')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Tenant: qa-tenant'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('editor-metric-label-override')),
        'Humedad sala',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Tenant: qa-tenant'), findsOneWidget);
      expect(find.textContaining('Device: qa-device'), findsOneWidget);
    });
  });
}
