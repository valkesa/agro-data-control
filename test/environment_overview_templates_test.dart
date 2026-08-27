import 'package:agro_data_control/models/cerdas_models.dart';
import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:agro_data_control/services/cerdas_repository.dart';
import 'package:agro_data_control/ui_templates/ui_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Sala1 and Sala2 render with room_climate DeviceBoardRenderer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[
              _sala('Sala1', resistencia1: true, resistencia2: false),
              _sala('Sala2', resistencia1: true, resistencia2: true),
            ],
            labels: const <String>['Sala1', 'Sala2'],
            plcIds: const <String?>['munters1', 'munters2'],
            templateIds: const <String?>['room_climate', 'room_climate'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
            cerdasRepository: const _FakeCerdasRepository.map(
              <CerdasContextKey, int?>{},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DeviceBoardRenderer), findsNWidgets(2));
    expect(
      find.byKey(const Key('device-board-slot-tempInterior')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const Key('device-board-slot-position-13')),
      findsNWidgets(2),
    );
    expect(find.text('22.1'), findsNWidgets(2));
    expect(find.text('45'), findsNWidgets(2));
    expect(
      find.byKey(const Key('device-board-indicator-calefaccionEtapa1')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const Key('device-board-indicator-calefaccionEtapa2')),
      findsNWidgets(2),
    );
    expect(find.text(templateNoDataLabel), findsAtLeastNWidgets(6));
  });

  testWidgets(
    'site without real lab or arch devices does not show their cards',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[_sala('Sala1')],
              labels: const <String>['Sala1'],
              plcIds: const <String?>['munters1'],
              templateIds: const <String?>['room_climate'],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DeviceBoardRenderer), findsOneWidget);
      expect(find.text('Laboratorio'), findsNothing);
      expect(find.text('Arco de desinfección'), findsNothing);
    },
  );

  testWidgets('real laboratory device identity drives the renderer template', (
    WidgetTester tester,
  ) async {
    const DeviceTemplateResolver resolver = DeviceTemplateResolver();
    final List<AgroDevice> devices = <AgroDevice>[
      _device(
        id: 'plc-genetica-sala1',
        name: 'Sala1',
        type: 'environment_single_room',
      ),
      _device(
        id: 'plc-genetica-laboratorio',
        name: 'Laboratorio',
        type: 'environment_single_room',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[
              _sala('Sala1'),
              MuntersModel.placeholder(name: 'Laboratorio'),
            ],
            labels: <String>[
              for (final AgroDevice device in devices) device.name,
            ],
            plcIds: const <String?>['munters1', null],
            templateIds: <String?>[
              for (final AgroDevice device in devices)
                resolver.templateIdForDevice(device),
            ],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
            cerdasRepository: const _FakeCerdasRepository.map(
              <CerdasContextKey, int?>{},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DeviceBoardRenderer), findsNWidgets(2));
    expect(find.text('Laboratorio'), findsOneWidget);
    expect(
      find.byKey(const Key('device-board-slot-humedadInterior')),
      findsNWidgets(2),
    );
    expect(find.text('Arco de desinfección'), findsNothing);

    final Size salaSize = tester.getSize(
      find.byType(DeviceBoardRenderer).first,
    );
    final Size labSize = tester.getSize(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is DeviceBoardRenderer &&
            widget.template.id == 'laboratory_basic',
      ),
    );
    expect(labSize.height, lessThan(salaSize.height));
  });

  testWidgets('La Payana multiroom does not add lab or arch cards', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[
              for (int i = 1; i <= 8; i++) _sala('Sala $i'),
            ],
            labels: <String>[for (int i = 1; i <= 8; i++) 'Sala $i'],
            plcIds: const <String?>[
              null,
              null,
              null,
              null,
              null,
              null,
              null,
              null,
            ],
            deviceNames: const <String>[
              'PLC Maternidad',
              'PLC Maternidad',
              'PLC Maternidad',
              'PLC Maternidad',
              'PLC Maternidad',
              'PLC Maternidad',
              'PLC Maternidad',
              'PLC Maternidad',
            ],
            templateIds: const <String?>[
              'room_climate',
              'room_climate',
              'room_climate',
              'room_climate',
              'room_climate',
              'room_climate',
              'room_climate',
              'room_climate',
            ],
            tenantId: 'la-payana',
            siteId: 'roque-perez',
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DeviceBoardRenderer), findsNWidgets(8));
    expect(find.text('PLC Maternidad'), findsOneWidget);
    expect(find.text('Laboratorio'), findsNothing);
    expect(find.text('Arco de desinfección'), findsNothing);
    expect(
      find.byKey(const Key('device-board-slot-vehiclesDisinfectedDaily')),
      findsNothing,
    );
  });

  testWidgets('unscoped legacy room keeps the previous safe card fallback', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[_sala('Sala1')],
            labels: const <String>['Sala1'],
            plcIds: const <String?>['munters1'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DeviceBoardRenderer), findsNothing);
    expect(find.text('Sala1'), findsWidgets);
  });

  testWidgets('missing template falls back safely without breaking overview', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[_sala('Sala1')],
            labels: const <String>['Sala1'],
            plcIds: const <String?>['munters1'],
            templateIds: const <String?>['missing_template'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DeviceBoardRenderer), findsNothing);
    expect(find.text('Sala1'), findsWidgets);
  });

  testWidgets('overview has no overflow at representative reduced width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[_sala('Sala1'), _sala('Sala2')],
            labels: const <String>['Sala1', 'Sala2'],
            plcIds: const <String?>['munters1', 'munters2'],
            tenantId: 'the-gene-pig',
            siteId: 'genetica-1',
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
            cerdasRepository: const _FakeCerdasRepository.map(
              <CerdasContextKey, int?>{},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('cerdas llega por repository manual al renderer dinamico', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[_sala('Sala1')],
            labels: const <String>['Sala1'],
            plcIds: const <String?>['munters1'],
            templateIds: const <String?>['room_climate'],
            tenantId: 'the-gene-pig',
            siteId: 'genetica-1',
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
            cerdasRepository: _FakeCerdasRepository(57),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DeviceBoardRenderer), findsOneWidget);
    expect(find.byKey(const Key('device-board-slot-sowCount')), findsOneWidget);
    expect(find.text('57'), findsOneWidget);
  });

  testWidgets(
    'rebuild del padre no recrea stream Firestore de cerdas en TABLERO',
    (WidgetTester tester) async {
      final CerdasContextKey key = CerdasContextKey.legacy(
        tenantId: 'the-gene-pig',
        siteId: 'genetica-1',
        plcId: 'munters1',
      );
      int watchCount = 0;
      final _FakeCerdasRepository repository = _FakeCerdasRepository.map(
        <CerdasContextKey, int?>{key: 57},
        onWatch: (_) => watchCount += 1,
      );

      late StateSetter rebuildParent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                rebuildParent = setState;
                return EnvironmentOverviewPage(
                  units: <MuntersModel>[_sala('Sala1')],
                  labels: const <String>['Sala1'],
                  plcIds: const <String?>['munters1'],
                  templateIds: const <String?>['room_climate'],
                  tenantId: 'the-gene-pig',
                  siteId: 'genetica-1',
                  rangeSettings: const DashboardRangeSettings.defaults(),
                  showSnapshotPulse: false,
                  snapshotStale: false,
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
      expect(find.text('57'), findsOneWidget);
    },
  );

  testWidgets('cerdas dinamicas single-room llegan al TABLERO sin plcId', (
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
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[_sala('Gestacion')],
            labels: const <String>['Gestacion'],
            plcIds: const <String?>[null],
            templateIds: const <String?>['room_climate'],
            cerdasContextKeys: <CerdasContextKey?>[key],
            tenantId: 'the-gene-pig',
            siteId: 'las-heras',
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
            cerdasRepository: _FakeCerdasRepository.map(
              <CerdasContextKey, int?>{key: 24},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DeviceBoardRenderer), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('cerdas dinamicas multi-room no colisionan en TABLERO', (
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
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[_sala('Sala 1'), _sala('Sala 2')],
            labels: const <String>['Sala 1', 'Sala 2'],
            plcIds: const <String?>[null, null],
            deviceNames: const <String>['PLC Maternidad', 'PLC Maternidad'],
            templateIds: const <String?>['room_climate', 'room_climate'],
            cerdasContextKeys: <CerdasContextKey?>[sala1, sala2],
            tenantId: 'la-payana',
            siteId: 'roque-perez',
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
            cerdasRepository: _FakeCerdasRepository.map(
              <CerdasContextKey, int?>{sala1: 20, sala2: 35},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('20'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
  });

  testWidgets('cerdas en TABLERO distingue null de cero', (
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
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[_sala('Sin dato'), _sala('Cero')],
            labels: const <String>['Sin dato', 'Cero'],
            plcIds: const <String?>[null, null],
            templateIds: const <String?>['room_climate', 'room_climate'],
            cerdasContextKeys: <CerdasContextKey?>[sinDato, cero],
            tenantId: 'the-gene-pig',
            siteId: 'las-heras',
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
            cerdasRepository: _FakeCerdasRepository.map(
              <CerdasContextKey, int?>{cero: 0},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('0'), findsOneWidget);
    expect(find.text('Sin datos'), findsWidgets);
  });

  testWidgets('puertas no muestran cruz y Munters usa label contextual', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentOverviewPage(
            units: <MuntersModel>[_sala('Sala2')],
            labels: const <String>['Sala2'],
            plcIds: const <String?>['munters2'],
            templateIds: const <String?>['room_climate'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
            showSnapshotPulse: false,
            snapshotStale: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sala'), findsOneWidget);
    expect(find.text('Munters 2'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsNothing);
  });
}

class _FakeCerdasRepository extends CerdasRepository {
  const _FakeCerdasRepository(this.count) : countsByKey = null, onWatch = null;
  const _FakeCerdasRepository.map(this.countsByKey, {this.onWatch})
    : count = null;

  final int? count;
  final Map<CerdasContextKey, int?>? countsByKey;
  final void Function(CerdasContextKey key)? onWatch;

  @override
  Stream<PigStatsRecord?> watchPigStatsForKey(CerdasContextKey key) {
    onWatch?.call(key);
    final Map<CerdasContextKey, int?>? countsByKey = this.countsByKey;
    if (countsByKey != null) {
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
    return Stream<PigStatsRecord?>.value(
      PigStatsRecord(currentCount: count!, updatedAt: null, updatedBy: 'test'),
    );
  }
}

AgroDevice _device({
  required String id,
  required String name,
  required String type,
}) {
  return AgroDevice(
    id: id,
    tenantId: 'the-gene-pig',
    siteId: 'genetica-1',
    name: name,
    type: type,
    model: '',
    description: '',
    enabled: true,
    createdAt: null,
    updatedAt: null,
  );
}

MuntersModel _sala(
  String name, {
  bool resistencia1 = false,
  bool resistencia2 = false,
}) {
  return MuntersModel(
    name: name,
    historyPlcId: 'munters1',
    tempInterior: 22.1,
    tempIngresoSala: null,
    humInterior: 60,
    tempExterior: 18,
    humExterior: 70,
    tensionSalidaVentiladores: 450,
    bombaHumidificador: true,
    fanQ5: false,
    fanQ6: false,
    fanQ7: false,
    fanQ8: false,
    fanQ9: false,
    fanQ10: false,
    resistencia1: resistencia1,
    resistencia2: resistencia2,
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
