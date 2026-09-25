import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/models/dashboard_door_event.dart';
import 'package:agro_data_control/models/magnifier_settings.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:agro_data_control/services/device_environment_history_repository.dart';
import 'package:agro_data_control/widgets/device_environment_history_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgroDevice device(int n) => AgroDevice.fromFirestore(
  'plc-genetica-sala$n',
  tenantId: 'the-gene-pig',
  data: {'siteId': 'las-heras', 'enabled': true, 'name': 'Sala$n'},
);

class CountingRepository extends DeviceEnvironmentHistoryRepository {
  final calls = <String>[];
  final monthCalls = <String>[];
  int resolves = 0;
  bool fail = false;
  List<EnvironmentHistoryPoint> points = [
    EnvironmentHistoryPoint(
      DateTime.utc(2026, 9, 25, 12),
      const EnvironmentHistoryStats(21, 20, 22, 3),
      const EnvironmentHistoryStats(75, 70, 80, 3),
    ),
  ];
  @override
  Future<EnvironmentHistoryScope> resolve(String tenant, String unit) async {
    resolves++;
    return DeviceEnvironmentHistoryRepository.resolveFromDevices(tenant, unit, [
      device(1),
      device(2),
    ]);
  }

  @override
  Future<List<EnvironmentHistoryPoint>> load(
    EnvironmentHistoryScope s,
    EnvironmentHistoryMode m,
    int limit,
  ) async {
    calls.add('${s.key}/${m.name}/$limit');
    if (fail) throw StateError('offline');
    return points;
  }

  @override
  Future<List<EnvironmentHistoryPoint>> loadMonth(
    EnvironmentHistoryScope s,
    EnvironmentHistoryMonth month,
  ) async {
    monthCalls.add('${s.key}/$month');
    if (fail) throw StateError('offline');
    return points;
  }
}

void main() {
  test('mapping uses metadata Site, aliases scoped to tenant', () {
    for (var n = 1; n <= 2; n++) {
      final s = DeviceEnvironmentHistoryRepository.resolveFromDevices(
        'the-gene-pig',
        'munters$n',
        [device(1), device(2)],
      );
      expect(s.siteId, 'las-heras');
      expect(s.deviceId, 'plc-genetica-sala$n');
    }
    expect(
      () => DeviceEnvironmentHistoryRepository.resolveFromDevices(
        'other',
        'munters1',
        [device(1)],
      ),
      throwsStateError,
    );
  });
  test('missing averages and zero sample counts remain absent', () {
    expect(
      EnvironmentHistoryStats.parse({'avg': 21, 'sampleCount': 0}).value,
      isNull,
    );
    expect(
      EnvironmentHistoryStats.parse({'avg': null, 'sampleCount': 3}).value,
      isNull,
    );
    expect(
      EnvironmentHistoryStats.parse({'avg': 0, 'sampleCount': 3}).value,
      0,
    );
  });
  testWidgets('lazy, metric toggle, mode cache, hide/show and remount', (
    t,
  ) async {
    final repo = CountingRepository();
    Future<void> render(bool visible) async {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: DeviceEnvironmentHistoryCard(
              repository: repo,
              tenantId: 'the-gene-pig',
              unitId: 'munters1',
              visible: visible,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    await render(false);
    expect(repo.calls, isEmpty);
    expect(repo.resolves, 0);
    await render(true);
    expect(repo.calls.length, 1);
    expect(
      repo.calls.single,
      contains('las-heras/plc-genetica-sala1/hourly/24'),
    );
    await t.tap(find.byTooltip('Humedad'));
    await t.pumpAndSettle();
    expect(repo.calls.length, 1);
    expect(find.text('Humedad interior'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    await t.tap(find.text('Diario'));
    await t.pumpAndSettle();
    expect(repo.calls.length, 1); // hourly cache untouched
    expect(repo.monthCalls.length, 1); // Etapa 2/2: 1 mes (el actual)
    await t.tap(find.text('Horario'));
    await t.pumpAndSettle();
    expect(repo.calls.length, 1);
    expect(repo.monthCalls.length, 1);
    await t.tap(find.text('Diario'));
    await t.pumpAndSettle();
    expect(repo.monthCalls.length, 1); // el mismo mes ya cargado, 0 reads
    await render(false);
    expect(find.byType(LineChart), findsNothing);
    await render(true);
    expect(repo.calls.length, 1);
    expect(repo.monthCalls.length, 1);
    await t.pumpWidget(const SizedBox());
    await render(true);
    expect(repo.calls.length, 1);
    expect(repo.monthCalls.length, 1);
  });
  testWidgets('missing samples are gaps; empty and manual retry', (t) async {
    final repo = CountingRepository()..fail = true;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceEnvironmentHistoryCard(
            repository: repo,
            tenantId: 'the-gene-pig',
            unitId: 'munters2',
            visible: true,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('No se pudo cargar el histórico'), findsOneWidget);
    expect(repo.calls.length, 1);
    repo.fail = false;
    repo.points = [
      EnvironmentHistoryPoint(
        DateTime.utc(2026),
        const EnvironmentHistoryStats(30, 20, 40, 0),
        const EnvironmentHistoryStats(null, null, null, 0),
      ),
    ];
    await t.tap(find.text('Reintentar'));
    await t.pumpAndSettle();
    expect(repo.calls.length, 2);
    expect(find.text('Sin datos históricos'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });
  test('cache separates Site and deduplicates concurrent requests', () async {
    final repo = CountingRepository();
    const a = EnvironmentHistoryScope(
      'the-gene-pig',
      'las-heras',
      'plc-genetica-sala1',
    );
    const b = EnvironmentHistoryScope(
      'the-gene-pig',
      'another-site',
      'plc-genetica-sala1',
    );
    await Future.wait([
      repo.fetch(a, EnvironmentHistoryMode.hourly),
      repo.fetch(a, EnvironmentHistoryMode.hourly),
    ]);
    expect(repo.calls.length, 1);
    await repo.fetch(b, EnvironmentHistoryMode.hourly);
    expect(repo.calls.length, 2);
  });
  testWidgets('null points form a gap, never a zero', (t) async {
    final repo = CountingRepository();
    repo.points = [
      repo.points.first,
      EnvironmentHistoryPoint(
        DateTime.utc(2026, 9, 25, 13),
        const EnvironmentHistoryStats(0, 0, 0, 0),
        const EnvironmentHistoryStats(null, null, null, 0),
      ),
      EnvironmentHistoryPoint(
        DateTime.utc(2026, 9, 25, 14),
        const EnvironmentHistoryStats(22, 21, 23, 2),
        const EnvironmentHistoryStats(70, 60, 80, 2),
      ),
    ];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceEnvironmentHistoryCard(
            repository: repo,
            tenantId: 'the-gene-pig',
            unitId: 'munters1',
            visible: true,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final chart = t.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots[1], FlSpot.nullSpot);
    expect(
      chart.data.lineBarsData.single.spots.where((p) => p.y == 0),
      isEmpty,
    );
  });
  testWidgets('Detalle entry zero loads and independent columns', (t) async {
    await t.binding.setSurfaceSize(const Size(1500, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = CountingRepository();
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ComparisonPage(
            munters1: _unit('Sala1', 'munters1'),
            munters2: _unit('Sala2', 'munters2'),
            doorEvents: const <String, DashboardDoorEvent>{},
            tenantId: 'the-gene-pig',
            siteId:
                null, // Legacy Site is irrelevant; Device metadata supplies las-heras.
            environmentHistoryRepository: repo,
            showMunters1: true,
            showMunters2: true,
            snapshotStale: false,
            showSnapshotPulse: false,
            rangeSettings: const DashboardRangeSettings.defaults(),
            moduleOrder: ComparisonPage.defaultModuleOrder,
            onModuleOrderChanged: (_) {},
            reorderEnabled: false,
            onToggleReorder: () {},
            onDetailAction: () {},
            magnifierSettings: const MagnifierSettings.defaults(),
            homeGeneration: 0,
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(repo.calls, isEmpty);
    await t.tap(find.text('AMBIENTE'));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(repo.calls, isEmpty);
    await t.ensureVisible(find.text('Ver gráfico').first);
    await t.tap(find.text('Ver gráfico').first);
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(repo.calls.length, 1);
    expect(repo.calls.first, contains('plc-genetica-sala1'));
    await t.ensureVisible(find.text('Ver gráfico').last);
    await t.tap(find.text('Ver gráfico').last);
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(repo.calls.length, 2);
    expect(repo.calls.last, contains('plc-genetica-sala2'));
    expect(t.takeException(), isNull);
  });
}

MuntersModel _unit(String name, String plcId) {
  return MuntersModel(
    name: name,
    historyPlcId: plcId,
    tempInterior: 22,
    tempIngresoSala: null,
    humInterior: 60,
    tempExterior: 18,
    humExterior: 70,
    presionDiferencial: 14,
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
  );
}
