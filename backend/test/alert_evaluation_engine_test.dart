import 'package:agro_data_control_backend/src/alert_evaluation_engine.dart';
import 'package:agro_data_control_backend/src/alert_models.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/alert_processing_coordinator.dart';
import 'package:agro_data_control_backend/src/alert_runtime.dart';
import 'package:agro_data_control_backend/src/alert_settings_cache.dart';
import 'package:agro_data_control_backend/src/room_wash_registry.dart';

Future<void> main() async {
  _testDoorEvaluators();
  _testTemperatureEvaluators();
  _testPressureEvaluator();
  _testHumidityEvaluator();
  _testDewPointEvaluator();
  await _testCoordinatorTransitionsAndCache();
  await _testWhatsAppCandidatesUseConfiguredOrder();
  await _testOrderChangeDoesNotCreateTransition();
  await _testHysteresisPreventsThresholdFlapping();
  await _testCooldownSuppressesFastResend();
  await _testThresholdChangeCreatesActivation();
  await _testActiveAlertConfigChangeRespectsCooldown();
  await _testSendWhatsappEnableReevaluatesActiveAlert();
  _testMuntersSpecificThresholds();
  await _testStopDoesNotRecover();
  await _testOneHundredSnapshotsConsumption();
}

Future<void> _testThresholdChangeCreatesActivation() async {
  final AlertSettingsCache cache = AlertSettingsCache();
  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(tempMin: 19),
  );
  final AlertRuntime runtime = AlertRuntime(settingsCache: cache);
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );
  final DateTime t0 = DateTime.utc(2026, 1, 1, 10);
  SnapshotAlertProcessingResult result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 19.5)),
    evaluatedAt: t0,
  );
  _expect(result.whatsAppCandidates.isEmpty, 'initial threshold is normal');

  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(tempMin: 20),
    now: t0.add(const Duration(seconds: 10)),
  );
  result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 19.5)),
    evaluatedAt: t0.add(const Duration(seconds: 10)),
  );
  _expect(
    result.whatsAppCandidates.any(
      (EvaluatedAlert alert) => alert.type == AlertType.temperatureInterior,
    ),
    'threshold change creates new active alert',
  );
}

Future<void> _testActiveAlertConfigChangeRespectsCooldown() async {
  final AlertSettingsCache cache = AlertSettingsCache();
  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(tempMin: 19),
  );
  final AlertRuntime runtime = AlertRuntime(settingsCache: cache);
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );
  final DateTime t0 = DateTime.utc(2026, 1, 1, 10);
  SnapshotAlertProcessingResult result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 18.5)),
    evaluatedAt: t0,
  );
  _expect(result.whatsAppCandidates.length == 1, 'initial active alert sends');

  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(tempMin: 20),
    now: t0.add(const Duration(minutes: 3)),
  );
  result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 18.5)),
    evaluatedAt: t0.add(const Duration(minutes: 3)),
  );
  _expect(
    result.rooms.first.transitionBatch!.configChangedActivated.length == 1,
    'active alert is reevaluated by config change',
  );
  _expect(
    result.whatsAppCandidates.isEmpty,
    'cooldown suppresses config-change resend',
  );

  result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 18.5)),
    evaluatedAt: t0.add(const Duration(minutes: 4)),
  );
  _expect(
    result.rooms.first.transitionBatch!.configChangedActivated.isEmpty,
    'config version is marked evaluated after cooldown suppression',
  );
  _expect(result.whatsAppCandidates.isEmpty, 'does not retry every snapshot');
}

Future<void> _testSendWhatsappEnableReevaluatesActiveAlert() async {
  final AlertSettingsCache cache = AlertSettingsCache();
  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(
      tempMin: 19,
      toggleOverrides: <String, Object?>{
        'temperatureInterior': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': false,
        },
      },
    ),
  );
  final AlertRuntime runtime = AlertRuntime(settingsCache: cache);
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );
  final DateTime t0 = DateTime.utc(2026, 1, 1, 10);
  SnapshotAlertProcessingResult result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 18.5)),
    evaluatedAt: t0,
  );
  _expect(
    result.whatsAppCandidates.isEmpty,
    'sendWhatsapp false does not send',
  );

  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(tempMin: 19),
    now: t0.add(const Duration(minutes: 1)),
  );
  result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 18.5)),
    evaluatedAt: t0.add(const Duration(minutes: 1)),
  );
  _expect(
    result.whatsAppCandidates.length == 1,
    'sendWhatsapp false to true creates notification candidate',
  );
}

void _testMuntersSpecificThresholds() {
  final CachedAlertSettings settings = _settings(
    tempMin: 15,
    munters2TempMin: 20,
  );
  final AlertEvaluationEngine engine = AlertEvaluationEngine();
  final List<EvaluatedAlert> munters1Alerts = engine.evaluate(
    AlertEvaluationContext(
      identity: const AlertIdentity(
        tenantId: 'tenant-a',
        siteId: 'site-a',
        roomId: 'room_1',
        roomNumber: 1,
        muntersId: 'munters1',
      ),
      snapshot: SnapshotRoomData(values: _unit(tempInterior: 19)),
      settings: settings,
      evaluatedAt: DateTime.utc(2026),
      roomWashStatus: const RoomWashStatus(withinWashWindow: false),
    ),
  );
  final List<EvaluatedAlert> munters2Alerts = engine.evaluate(
    AlertEvaluationContext(
      identity: const AlertIdentity(
        tenantId: 'tenant-a',
        siteId: 'site-a',
        roomId: 'room_2',
        roomNumber: 2,
        muntersId: 'munters2',
      ),
      snapshot: SnapshotRoomData(values: _unit(tempInterior: 19)),
      settings: settings,
      evaluatedAt: DateTime.utc(2026),
      roomWashStatus: const RoomWashStatus(withinWashWindow: false),
    ),
  );
  _expect(
    !_hasAlert(AlertType.temperatureInterior, munters1Alerts),
    'munters1 uses munters1 threshold',
  );
  _expect(
    _hasAlert(AlertType.temperatureInterior, munters2Alerts),
    'munters2 uses munters2 threshold',
  );
}

Future<void> _testHysteresisPreventsThresholdFlapping() async {
  final AlertRuntime runtime = _runtimeWithSettings(_settings());
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );
  await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 31, resistencia1: true)),
    evaluatedAt: DateTime.utc(2026, 1, 1, 10),
  );
  SnapshotAlertProcessingResult nearNormal = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 29.5, resistencia1: false)),
    evaluatedAt: DateTime.utc(2026, 1, 1, 10, 0, 5),
  );
  _expect(
    nearNormal.rooms.first.transitionBatch!.recovered.isEmpty,
    'temperature alert does not recover inside hysteresis band',
  );
  _expect(
    runtime.activeAlertsRegistry.size == 2,
    'alert remains active inside hysteresis band',
  );
  nearNormal = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 29, resistencia1: false)),
    evaluatedAt: DateTime.utc(2026, 1, 1, 10, 0, 10),
  );
  _expect(
    nearNormal.rooms.first.transitionBatch!.recovered.length == 2,
    'temperature alert recovers after hysteresis clears',
  );
}

Future<void> _testCooldownSuppressesFastResend() async {
  final AlertRuntime runtime = _runtimeWithSettings(_settings());
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );
  final DateTime t0 = DateTime.utc(2026, 1, 1, 10);
  SnapshotAlertProcessingResult result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 31, resistencia1: true)),
    evaluatedAt: t0,
  );
  _expect(result.whatsAppCandidates.length == 2, 'first activation sends');
  await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 29, resistencia1: false)),
    evaluatedAt: t0.add(const Duration(seconds: 20)),
  );
  result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 31, resistencia1: true)),
    evaluatedAt: t0.add(const Duration(minutes: 1)),
  );
  _expect(
    result.rooms.first.transitionBatch!.activated.length == 2,
    'reactivation before cooldown is detected',
  );
  _expect(
    result.whatsAppCandidates.isEmpty,
    'reactivation before cooldown does not send',
  );
  await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 29, resistencia1: false)),
    evaluatedAt: t0.add(const Duration(minutes: 2)),
  );
  result = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 31, resistencia1: true)),
    evaluatedAt: t0.add(const Duration(minutes: 11)),
  );
  _expect(
    result.whatsAppCandidates.length == 2,
    'reactivation after cooldown sends again',
  );
}

Future<void> _testWhatsAppCandidatesUseConfiguredOrder() async {
  final _FakeLoader loader = _FakeLoader(
    _settingsRaw(
      dewPointRed: -100,
      toggleOverrides: <String, Object?>{
        'muntersDoorOpen': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
          'order': 7,
        },
        'highTemperatureHeatingActive': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
          'order': 3,
        },
        'highHumidity': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
          'order': 1,
        },
      },
    ),
  );
  final AlertRuntime runtime = AlertRuntime(
    settingsCache: AlertSettingsCache(loader: loader),
  );
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );

  final SnapshotAlertProcessingResult result = await coordinator
      .processSnapshot(
        _snapshot(
          _unit(
            tempInterior: 31,
            resistencia1: true,
            humInterior: 96,
            puertaMunter: true,
          ),
        ),
        evaluatedAt: DateTime.utc(2026, 1, 1, 10),
      );

  _expect(
    result.whatsAppCandidates
            .map((EvaluatedAlert alert) => alert.type)
            .join(',') ==
        <AlertType>[
          AlertType.highHumidity,
          AlertType.temperatureInterior,
          AlertType.highTemperatureHeatingActive,
          AlertType.muntersDoorOpen,
        ].join(','),
    'whatsapp candidates use configured order',
  );
}

Future<void> _testOrderChangeDoesNotCreateTransition() async {
  final AlertSettingsCache cache = AlertSettingsCache();
  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(
      toggleOverrides: <String, Object?>{
        'highTemperatureHeatingActive': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
          'order': 3,
        },
      },
    ),
  );
  final AlertRuntime runtime = AlertRuntime(settingsCache: cache);
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );
  final Map<String, Object?> snapshot = _snapshot(
    _unit(tempInterior: 31, resistencia1: true),
  );
  await coordinator.processSnapshot(
    snapshot,
    evaluatedAt: DateTime.utc(2026, 1, 1, 10),
  );
  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(
      toggleOverrides: <String, Object?>{
        'highTemperatureHeatingActive': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
          'order': 1,
        },
      },
    ),
  );
  final SnapshotAlertProcessingResult result = await coordinator
      .processSnapshot(
        snapshot,
        evaluatedAt: DateTime.utc(2026, 1, 1, 10, 0, 5),
      );
  final AlertTransitionBatch batch = result.rooms.first.transitionBatch!;
  _expect(batch.activated.isEmpty, 'order change does not reactivate');
  _expect(batch.recovered.isEmpty, 'order change does not recover');
  _expect(batch.stillActive.length == 2, 'order change remains stillActive');
}

void _testDoorEvaluators() {
  final List<EvaluatedAlert> alerts = _engineAlerts(
    unitJson: _unit(puertaMunter: true, puertaSala: true),
  );
  _expect(
    alerts.any(
      (EvaluatedAlert alert) => alert.type == AlertType.muntersDoorOpen,
    ),
    'munters door true activates',
  );
  _expect(
    alerts.any((EvaluatedAlert alert) => alert.type == AlertType.roomDoorOpen),
    'room door true activates',
  );
  final List<EvaluatedAlert> closed = _engineAlerts(
    unitJson: _unit(puertaMunter: false, puertaSala: false),
  );
  _expect(
    !closed.any(
      (EvaluatedAlert alert) => alert.type == AlertType.muntersDoorOpen,
    ),
    'munters door false does not activate',
  );
  _expect(
    !closed.any((EvaluatedAlert alert) => alert.type == AlertType.roomDoorOpen),
    'room door false does not activate',
  );
  final List<EvaluatedAlert> absent = _engineAlerts(unitJson: _unit());
  _expect(
    !absent.any(
      (EvaluatedAlert alert) =>
          alert.type == AlertType.muntersDoorOpen ||
          alert.type == AlertType.roomDoorOpen,
    ),
    'missing door fields do not activate',
  );
}

void _testTemperatureEvaluators() {
  final EvaluatedAlert lowInterior =
      _engineAlerts(
        settings: _settings(tempMin: 18.5),
        unitJson: _unit(tempInterior: 18, bombaHumidificador: false),
      ).firstWhere(
        (EvaluatedAlert alert) => alert.type == AlertType.temperatureInterior,
      );
  _expect(
    lowInterior.thresholdKind == AlertThresholdKind.minimum &&
        lowInterior.measuredValue == 18 &&
        lowInterior.thresholdValue == 18.5 &&
        lowInterior.sendWhatsapp,
    'interior temperature below minimum activates with whatsapp',
  );
  final EvaluatedAlert highInterior =
      _engineAlerts(
        settings: _settings(tempMax: 30),
        unitJson: _unit(tempInterior: 31, resistencia1: false),
      ).firstWhere(
        (EvaluatedAlert alert) => alert.type == AlertType.temperatureInterior,
      );
  _expect(
    highInterior.thresholdKind == AlertThresholdKind.maximum &&
        highInterior.measuredValue == 31 &&
        highInterior.thresholdValue == 30,
    'interior temperature above maximum activates without heating',
  );
  _expect(
    !_hasAlert(
      AlertType.temperatureInterior,
      _engineAlerts(
        settings: _settings(tempMin: 18.5),
        unitJson: _unit(tempInterior: 18.5),
      ),
    ),
    'interior temperature equal threshold does not activate',
  );
  _expect(
    _hasAlert(
      AlertType.highTemperatureHeatingActive,
      _engineAlerts(unitJson: _unit(tempInterior: 31, resistencia1: true)),
    ),
    'high temp with resistencia1 activates',
  );
  _expect(
    _hasAlert(
      AlertType.highTemperatureHeatingActive,
      _engineAlerts(unitJson: _unit(tempInterior: 31, resistencia2: true)),
    ),
    'high temp with resistencia2 activates',
  );
  _expect(
    !_hasAlert(
      AlertType.highTemperatureHeatingActive,
      _engineAlerts(unitJson: _unit(tempInterior: 31)),
    ),
    'high temp without heating does not activate',
  );
  _expect(
    !_hasAlert(
      AlertType.highTemperatureHeatingActive,
      _engineAlerts(unitJson: _unit(tempInterior: 30, resistencia1: true)),
    ),
    'temperature equal maximum does not activate',
  );
  _expect(
    !_hasAlert(
      AlertType.highTemperatureHeatingActive,
      _engineAlerts(
        unitJson: _unit(tempInterior: double.nan, resistencia1: true),
      ),
    ),
    'invalid high temperature does not activate',
  );
  _expect(
    !_hasAlert(
      AlertType.highTemperatureHeatingActive,
      _engineAlerts(
        settings: _settings(
          toggleOverrides: <String, Object?>{
            'highTemperatureHeatingActive': <String, Object?>{
              'enabled': false,
              'sendWhatsapp': true,
            },
          },
        ),
        unitJson: _unit(tempInterior: 31, resistencia1: true),
      ),
    ),
    'disabled high temp heating does not activate',
  );
  final EvaluatedAlert highNoWhatsapp =
      _engineAlerts(
        settings: _settings(
          toggleOverrides: <String, Object?>{
            'highTemperatureHeatingActive': <String, Object?>{
              'enabled': true,
              'sendWhatsapp': false,
            },
          },
        ),
        unitJson: _unit(tempInterior: 31, resistencia1: true),
      ).firstWhere(
        (EvaluatedAlert alert) =>
            alert.type == AlertType.highTemperatureHeatingActive,
      );
  _expect(!highNoWhatsapp.sendWhatsapp, 'sendWhatsapp false is copied');

  _expect(
    _hasAlert(
      AlertType.lowTemperatureHumidifierActive,
      _engineAlerts(
        unitJson: _unit(tempInterior: 14, bombaHumidificador: true),
      ),
    ),
    'low temp with pump activates',
  );
  _expect(
    !_hasAlert(
      AlertType.lowTemperatureHumidifierActive,
      _engineAlerts(
        unitJson: _unit(tempInterior: 14, bombaHumidificador: false),
      ),
    ),
    'low temp without pump does not activate',
  );
  _expect(
    !_hasAlert(
      AlertType.lowTemperatureHumidifierActive,
      _engineAlerts(
        unitJson: _unit(tempInterior: 15, bombaHumidificador: true),
      ),
    ),
    'temperature equal minimum does not activate',
  );
}

void _testPressureEvaluator() {
  _expect(
    _hasAlert(
      AlertType.highDifferentialPressure,
      _engineAlerts(unitJson: _unit(presionDiferencial: 31)),
    ),
    'pressure over maximum activates',
  );
  _expect(
    !_hasAlert(
      AlertType.highDifferentialPressure,
      _engineAlerts(unitJson: _unit(presionDiferencial: 30)),
    ),
    'pressure equal maximum does not activate',
  );
  _expect(
    !_hasAlert(
      AlertType.highDifferentialPressure,
      _engineAlerts(unitJson: _unit(presionDiferencial: double.infinity)),
    ),
    'invalid pressure does not activate',
  );
}

void _testHumidityEvaluator() {
  _expect(
    !_hasAlert(
      AlertType.highHumidity,
      _engineAlerts(unitJson: _unit(humInterior: 95)),
    ),
    'humidity equal redMinExclusive does not activate',
  );
  _expect(
    _hasAlert(
      AlertType.highHumidity,
      _engineAlerts(unitJson: _unit(humInterior: 96)),
    ),
    'humidity greater than redMinExclusive activates',
  );
  final EvaluatedAlert clamped = _engineAlerts(
    unitJson: _unit(humInterior: 104),
  ).firstWhere((EvaluatedAlert alert) => alert.type == AlertType.highHumidity);
  _expect(clamped.measuredValue == 100, 'humidity is clamped to 100');

  final AlertRuntime runtime = _runtimeWithSettings(_settings());
  runtime.roomWashRegistry.registerWash(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    washedAt: DateTime.utc(2026, 1, 1, 10),
  );
  _expect(
    !_hasAlert(
      AlertType.highHumidity,
      _engineAlerts(
        runtime: runtime,
        unitJson: _unit(humInterior: 99),
        evaluatedAt: DateTime.utc(2026, 1, 1, 11, 59),
      ),
    ),
    'humidity inside wash window does not activate',
  );
  _expect(
    _hasAlert(
      AlertType.highHumidity,
      _engineAlerts(
        runtime: runtime,
        unitJson: _unit(humInterior: 99),
        evaluatedAt: DateTime.utc(2026, 1, 1, 12),
      ),
    ),
    'humidity at wash window boundary can activate',
  );
}

void _testDewPointEvaluator() {
  _expect(
    _hasAlert(
      AlertType.dewPointRisk,
      _engineAlerts(
        settings: _settings(dewPointRed: 5),
        unitJson: _unit(tempInterior: 22, humInterior: 75),
      ),
    ),
    'dew point red condition activates',
  );
  _expect(
    !_hasAlert(
      AlertType.dewPointRisk,
      _engineAlerts(
        settings: _settings(dewPointRed: 1),
        unitJson: _unit(tempInterior: 22, humInterior: 75),
      ),
    ),
    'dew point non red condition does not activate',
  );
  _expect(
    !_hasAlert(
      AlertType.dewPointRisk,
      _engineAlerts(unitJson: _unit(tempInterior: null, humInterior: 75)),
    ),
    'dew point missing temperature does not activate',
  );
  _expect(
    !_hasAlert(
      AlertType.dewPointRisk,
      _engineAlerts(unitJson: _unit(tempInterior: 22, humInterior: null)),
    ),
    'dew point missing humidity does not activate',
  );
}

Future<void> _testCoordinatorTransitionsAndCache() async {
  final _FakeLoader loader = _FakeLoader(_settingsRaw());
  final AlertRuntime runtime = AlertRuntime(
    settingsCache: AlertSettingsCache(loader: loader),
  );
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );
  final Map<String, Object?> snapshot = _snapshot(
    _unit(tempInterior: 31, resistencia1: true),
  );
  final SnapshotAlertProcessingResult first = await coordinator.processSnapshot(
    snapshot,
    evaluatedAt: DateTime.utc(2026, 1, 1, 10),
  );
  final AlertTransitionBatch firstBatch = first.rooms.first.transitionBatch!;
  _expect(firstBatch.activated.length == 2, 'first snapshot activates once');
  _expect(
    first.whatsAppCandidates.length == 2,
    'whatsapp candidate on activation',
  );
  _expect(
    runtime.activeAlertsRegistry.size == 2,
    'active alert size increases',
  );
  _expect(loader.calls == 1, 'cache miss reads once');

  final SnapshotAlertProcessingResult second = await coordinator
      .processSnapshot(
        snapshot,
        evaluatedAt: DateTime.utc(2026, 1, 1, 10, 0, 5),
      );
  final AlertTransitionBatch secondBatch = second.rooms.first.transitionBatch!;
  _expect(secondBatch.activated.isEmpty, 'still active does not reactivate');
  _expect(secondBatch.stillActive.length == 2, 'stillActive reported');
  _expect(second.whatsAppCandidates.isEmpty, 'no candidate for stillActive');
  _expect(
    runtime.activeAlertsRegistry.size == 2,
    'stillActive does not grow size',
  );
  _expect(loader.calls == 1, 'cache hit does not read');

  final SnapshotAlertProcessingResult third = await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 29, resistencia1: true)),
    evaluatedAt: DateTime.utc(2026, 1, 1, 10, 0, 10),
  );
  final AlertTransitionBatch thirdBatch = third.rooms.first.transitionBatch!;
  _expect(thirdBatch.recovered.length == 2, 'normal snapshot recovers');
  _expect(runtime.activeAlertsRegistry.size == 0, 'recovery decreases size');
}

Future<void> _testStopDoesNotRecover() async {
  final AlertRuntime runtime = _runtimeWithSettings(_settings());
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );
  await coordinator.processSnapshot(
    _snapshot(_unit(tempInterior: 31, resistencia1: true)),
  );
  final SnapshotAlertProcessingResult stop = await coordinator.processSnapshot(
    _snapshot(
      _unit(
        tempInterior: null,
        resistencia1: false,
        stateCode: 'PLC_STOP_CONFIRMED',
      ),
    ),
  );
  _expect(!stop.rooms.first.snapshotEvaluable, 'STOP snapshot ignored');
  _expect(
    stop.rooms.first.transitionBatch == null,
    'STOP snapshot has no transitions',
  );
  _expect(
    runtime.activeAlertsRegistry.size == 2,
    'STOP does not recover active alert',
  );
}

Future<void> _testOneHundredSnapshotsConsumption() async {
  final _FakeLoader loader = _FakeLoader(_settingsRaw());
  final AlertRuntime runtime = AlertRuntime(
    settingsCache: AlertSettingsCache(loader: loader),
  );
  final AlertProcessingCoordinator coordinator = AlertProcessingCoordinator(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    runtime: runtime,
  );
  int activated = 0;
  int stillActive = 0;
  int candidates = 0;
  for (int i = 0; i < 100; i += 1) {
    final SnapshotAlertProcessingResult result = await coordinator
        .processSnapshot(
          _snapshot(_unit(tempInterior: 31, resistencia1: true)),
          evaluatedAt: DateTime.utc(2026, 1, 1, 10, 0, i),
        );
    final AlertTransitionBatch batch = result.rooms.first.transitionBatch!;
    activated += batch.activated.length;
    stillActive += batch.stillActive.length;
    candidates += result.whatsAppCandidates.length;
  }
  _expect(loader.calls == 1, '100 snapshots cause one settings read');
  _expect(activated == 2, '100 active snapshots activate once');
  _expect(stillActive == 198, '100 active snapshots produce 99 stillActive');
  _expect(
    candidates == 2,
    '100 active snapshots produce one whatsapp candidate',
  );
  _expect(
    runtime.activeAlertsRegistry.size == 2,
    'active alert size remains one',
  );
}

List<EvaluatedAlert> _engineAlerts({
  CachedAlertSettings? settings,
  AlertRuntime? runtime,
  Map<String, Object?>? unitJson,
  DateTime? evaluatedAt,
}) {
  final CachedAlertSettings effectiveSettings = settings ?? _settings();
  final AlertRuntime effectiveRuntime =
      runtime ?? _runtimeWithSettings(effectiveSettings);
  return AlertEvaluationEngine().evaluate(
    AlertEvaluationContext(
      identity: const AlertIdentity(
        tenantId: 'tenant-a',
        siteId: 'site-a',
        roomId: 'room_1',
        roomNumber: 1,
        muntersId: 'munters1',
      ),
      snapshot: SnapshotRoomData(values: unitJson ?? _unit()),
      settings: effectiveSettings,
      evaluatedAt: evaluatedAt ?? DateTime.utc(2026, 1, 1, 10),
      roomWashStatus: RoomWashStatus(
        withinWashWindow: effectiveRuntime.roomWashRegistry.isWithinWashWindow(
          tenantId: 'tenant-a',
          siteId: 'site-a',
          roomId: 'room_1',
          now: evaluatedAt ?? DateTime.utc(2026, 1, 1, 10),
        ),
      ),
    ),
  );
}

AlertRuntime _runtimeWithSettings(CachedAlertSettings settings) {
  final AlertSettingsCache cache = AlertSettingsCache();
  cache.updateFromPayload(
    tenantId: settings.tenantId,
    siteId: settings.siteId,
    payload: _settingsRaw(),
  );
  return AlertRuntime(
    settingsCache: cache,
    roomWashRegistry: RoomWashRegistry(),
  );
}

CachedAlertSettings _settings({
  double tempMin = 15,
  double? munters2TempMin,
  double tempMax = 30,
  double humidityRed = 95,
  double dewPointRed = 1,
  double pressureMax = 30,
  Map<String, Object?> toggleOverrides = const <String, Object?>{},
}) {
  return CachedAlertSettings.fromRaw(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    raw: _settingsRaw(
      tempMin: tempMin,
      munters2TempMin: munters2TempMin,
      tempMax: tempMax,
      humidityRed: humidityRed,
      dewPointRed: dewPointRed,
      pressureMax: pressureMax,
      toggleOverrides: toggleOverrides,
    ),
    loadedAt: DateTime.utc(2026),
    source: 'test',
  );
}

Map<String, Object?> _settingsRaw({
  double tempMin = 15,
  double? munters2TempMin,
  double tempMax = 30,
  double humidityRed = 95,
  double dewPointRed = 1,
  double pressureMax = 30,
  Map<String, Object?> toggleOverrides = const <String, Object?>{},
}) {
  final Map<String, Object?> alerts = <String, Object?>{
    for (final AlertType type in alertPriorityOrder)
      _settingsKey(type): <String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
      },
    ...toggleOverrides,
  };
  return <String, Object?>{
    'alerts': alerts,
    'munters': <String, Object?>{
      'munters1': <String, Object?>{
        'tempInterior': <String, Object?>{'min': tempMin, 'max': tempMax},
        'humidityInterior': <String, Object?>{
          'alarm': <String, Object?>{'redMinExclusive': humidityRed},
        },
        'dewPointMargin': <String, Object?>{
          'alarm': <String, Object?>{'redMaxInclusive': dewPointRed},
        },
        'presionDiferencial': <String, Object?>{'max': pressureMax},
      },
      if (munters2TempMin != null)
        'munters2': <String, Object?>{
          'tempInterior': <String, Object?>{
            'min': munters2TempMin,
            'max': tempMax,
          },
          'humidityInterior': <String, Object?>{
            'alarm': <String, Object?>{'redMinExclusive': humidityRed},
          },
          'dewPointMargin': <String, Object?>{
            'alarm': <String, Object?>{'redMaxInclusive': dewPointRed},
          },
          'presionDiferencial': <String, Object?>{'max': pressureMax},
        },
    },
  };
}

String _settingsKey(AlertType type) {
  return switch (type) {
    AlertType.muntersDoorOpen => 'muntersDoorOpen',
    AlertType.roomDoorOpen => 'roomDoorOpen',
    AlertType.temperatureInterior => 'temperatureInterior',
    AlertType.highTemperatureHeatingActive => 'highTemperatureHeatingActive',
    AlertType.lowTemperatureHumidifierActive =>
      'lowTemperatureHumidifierActive',
    AlertType.highDifferentialPressure => 'highDifferentialPressure',
    AlertType.highHumidity => 'highHumidity',
    AlertType.dewPointRisk => 'dewPointRisk',
  };
}

Map<String, Object?> _snapshot(Map<String, Object?> munters1) {
  return <String, Object?>{'munters1': munters1};
}

Map<String, Object?> _unit({
  Object? tempInterior = 20,
  Object? humInterior = 50,
  Object? presionDiferencial = 10,
  Object? resistencia1 = false,
  Object? resistencia2 = false,
  Object? bombaHumidificador = false,
  Object? puertaMunter,
  Object? puertaSala,
  String stateCode = 'PLC_HEALTHY',
}) {
  return <String, Object?>{
    'tempInterior': tempInterior,
    'humInterior': humInterior,
    'presionDiferencial': presionDiferencial,
    'resistencia1': resistencia1,
    'resistencia2': resistencia2,
    'bombaHumidificador': bombaHumidificador,
    if (puertaMunter != null) 'puertaMunter': puertaMunter,
    if (puertaSala != null) 'puertaSala': puertaSala,
    'diagnostics': <String, Object?>{'stateCode': stateCode},
  };
}

bool _hasAlert(AlertType type, List<EvaluatedAlert> alerts) {
  return alerts.any((EvaluatedAlert alert) => alert.type == type);
}

class _FakeLoader implements AlertSettingsLoader {
  _FakeLoader(this.raw);

  final Map<String, Object?> raw;
  int calls = 0;

  @override
  Future<Map<String, Object?>?> load(String tenantId, String siteId) async {
    calls += 1;
    return raw;
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
