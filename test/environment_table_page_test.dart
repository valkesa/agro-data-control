// Widget tests for the productive "Tabla" view (EnvironmentTablePage).
//
// Migrated in Etapa 5B from a single unified table to
// `DeviceTableRenderer` (one section per `DeviceTemplate.tableSection`).
// `tenantId`/`siteId` are kept null across these tests and `templateIds`
// is supplied explicitly instead — this keeps template resolution
// deterministic without depending on the real `the-gene-pig`/`genetica-1`
// legacy mapping, and (together with a null/empty plcId where relevant)
// keeps the pig-count cell's `CerdasRepository.watchPigStats` call gated
// off, so the whole page can be pumped safely with no Firebase init.
import 'dart:io';

import 'package:agro_data_control/models/cerdas_models.dart';
import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:agro_data_control/services/cerdas_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firestore streams persistentes quedan fuera de build()', () {
    final String comparisonPageSource = File(
      'lib/pages/comparison_page.dart',
    ).readAsStringSync();
    final String mainSource = File('lib/main.dart').readAsStringSync();

    expect(
      comparisonPageSource,
      contains('class _PigStatsForKeyBuilder extends StatefulWidget'),
    );
    expect(
      comparisonPageSource,
      isNot(contains('final List<Stream<PigStatsRecord?>?> pigStreams')),
    );
    expect(
      comparisonPageSource,
      isNot(contains('stream: repository.watchPigStats(')),
    );
    expect(
      comparisonPageSource,
      isNot(contains('stream: cerdasRepository.watchPigStatsForKey(')),
    );
    expect(
      mainSource,
      contains('late Stream<List<DoorOpeningRecord>> _openingsStream;'),
    );
    expect(
      mainSource,
      isNot(contains('stream: widget.repository.watchDoorOpeningsForCleanup(')),
    );
  });

  testWidgets(
    'renders devices grouped into a Salas section with per-section header',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentTablePage(
              units: <MuntersModel>[_sala1Healthy(), _sala2Alarm()],
              labels: const <String>['Sala 1', 'Sala 2'],
              plcIds: const <String?>['munters1', 'munters2'],
              templateIds: const <String?>['room_climate', 'room_climate'],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('device-table-section-Salas')),
        findsOneWidget,
      );
      expect(find.text('Sala 1'), findsOneWidget);
      expect(find.text('Sala 2'), findsOneWidget);

      // shortLabels reales del catálogo room_climate con unidades en header.
      expect(find.text('Temp. int. °C'), findsOneWidget);
      expect(find.text('HR int. %'), findsOneWidget);
      expect(find.text('Delta PR °C'), findsOneWidget);
      expect(find.text('Fan %'), findsOneWidget);

      // Leyenda de colores, sin cambios.
      expect(find.text('Verde: Óptimo'), findsOneWidget);
      expect(find.text('Amarillo: Atención'), findsOneWidget);
      expect(find.text('Rojo: Alarma'), findsOneWidget);
    },
  );

  testWidgets('shows real measurements and "-" for missing fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy()],
            labels: const <String>['Sala 1'],
            plcIds: const <String?>['munters1'],
            templateIds: const <String?>['room_climate'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('22.1'), findsOneWidget); // temperatureC
    expect(find.textContaining('18.0'), findsOneWidget); // exteriorTemperatureC
    expect(find.textContaining('8.1'), findsOneWidget); // dew point delta
    expect(find.textContaining('70'), findsWidgets); // exteriorHumidityPercent
    expect(find.textContaining('60'), findsWidgets); // humidityPercent
    expect(find.text('Cerrada'), findsNothing); // closed doors are icon-only
    expect(find.text('true'), findsNothing);
    expect(find.text('false'), findsNothing);
    // CO2 y Agua siguen sin fuente real (pending.*); presion y sowCount
    // tampoco tienen dato en este fixture (sin presionDiferencial, sin
    // currentCount inyectado). NH3 sí tiene dato real (11.0).
    expect(find.text('Sin datos'), findsNothing);
    expect(find.text('-'), findsNWidgets(4));
  });

  testWidgets('pig count cell shows "-" without a tenant/site/plc', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy()],
            labels: const <String>['Sala 1'],
            plcIds: const <String?>[null],
            templateIds: const <String?>['room_climate'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
          ),
        ),
      ),
    );
    await tester.pump();

    // Sin plcId, el gate de cerdas nunca activa el StreamBuilder — la celda
    // de sowCount resuelve `currentCount` como null, igual que cualquier
    // otro dato ausente ("-"), no un placeholder aparte.
    expect(find.text('-'), findsWidgets);
  });

  testWidgets('legacy room currentCount sigue funcionando en TABLA', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey key = CerdasContextKey.legacy(
      tenantId: 'the-gene-pig',
      siteId: 'genetica-1',
      plcId: 'munters1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy()],
            labels: const <String>['Sala 1'],
            plcIds: const <String?>['munters1'],
            templateIds: const <String?>['room_climate'],
            tenantId: 'the-gene-pig',
            siteId: 'genetica-1',
            rangeSettings: const DashboardRangeSettings.defaults(),
            cerdasRepository: _FakeCerdasRepository(<CerdasContextKey, int?>{
              key: 57,
            }),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder sowCell = find.byKey(
      const ValueKey<String>('device-table-cell-Sala 1-sowCount'),
    );
    expect(
      find.descendant(of: sowCell, matching: find.text('57')),
      findsOneWidget,
    );
  });

  testWidgets('dynamic single-room currentCount llega a TABLA sin plcId', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey key = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'plc-gestacion',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy()],
            labels: const <String>['Gestacion'],
            plcIds: const <String?>[null],
            templateIds: const <String?>['room_climate'],
            cerdasContextKeys: <CerdasContextKey?>[key],
            tenantId: 'the-gene-pig',
            siteId: 'las-heras',
            rangeSettings: const DashboardRangeSettings.defaults(),
            cerdasRepository: _FakeCerdasRepository(<CerdasContextKey, int?>{
              key: 24,
            }),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder sowCell = find.byKey(
      const ValueKey<String>('device-table-cell-Gestacion-sowCount'),
    );
    expect(
      find.descendant(of: sowCell, matching: find.text('24')),
      findsOneWidget,
    );
  });

  testWidgets('rebuild del padre no recrea stream Firestore de cerdas', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey key = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'plc-gestacion',
    );
    int watchCount = 0;
    final _FakeCerdasRepository repository = _FakeCerdasRepository(
      <CerdasContextKey, int?>{key: 24},
      onWatch: (_) => watchCount += 1,
    );

    late StateSetter rebuildParent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuildParent = setState;
              return EnvironmentTablePage(
                units: <MuntersModel>[_sala1Healthy()],
                labels: const <String>['Gestacion'],
                plcIds: const <String?>[null],
                templateIds: const <String?>['room_climate'],
                cerdasContextKeys: <CerdasContextKey?>[key],
                tenantId: 'the-gene-pig',
                siteId: 'las-heras',
                rangeSettings: const DashboardRangeSettings.defaults(),
                cerdasRepository: repository,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(watchCount, 1);
    rebuildParent(() {});
    await tester.pump();

    expect(watchCount, 1);
    final Finder sowCell = find.byKey(
      const ValueKey<String>('device-table-cell-Gestacion-sowCount'),
    );
    expect(
      find.descendant(of: sowCell, matching: find.text('24')),
      findsOneWidget,
    );
  });

  testWidgets('stream de cerdas con throw sincronico cae a fallback null', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey key = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'plc-gestacion',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy()],
            labels: const <String>['Gestacion'],
            plcIds: const <String?>[null],
            templateIds: const <String?>['room_climate'],
            cerdasContextKeys: <CerdasContextKey?>[key],
            tenantId: 'the-gene-pig',
            siteId: 'las-heras',
            rangeSettings: const DashboardRangeSettings.defaults(),
            cerdasRepository: const _FakeCerdasRepository(
              <CerdasContextKey, int?>{},
              throwOnWatch: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final Finder sowCell = find.byKey(
      const ValueKey<String>('device-table-cell-Gestacion-sowCount'),
    );
    expect(
      find.descendant(of: sowCell, matching: find.text('-')),
      findsOneWidget,
    );
  });

  testWidgets('dynamic multi-room currentCount no colisiona en TABLA', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey sala1 = CerdasContextKey.dynamic(
      tenantId: 'la-payana',
      siteId: 'roque-perez',
      deviceId: 'plc-maternidad',
      roomId: 'sala-1',
    );
    final CerdasContextKey sala2 = CerdasContextKey.dynamic(
      tenantId: 'la-payana',
      siteId: 'roque-perez',
      deviceId: 'plc-maternidad',
      roomId: 'sala-2',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy(), _sala2Alarm()],
            labels: const <String>['Sala 1', 'Sala 2'],
            plcIds: const <String?>[null, null],
            deviceNames: const <String>['PLC Maternidad', 'PLC Maternidad'],
            templateIds: const <String?>['room_climate', 'room_climate'],
            cerdasContextKeys: <CerdasContextKey?>[sala1, sala2],
            tenantId: 'la-payana',
            siteId: 'roque-perez',
            rangeSettings: const DashboardRangeSettings.defaults(),
            cerdasRepository: _FakeCerdasRepository(<CerdasContextKey, int?>{
              sala1: 20,
              sala2: 35,
            }),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder sala1Cell = find.byKey(
      const ValueKey<String>('device-table-cell-Sala 1-sowCount'),
    );
    final Finder sala2Cell = find.byKey(
      const ValueKey<String>('device-table-cell-Sala 2-sowCount'),
    );
    expect(
      find.descendant(of: sala1Cell, matching: find.text('20')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sala2Cell, matching: find.text('35')),
      findsOneWidget,
    );
  });

  testWidgets('TABLA distingue null de cero en currentCount', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey sinDato = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'sin-dato',
    );
    final CerdasContextKey cero = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'cero',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy(), _sala2Alarm()],
            labels: const <String>['Sin dato', 'Cero'],
            plcIds: const <String?>[null, null],
            templateIds: const <String?>['room_climate', 'room_climate'],
            cerdasContextKeys: <CerdasContextKey?>[sinDato, cero],
            tenantId: 'the-gene-pig',
            siteId: 'las-heras',
            rangeSettings: const DashboardRangeSettings.defaults(),
            cerdasRepository: _FakeCerdasRepository(<CerdasContextKey, int?>{
              cero: 0,
            }),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder nullCell = find.byKey(
      const ValueKey<String>('device-table-cell-Sin dato-sowCount'),
    );
    final Finder zeroCell = find.byKey(
      const ValueKey<String>('device-table-cell-Cero-sowCount'),
    );
    expect(
      find.descendant(of: nullCell, matching: find.text('-')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: zeroCell, matching: find.text('0')),
      findsOneWidget,
    );
  });

  testWidgets('shows heating stage indicators next to the temperature cell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_salaOneOfTwoHeatingStages()],
            labels: const <String>['Sala 1'],
            plcIds: const <String?>['munters1'],
            templateIds: const <String?>['room_climate'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder tempCell = find.byKey(
      const ValueKey<String>('device-table-cell-Sala 1-tempInterior'),
    );
    // The active stage renders as the animated multi-tip flame (several
    // overlaid `local_fire_department` icons, all orange), not a single
    // static icon — so this checks both target colors are present rather
    // than an exact icon count.
    final Iterable<Icon> flameIcons = tester.widgetList<Icon>(
      find.descendant(
        of: tempCell,
        matching: find.byIcon(Icons.local_fire_department),
      ),
    );
    expect(flameIcons, isNotEmpty);
    expect(
      flameIcons.map((Icon icon) => icon.color).toSet(),
      containsAll(<Color>[const Color(0xFFF97316), const Color(0xFF64748B)]),
    );
  });

  testWidgets('shows sensor failure icon instead of invalid temperature', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_salaSensorFailure()],
            labels: const <String>['Sala 1'],
            plcIds: const <String?>['munters1'],
            templateIds: const <String?>['room_climate'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('-51.0'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byTooltip('Falla sensor (cod. -51)'), findsOneWidget);
  });

  testWidgets(
    'device without a resolvable template falls back to the legacy flat '
    'table instead of room_climate or an empty state',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentTablePage(
              units: <MuntersModel>[_sala1Healthy()],
              labels: const <String>['Sala 1'],
              plcIds: const <String?>['munters1'],
              templateIds: const <String?>[null],
              tenantId: null, // no legacy fallback either: stays unresolved
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Sin `DeviceTemplate`, no rompe la vista ni cae a `room_climate` por
      // defecto: se degrada a la tabla plana legacy (mismo criterio que el
      // fallback por-card de TABLERO), y la fila sigue siendo visible.
      expect(
        find.text('No hay equipos configurados para este site.'),
        findsNothing,
      );
      expect(find.text('Sala 1'), findsOneWidget);
      expect(find.byKey(const Key('device-table-section-Salas')), findsNothing);
    },
  );

  group('Etapa 5C.1 — site switching regression', () {
    const CerdasRepository fakeRepo = _FakeCerdasRepository(
      <CerdasContextKey, int?>{},
    );

    Widget buildLasHeras() {
      return MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[
              _sala1Healthy(),
              _sala2Alarm(),
              _sala1Healthy(),
              _sala1Healthy(),
            ],
            labels: const <String>['Sala1', 'Sala2', 'Lab', 'Arco Desf'],
            plcIds: const <String?>[null, null, null, null],
            templateIds: const <String?>[
              'room_climate',
              'room_climate',
              'laboratory_basic',
              'disinfection_arch',
            ],
            tenantId: 'the-gene-pig',
            siteId: 'las-heras',
            rangeSettings: const DashboardRangeSettings.defaults(),
            cerdasRepository: fakeRepo,
          ),
        ),
      );
    }

    Widget buildGenetica1() {
      return MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy(), _sala2Alarm()],
            labels: const <String>['Munters 1', 'Munters 2'],
            plcIds: const <String?>['munters1', 'munters2'],
            templateIds: const <String?>['room_climate', 'room_climate'],
            tenantId: 'the-gene-pig',
            siteId: 'genetica-1',
            rangeSettings: const DashboardRangeSettings.defaults(),
            cerdasRepository: fakeRepo,
          ),
        ),
      );
    }

    void expectLasHeras(WidgetTester tester) {
      expect(
        find.byKey(const Key('device-table-section-Laboratorio')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('device-table-section-Arco de desinfección')),
        findsOneWidget,
      );
      expect(find.text('Sala1'), findsOneWidget);
      expect(find.text('Munters 1'), findsNothing);
    }

    void expectGenetica1(WidgetTester tester) {
      expect(
        find.byKey(const Key('device-table-section-Laboratorio')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('device-table-section-Arco de desinfección')),
        findsNothing,
      );
      expect(find.text('Munters 1'), findsOneWidget);
      expect(find.text('Sala1'), findsNothing);
    }

    testWidgets(
      'dynamic -> legacy -> dynamic: Las Heras renders the dynamic table '
      'again after bouncing through Genetica-1',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildLasHeras());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectLasHeras(tester);

        await tester.pumpWidget(buildGenetica1());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectGenetica1(tester);

        // The step that reproduced the bug: back on Las Heras, the
        // dynamic per-section renderer must return — not the legacy grid
        // left over from Genetica-1.
        await tester.pumpWidget(buildLasHeras());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectLasHeras(tester);
      },
    );

    testWidgets(
      'legacy -> dynamic -> legacy: Genetica-1 renders the legacy table '
      'again after bouncing through Las Heras',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildGenetica1());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectGenetica1(tester);

        await tester.pumpWidget(buildLasHeras());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectLasHeras(tester);

        await tester.pumpWidget(buildGenetica1());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectGenetica1(tester);
      },
    );

    testWidgets('repeated alternation does not leave stale state behind', (
      WidgetTester tester,
    ) async {
      for (int i = 0; i < 3; i++) {
        await tester.pumpWidget(buildLasHeras());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectLasHeras(tester);

        await tester.pumpWidget(buildGenetica1());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expectGenetica1(tester);
      }
      await tester.pumpWidget(buildLasHeras());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expectLasHeras(tester);
    });
  });

  group('Etapa 5C.1 — owner legacy TABLA preview', () {
    Widget build({required bool forceLegacyLayout}) {
      return MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy(), _sala2Alarm()],
            labels: const <String>['Sala1', 'Sala2'],
            plcIds: const <String?>[null, null],
            templateIds: const <String?>['room_climate', 'room_climate'],
            tenantId: 'the-gene-pig',
            siteId: 'las-heras',
            rangeSettings: const DashboardRangeSettings.defaults(),
            forceLegacyLayout: forceLegacyLayout,
          ),
        ),
      );
    }

    testWidgets(
      'toggling forceLegacyLayout switches to the legacy grid and back, '
      'showing the preview badge only while active',
      (WidgetTester tester) async {
        // Tabla actual (dynamic).
        await tester.pumpWidget(build(forceLegacyLayout: false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byKey(const Key('device-table-section-Salas')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('environment-table-legacy-preview-badge')),
          findsNothing,
        );

        // "Ver tabla legacy".
        await tester.pumpWidget(build(forceLegacyLayout: true));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byKey(const Key('device-table-section-Salas')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('environment-table-legacy-preview-badge')),
          findsOneWidget,
        );
        expect(find.text('Sala1'), findsOneWidget);

        // "Volver a tabla actual".
        await tester.pumpWidget(build(forceLegacyLayout: false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byKey(const Key('device-table-section-Salas')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('environment-table-legacy-preview-badge')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'the pre-existing no-template fallback (not an owner override) never '
      'shows the preview badge',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnvironmentTablePage(
                units: <MuntersModel>[_sala1Healthy(), _sala2Alarm()],
                labels: const <String>['Munters 1', 'Munters 2'],
                plcIds: const <String?>['munters1', 'munters2'],
                templateIds: const <String?>[null, null],
                tenantId: null, // no legacy fallback match: unresolved
                siteId: null,
                rangeSettings: const DashboardRangeSettings.defaults(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Munters 1'), findsOneWidget);
        expect(
          find.byKey(const Key('environment-table-legacy-preview-badge')),
          findsNothing,
        );
      },
    );
  });
}

class _FakeCerdasRepository extends CerdasRepository {
  const _FakeCerdasRepository(
    this.countsByKey, {
    this.onWatch,
    this.throwOnWatch = false,
  });

  final Map<CerdasContextKey, int?> countsByKey;
  final void Function(CerdasContextKey key)? onWatch;
  final bool throwOnWatch;

  @override
  Stream<PigStatsRecord?> watchPigStatsForKey(CerdasContextKey key) {
    onWatch?.call(key);
    if (throwOnWatch) {
      throw StateError('sync stream creation failure');
    }
    if (!countsByKey.containsKey(key) || countsByKey[key] == null) {
      return Stream<PigStatsRecord?>.value(null);
    }
    return Stream<PigStatsRecord?>.value(
      PigStatsRecord(
        currentCount: countsByKey[key]!,
        updatedAt: null,
        updatedBy: 'test',
      ),
    );
  }
}

MuntersModel _sala1Healthy() {
  return const MuntersModel(
    name: 'Sala 1',
    tempInterior: 22.1,
    tempIngresoSala: null,
    humInterior: 60,
    tempExterior: 18,
    humExterior: 70,
    tensionSalidaVentiladores: 400,
    bombaHumidificador: true,
    fanQ5: false,
    fanQ6: false,
    fanQ7: false,
    fanQ8: false,
    fanQ9: false,
    fanQ10: false,
    resistencia1: false,
    resistencia2: false,
    alarmaGeneral: false,
    fallaRed: false,
    nivelAguaAlarma: false,
    fallaTermicaBomba: false,
    eventosSinAgua: 0,
    horasMunter: 0,
    horasFiltroF9: 0,
    horasFiltroG4: 0,
    horasPolifosfato: 0,
    salaAbierta: false,
    aperturasSala: 0,
    munterAbierto: false,
    aperturasMunter: 0,
    cantidadApagadas: 0,
    estadoEquipo: 'RUN',
    nh3: 11,
  );
}

MuntersModel _sala2Alarm() {
  return const MuntersModel(
    name: 'Sala 2',
    tempInterior: 31.2,
    tempIngresoSala: null,
    humInterior: 78,
    tempExterior: 24,
    humExterior: 80,
    tensionSalidaVentiladores: 900,
    bombaHumidificador: false,
    fanQ5: true,
    fanQ6: true,
    fanQ7: true,
    fanQ8: true,
    fanQ9: true,
    fanQ10: true,
    resistencia1: false,
    resistencia2: false,
    alarmaGeneral: true,
    fallaRed: false,
    nivelAguaAlarma: false,
    fallaTermicaBomba: false,
    eventosSinAgua: 0,
    horasMunter: 0,
    horasFiltroF9: 0,
    horasFiltroG4: 0,
    horasPolifosfato: 0,
    salaAbierta: false,
    aperturasSala: 0,
    munterAbierto: false,
    aperturasMunter: 0,
    cantidadApagadas: 0,
    estadoEquipo: 'RUN',
  );
}

MuntersModel _salaOneOfTwoHeatingStages() {
  return const MuntersModel(
    name: 'Sala 1',
    tempInterior: 22.1,
    tempIngresoSala: null,
    humInterior: 60,
    tempExterior: 18,
    humExterior: 70,
    tensionSalidaVentiladores: 400,
    bombaHumidificador: false,
    fanQ5: false,
    fanQ6: false,
    fanQ7: false,
    fanQ8: false,
    fanQ9: false,
    fanQ10: false,
    resistencia1: true,
    resistencia2: false,
    alarmaGeneral: false,
    fallaRed: false,
    nivelAguaAlarma: false,
    fallaTermicaBomba: false,
    eventosSinAgua: 0,
    horasMunter: 0,
    horasFiltroF9: 0,
    horasFiltroG4: 0,
    horasPolifosfato: 0,
    salaAbierta: false,
    aperturasSala: 0,
    munterAbierto: false,
    aperturasMunter: 0,
    cantidadApagadas: 0,
    estadoEquipo: 'RUN',
  );
}

MuntersModel _salaSensorFailure() {
  return const MuntersModel(
    name: 'Sala 1',
    tempInterior: -51,
    tempIngresoSala: null,
    humInterior: 60,
    tempExterior: 18,
    humExterior: 70,
    tensionSalidaVentiladores: 400,
    bombaHumidificador: false,
    fanQ5: false,
    fanQ6: false,
    fanQ7: false,
    fanQ8: false,
    fanQ9: false,
    fanQ10: false,
    resistencia1: false,
    resistencia2: false,
    alarmaGeneral: false,
    fallaRed: false,
    nivelAguaAlarma: false,
    fallaTermicaBomba: false,
    eventosSinAgua: 0,
    horasMunter: 0,
    horasFiltroF9: 0,
    horasFiltroG4: 0,
    horasPolifosfato: 0,
    salaAbierta: false,
    aperturasSala: 0,
    munterAbierto: false,
    aperturasMunter: 0,
    cantidadApagadas: 0,
    estadoEquipo: 'RUN',
  );
}
