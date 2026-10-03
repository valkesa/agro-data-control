import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/board_presets/board_presets_page.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/device_capabilities/device_capability_profile_store.dart';
import 'package:agro_data_control/device_capabilities/reference_capability_seeds.dart';

/// N6.5.1 — Selección explícita de catálogo al crear un BoardPreset.
///
/// N6.5 already let an *existing* preset's catalog be changed from the
/// editor; the gap this stage closed was narrower:
/// `BoardPresetCatalog.create()` used to hardcode
/// `metricCatalogId: 'environment_room_v1'` and the "Nuevo preset" dialog
/// never asked, so a brand-new preset was silently bound to a catalog the
/// user never chose. These tests cover that delta — creation-time catalog
/// selection — not the switch/revalidation mechanics already covered by
/// N6.5. Field/identifier names were renamed to `capabilityProfileId`/
/// `DeviceCapabilityProfileStore`/etc. in N6.5.2's library/profile split;
/// the assertions below are otherwise unchanged.
Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

Future<void> createPresetViaDialog(
  WidgetTester tester, {
  required String name,
  String? catalogName,
}) async {
  await tester.tap(find.byKey(const ValueKey('presets-new')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('new-preset-name')), name);
  await tester.pump();
  if (catalogName != null) {
    await tester.tap(find.byKey(const ValueKey('new-preset-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(catalogName).last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('new-preset-confirm')));
  await tester.pumpAndSettle();
}

Future<void> openAgregarTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
  await tester.pumpAndSettle();
}

void main() {
  group('N6.5.1 §1/§3 — BoardPresetCatalog.create() no longer auto-asigna', () {
    test(
      'sin capabilityProfileId explícito, el preset nace con filtro global',
      () {
        final catalog = BoardPresetCatalog(initial: []);
        final preset = catalog.create(
          name: 'Prueba',
          layout: buildLayoutTemplate(6, 4),
        );
        expect(preset.capabilityProfileId, isNull);
      },
    );

    test('un capabilityProfileId explícito se persiste tal cual', () {
      final catalog = BoardPresetCatalog(initial: []);
      final preset = catalog.create(
        name: 'Prueba',
        layout: buildLayoutTemplate(6, 4),
        capabilityProfileId: 'laboratory_v1',
      );
      expect(preset.capabilityProfileId, 'laboratory_v1');
    });
  });

  group('N6.5.1 §2/§3/§10 — diálogo "Nuevo preset" pide el catálogo', () {
    testWidgets(
      '"Todas las métricas" persiste null y ofrece la biblioteca global',
      (tester) async {
        final catalog = BoardPresetCatalog(initial: []);
        await pump(tester, BoardPresetsPage(isOwner: true, catalog: catalog));
        await tester.pumpAndSettle();

        await createPresetViaDialog(tester, name: 'Arco libre');

        final created = catalog.presets.single;
        expect(created.capabilityProfileId, isNull);

        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-pending-metric-key')),
          findsOneWidget,
        );
        final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(const ValueKey('editor-pending-metric-key')),
        );
        expect(dropdown.items, isNotEmpty);
        expect(
          dropdown.items!.map((item) => item.value),
          containsAll(['tempInterior', 'vehiclesTotalDaily']),
        );
      },
    );

    testWidgets(
      'elegir un catálogo en el diálogo persiste su id y filtra Agregar '
      'métrica a solo sus métricas',
      (tester) async {
        final catalog = BoardPresetCatalog(initial: []);
        await pump(tester, BoardPresetsPage(isOwner: true, catalog: catalog));
        await tester.pumpAndSettle();

        await createPresetViaDialog(
          tester,
          name: 'Prueba laboratorio',
          catalogName: 'Temperatura y humedad',
        );

        final created = catalog.presets.single;
        expect(created.capabilityProfileId, 'laboratory_v1');

        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();
        // "Temperatura interior" is shared by both reference catalogs, but
        // "Delta punto de rocio" only exists in environment_room_v1 —
        // its absence here proves the list is scoped to laboratory_v1, not
        // silently pooling every catalog.
        expect(find.text('Temperatura interior'), findsWidgets);
        expect(find.text('Delta punto de rocio'), findsNothing);
      },
    );

    testWidgets(
      'caso de aceptación "Prueba laboratorio": cambiar de catálogo después '
      'de creado no borra items y actualiza la lista de Agregar métrica',
      (tester) async {
        final catalog = BoardPresetCatalog(initial: []);
        await pump(tester, BoardPresetsPage(isOwner: true, catalog: catalog));
        await tester.pumpAndSettle();

        await createPresetViaDialog(
          tester,
          name: 'Prueba laboratorio',
          catalogName: 'Temperatura y humedad',
        );

        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
        await tester.pumpAndSettle();

        final preset = catalog.presets.single;
        expect(preset.items, hasLength(1));

        // Cambiar a "Capacidades ambientales" desde el selector del editor.
        await tester.tap(
          find.byKey(const ValueKey('editor-capability-profile')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Capacidades ambientales').last);
        await tester.pumpAndSettle();

        // El item agregado nunca se borra al cambiar de catálogo (N6.5 §27,
        // reutilizado sin cambios por esta etapa).
        expect(catalog.byId(preset.id)!.items, hasLength(1));

        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('editor-pending-metric-key')),
        );
        await tester.pumpAndSettle();
        // Ahora sí aparece, porque Capacidades ambientales lo tiene.
        expect(find.text('Delta punto de rocio'), findsWidgets);
      },
    );
  });

  group('N6.5.1 §11 — caso de aceptación "Arco libre"', () {
    testWidgets(
      'Sin catálogo permite diseño libre; seleccionar un catálogo después '
      'habilita recién entonces sus métricas',
      (tester) async {
        final catalog = BoardPresetCatalog(initial: []);
        await pump(tester, BoardPresetsPage(isOwner: true, catalog: catalog));
        await tester.pumpAndSettle();

        await createPresetViaDialog(tester, name: 'Arco libre');
        expect(catalog.presets.single.capabilityProfileId, isNull);

        // Contenido libre (N6.4) sigue disponible sin catálogo.
        await openAgregarTab(tester);
        await tester.tap(
          find.byKey(const ValueKey('editor-add-type-placeholder')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
        await tester.pumpAndSettle();
        expect(catalog.presets.single.items, hasLength(1));

        // Recién al elegir "Capacidades de desinfección" aparecen sus
        // métricas — nunca antes, y nunca se pierde el placeholder ya
        // agregado.
        await tester.tap(
          find.byKey(const ValueKey('editor-capability-profile')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.textContaining('Capacidades de desinfección').last,
        );
        await tester.pumpAndSettle();

        expect(catalog.presets.single.items, hasLength(1));

        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();
        expect(find.text('Vehiculos desinfectados dia'), findsWidgets);
      },
    );
  });

  group('N6.5.1 §4 — seeds siguen sin bloquear el selector', () {
    testWidgets(
      'un preset seed abre con su catálogo real y el selector permite '
      'cambiarlo',
      (tester) async {
        final catalog = BoardPresetCatalog();
        final seed = catalog.presets.firstWhere(
          (p) => p.id == 'preset-laboratorio-estandar',
        );
        expect(seed.capabilityProfileId, 'laboratory_v1');

        await pump(tester, BoardPresetsPage(isOwner: true, catalog: catalog));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('preset-edit-${seed.id}')));
        await tester.pumpAndSettle();

        final dropdown = find.byKey(
          const ValueKey('editor-capability-profile'),
        );
        expect(dropdown, findsOneWidget);
        expect(
          tester.widget<DropdownButton<String?>>(dropdown).onChanged,
          isNotNull,
        );
      },
    );
  });

  test(
    'sharedDeviceCapabilityProfileStore expone los 3 catálogos de referencia',
    () {
      final ids = sharedDeviceCapabilityProfileStore.profiles.map((c) => c.id);
      expect(
        ids,
        containsAll([
          'environment_room_v1',
          'laboratory_v1',
          'disinfection_arch_v1',
        ]),
      );
    },
  );

  group('N6.5.1 — revisión: cambiar de catálogo con un "Agregar métrica" '
      'pendiente abierto', () {
    testWidgets(
      'una key incompatible con el catálogo nuevo nunca crashea el dropdown '
      'ni queda confirmable',
      (tester) async {
        // N6.5.2: unlike the retired `DeviceMetricCatalogStore()`, a fresh
        // `DeviceCapabilityProfileStore()` starts empty by design (no
        // implicit seeding) — reuse the shared reference profiles
        // explicitly so the dropdown has "Temperatura y humedad" to switch
        // to.
        final store = DeviceCapabilityProfileStore(
          initial: sharedDeviceCapabilityProfileStore.profiles,
        );
        final presets = BoardPresetCatalog(initial: []);
        final preset = presets.create(
          name: 'Repro',
          layout: buildLayoutTemplate(6, 4),
          capabilityProfileId: 'environment_room_v1',
        );
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            presetId: preset.id,
            presetCatalog: presets,
            capabilityProfileStore: store,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();

        // "Delta punto de rocio" (dewPointDelta) only exists in
        // environment_room_v1.
        await tester.tap(
          find.byKey(const ValueKey('editor-pending-metric-key')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delta punto de rocio').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Switch to laboratory_v1 (no dewPointDelta) without cancelling the
        // pending add first — before N6.5.1's fix this crashed the
        // DropdownMenuItem assertion on rebuild.
        await tester.tap(
          find.byKey(const ValueKey('editor-capability-profile')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Temperatura y humedad').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // The stale key must never be silently confirmable either.
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('editor-confirm-add')),
              )
              .onPressed,
          isNull,
        );
      },
    );
  });
}
