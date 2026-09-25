// Etapa 2/2 — widget-level coverage: meses anteriores, cache por período,
// doble solicitud, sin más historia, Ambas con una sola carga por mes,
// vista ampliada sin reads extra, lazy loading, aislamiento de scope.
import 'dart:async';

import 'package:agro_data_control/services/device_environment_history_repository.dart';
import 'package:agro_data_control/widgets/device_environment_history_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EnvironmentHistoryStats _stats(double v, {int count = 3}) =>
    EnvironmentHistoryStats(v, v - 1, v + 1, count);

List<EnvironmentHistoryPoint> _monthPoints(
  int year,
  int month,
  List<int> days, {
  double baseTemp = 20,
  bool withHumidity = true,
}) => [
  for (final d in days)
    EnvironmentHistoryPoint(
      DateTime.utc(year, month, d, 3),
      _stats(baseTemp + d * 0.1),
      withHumidity
          ? _stats(70 + d * 0.5)
          : const EnvironmentHistoryStats(null, null, null, 0),
    ),
];

class CountingRepository extends DeviceEnvironmentHistoryRepository {
  final monthCalls = <String>[];
  // month -> points (missing key = empty result, i.e. "no more history").
  Map<String, List<EnvironmentHistoryPoint>> pointsByMonth = {};

  @override
  Future<EnvironmentHistoryScope> resolve(String tenant, String unit) async =>
      EnvironmentHistoryScope(tenant, 'las-heras', 'device-$unit');

  @override
  Future<List<EnvironmentHistoryPoint>> load(
    EnvironmentHistoryScope s,
    EnvironmentHistoryMode m,
    int limit,
  ) async => const []; // Horario no es objeto de estos tests.

  @override
  Future<List<EnvironmentHistoryPoint>> loadMonth(
    EnvironmentHistoryScope s,
    EnvironmentHistoryMonth month,
  ) async {
    monthCalls.add('${s.deviceId}/$month');
    return pointsByMonth['${s.deviceId}/$month'] ?? const [];
  }
}

/// Like [CountingRepository] but each loadMonth call waits on an
/// externally-controlled [Completer], so a test can dispatch a second tap
/// WHILE the first fetch is still genuinely pending.
class _GatedRepository extends DeviceEnvironmentHistoryRepository {
  _GatedRepository(this.gate);
  final Map<String, Completer<List<EnvironmentHistoryPoint>>> gate;
  final monthCalls = <String>[];
  Map<String, List<EnvironmentHistoryPoint>> pointsByMonth = {};

  @override
  Future<EnvironmentHistoryScope> resolve(String tenant, String unit) async =>
      EnvironmentHistoryScope(tenant, 'las-heras', 'device-$unit');

  @override
  Future<List<EnvironmentHistoryPoint>> load(
    EnvironmentHistoryScope s,
    EnvironmentHistoryMode m,
    int limit,
  ) async => const [];

  @override
  Future<List<EnvironmentHistoryPoint>> loadMonth(
    EnvironmentHistoryScope s,
    EnvironmentHistoryMonth month,
  ) {
    final key = '${s.deviceId}/$month';
    monthCalls.add(key);
    final completer =
        gate[key] ??= Completer<List<EnvironmentHistoryPoint>>();
    return completer.future;
  }
}

EnvironmentHistoryMonth _currentArtMonth() {
  final art = DateTime.now().toUtc().subtract(const Duration(hours: 3));
  return EnvironmentHistoryMonth(art.year, art.month);
}

void main() {
  final current = _currentArtMonth();
  final previous = current.previous;
  final twoBack = previous.previous;

  Widget host(
    DeviceEnvironmentHistoryRepository repo, {
    EnvironmentHistoryMetric metric = EnvironmentHistoryMetric.temperature,
    String unit = 'munters1',
  }) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: DeviceEnvironmentHistoryCard(
        repository: repo,
        tenantId: 'the-gene-pig',
        unitId: unit,
        visible: true,
        initialMode: EnvironmentHistoryMode.daily,
        initialMetric: metric,
      ),
    ),
  );

  testWidgets('abrir Diario carga solo el mes actual (§1)', (t) async {
    final repo = CountingRepository()
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1, 2, 3],
      );
    await t.pumpWidget(host(repo));
    await t.pumpAndSettle();
    expect(repo.monthCalls, ['device-munters1/$current']);
    expect(find.text('Mes anterior'), findsOneWidget);
  });

  testWidgets('tap Mes anterior carga exactamente 1 mes adicional (§2)', (
    t,
  ) async {
    final repo = CountingRepository()
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1, 2],
      )
      ..pointsByMonth['device-munters1/$previous'] = _monthPoints(
        previous.year,
        previous.month,
        [28, 29],
      );
    await t.pumpWidget(host(repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Mes anterior'));
    await t.pumpAndSettle();
    expect(repo.monthCalls, [
      'device-munters1/$current',
      'device-munters1/$previous',
    ]);
    // Ambos meses concatenados: 4 puntos en total, sin perder los del mes
    // actual al agregar el anterior.
    final chart = t.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots.length, 4);
  });

  testWidgets('volver a un mes ya cargado (toggle Horario/Diario) → 0 reads (§4)', (
    t,
  ) async {
    final repo = CountingRepository()
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1],
      )
      ..pointsByMonth['device-munters1/$previous'] = _monthPoints(
        previous.year,
        previous.month,
        [28],
      );
    await t.pumpWidget(host(repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Mes anterior'));
    await t.pumpAndSettle();
    expect(repo.monthCalls.length, 2);
    await t.tap(find.text('Horario'));
    await t.pumpAndSettle();
    await t.tap(find.text('Diario'));
    await t.pumpAndSettle();
    expect(repo.monthCalls.length, 2); // los mismos 2 meses, sin repetir
  });

  testWidgets('doble tap en Mes anterior no duplica la query (§ doble solicitud)', (
    t,
  ) async {
    // Completer-controlled fetch so the second tap genuinely lands WHILE
    // the first is still in flight (a fake in-memory repo would otherwise
    // resolve instantly between the two tap() calls, defeating the test).
    final gate = <String, Completer<List<EnvironmentHistoryPoint>>>{};
    final repo = _GatedRepository(gate)
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1],
      )
      ..pointsByMonth['device-munters1/$previous'] = _monthPoints(
        previous.year,
        previous.month,
        [28],
      );
    await t.pumpWidget(host(repo));
    await t.pump(); // lets resolve()+loadMonth() actually run and gate the completer
    gate['device-munters1/$current']!.complete(
      repo.pointsByMonth['device-munters1/$current'],
    );
    await t.pumpAndSettle();

    await t.tap(find.text('Mes anterior'));
    await t.pump(); // starts the fetch, does not resolve it
    await t.tap(find.text('Mes anterior')); // button now disabled: no-op
    await t.pump();
    expect(repo.monthCalls, [
      'device-munters1/$current',
      'device-munters1/$previous',
    ]); // "previous" solicitado una sola vez pese a los dos taps
    gate['device-munters1/$previous']!.complete(
      repo.pointsByMonth['device-munters1/$previous'],
    );
    await t.pumpAndSettle();
    expect(repo.monthCalls, [
      'device-munters1/$current',
      'device-munters1/$previous',
    ]);
  });

  testWidgets('sin más historia: botón se deshabilita y no repite queries vacías (§19)', (
    t,
  ) async {
    final repo = CountingRepository()
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1],
      );
    // pointsByMonth no tiene entrada para `previous` => loadMonth devuelve [].
    await t.pumpWidget(host(repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Mes anterior'));
    await t.pumpAndSettle();
    expect(repo.monthCalls, [
      'device-munters1/$current',
      'device-munters1/$previous',
    ]);
    final button = t.widget<TextButton>(
      find.ancestor(
        of: find.text('Mes anterior'),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNull); // deshabilitado
    // Un segundo tap (si el test forzara el gesto) no debería ni ejecutarse
    // por estar disabled; confirmamos indirectamente que no hay más calls.
    expect(repo.monthCalls.length, 2);
  });

  testWidgets('humedad en mes viejo (solo legacy): gap, nunca cero (§6)', (
    t,
  ) async {
    final repo = CountingRepository()
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1],
      )
      ..pointsByMonth['device-munters1/$previous'] = _monthPoints(
        previous.year,
        previous.month,
        [28],
        withHumidity: false,
      );
    await t.pumpWidget(
      host(repo, metric: EnvironmentHistoryMetric.humidity),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Mes anterior'));
    await t.pumpAndSettle();
    final chart = t.widget<LineChart>(find.byType(LineChart));
    final spots = chart.data.lineBarsData.single.spots;
    expect(spots.length, 2);
    expect(spots.first, FlSpot.nullSpot); // mes viejo: sin humedad, gap
    expect(spots.where((s) => s.y == 0), isEmpty); // nunca cero artificial
  });

  testWidgets('Ambas: cargar mes nuevo actualiza las dos series con una sola carga (§7)', (
    t,
  ) async {
    final repo = CountingRepository()
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1],
      )
      ..pointsByMonth['device-munters1/$previous'] = _monthPoints(
        previous.year,
        previous.month,
        [28],
      );
    await t.pumpWidget(host(repo, metric: EnvironmentHistoryMetric.both));
    await t.pumpAndSettle();
    await t.tap(find.text('Mes anterior'));
    await t.pumpAndSettle();
    expect(repo.monthCalls.length, 2); // 1 carga por mes, no 2 (una por métrica)
    expect(find.byType(LineChart), findsNWidgets(2)); // temp + hum superpuestos
  });

  testWidgets('ampliar no genera reads extra y conserva el estado al cerrar (§12-13)', (
    t,
  ) async {
    final repo = CountingRepository()
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1],
      )
      ..pointsByMonth['device-munters1/$previous'] = _monthPoints(
        previous.year,
        previous.month,
        [28],
      );
    await t.pumpWidget(host(repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Mes anterior'));
    await t.pumpAndSettle();
    expect(repo.monthCalls.length, 2);

    await t.tap(find.byTooltip('Ampliar'));
    await t.pumpAndSettle();
    expect(repo.monthCalls.length, 2); // 0 reads extra al ampliar
    expect(find.text('Histórico ampliado'), findsOneWidget);
    // El mismo estado (2 meses) se ve reflejado en la copia ampliada.
    expect(find.text('Mes anterior'), findsNWidgets(2)); // compacta + ampliada

    await t.tap(find.byTooltip('Cerrar'));
    await t.pumpAndSettle();
    expect(find.text('Histórico ampliado'), findsNothing);
    expect(repo.monthCalls.length, 2); // cerrar tampoco genera reads
    // El estado original sigue disponible sin recargar.
    final chart = t.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots.length, 2);
  });

  testWidgets('lazy loading: visible=false → 0 reads; visible=true → 1 mes', (
    t,
  ) async {
    final repo = CountingRepository()
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1],
      );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceEnvironmentHistoryCard(
            repository: repo,
            tenantId: 'the-gene-pig',
            unitId: 'munters1',
            visible: false,
            initialMode: EnvironmentHistoryMode.daily,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(repo.monthCalls, isEmpty);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceEnvironmentHistoryCard(
            repository: repo,
            tenantId: 'the-gene-pig',
            unitId: 'munters1',
            visible: true,
            initialMode: EnvironmentHistoryMode.daily,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(repo.monthCalls, ['device-munters1/$current']);
  });

  testWidgets('scope: Sala1 y Sala2 mantienen meses cargados independientes', (
    t,
  ) async {
    final repo = CountingRepository()
      ..pointsByMonth['device-munters1/$current'] = _monthPoints(
        current.year,
        current.month,
        [1],
      )
      ..pointsByMonth['device-munters1/$previous'] = _monthPoints(
        previous.year,
        previous.month,
        [28],
      )
      ..pointsByMonth['device-munters2/$current'] = _monthPoints(
        current.year,
        current.month,
        [1, 2, 3],
      );
    await t.pumpWidget(host(repo, unit: 'munters1'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mes anterior'));
    await t.pumpAndSettle();
    expect(repo.monthCalls, [
      'device-munters1/$current',
      'device-munters1/$previous',
    ]);

    await t.pumpWidget(host(repo, unit: 'munters2'));
    await t.pumpAndSettle();
    expect(repo.monthCalls, [
      'device-munters1/$current',
      'device-munters1/$previous',
      'device-munters2/$current',
    ]);
    final chart = t.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots.length, 3); // solo Sala2
  });

  test('regresión: el punto de corte de "hace dos meses" también funciona', () {
    // Sanity check on the fixtures themselves — not a real Firestore round
    // trip, just confirming previous.previous rolls over correctly for the
    // scenarios above regardless of which real month "today" happens to be.
    expect(twoBack.month, isNot(previous.month));
  });
}
