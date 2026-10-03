import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control/demo/demo.dart';
import 'package:agro_data_control/models/dashboard_snapshot.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:flutter_test/flutter_test.dart';

MuntersModel _unit(double temperature) => MuntersModel(
  name: 'QA Device',
  historyPlcId: 'qa-unit',
  backendOnline: true,
  configured: true,
  plcReachable: true,
  plcRunning: true,
  dataFresh: true,
  plcOnline: true,
  tempInterior: temperature,
  tempIngresoSala: 22,
  humInterior: 60,
  tempExterior: 18,
  humExterior: 70,
  fanQ5: false,
  fanQ6: false,
  fanQ7: false,
  fanQ8: false,
  fanQ9: false,
  fanQ10: false,
  bombaHumidificador: false,
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

DashboardSnapshot _snapshot(double temperature) => DashboardSnapshot(
  units: <MuntersModel>[_unit(temperature)],
  doorEvents: const {},
  backendOnline: true,
  lastUpdatedAt: DateTime(2026, 10, 2, 10),
  startedAt: DateTime(2026, 10, 2, 9),
);

DemoRuntimeScope _scope({
  String tenant = 'qa-structural-test',
  String site = 'qa-site',
  String device = 'qa-device',
  String unit = 'qa-unit',
}) => DemoRuntimeScope(
  tenantId: tenant,
  siteId: site,
  deviceId: device,
  snapshotUnitKey: unit,
);

bool _activate(DemoRuntimeSelector selector, DashboardSnapshot real) =>
    selector.activate(
      role: 'owner',
      realSnapshot: real,
      scope: _scope(),
      overrides: const <DemoSignalKey, Object?>{
        DemoSignalKey.indoorTemperature: 35,
      },
    );

class _RuntimeHarness {
  _RuntimeHarness(this.selector, this.realSnapshot);

  final DemoRuntimeSelector selector;
  DashboardSnapshot realSnapshot;
  int pollingCycles = 0;
  final List<DashboardSnapshot> detectorInputs = <DashboardSnapshot>[];
  final List<DashboardSnapshot> eventInputs = <DashboardSnapshot>[];
  final List<DashboardSnapshot> historyInputs = <DashboardSnapshot>[];

  void receiveReal(DashboardSnapshot next) {
    pollingCycles++;
    realSnapshot = next;
    detectorInputs.add(next);
    eventInputs.add(next);
  }

  DemoSnapshotSelection get selection => DemoSnapshotSelection.resolve(
    realSnapshot: realSnapshot,
    selector: selector,
  );

  void openHistory() => historyInputs.add(selection.forHistoricalViews);
}

void main() {
  test('1. Demo OFF devuelve exactamente realSnapshot', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final real = _snapshot(20);
    expect(selector.selectForPresentation(real), same(real));
  });

  test('2. Demo ON devuelve otro snapshot sin modificar el real', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final real = _snapshot(20);
    expect(_activate(selector, real), isTrue);
    final display = selector.selectForPresentation(real);
    expect(display, isNot(same(real)));
    expect(display.units.single.tempInterior, 35);
    expect(real.units.single.tempInterior, 20);
    expect(selector.baselineSnapshot, isNot(same(real)));
    expect(selector.baselineSnapshot!.units.single.tempInterior, 20);
  });

  test('3. polling real continúa mientras Demo permanece activo', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final harness = _RuntimeHarness(selector, _snapshot(20));
    _activate(selector, harness.realSnapshot);

    harness.receiveReal(_snapshot(21));
    harness.receiveReal(_snapshot(22));
    harness.receiveReal(_snapshot(23));

    expect(harness.pollingCycles, 3);
    expect(harness.realSnapshot.units.single.tempInterior, 23);
    expect(harness.selection.displaySnapshot.units.single.tempInterior, 35);
  });

  test('4. snapshots reales nuevos quedan disponibles durante Demo', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final harness = _RuntimeHarness(selector, _snapshot(20));
    _activate(selector, harness.realSnapshot);
    final newest = _snapshot(29);
    harness.receiveReal(newest);

    expect(harness.selection.realSnapshot, same(newest));
    expect(harness.selection.displaySnapshot, isNot(same(newest)));
  });

  test('5. Stop vuelve inmediatamente al último realSnapshot', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final harness = _RuntimeHarness(selector, _snapshot(20));
    _activate(selector, harness.realSnapshot);
    final newest = _snapshot(29);
    harness.receiveReal(newest);
    selector.stop();

    expect(harness.selection.displaySnapshot, same(newest));
    expect(harness.selection.displaySnapshot.units.single.tempInterior, 29);
  });

  test('6. cambiar Tenant detiene Demo', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    _activate(selector, _snapshot(20));
    selector.onTenantChanged('another-tenant');
    expect(selector.isActive, isFalse);
  });

  test('7. cambiar Site detiene Demo', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    _activate(selector, _snapshot(20));
    selector.onSiteChanged('another-site');
    expect(selector.isActive, isFalse);
  });

  test('8. cambiar Device o snapshotUnitKey detiene Demo', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    _activate(selector, _snapshot(20));
    selector.onDeviceChanged(
      deviceId: 'another-device',
      snapshotUnitKey: 'qa-unit',
    );
    expect(selector.isActive, isFalse);

    _activate(selector, _snapshot(20));
    selector.onDeviceChanged(
      deviceId: 'qa-device',
      snapshotUnitKey: 'another-unit',
    );
    expect(selector.isActive, isFalse);
  });

  test('9. logout detiene Demo', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    _activate(selector, _snapshot(20));
    selector.onLogout();
    expect(selector.isActive, isFalse);
  });

  test('10. dispose detiene Demo y clausura el selector', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    _activate(selector, _snapshot(20));
    selector.dispose();
    expect(selector.isActive, isFalse);
    expect(
      () => selector.selectForPresentation(_snapshot(20)),
      throwsStateError,
    );
  });

  test('11. una inicialización nueva siempre comienza Demo OFF', () {
    final oldSelector = DemoRuntimeSelector(buildEnabled: true);
    _activate(oldSelector, _snapshot(20));
    final refreshedSelector = DemoRuntimeSelector(buildEnabled: true);
    final real = _snapshot(21);
    expect(refreshedSelector.isActive, isFalse);
    expect(refreshedSelector.selectForPresentation(real), same(real));
  });

  test('12. detectores reciben exclusivamente realSnapshot', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final real = _snapshot(20);
    final harness = _RuntimeHarness(selector, real);
    _activate(selector, real);
    final next = _snapshot(27);
    harness.receiveReal(next);

    expect(harness.detectorInputs.single, same(next));
    expect(
      harness.detectorInputs.single,
      same(harness.selection.forProductiveSideEffects),
    );
    expect(
      harness.detectorInputs.single,
      isNot(same(harness.selection.displaySnapshot)),
    );
  });

  test('13. eventos y side effects nunca reciben displaySnapshot', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final harness = _RuntimeHarness(selector, _snapshot(20));
    _activate(selector, harness.realSnapshot);
    final next = _snapshot(26);
    harness.receiveReal(next);

    expect(harness.eventInputs.single, same(next));
    expect(harness.selection.forProductiveSideEffects, same(next));
    expect(
      harness.eventInputs.single,
      isNot(same(harness.selection.displaySnapshot)),
    );
  });

  test('14. las cuatro vistas live reciben una fuente coherente', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final real = _snapshot(20);
    _activate(selector, real);
    final selection = DemoSnapshotSelection.resolve(
      realSnapshot: real,
      selector: selector,
    );
    final snapshots = <DashboardSnapshot>[
      for (final view in DemoLiveView.values) selection.forLiveView(view),
    ];
    expect(snapshots, everyElement(same(selection.displaySnapshot)));
  });

  test('15. las vistas históricas reciben sólo realSnapshot', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final harness = _RuntimeHarness(selector, _snapshot(20));
    _activate(selector, harness.realSnapshot);
    harness.openHistory();
    expect(harness.historyInputs.single, same(harness.realSnapshot));
    expect(
      harness.historyInputs.single,
      isNot(same(harness.selection.displaySnapshot)),
    );
  });

  test('16. build flag false conserva comportamiento productivo idéntico', () {
    final selector = DemoRuntimeSelector(buildEnabled: false);
    final real = _snapshot(20);
    expect(_activate(selector, real), isFalse);
    expect(selector.isActive, isFalse);
    expect(selector.selectForPresentation(real), same(real));
  });

  test('17. usuario distinto de owner no puede activar Demo', () {
    final selector = DemoRuntimeSelector(buildEnabled: true);
    final real = _snapshot(20);
    final activated = selector.activate(
      role: 'admin',
      realSnapshot: real,
      scope: _scope(),
      overrides: const <DemoSignalKey, Object?>{},
    );
    expect(activated, isFalse);
    expect(selector.selectForPresentation(real), same(real));
  });

  test('18. polling frontend 5 s y backend productivo 10 s se conservan', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(
      mainSource,
      contains(
        'static const Duration _liveRefreshInterval = Duration(seconds: 5);',
      ),
    );
    expect(mainSource, contains('if (dataUnchanged)'));

    for (final path in <String>[
      'backend/config/sites/default.json',
      'backend/config/sites/la-payana__roque-perez.json',
    ]) {
      final config = jsonDecode(File(path).readAsStringSync());
      expect(config['pollingIntervalMs'], 10000, reason: path);
    }
  });
}
