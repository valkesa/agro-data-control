// Prompt_Fix_Etapa_1_de_2_Accesos_Historicos_en_Las_Heras: root-cause was
// EnvironmentOverviewPage's dynamic-Devices branch (main.dart) always
// passing plcIds: [null, null] — nothing needed it before this history
// feature existed. The old icon code only ever looked at legacyPlcId, so it
// silently depended on the legacy PLC path (genetica-1) and never showed up
// from the real structural Site (las-heras). These tests build the SAME two
// shapes EnvironmentOverviewPage actually receives from main.dart today:
// dynamic-Devices (deviceIds populated, plcIds all null — las-heras) and
// legacy (plcIds populated, deviceIds omitted — genetica-1) — not a helper
// that assumes either path works.
import 'package:agro_data_control/models/cerdas_models.dart';
import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:agro_data_control/services/cerdas_repository.dart';
import 'package:agro_data_control/services/device_environment_history_repository.dart';
import 'package:agro_data_control/widgets/device_environment_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCerdasRepository extends CerdasRepository {
  const _FakeCerdasRepository();
  @override
  Stream<PigStatsRecord?> watchPigStatsForKey(CerdasContextKey key) =>
      Stream<PigStatsRecord?>.value(null);
}

class CountingRepository extends DeviceEnvironmentHistoryRepository {
  final calls = <String>[];

  @override
  Future<EnvironmentHistoryScope> resolve(String tenant, String unit) async =>
      EnvironmentHistoryScope(tenant, 'las-heras', unit);

  @override
  Future<List<EnvironmentHistoryPoint>> load(
    EnvironmentHistoryScope s,
    EnvironmentHistoryMode m,
    int limit,
  ) async {
    calls.add(s.deviceId);
    return const [];
  }
}

MuntersModel _unit(String name, {bool blocked = false}) => MuntersModel(
  name: name,
  historyPlcId: null,
  tempInterior: blocked ? null : 22,
  tempIngresoSala: null,
  humInterior: blocked ? null : 60,
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
  estadoEquipo: blocked ? 'STOP' : 'RUN',
);

Finder tempSlot(int index) =>
    find.byKey(const Key('device-board-slot-tempInterior')).at(index);
Finder humSlot(int index) =>
    find.byKey(const Key('device-board-slot-humedadInterior')).at(index);
Finder historyIconIn(Finder slot) =>
    find.descendant(of: slot, matching: find.byTooltip('Ver histórico'));

void main() {
  group('Las Heras (dynamic-Devices path: deviceIds set, plcIds null)', () {
    Widget lasHeras(CountingRepository repo, {bool blocked = false}) =>
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[
                _unit('Sala1', blocked: blocked),
                _unit('Sala2', blocked: blocked),
              ],
              labels: const <String>['Sala1', 'Sala2'],
              // Exactly what main.dart's _activeSiteUsesDynamicDevices
              // branch actually passes today — see EnvironmentOverviewPage
              // construction site in main.dart.
              plcIds: const <String?>[null, null],
              deviceIds: const <String?>[
                'plc-genetica-sala1',
                'plc-genetica-sala2',
              ],
              templateIds: const <String?>['room_climate', 'room_climate'],
              tenantId: 'the-gene-pig',
              siteId: 'las-heras',
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
              environmentHistoryRepository: repo,
              cerdasRepository: const _FakeCerdasRepository(),
            ),
          ),
        );

    testWidgets(
      'Sala1 y Sala2 muestran icono Temp e icono Hum (root-cause resuelto)',
      (t) async {
        final repo = CountingRepository();
        await t.pumpWidget(lasHeras(repo));
        await t.pump();
        expect(repo.calls, isEmpty); // lazy loading intacto
        expect(historyIconIn(tempSlot(0)), findsOneWidget); // Sala1 Temp
        expect(historyIconIn(tempSlot(1)), findsOneWidget); // Sala2 Temp
        expect(historyIconIn(humSlot(0)), findsOneWidget); // Sala1 Hum
        expect(historyIconIn(humSlot(1)), findsOneWidget); // Sala2 Hum
      },
    );

    testWidgets('tap Temp de Sala1 resuelve el Device real, no un alias', (
      t,
    ) async {
      final repo = CountingRepository();
      await t.pumpWidget(lasHeras(repo));
      await t.pump();
      await t.tap(historyIconIn(tempSlot(0)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['plc-genetica-sala1']);
      final card = t.widget<DeviceEnvironmentHistoryCard>(
        find.byType(DeviceEnvironmentHistoryCard),
      );
      expect(card.initialMetric, EnvironmentHistoryMetric.temperature);
    });

    testWidgets('tap Hum de Sala2 abre en humidity y no mezcla con Sala1', (
      t,
    ) async {
      final repo = CountingRepository();
      await t.pumpWidget(lasHeras(repo));
      await t.pump();
      await t.tap(historyIconIn(humSlot(1)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['plc-genetica-sala2']);
      final card = t.widget<DeviceEnvironmentHistoryCard>(
        find.byType(DeviceEnvironmentHistoryCard),
      );
      expect(card.initialMetric, EnvironmentHistoryMetric.humidity);
    });

    testWidgets('offline/blocked no oculta el icono', (t) async {
      final repo = CountingRepository();
      await t.pumpWidget(lasHeras(repo, blocked: true));
      await t.pump();
      expect(historyIconIn(tempSlot(0)), findsOneWidget);
      expect(historyIconIn(humSlot(0)), findsOneWidget);
    });

    testWidgets('posición: el icono está dentro del slot de la métrica, no de toda la card', (
      t,
    ) async {
      final repo = CountingRepository();
      await t.pumpWidget(lasHeras(repo));
      await t.pump();
      // Same tooltip text exists exactly twice per Sala (once per metric),
      // each nested under its own metric slot Key — not a pair floating at
      // the card level (which is what the old implementation did).
      expect(find.byTooltip('Ver histórico'), findsNWidgets(4));
      expect(historyIconIn(tempSlot(0)), findsOneWidget);
      expect(historyIconIn(humSlot(0)), findsOneWidget);
      // A slot's action icon must NOT also satisfy the other slot's finder.
      expect(
        find.descendant(
          of: tempSlot(0),
          matching: find.byKey(const Key('device-board-slot-humedadInterior')),
        ),
        findsNothing,
      );
    });
  });

  group('Genética 1 (legacy path: plcIds set, deviceIds omitted) no se rompe', () {
    Widget genetica1(CountingRepository repo) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: EnvironmentOverviewPage(
          units: <MuntersModel>[_unit('M1'), _unit('M2')],
          labels: const <String>['M1', 'M2'],
          plcIds: const <String?>['munters1', 'munters2'],
          templateIds: const <String?>['room_climate', 'room_climate'],
          tenantId: 'the-gene-pig',
          siteId: 'genetica-1',
          rangeSettings: const DashboardRangeSettings.defaults(),
          showSnapshotPulse: false,
          snapshotStale: false,
          environmentHistoryRepository: repo,
          cerdasRepository: const _FakeCerdasRepository(),
        ),
      ),
    );

    testWidgets('sigue mostrando los accesos, resueltos por el alias legacy', (
      t,
    ) async {
      final repo = CountingRepository();
      await t.pumpWidget(genetica1(repo));
      await t.pump();
      expect(repo.calls, isEmpty);
      expect(historyIconIn(tempSlot(0)), findsOneWidget);
      expect(historyIconIn(humSlot(1)), findsOneWidget);
      await t.tap(historyIconIn(tempSlot(0)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['munters1']); // legacyPlcId, not a Device id
    });
  });
}
