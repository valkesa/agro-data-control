import 'package:agro_data_control/models/cerdas_models.dart';
import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:agro_data_control/services/cerdas_repository.dart';
import 'package:agro_data_control/services/device_environment_history_repository.dart';
import 'package:agro_data_control/widgets/device_environment_history_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Real CerdasRepository.watchPigStatsForKey streams never complete, which
// hangs pumpAndSettle — same reason environment_overview_templates_test.dart
// injects a fake for any room_climate card with a real tenant/site/plc.
class _FakeCerdasRepository extends CerdasRepository {
  const _FakeCerdasRepository();
  @override
  Stream<PigStatsRecord?> watchPigStatsForKey(CerdasContextKey key) =>
      Stream<PigStatsRecord?>.value(null);
}

EnvironmentHistoryStats _stats(double v, {int count = 3}) =>
    EnvironmentHistoryStats(v, v - 1, v + 1, count);

// Mirrors the private list in device_environment_history_card.dart — kept
// here too since month-abbreviation assertions need it and it isn't
// exported.
const _testMonthAbbreviations = [
  'ENE',
  'FEB',
  'MAR',
  'ABR',
  'MAY',
  'JUN',
  'JUL',
  'AGO',
  'SEP',
  'OCT',
  'NOV',
  'DIC',
];

// Each chart mode now also renders 1-2 non-interactive, dataless LineCharts
// pinned outside the horizontal scroll to keep the Y axis visible (see
// device_environment_history_card.dart's `_pinnedAxis`). This finder ignores
// those and matches only the "real" chart(s) that actually carry data.
Finder dataCharts() => find.byWidgetPredicate(
  (w) => w is LineChart && w.data.lineBarsData.isNotEmpty,
);

class CountingRepository extends DeviceEnvironmentHistoryRepository {
  final calls = <String>[];
  final monthCalls = <String>[];
  Map<String, List<EnvironmentHistoryPoint>> pointsByUnit = {};

  @override
  Future<EnvironmentHistoryScope> resolve(String tenant, String unit) async =>
      EnvironmentHistoryScope(tenant, 'las-heras', 'device-$unit');

  @override
  Future<List<EnvironmentHistoryPoint>> load(
    EnvironmentHistoryScope s,
    EnvironmentHistoryMode m,
    int limit, {
    DateTime? beforeUtc,
  }) async {
    calls.add(s.deviceId);
    return pointsByUnit[s.deviceId] ?? const [];
  }

  // The widget loads Horario by ART day now (see loadDay below), never via
  // load() directly — kept simple (no day filtering) since these tests are
  // about UI behavior, not date-boundary logic, and filtering by the exact
  // requested day would make fixtures dated relative to "today" go stale as
  // real time passes.
  @override
  Future<List<EnvironmentHistoryPoint>> loadDay(
    EnvironmentHistoryScope s,
    EnvironmentHistoryDay day,
  ) async {
    calls.add(s.deviceId);
    return pointsByUnit[s.deviceId] ?? const [];
  }

  @override
  Future<List<EnvironmentHistoryPoint>> loadMonth(
    EnvironmentHistoryScope s,
    EnvironmentHistoryMonth month,
  ) async {
    monthCalls.add('${s.deviceId}/$month');
    final all = pointsByUnit[s.deviceId] ?? const [];
    return all.where((p) {
      final art = p.start.toUtc().subtract(const Duration(hours: 3));
      return art.year == month.year && art.month == month.month;
    }).toList();
  }
}

MuntersModel _unit(String name, String plcId) => MuntersModel(
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

void main() {
  group('Icon selector (§1)', () {
    testWidgets(
      'renders icons with tooltip/semantics, no literal text labels',
      (t) async {
        final repo = CountingRepository()
          ..pointsByUnit['device-munters1'] = [
            EnvironmentHistoryPoint(
              DateTime.utc(2026, 9, 25, 12),
              _stats(21),
              _stats(75),
            ),
          ];
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: DeviceEnvironmentHistoryCard(
                repository: repo,
                tenantId: 'the-gene-pig',
                unitId: 'munters1',
                visible: true,
                chartHeight: 200,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byIcon(Icons.thermostat), findsOneWidget);
        expect(find.byIcon(Icons.water_drop), findsOneWidget);
        expect(find.byIcon(Icons.stacked_line_chart), findsOneWidget);
        expect(find.byTooltip('Temperatura'), findsOneWidget);
        expect(find.byTooltip('Humedad'), findsOneWidget);
        expect(find.byTooltip('Ambas'), findsOneWidget);
        // The metric row itself no longer carries the word as plain text —
        // only the legend below still says it (kept for readability).
        expect(find.text('Temperatura interior'), findsOneWidget);
      },
    );
  });

  group('Modo Ambas (§2/§4)', () {
    testWidgets('selecting Ambas draws two series with 0 extra reads', (
      t,
    ) async {
      final repo = CountingRepository()
        ..pointsByUnit['device-munters1'] = [
          EnvironmentHistoryPoint(
            DateTime.utc(2026, 9, 25, 12),
            _stats(21),
            _stats(75),
          ),
          EnvironmentHistoryPoint(
            DateTime.utc(2026, 9, 25, 13),
            _stats(22),
            _stats(78),
          ),
        ];
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: DeviceEnvironmentHistoryCard(
              repository: repo,
              tenantId: 'the-gene-pig',
              unitId: 'munters1',
              visible: true,
              chartHeight: 200,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(repo.calls.length, 1);
      expect(dataCharts(), findsOneWidget); // single-metric mode

      await t.tap(find.byTooltip('Ambas'));
      await t.pumpAndSettle();
      expect(repo.calls.length, 1); // 0 extra reads
      expect(dataCharts(), findsNWidgets(2)); // temp base + hum overlay
      expect(find.text('Temperatura interior'), findsOneWidget);
      expect(find.text('Humedad interior'), findsOneWidget);

      final hoverFinder = find.byKey(const Key('history-dual-hover-region'));
      final hoverRegion = t.widget<MouseRegion>(hoverFinder);
      final hoverSize = t.getSize(hoverFinder);
      hoverRegion.onHover!(
        PointerHoverEvent(
          position: Offset(hoverSize.width, hoverSize.height * 0.22),
        ),
      );
      await t.pump();

      final charts = t.widgetList<LineChart>(dataCharts()).toList();
      final humidityChart = charts.singleWhere(
        (chart) => chart.data.lineBarsData.first.color == Colors.cyanAccent,
      );
      expect(humidityChart.data.lineTouchData.enabled, isTrue);
      expect(humidityChart.data.lineTouchData.touchSpotThreshold, 8);
      final humidityBar = humidityChart.data.lineBarsData.first;
      final tooltip = humidityChart.data.lineTouchData.touchTooltipData
          .getTooltipItems(<LineBarSpot>[
            LineBarSpot(humidityBar, 0, humidityBar.spots.last),
          ])
          .single!;
      expect(tooltip.text, contains('mi/pr/ma: 77.0/78.0/79.0 %'));
      expect(tooltip.text, isNot(contains('Temp:')));
    });

    testWidgets(
      'a period missing one metric only gaps that series, not the whole point',
      (t) async {
        final repo = CountingRepository()
          ..pointsByUnit['device-munters1'] = [
            EnvironmentHistoryPoint(
              DateTime.utc(2026, 9, 25, 12),
              _stats(21),
              const EnvironmentHistoryStats(
                null,
                null,
                null,
                0,
              ), // no humidity yet
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
                initialMetric: EnvironmentHistoryMetric.both,
                chartHeight: 200,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        // Renders (not "Sin datos históricos") because temperature is present.
        expect(find.text('Sin datos históricos'), findsNothing);
        expect(dataCharts(), findsOneWidget); // no humidity => no overlay chart
      },
    );
  });

  group('Ejes dual-axis (§3)', () {
    testWidgets('temperature and humidity keep independent real scales', (
      t,
    ) async {
      final repo = CountingRepository()
        ..pointsByUnit['device-munters1'] = [
          EnvironmentHistoryPoint(
            DateTime.utc(2026, 9, 25, 12),
            _stats(21),
            _stats(75),
          ),
          EnvironmentHistoryPoint(
            DateTime.utc(2026, 9, 25, 13),
            _stats(23),
            _stats(80),
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
              initialMetric: EnvironmentHistoryMetric.both,
              chartHeight: 200,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final charts = t.widgetList<LineChart>(dataCharts()).toList();
      expect(charts.length, 2);
      final maxYs = charts.map((c) => c.data.maxY).toList()..sort();
      // Temperature (~23 + margin) and humidity (fixed 0-100) must NOT
      // collapse onto one shared/rescaled axis: their maxY stay genuinely
      // different and humidity's is always exactly 100, never normalized
      // down into the temperature range.
      expect(maxYs.first, lessThan(30));
      expect(maxYs.last, 100);
    });
  });

  group('Eje X Diario (§5/§6)', () {
    testWidgets(
      'all days shown, 1-9 without leading zero, month marker on change',
      (t) async {
        // Derived from the real current ART date rather than hardcoded, so
        // this test doesn't go stale at every calendar month boundary (it
        // previously hardcoded Aug/Sep 2026 and broke once "today" rolled
        // into October — the widget's "current month" is always real
        // DateTime.now(), so the fixture must track it instead of a fixed
        // date).
        final nowArt = DateTime.now().toUtc().subtract(
          const Duration(hours: 3),
        );
        final currentMonthStart = DateTime.utc(nowArt.year, nowArt.month, 1);
        final prevMonthLastDay = currentMonthStart.subtract(
          const Duration(days: 1),
        );
        final prevMonthSecondLastDay = prevMonthLastDay.subtract(
          const Duration(days: 1),
        );
        final currentMonthAbbrev =
            _testMonthAbbreviations[currentMonthStart.month - 1];
        final prevMonthAbbrev =
            _testMonthAbbreviations[prevMonthLastDay.month - 1];
        DateTime artMidnightUtc(DateTime artDay) =>
            DateTime.utc(artDay.year, artDay.month, artDay.day, 3);
        final repo = CountingRepository()
          ..pointsByUnit['device-munters1'] = [
            EnvironmentHistoryPoint(
              artMidnightUtc(prevMonthSecondLastDay),
              _stats(19),
              _stats(70),
            ),
            EnvironmentHistoryPoint(
              artMidnightUtc(prevMonthLastDay),
              _stats(19),
              _stats(71),
            ),
            EnvironmentHistoryPoint(
              artMidnightUtc(currentMonthStart),
              _stats(20),
              _stats(72),
            ),
            EnvironmentHistoryPoint(
              artMidnightUtc(currentMonthStart.add(const Duration(days: 1))),
              _stats(20),
              _stats(73),
            ),
            EnvironmentHistoryPoint(
              artMidnightUtc(currentMonthStart.add(const Duration(days: 2))),
              _stats(21),
              _stats(74),
            ),
          ];
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                child: DeviceEnvironmentHistoryCard(
                  repository: repo,
                  tenantId: 'the-gene-pig',
                  unitId: 'munters1',
                  visible: true,
                  chartHeight: 200,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Diario'));
        await t.pumpAndSettle();
        // Diario abre solo con el mes ART actual — los días del mes anterior
        // todavía no están cargados; cargarlos requiere el tap manual de "Mes
        // anterior" de abajo (no hay auto-relleno).
        expect(find.text('1'), findsOneWidget); // not '01'
        expect(find.text('01'), findsNothing);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text(currentMonthAbbrev), findsOneWidget);
        expect(find.text('${prevMonthLastDay.day}'), findsNothing);
        expect(find.text(prevMonthAbbrev), findsNothing);

        await t.tap(find.text('Mes anterior'));
        await t.pumpAndSettle();
        expect(find.text('${prevMonthSecondLastDay.day}'), findsOneWidget);
        expect(find.text('${prevMonthLastDay.day}'), findsOneWidget);
        expect(
          find.text(prevMonthAbbrev),
          findsOneWidget,
        ); // first point's month
        expect(
          find.text(currentMonthAbbrev),
          findsOneWidget,
        ); // month change at day 1
      },
    );
  });

  group('Tablero: acceso e integración (§8-§11)', () {
    Widget overview(CountingRepository repo) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: EnvironmentOverviewPage(
          units: <MuntersModel>[
            _unit('Sala1', 'munters1'),
            _unit('Sala2', 'munters2'),
          ],
          labels: const <String>['Sala1', 'Sala2'],
          plcIds: const <String?>['munters1', 'munters2'],
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

    // FIX Etapa 1/2: el icono ahora vive DENTRO del slot de cada métrica
    // (Key 'device-board-slot-tempInterior'/'...-humedadInterior'), no
    // flotando sobre toda la card — ver device_board_renderer.dart.
    Finder tempSlot(int index) =>
        find.byKey(const Key('device-board-slot-tempInterior')).at(index);
    Finder humSlot(int index) =>
        find.byKey(const Key('device-board-slot-humedadInterior')).at(index);
    Finder historyIconIn(Finder slot) =>
        find.descendant(of: slot, matching: find.byTooltip('Ver histórico'));

    testWidgets('entrar a Tablero → 0 reads históricos', (t) async {
      final repo = CountingRepository();
      await t.pumpWidget(overview(repo));
      await t.pump();
      expect(repo.calls, isEmpty);
      expect(
        find.byTooltip('Ver histórico'),
        findsNWidgets(4),
      ); // 2 icons x 2 Salas
      expect(historyIconIn(tempSlot(0)), findsOneWidget);
      expect(historyIconIn(tempSlot(1)), findsOneWidget);
      expect(historyIconIn(humSlot(0)), findsOneWidget);
      expect(historyIconIn(humSlot(1)), findsOneWidget);
    });

    testWidgets(
      'tap icon Temp abre el mismo histórico con estado inicial temperature',
      (t) async {
        // Bounded pumps, not pumpAndSettle: room_climate board cards carry a
        // persistent status animation (same reason
        // environment_overview_templates_test.dart never calls pumpAndSettle
        // on this page), which would hang waiting for it to finish.
        final repo = CountingRepository()
          ..pointsByUnit['device-munters1'] = [
            EnvironmentHistoryPoint(
              DateTime.utc(2026, 9, 25, 12),
              _stats(21),
              _stats(75),
            ),
          ];
        await t.pumpWidget(overview(repo));
        await t.pump();
        await t.tap(historyIconIn(tempSlot(0)));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byType(DeviceEnvironmentHistoryCard), findsOneWidget);
        final card = t.widget<DeviceEnvironmentHistoryCard>(
          find.byType(DeviceEnvironmentHistoryCard),
        );
        expect(card.initialMetric, EnvironmentHistoryMetric.temperature);
        expect(repo.calls, ['device-munters1']); // opened => exactly 1 read
      },
    );

    testWidgets(
      'tap icon Hum abre el mismo histórico con estado inicial humidity',
      (t) async {
        final repo = CountingRepository()
          ..pointsByUnit['device-munters2'] = [
            EnvironmentHistoryPoint(
              DateTime.utc(2026, 9, 25, 12),
              _stats(21),
              _stats(75),
            ),
          ];
        await t.pumpWidget(overview(repo));
        await t.pump();
        await t.tap(historyIconIn(humSlot(1)));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        final card = t.widget<DeviceEnvironmentHistoryCard>(
          find.byType(DeviceEnvironmentHistoryCard),
        );
        expect(card.initialMetric, EnvironmentHistoryMetric.humidity);
        expect(repo.calls, ['device-munters2']);
      },
    );

    testWidgets('Sala1 y Sala2 resuelven a scopes distintos (sin mezcla)', (
      t,
    ) async {
      final repo = CountingRepository();
      await t.pumpWidget(overview(repo));
      await t.pump();
      await t.tap(historyIconIn(tempSlot(0))); // Sala1
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byTooltip('Cerrar'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(historyIconIn(tempSlot(1))); // Sala2
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['device-munters1', 'device-munters2']);
    });
  });
}
