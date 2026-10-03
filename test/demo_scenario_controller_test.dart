import 'dart:io';

import 'package:agro_data_control/demo/demo.dart';
import 'package:agro_data_control/models/dashboard_snapshot.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeClock implements DemoMonotonicClock {
  Duration now = Duration.zero;
  @override
  Duration get elapsed => now;
  void advance(Duration value) => now += value;
  void reset() => now = Duration.zero;
}

MuntersModel unit(double temp, {bool fanQ5 = false}) => MuntersModel(
  name: 'Sala',
  historyPlcId: 'unit-1',
  backendOnline: true,
  configured: true,
  plcReachable: true,
  plcRunning: true,
  dataFresh: true,
  plcOnline: true,
  tempInterior: temp,
  tempIngresoSala: 21,
  humInterior: 60,
  tempExterior: 18,
  humExterior: 70,
  fanQ5: fanQ5,
  fanQ6: false,
  fanQ7: false,
  fanQ8: false,
  fanQ9: false,
  fanQ10: false,
  resistencia1: false,
  resistencia2: false,
  bombaHumidificador: false,
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
DashboardSnapshot snapshot(double temp, {bool fanQ5 = false}) =>
    DashboardSnapshot(
      units: <MuntersModel>[unit(temp, fanQ5: fanQ5)],
      doorEvents: const {},
      backendOnline: true,
      lastUpdatedAt: DateTime(2026, 10, 2),
      startedAt: DateTime(2026, 10, 2),
    );
DemoRuntimeScope scope({String site = 'site'}) => DemoRuntimeScope(
  tenantId: 'tenant',
  siteId: site,
  deviceId: 'device',
  snapshotUnitKey: 'unit-1',
);
DemoScenario scenario({List<DemoEvent>? events, Duration? duration}) =>
    DemoScenario(
      id: 'scenario',
      name: 'Scenario',
      duration: duration ?? const Duration(seconds: 20),
      events:
          events ??
          <DemoEvent>[
            DemoEvent(
              id: 'temp',
              targetSnapshotUnitKey: 'unit-1',
              signalKey: DemoSignalKey.indoorTemperature,
              startTime: Duration.zero,
              duration: const Duration(seconds: 10),
              fromValue: 20,
              toValue: 40,
              transition: DemoTransition.linear,
            ),
            DemoEvent(
              id: 'heat',
              targetSnapshotUnitKey: 'unit-1',
              signalKey: DemoSignalKey.heatingStage1,
              startTime: const Duration(seconds: 5),
              duration: Duration.zero,
              toValue: true,
            ),
          ],
    );

void main() {
  late FakeClock clock;
  late DemoRuntimeSelector selector;
  late DemoScenarioController controller;
  setUp(() {
    clock = FakeClock();
    selector = DemoRuntimeSelector(buildEnabled: true);
    controller = DemoScenarioController(selector: selector, clock: clock);
  });

  test('estado inicial OFF y activación congela baseline real', () {
    final real = snapshot(20);
    expect(controller.state, DemoPlaybackState.stopped);
    expect(
      controller.start(
        role: 'owner',
        realSnapshot: real,
        scope: scope(),
        scenario: scenario(),
      ),
      isTrue,
    );
    expect(selector.baselineSnapshot, isNot(same(real)));
    expect(selector.baselineSnapshot!.units.single.tempInterior, 20);
  });

  test('inicio, progreso lineal medio y final son deterministas', () {
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    expect(
      selector.selectForPresentation(snapshot(99)).units.single.tempInterior,
      20,
    );
    clock.advance(const Duration(seconds: 5));
    controller.tick();
    expect(
      selector.selectForPresentation(snapshot(99)).units.single.tempInterior,
      30,
    );
    clock.advance(const Duration(seconds: 5));
    controller.tick();
    expect(
      selector.selectForPresentation(snapshot(99)).units.single.tempInterior,
      40,
    );
  });

  test('reloj reiniciado accidentalmente se reancla en cero sin espera', () {
    final zeroEventScenario = scenario(
      events: <DemoEvent>[
        DemoEvent(
          id: 'at-zero',
          targetSnapshotUnitKey: 'unit-1',
          signalKey: DemoSignalKey.indoorTemperature,
          startTime: Duration.zero,
          duration: Duration.zero,
          toValue: 33,
        ),
      ],
    );
    clock.advance(const Duration(seconds: 13));
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: zeroEventScenario,
    );

    // Reproduce exactamente el lifecycle anterior: el controlador tomaba
    // el ancla en 13 s y la UI reiniciaba luego su Stopwatch a cero.
    clock.reset();
    expect(controller.position, Duration.zero);
    controller.tick();
    expect(controller.position, Duration.zero);
    expect(
      selector.selectForPresentation(snapshot(99)).units.single.tempInterior,
      33,
    );
  });

  test('reproducciones repetidas comienzan siempre en cero', () {
    for (var attempt = 0; attempt < 5; attempt++) {
      controller.start(
        role: 'owner',
        realSnapshot: snapshot(20 + attempt.toDouble()),
        scope: scope(),
        scenario: scenario(),
      );
      expect(controller.position, Duration.zero, reason: 'intento $attempt');
      clock.advance(const Duration(seconds: 3));
      controller.tick();
      expect(controller.position, const Duration(seconds: 3));
      controller.stop();
      clock.advance(const Duration(seconds: 2));
    }
  });

  test('reemplazar secuencia activa no hereda tiempo de la anterior', () {
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    clock.advance(const Duration(seconds: 7));
    controller.tick();

    controller.start(
      role: 'owner',
      realSnapshot: snapshot(41),
      scope: scope(),
      scenario: scenario(),
    );
    expect(controller.position, Duration.zero);
    expect(selector.baselineSnapshot!.units.single.tempInterior, 41);
    expect(controller.manualOverrides, isEmpty);
  });

  test('instantáneos, booleanos y concurrentes se evalúan juntos', () {
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    clock.advance(const Duration(seconds: 5));
    controller.tick();
    final display = selector.selectForPresentation(snapshot(99)).units.single;
    expect(display.tempInterior, 30);
    expect(display.resistencia1, isTrue);
    expect(
      controller.activeEvents.map((e) => e.id),
      containsAll(<String>['temp', 'heat']),
    );
  });

  test('solapamiento: gana inicio más reciente y luego id mayor', () {
    final s = scenario(
      events: <DemoEvent>[
        DemoEvent(
          id: 'a',
          targetSnapshotUnitKey: 'unit-1',
          signalKey: DemoSignalKey.indoorTemperature,
          startTime: Duration.zero,
          duration: Duration.zero,
          toValue: 25,
        ),
        DemoEvent(
          id: 'b',
          targetSnapshotUnitKey: 'unit-1',
          signalKey: DemoSignalKey.indoorTemperature,
          startTime: const Duration(seconds: 2),
          duration: Duration.zero,
          toValue: 30,
        ),
        DemoEvent(
          id: 'z',
          targetSnapshotUnitKey: 'unit-1',
          signalKey: DemoSignalKey.indoorTemperature,
          startTime: const Duration(seconds: 2),
          duration: Duration.zero,
          toValue: 35,
        ),
      ],
    );
    expect(
      DemoScenarioEvaluator.overridesAt(
        s,
        const Duration(seconds: 3),
      )[DemoSignalKey.indoorTemperature],
      35,
    );
  });

  test('rechaza eventos fuera del snapshotUnitKey del scope', () {
    final invalid = scenario(
      events: <DemoEvent>[
        DemoEvent(
          id: 'wrong-scope',
          targetSnapshotUnitKey: 'unit-2',
          signalKey: DemoSignalKey.indoorTemperature,
          startTime: Duration.zero,
          duration: Duration.zero,
          toValue: 30,
        ),
      ],
    );
    expect(
      () => controller.start(
        role: 'owner',
        realSnapshot: snapshot(20),
        scope: scope(),
        scenario: invalid,
      ),
      throwsArgumentError,
    );
    expect(selector.isActive, isFalse);
  });

  test('pause/resume no cuenta pausa y velocidad no salta', () {
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    clock.advance(const Duration(seconds: 2));
    controller.pause();
    clock.advance(const Duration(seconds: 8));
    expect(controller.position, const Duration(seconds: 2));
    controller.resume();
    clock.advance(const Duration(seconds: 1));
    controller.tick();
    expect(controller.position, const Duration(seconds: 3));
    controller.setSpeed(2);
    final before = controller.position;
    expect(controller.position, before);
    clock.advance(const Duration(seconds: 1));
    controller.tick();
    expect(controller.position, const Duration(seconds: 5));
  });

  test('admite exactamente 0.5x, 1x, 2x y 4x', () {
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    for (final speed in <double>[0.5, 1, 2, 4]) {
      expect(() => controller.setSpeed(speed), returnsNormally);
    }
    expect(() => controller.setSpeed(3), throwsArgumentError);
  });

  test('restart vuelve a cero sobre el mismo baseline', () {
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    clock.advance(const Duration(seconds: 8));
    controller.tick();
    expect(controller.restart(), isTrue);
    expect(controller.position, Duration.zero);
    expect(selector.baselineSnapshot!.units.single.tempInterior, 20);
  });

  test('nuevo real no muta baseline; Stop retorna el último real', () {
    final baseline = snapshot(20);
    final latest = snapshot(77);
    controller.start(
      role: 'owner',
      realSnapshot: baseline,
      scope: scope(),
      scenario: scenario(),
    );
    clock.advance(const Duration(seconds: 5));
    controller.tick();
    expect(selector.baselineSnapshot!.units.single.tempInterior, 20);
    controller.stop();
    expect(selector.selectForPresentation(latest), same(latest));
    expect(baseline.units.single.tempInterior, 20);
  });

  test('final natural desactiva demo y expone último real', () {
    final latest = snapshot(88);
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    clock.advance(const Duration(seconds: 20));
    controller.tick();
    expect(controller.state, DemoPlaybackState.completed);
    expect(selector.selectForPresentation(latest), same(latest));
    expect(controller.restart(), isTrue);
  });

  test('scope, logout, pérdida de gate y dispose limpian sesión', () {
    void activate() => controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    activate();
    controller.onSiteChanged('other');
    expect(controller.isActive, isFalse);
    activate();
    controller.onTenantChanged('other');
    expect(controller.isActive, isFalse);
    activate();
    controller.onDeviceChanged(deviceId: 'other', snapshotUnitKey: 'unit-1');
    expect(controller.isActive, isFalse);
    activate();
    controller.onLogout();
    expect(controller.isActive, isFalse);
    activate();
    controller.onRoleChanged('admin');
    expect(controller.isActive, isFalse);
    activate();
    controller.dispose();
    expect(controller.state, DemoPlaybackState.disposed);
  });

  test('fan demo prevalece en display sin mutar real ni comandos', () {
    final s = scenario(
      events: <DemoEvent>[
        DemoEvent(
          id: 'fan',
          targetSnapshotUnitKey: 'unit-1',
          signalKey: DemoSignalKey.fanQ5,
          startTime: Duration.zero,
          duration: Duration.zero,
          toValue: true,
        ),
      ],
      duration: const Duration(seconds: 2),
    );
    final real = snapshot(20, fanQ5: false);
    controller.start(
      role: 'owner',
      realSnapshot: real,
      scope: scope(),
      scenario: s,
    );
    expect(selector.selectForPresentation(real).units.single.fanQ5, isTrue);
    expect(real.units.single.fanQ5, isFalse);
  });

  test('modo manual valida y aplica numéricos, booleanos y null técnico', () {
    expect(
      controller.startManual(
        role: 'owner',
        realSnapshot: snapshot(20),
        scope: scope(),
      ),
      isTrue,
    );
    controller.setManualOverride(DemoSignalKey.indoorTemperature, 31.5);
    controller.setManualOverride(DemoSignalKey.roomDoorOpen, true);
    controller.setManualOverride(DemoSignalKey.networkFailure, null);
    final display = selector.selectForPresentation(snapshot(99)).units.single;
    expect(display.tempInterior, 31.5);
    expect(display.salaAbierta, isTrue);
    expect(display.fallaRed, isNull);
    expect(
      () => controller.setManualOverride(DemoSignalKey.indoorHumidity, 101),
      throwsArgumentError,
    );
  });

  test('manual gana a temporal y liberar vuelve al frame temporal actual', () {
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    clock.advance(const Duration(seconds: 5));
    controller.tick();
    controller.setManualOverride(DemoSignalKey.indoorTemperature, 50);
    expect(
      selector.selectForPresentation(snapshot(90)).units.single.tempInterior,
      50,
    );
    clock.advance(const Duration(seconds: 2));
    controller.tick();
    expect(
      selector.selectForPresentation(snapshot(90)).units.single.tempInterior,
      50,
    );
    controller.releaseManualOverride(DemoSignalKey.indoorTemperature);
    expect(
      selector.selectForPresentation(snapshot(90)).units.single.tempInterior,
      34,
    );
  });

  test('pausa permite override; restart, Stop y final limpian overrides', () {
    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    controller.pause();
    controller.setManualOverride(DemoSignalKey.indoorHumidity, 80);
    expect(controller.manualOverrides, isNotEmpty);
    controller.restart();
    expect(controller.manualOverrides, isEmpty);
    controller.setManualOverride(DemoSignalKey.indoorHumidity, 80);
    controller.stop();
    expect(controller.manualOverrides, isEmpty);

    controller.start(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
      scenario: scenario(),
    );
    controller.setManualOverride(DemoSignalKey.indoorHumidity, 80);
    clock.advance(const Duration(seconds: 20));
    controller.tick();
    expect(controller.manualOverrides, isEmpty);
    expect(selector.isActive, isFalse);
  });

  test('modo manual rechaza gate cerrado y conserva real nuevo al Stop', () {
    expect(
      controller.startManual(
        role: 'admin',
        realSnapshot: snapshot(20),
        scope: scope(),
      ),
      isFalse,
    );
    final latest = snapshot(77);
    controller.startManual(
      role: 'owner',
      realSnapshot: snapshot(20),
      scope: scope(),
    );
    controller.setManualOverride(DemoSignalKey.indoorTemperature, 50);
    controller.stop();
    expect(selector.selectForPresentation(latest), same(latest));
  });

  test('núcleo no contiene Timer, Firebase, HTTP ni persistencia', () {
    final source = File(
      'lib/demo/demo_scenario_controller.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Timer')));
    expect(source, isNot(contains('Firebase')));
    expect(source, isNot(contains('SharedPreferences')));
    expect(source, isNot(contains('package:http')));
  });
}
