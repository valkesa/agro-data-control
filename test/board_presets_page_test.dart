import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/board_presets/board_presets_page.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

void main() {
  group('BoardPresetsPage', () {
    testWidgets('owner sees the list, non-owner is denied', (tester) async {
      final catalog = BoardPresetCatalog(initial: []);
      await pump(tester, BoardPresetsPage(isOwner: false, catalog: catalog));
      await tester.pumpAndSettle();
      expect(
        find.text('Board Presets disponible solo para owner'),
        findsOneWidget,
      );

      await pump(tester, BoardPresetsPage(isOwner: true, catalog: catalog));
      await tester.pumpAndSettle();
      expect(find.text('BOARD PRESETS — OWNER ONLY'), findsOneWidget);
    });

    testWidgets(
      'Nuevo preset creates "Maternidad estándar" and opens the editor',
      (tester) async {
        final catalog = BoardPresetCatalog(initial: []);
        await pump(tester, BoardPresetsPage(isOwner: true, catalog: catalog));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('presets-new')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('new-preset-name')),
          'Maternidad estándar',
        );
        await tester.pump();
        // N6.5.1 §2/§3, N6.5.2 §18: the profile is never auto-assigned —
        // pick one explicitly so "Agregar métrica" below has something to
        // offer.
        await tester.tap(find.byKey(const ValueKey('new-preset-profile')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Capacidades ambientales').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('new-preset-confirm')));
        await tester.pumpAndSettle();

        // Creating a preset navigates straight into its editor (N6.2 §9).
        expect(find.text('BOARD PRESET EDITOR'), findsOneWidget);
        expect(
          find.text('Preset de tablero: Maternidad estándar'),
          findsOneWidget,
        );
        expect(
          catalog.presets.any((p) => p.name == 'Maternidad estándar'),
          isTrue,
        );
        expect(
          catalog.presets
              .firstWhere((p) => p.name == 'Maternidad estándar')
              .capabilityProfileId,
          'environment_room_v1',
        );

        // Add a metric, matching Chrome step 11.
        await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
        await tester.pumpAndSettle();

        final saved = catalog.presets.firstWhere(
          (p) => p.name == 'Maternidad estándar',
        );
        expect(saved.items, hasLength(1));
      },
    );

    testWidgets('Duplicar + editar duplicado never changes the original', (
      tester,
    ) async {
      final catalog = BoardPresetCatalog(initial: []);
      final original = catalog.create(
        name: 'Sala clima estándar',
        description: 'Original',
        layout: buildLayoutTemplate(6, 4),
        // N6.5.1: create() no longer defaults to a catalog — this test is
        // about duplicate independence, not catalog selection.
        capabilityProfileId: 'environment_room_v1',
      );
      await pump(tester, BoardPresetsPage(isOwner: true, catalog: catalog));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('preset-duplicate-${original.id}')));
      await tester.pumpAndSettle();

      final duplicate = catalog.presets.firstWhere((p) => p.id != original.id);
      expect(duplicate.name, contains('copia'));
      expect(
        find.byKey(ValueKey('preset-row-${duplicate.id}')),
        findsOneWidget,
      );

      // Editar duplicado: open its editor and add content.
      await tester.tap(find.byKey(ValueKey('preset-edit-${duplicate.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();

      // Comprobar original intacto (Chrome step 14).
      final originalAfter = catalog.byId(original.id)!;
      final duplicateAfter = catalog.byId(duplicate.id)!;
      expect(originalAfter.items, isEmpty);
      expect(duplicateAfter.items, hasLength(1));
    });

    testWidgets('Renombrar changes name/description but keeps the id', (
      tester,
    ) async {
      final catalog = BoardPresetCatalog(initial: []);
      final preset = catalog.create(
        name: 'Original',
        layout: buildLayoutTemplate(6, 1),
      );
      await pump(tester, BoardPresetsPage(isOwner: true, catalog: catalog));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('preset-rename-${preset.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rename-preset-name')),
        'Renombrado',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rename-preset-confirm')));
      await tester.pumpAndSettle();

      final updated = catalog.byId(preset.id)!;
      expect(updated.id, preset.id);
      expect(updated.name, 'Renombrado');
      expect(find.text('Renombrado'), findsOneWidget);
    });
  });
}
