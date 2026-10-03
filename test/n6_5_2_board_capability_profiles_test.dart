import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/board_preview/board_editor_canvas.dart';
import 'package:agro_data_control/board_preview/board_editor_controller.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/device_capabilities/capability_indicator_definition.dart';
import 'package:agro_data_control/device_capabilities/device_capability_profile_store.dart';
import 'package:agro_data_control/device_capabilities/indicator_binding.dart';
import 'package:agro_data_control/device_capabilities/metric_binding.dart';
import 'package:agro_data_control/device_capabilities/reference_capability_seeds.dart';

/// N6.5.2 §21/§22 (grupo "Board") — the Board Editor no longer restricts
/// indicator selection to a fixed per-metric list (that restriction is
/// exactly what N6.5.2 removes, §7/§9): every indicator the active *profile*
/// offers is selectable for any metric it has, `suggestedIndicatorsByMetric`
/// is only a prefill, and an indicator the profile doesn't have can never
/// appear at all.
Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

BoardEditorController _liveController(WidgetTester tester) =>
    tester.widget<BoardEditorCanvas>(find.byType(BoardEditorCanvas)).controller;

Finder _issuesPanel() => find.byKey(const ValueKey('editor-issues-panel'));

bool _issuesContain(WidgetTester tester, String code) => tester
    .widgetList<Text>(
      find.descendant(of: _issuesPanel(), matching: find.byType(Text)),
    )
    .any((t) => (t.data ?? '').contains(code));

/// Builds the §21 acceptance-case fixtures fresh for each test: a private
/// [DeviceCapabilityProfileStore] (so "Sala A"/"Sala B" never leak into
/// other tests or the shared admin store) reusing the *shared*, already
/// seeded `tempInterior` global metric (proving reuse across a 3rd/4th
/// profile beyond N6.5's own two), plus 3 fresh global indicators
/// (`heater`/`fan`/`humidifier`) upserted into the shared indicator
/// library — those keys don't collide with the real seed indicators
/// (`calefaccionEtapa1`/`calefaccionEtapa2`/`humidificacion`).
({DeviceCapabilityProfileStore profiles, String profileAId, String profileBId})
_seedAcceptanceCaseProfiles() {
  sharedIndicatorLibraryStore.upsert(
    CapabilityIndicatorDefinition(
      key: 'heater',
      label: 'Heater',
      defaultIcon: 'flame',
    ),
  );
  sharedIndicatorLibraryStore.upsert(
    CapabilityIndicatorDefinition(key: 'fan', label: 'Fan', defaultIcon: 'fan'),
  );
  sharedIndicatorLibraryStore.upsert(
    CapabilityIndicatorDefinition(
      key: 'humidifier',
      label: 'Humidifier',
      defaultIcon: 'snowflake',
    ),
  );
  final profiles = DeviceCapabilityProfileStore();
  final a = profiles.create(name: 'Sala A');
  profiles.addMetric(
    a.id,
    'tempInterior',
    MetricBinding(sourceField: 'salaA.temp'),
  );
  profiles.addIndicator(
    a.id,
    'heater',
    IndicatorBinding(sourceField: 'salaA.heater'),
  );
  profiles.addIndicator(
    a.id,
    'fan',
    IndicatorBinding(sourceField: 'salaA.fan'),
  );
  profiles.setSuggestedIndicators(a.id, 'tempInterior', ['heater']);

  final b = profiles.create(name: 'Sala B');
  profiles.addMetric(
    b.id,
    'tempInterior',
    MetricBinding(sourceField: 'salaB.temp'),
  );
  profiles.addIndicator(
    b.id,
    'humidifier',
    IndicatorBinding(sourceField: 'salaB.humidifier'),
  );

  return (profiles: profiles, profileAId: a.id, profileBId: b.id);
}

Future<void> openAgregarTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
  await tester.pumpAndSettle();
}

void main() {
  group('N6.5.2 §22 Board — crear/agregar/seleccionar indicators', () {
    testWidgets(
      'crear un BoardPreset con perfil resuelve sus métricas reales',
      (tester) async {
        final fixtures = _seedAcceptanceCaseProfiles();
        final presets = BoardPresetCatalog(initial: []);
        final preset = presets.create(
          name: 'Board Sala A',
          layout: buildLayoutTemplate(6, 4),
          capabilityProfileId: fixtures.profileAId,
        );
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            presetId: preset.id,
            presetCatalog: presets,
            capabilityProfileStore: fixtures.profiles,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _liveController(tester).catalog.metricByKey('tempInterior'),
          isNotNull,
        );
      },
    );

    testWidgets(
      'agregar la métrica del perfil, con el indicator sugerido pre-tildado',
      (tester) async {
        final fixtures = _seedAcceptanceCaseProfiles();
        final presets = BoardPresetCatalog(initial: []);
        final preset = presets.create(
          name: 'Board Sala A',
          layout: buildLayoutTemplate(6, 4),
          capabilityProfileId: fixtures.profileAId,
        );
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            presetId: preset.id,
            presetCatalog: presets,
            capabilityProfileStore: fixtures.profiles,
          ),
        );
        await tester.pumpAndSettle();
        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();

        // Both "heater" (suggested) and "fan" (not suggested) are offered —
        // the whole profile's indicator list, not a fixed per-metric subset.
        expect(
          find.byKey(const ValueKey('editor-pending-indicator-heater')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('editor-pending-indicator-fan')),
          findsOneWidget,
        );
        // Only "heater" is pre-checked (suggested).
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(const ValueKey('editor-pending-indicator-heater')),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(const ValueKey('editor-pending-indicator-fan')),
              )
              .selected,
          isFalse,
        );
      },
    );

    testWidgets(
      'seleccionar un indicator disponible pero NO sugerido (fan) igual funciona',
      (tester) async {
        final fixtures = _seedAcceptanceCaseProfiles();
        final presets = BoardPresetCatalog(initial: []);
        final preset = presets.create(
          name: 'Board Sala A',
          layout: buildLayoutTemplate(6, 4),
          capabilityProfileId: fixtures.profileAId,
        );
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            presetId: preset.id,
            presetCatalog: presets,
            capabilityProfileStore: fixtures.profiles,
          ),
        );
        await tester.pumpAndSettle();
        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();
        // Add "fan" (not suggested) on top of the pre-checked "heater".
        await tester.tap(
          find.byKey(const ValueKey('editor-pending-indicator-fan')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
        await tester.pumpAndSettle();

        final content = presets.byId(preset.id)!.items.single.content;
        // ignore: avoid_dynamic_calls
        expect(
          (content as dynamic).indicatorKeys,
          containsAll(['heater', 'fan']),
        );
      },
    );

    testWidgets(
      'quitar el indicator sugerido (heater) antes de confirmar también funciona',
      (tester) async {
        final fixtures = _seedAcceptanceCaseProfiles();
        final presets = BoardPresetCatalog(initial: []);
        final preset = presets.create(
          name: 'Board Sala A',
          layout: buildLayoutTemplate(6, 4),
          capabilityProfileId: fixtures.profileAId,
        );
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            presetId: preset.id,
            presetCatalog: presets,
            capabilityProfileStore: fixtures.profiles,
          ),
        );
        await tester.pumpAndSettle();
        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();
        // Un-check "heater" (suggested by default).
        await tester.tap(
          find.byKey(const ValueKey('editor-pending-indicator-heater')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
        await tester.pumpAndSettle();

        final content = presets.byId(preset.id)!.items.single.content;
        // ignore: avoid_dynamic_calls
        expect((content as dynamic).indicatorKeys, isEmpty);
      },
    );

    testWidgets(
      'un indicator que el perfil no ofrece (humidifier en Sala A) nunca aparece como opción',
      (tester) async {
        final fixtures = _seedAcceptanceCaseProfiles();
        final presets = BoardPresetCatalog(initial: []);
        final preset = presets.create(
          name: 'Board Sala A',
          layout: buildLayoutTemplate(6, 4),
          capabilityProfileId: fixtures.profileAId,
        );
        await pump(
          tester,
          BoardEditorPage(
            isOwner: true,
            presetId: preset.id,
            presetCatalog: presets,
            capabilityProfileStore: fixtures.profiles,
          ),
        );
        await tester.pumpAndSettle();
        await openAgregarTab(tester);
        await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
        await tester.pumpAndSettle();

        // "humidifier" belongs to Sala B, not Sala A — never selectable here.
        expect(
          find.byKey(const ValueKey('editor-pending-indicator-humidifier')),
          findsNothing,
        );
      },
    );
  });

  group(
    'N6.5.2 §21 — caso crítico de aceptación, de punta a punta por la UI real',
    () {
      testWidgets(
        'Board A (Sala A) usa heater+fan; Board B (Sala B) usa humidifier; nunca '
        'duplica tempInterior ni deja elegir heater en Sala B',
        (tester) async {
          final fixtures = _seedAcceptanceCaseProfiles();
          final presets = BoardPresetCatalog(initial: []);

          // Board A: tempInterior + heater + fan (fan added despite not being
          // suggested — §22 "seleccionar indicator disponible pero no sugerido").
          final presetA = presets.create(
            name: 'Board A',
            layout: buildLayoutTemplate(6, 4),
            capabilityProfileId: fixtures.profileAId,
          );
          await pump(
            tester,
            BoardEditorPage(
              isOwner: true,
              presetId: presetA.id,
              presetCatalog: presets,
              capabilityProfileStore: fixtures.profiles,
            ),
          );
          await tester.pumpAndSettle();
          await openAgregarTab(tester);
          await tester.tap(
            find.byKey(const ValueKey('editor-add-type-metric')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('editor-pending-indicator-fan')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
          await tester.pumpAndSettle();
          final contentA = presets.byId(presetA.id)!.items.single.content;
          // ignore: avoid_dynamic_calls
          expect(
            (contentA as dynamic).indicatorKeys,
            containsAll(['heater', 'fan']),
          );

          // Board B: tempInterior + humidifier — heater must never be offered.
          final presetB = presets.create(
            name: 'Board B',
            layout: buildLayoutTemplate(6, 4),
            capabilityProfileId: fixtures.profileBId,
          );
          // Force a full teardown before re-pumping: without this, Flutter
          // reuses the existing BoardEditorPage State (same widget position)
          // instead of running a fresh initState() for presetB, leaving
          // Board A's controller/profile alive underneath.
          await tester.pumpWidget(const SizedBox());
          await pump(
            tester,
            BoardEditorPage(
              isOwner: true,
              presetId: presetB.id,
              presetCatalog: presets,
              capabilityProfileStore: fixtures.profiles,
            ),
          );
          await tester.pumpAndSettle();
          await openAgregarTab(tester);
          await tester.tap(
            find.byKey(const ValueKey('editor-add-type-metric')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('editor-pending-indicator-heater')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('editor-pending-indicator-humidifier')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('editor-pending-indicator-humidifier')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
          await tester.pumpAndSettle();
          final contentB = presets.byId(presetB.id)!.items.single.content;
          // ignore: avoid_dynamic_calls
          expect((contentB as dynamic).indicatorKeys, ['humidifier']);

          // Never duplicated the global tempInterior definition.
          expect(
            sharedMetricLibraryStore.metrics.where(
              (m) => m.key == 'tempInterior',
            ),
            hasLength(1),
          );
        },
      );
    },
  );

  group('N6.5.2 §19 — cambio de perfil en un Board existente', () {
    testWidgets('Perfil A → Perfil B solo filtra; no borra ni invalida items', (
      tester,
    ) async {
      final fixtures = _seedAcceptanceCaseProfiles();
      final presets = BoardPresetCatalog(initial: []);
      final preset = presets.create(
        name: 'Board cambia de perfil',
        layout: buildLayoutTemplate(6, 4),
        capabilityProfileId: fixtures.profileAId,
      );
      await pump(
        tester,
        BoardEditorPage(
          isOwner: true,
          presetId: preset.id,
          presetCatalog: presets,
          capabilityProfileStore: fixtures.profiles,
        ),
      );
      await tester.pumpAndSettle();
      await openAgregarTab(tester);
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      // Keep the suggested "heater" checked, confirm.
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();
      expect(presets.byId(preset.id)!.items, hasLength(1));

      final before = presets.byId(preset.id)!.toMap();
      final versionBefore = presets.byId(preset.id)!.presetVersion;

      // Switch to Sala B, which doesn't have "heater". This is now only
      // a picker filter; validation still resolves against global libraries.
      await tester.tap(find.byKey(const ValueKey('editor-capability-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sala B').last);
      await tester.pumpAndSettle();

      // Item never deleted.
      expect(presets.byId(preset.id)!.items, hasLength(1));
      expect(_issuesContain(tester, 'indicator_not_available'), isFalse);
      expect(presets.byId(preset.id)!.toMap(), before);
      expect(presets.byId(preset.id)!.presetVersion, versionBefore);
    });
  });
}
