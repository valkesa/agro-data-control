import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/device_capabilities/capability_admin_page.dart';
import 'package:agro_data_control/device_capabilities/capability_indicator_definition.dart';
import 'package:agro_data_control/device_capabilities/capability_library_store.dart';
import 'package:agro_data_control/device_capabilities/capability_metric_definition.dart';
import 'package:agro_data_control/device_capabilities/device_capability_profile_store.dart';
import 'package:agro_data_control/device_capabilities/indicator_binding.dart';
import 'package:agro_data_control/device_capabilities/metric_binding.dart';
import 'package:agro_data_control/ui_templates/enums/metric_display_type.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

({
  MetricLibraryStore metrics,
  IndicatorLibraryStore indicators,
  DeviceCapabilityProfileStore profiles,
  BoardPresetCatalog presets,
})
_isolatedStores() => (
  metrics: MetricLibraryStore(),
  indicators: IndicatorLibraryStore(),
  profiles: DeviceCapabilityProfileStore(),
  presets: BoardPresetCatalog(initial: []),
);

void main() {
  group('N6.5.2 §10 — Capacidades: navegación de tabs', () {
    testWidgets('las 3 tabs existen y cambian el contenido visible', (
      tester,
    ) async {
      final s = _isolatedStores();
      await pump(
        tester,
        CapabilityAdminPage(
          isOwner: true,
          metricLibrary: s.metrics,
          indicatorLibrary: s.indicators,
          profileStore: s.profiles,
          presetCatalog: s.presets,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('BIBLIOTECA DE MÉTRICAS'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('capability-admin-tab-indicators')),
      );
      await tester.pumpAndSettle();
      expect(find.text('BIBLIOTECA DE INDICATORS'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('capability-admin-tab-profiles')),
      );
      await tester.pumpAndSettle();
      expect(find.text('PERFILES DE CAPACIDADES'), findsOneWidget);
    });

    testWidgets('non-owner ve el mensaje de acceso denegado', (tester) async {
      final s = _isolatedStores();
      await pump(
        tester,
        CapabilityAdminPage(
          isOwner: false,
          metricLibrary: s.metrics,
          indicatorLibrary: s.indicators,
          profileStore: s.profiles,
          presetCatalog: s.presets,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Capacidades disponible solo para owner'),
        findsOneWidget,
      );
    });
  });

  group('N6.5.2 §11 — CRUD Biblioteca de métricas', () {
    testWidgets('crear métrica sin tocar código, editarla en vivo', (
      tester,
    ) async {
      final s = _isolatedStores();
      await pump(
        tester,
        CapabilityAdminPage(
          isOwner: true,
          metricLibrary: s.metrics,
          indicatorLibrary: s.indicators,
          profileStore: s.profiles,
          presetCatalog: s.presets,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-new-metric')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-capability-metric-key')),
        'pressure',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-capability-metric-label')),
        'Presión',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('new-capability-metric-confirm')),
      );
      await tester.pumpAndSettle();

      expect(s.metrics.byKey('pressure'), isNotNull);
      expect(find.text('DETALLE · Presión'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('capability-admin-metric-label')),
        'Presión diferencial',
      );
      await tester.pump();
      expect(s.metrics.byKey('pressure')!.label, 'Presión diferencial');
    });

    testWidgets(
      'duplicate metricKey se rechaza con mensaje, no crea la métrica',
      (tester) async {
        final s = _isolatedStores();
        s.metrics.upsert(
          CapabilityMetricDefinition(
            key: 'tempInterior',
            label: 'Temperatura interior',
            defaultUnit: '°C',
            icon: 'thermometer',
            displayType: MetricDisplayType.number,
            decimals: 1,
          ),
        );
        await pump(
          tester,
          CapabilityAdminPage(
            isOwner: true,
            metricLibrary: s.metrics,
            indicatorLibrary: s.indicators,
            profileStore: s.profiles,
            presetCatalog: s.presets,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-new-metric')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('new-capability-metric-key')),
          'tempInterior',
        );
        await tester.enterText(
          find.byKey(const ValueKey('new-capability-metric-label')),
          'Otra',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('new-capability-metric-confirm')),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('ya existe en la biblioteca'),
          findsOneWidget,
        );
        expect(s.metrics.metrics, hasLength(1));
      },
    );

    testWidgets('eliminar una métrica referenciada por un perfil se bloquea', (
      tester,
    ) async {
      final s = _isolatedStores();
      s.metrics.upsert(
        CapabilityMetricDefinition(
          key: 'tempInterior',
          label: 'Temperatura interior',
          defaultUnit: '°C',
          icon: 'thermometer',
          displayType: MetricDisplayType.number,
          decimals: 1,
        ),
      );
      final profile = s.profiles.create(name: 'Perfil X');
      s.profiles.addMetric(
        profile.id,
        'tempInterior',
        MetricBinding(sourceField: 'x.temp'),
      );
      await pump(
        tester,
        CapabilityAdminPage(
          isOwner: true,
          metricLibrary: s.metrics,
          indicatorLibrary: s.indicators,
          profileStore: s.profiles,
          presetCatalog: s.presets,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-metric-tempInterior')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-delete-metric')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('capability-metric-delete-reference-warning'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('capability-metric-delete-confirm')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('eliminar sin referencias funciona directo', (tester) async {
      final s = _isolatedStores();
      s.metrics.upsert(
        CapabilityMetricDefinition(
          key: 'tempInterior',
          label: 'Temperatura interior',
          defaultUnit: '°C',
          icon: 'thermometer',
          displayType: MetricDisplayType.number,
          decimals: 1,
        ),
      );
      await pump(
        tester,
        CapabilityAdminPage(
          isOwner: true,
          metricLibrary: s.metrics,
          indicatorLibrary: s.indicators,
          profileStore: s.profiles,
          presetCatalog: s.presets,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-metric-tempInterior')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-delete-metric')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-metric-delete-confirm')),
      );
      await tester.pumpAndSettle();
      expect(s.metrics.byKey('tempInterior'), isNull);
    });
  });

  group('N6.5.2 §12 — CRUD Biblioteca de indicators', () {
    testWidgets('crear indicator, editarlo, duplicarlo, eliminarlo', (
      tester,
    ) async {
      final s = _isolatedStores();
      await pump(
        tester,
        CapabilityAdminPage(
          isOwner: true,
          metricLibrary: s.metrics,
          indicatorLibrary: s.indicators,
          profileStore: s.profiles,
          presetCatalog: s.presets,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-tab-indicators')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-new-indicator')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-capability-indicator-key')),
        'heater',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-capability-indicator-label')),
        'Calefacción',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('new-capability-indicator-confirm')),
      );
      await tester.pumpAndSettle();
      expect(s.indicators.byKey('heater'), isNotNull);

      await tester.tap(
        find.byKey(const ValueKey('capability-admin-duplicate-indicator')),
      );
      await tester.pumpAndSettle();
      expect(s.indicators.indicators, hasLength(2));

      await tester.tap(
        find.byKey(const ValueKey('capability-admin-delete-indicator')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-indicator-delete-confirm')),
      );
      await tester.pumpAndSettle();
      expect(s.indicators.indicators, hasLength(1));
    });

    testWidgets('eliminar un indicator referenciado por un perfil se bloquea', (
      tester,
    ) async {
      final s = _isolatedStores();
      s.indicators.upsert(
        CapabilityIndicatorDefinition(
          key: 'heater',
          label: 'Calefacción',
          defaultIcon: 'flame',
        ),
      );
      final profile = s.profiles.create(name: 'Perfil X');
      s.profiles.addIndicator(
        profile.id,
        'heater',
        IndicatorBinding(sourceField: 'x'),
      );
      await pump(
        tester,
        CapabilityAdminPage(
          isOwner: true,
          metricLibrary: s.metrics,
          indicatorLibrary: s.indicators,
          profileStore: s.profiles,
          presetCatalog: s.presets,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-tab-indicators')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-indicator-heater')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-delete-indicator')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('capability-indicator-delete-reference-warning'),
        ),
        findsOneWidget,
      );
    });
  });

  group('N6.5.2 §13 — CRUD Perfil de capacidades', () {
    testWidgets('crear, duplicar perfil', (tester) async {
      final s = _isolatedStores();
      await pump(
        tester,
        CapabilityAdminPage(
          isOwner: true,
          metricLibrary: s.metrics,
          indicatorLibrary: s.indicators,
          profileStore: s.profiles,
          presetCatalog: s.presets,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-tab-profiles')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-new-profile')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-capability-profile-name')),
        'Sala nueva',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('new-capability-profile-confirm')),
      );
      await tester.pumpAndSettle();
      expect(s.profiles.profiles, hasLength(1));

      await tester.tap(
        find.byKey(const ValueKey('capability-admin-duplicate-profile')),
      );
      await tester.pumpAndSettle();
      expect(s.profiles.profiles, hasLength(2));
      expect(s.profiles.profiles.last.name, contains('copia'));
    });

    testWidgets(
      'agregar/quitar métrica y indicator del perfil; binding sourceField por perfil',
      (tester) async {
        final s = _isolatedStores();
        s.metrics.upsert(
          CapabilityMetricDefinition(
            key: 'tempInterior',
            label: 'Temperatura interior',
            defaultUnit: '°C',
            icon: 'thermometer',
            displayType: MetricDisplayType.number,
            decimals: 1,
          ),
        );
        s.indicators.upsert(
          CapabilityIndicatorDefinition(
            key: 'heater',
            label: 'Calefacción',
            defaultIcon: 'flame',
          ),
        );
        final profile = s.profiles.create(name: 'Sala A');
        await pump(
          tester,
          CapabilityAdminPage(
            isOwner: true,
            metricLibrary: s.metrics,
            indicatorLibrary: s.indicators,
            profileStore: s.profiles,
            presetCatalog: s.presets,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-tab-profiles')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('capability-admin-profile-${profile.id}')),
        );
        await tester.pumpAndSettle();

        // Add metric with a binding.
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-profile-add-metric')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(
            const ValueKey('capability-admin-add-metric-source-field'),
          ),
          'salaA.temp',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-add-metric-confirm')),
        );
        await tester.pumpAndSettle();
        expect(
          s.profiles.byId(profile.id)!.metricKeys,
          contains('tempInterior'),
        );
        expect(
          s.profiles
              .byId(profile.id)!
              .metricBindings['tempInterior']!
              .sourceField,
          'salaA.temp',
        );

        // Add indicator with a binding.
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-profile-add-indicator')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(
            const ValueKey('capability-admin-add-indicator-source-field'),
          ),
          'salaA.heater',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-add-indicator-confirm')),
        );
        await tester.pumpAndSettle();
        expect(s.profiles.byId(profile.id)!.indicatorKeys, contains('heater'));

        // Edit the metric binding's sourceField.
        await tester.tap(
          find.byKey(
            const ValueKey(
              'capability-admin-profile-edit-metric-binding-tempInterior',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(
            const ValueKey('capability-admin-metric-binding-source-field'),
          ),
          'salaA.temp.v2',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-metric-binding-confirm')),
        );
        await tester.pumpAndSettle();
        expect(
          s.profiles
              .byId(profile.id)!
              .metricBindings['tempInterior']!
              .sourceField,
          'salaA.temp.v2',
        );

        // Remove the metric and indicator.
        await tester.tap(
          find.byKey(
            const ValueKey(
              'capability-admin-profile-remove-metric-tempInterior',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(s.profiles.byId(profile.id)!.metricKeys, isEmpty);
        await tester.tap(
          find.byKey(
            const ValueKey('capability-admin-profile-remove-indicator-heater'),
          ),
        );
        await tester.pumpAndSettle();
        expect(s.profiles.byId(profile.id)!.indicatorKeys, isEmpty);
      },
    );

    testWidgets(
      'suggestedIndicatorsByMetric: togglear sugeridos para una métrica',
      (tester) async {
        final s = _isolatedStores();
        s.metrics.upsert(
          CapabilityMetricDefinition(
            key: 'tempInterior',
            label: 'Temperatura interior',
            defaultUnit: '°C',
            icon: 'thermometer',
            displayType: MetricDisplayType.number,
            decimals: 1,
          ),
        );
        s.indicators.upsert(
          CapabilityIndicatorDefinition(
            key: 'heater',
            label: 'Calefacción',
            defaultIcon: 'flame',
          ),
        );
        s.indicators.upsert(
          CapabilityIndicatorDefinition(
            key: 'fan',
            label: 'Ventilador',
            defaultIcon: 'fan',
          ),
        );
        final profile = s.profiles.create(name: 'Sala A');
        s.profiles.addMetric(
          profile.id,
          'tempInterior',
          MetricBinding(sourceField: 'x'),
        );
        s.profiles.addIndicator(
          profile.id,
          'heater',
          IndicatorBinding(sourceField: 'y'),
        );
        s.profiles.addIndicator(
          profile.id,
          'fan',
          IndicatorBinding(sourceField: 'z'),
        );
        await pump(
          tester,
          CapabilityAdminPage(
            isOwner: true,
            metricLibrary: s.metrics,
            indicatorLibrary: s.indicators,
            profileStore: s.profiles,
            presetCatalog: s.presets,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-tab-profiles')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('capability-admin-profile-${profile.id}')),
        );
        await tester.pumpAndSettle();
        // Select the metric row to reveal the suggested-indicators section.
        await tester.tap(
          find.byKey(
            const ValueKey('capability-admin-profile-metric-tempInterior'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('capability-admin-suggested-heater')),
        );
        await tester.pumpAndSettle();
        expect(
          s.profiles
              .byId(profile.id)!
              .suggestedIndicatorsByMetric['tempInterior'],
          ['heater'],
        );

        // "fan" stays unsuggested — a suggestion is opt-in per indicator.
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(const ValueKey('capability-admin-suggested-fan')),
              )
              .selected,
          isFalse,
        );
      },
    );

    testWidgets(
      'eliminar un perfil referenciado por un BoardPreset se bloquea',
      (tester) async {
        final s = _isolatedStores();
        final profile = s.profiles.create(name: 'Sala A');
        s.presets.create(
          name: 'Board usando Sala A',
          layout: buildLayoutTemplate(6, 4),
          capabilityProfileId: profile.id,
        );
        await pump(
          tester,
          CapabilityAdminPage(
            isOwner: true,
            metricLibrary: s.metrics,
            indicatorLibrary: s.indicators,
            profileStore: s.profiles,
            presetCatalog: s.presets,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-tab-profiles')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('capability-admin-profile-${profile.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('capability-admin-delete-profile')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey('capability-profile-delete-reference-warning'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('capability-profile-delete-confirm')),
              )
              .onPressed,
          isNull,
        );
      },
    );
  });

  group('N6.5.2 — revisión: sourceField inválido en un binding nunca crashea, '
      'siempre muestra error inline', () {
    late MetricLibraryStore metrics;
    late IndicatorLibraryStore indicators;
    late DeviceCapabilityProfileStore profiles;
    late String profileId;

    setUp(() {
      metrics = MetricLibraryStore();
      indicators = IndicatorLibraryStore();
      profiles = DeviceCapabilityProfileStore();
      metrics.upsert(
        CapabilityMetricDefinition(
          key: 'tempInterior',
          label: 'Temperatura interior',
          defaultUnit: '°C',
          icon: 'thermometer',
          displayType: MetricDisplayType.number,
          decimals: 1,
        ),
      );
      indicators.upsert(
        CapabilityIndicatorDefinition(
          key: 'heater',
          label: 'Calefacción',
          defaultIcon: 'flame',
        ),
      );
      profileId = profiles.create(name: 'Sala A').id;
    });

    Future<void> openProfile(WidgetTester tester) async {
      await pump(
        tester,
        CapabilityAdminPage(
          isOwner: true,
          metricLibrary: metrics,
          indicatorLibrary: indicators,
          profileStore: profiles,
          presetCatalog: BoardPresetCatalog(initial: []),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-tab-profiles')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('capability-admin-profile-$profileId')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('agregar métrica con sourceField inválido', (tester) async {
      await openProfile(tester);
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-profile-add-metric')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('capability-admin-add-metric-source-field')),
        'invalid source field',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-add-metric-confirm')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('sourceField inválido'), findsOneWidget);
      expect(profiles.byId(profileId)!.metricKeys, isEmpty);
    });

    testWidgets('editar el binding de una métrica con sourceField inválido', (
      tester,
    ) async {
      profiles.addMetric(
        profileId,
        'tempInterior',
        MetricBinding(sourceField: 'ok'),
      );
      await openProfile(tester);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'capability-admin-profile-edit-metric-binding-tempInterior',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey('capability-admin-metric-binding-source-field'),
        ),
        'invalid source field',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-metric-binding-confirm')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('sourceField inválido'), findsOneWidget);
      // The previously-valid binding survives untouched.
      expect(
        profiles.byId(profileId)!.metricBindings['tempInterior']!.sourceField,
        'ok',
      );
    });

    testWidgets('agregar indicator con sourceField inválido', (tester) async {
      await openProfile(tester);
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-profile-add-indicator')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey('capability-admin-add-indicator-source-field'),
        ),
        'invalid source field',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('capability-admin-add-indicator-confirm')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('sourceField inválido'), findsOneWidget);
      expect(profiles.byId(profileId)!.indicatorKeys, isEmpty);
    });

    testWidgets('editar el binding de un indicator con sourceField inválido', (
      tester,
    ) async {
      profiles.addIndicator(
        profileId,
        'heater',
        IndicatorBinding(sourceField: 'ok'),
      );
      await openProfile(tester);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'capability-admin-profile-edit-indicator-binding-heater',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey('capability-admin-indicator-binding-source-field'),
        ),
        'invalid source field',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey('capability-admin-indicator-binding-confirm'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('sourceField inválido'), findsOneWidget);
      expect(
        profiles.byId(profileId)!.indicatorBindings['heater']!.sourceField,
        'ok',
      );
    });
  });
}
