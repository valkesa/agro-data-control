import 'package:agro_data_control_backend/src/alert_evaluation_engine.dart';
import 'package:agro_data_control_backend/src/alert_models.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/alert_settings_cache.dart';

Future<void> main() async {
  _testMetadataRegistry();
  _testDefaultEvaluatorFactory();
  _testLegacyTemperatureToggleKeys();
  _testAlertOrderParsing();
  _testDuplicateEvaluatorRejected();
  _testEngineOrdersByMetadata();
  await _testBackoff();
  await _testInFlightFailureCountsOnce();
  await _testCachedConfigSurvivesFailures();
}

void _testAlertOrderParsing() {
  final CachedAlertSettings settings = CachedAlertSettings.fromRaw(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    raw: <String, Object?>{
      'alerts': <String, Object?>{
        'muntersDoorOpen': <String, Object?>{'order': 7},
        'roomDoorOpen': <String, Object?>{'order': -1},
        'highTemperatureHeatingActive': <String, Object?>{'order': 1},
        'lowTemperatureHumidifierActive': <String, Object?>{'order': 1},
        'highDifferentialPressure': <String, Object?>{'order': 5},
        'highHumidity': <String, Object?>{'order': 3},
        'dewPointRisk': <String, Object?>{'order': 'bad'},
      },
    },
    loadedAt: DateTime.utc(2026),
    source: 'test',
  );

  final List<int> orders = <AlertType>[
    AlertType.highTemperatureHeatingActive,
    AlertType.lowTemperatureHumidifierActive,
    AlertType.roomDoorOpen,
    AlertType.highHumidity,
    AlertType.highDifferentialPressure,
    AlertType.muntersDoorOpen,
    AlertType.dewPointRisk,
  ].map(settings.alerts.effectiveOrder).toList(growable: false);
  _expect(orders.join(',') == '1,2,3,4,5,6,7', 'normalizes alert order');
  _expect(
    settings.alerts.compareAlertTypes(
          AlertType.highHumidity,
          AlertType.muntersDoorOpen,
        ) <
        0,
    'configured order compares before metadata fallback',
  );
}

void _testLegacyTemperatureToggleKeys() {
  final CachedAlertSettings settings = CachedAlertSettings.fromRaw(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    raw: <String, Object?>{
      'alerts': <String, Object?>{
        'lowTemperatureHeatingActive': <String, Object?>{
          'enabled': false,
          'sendWhatsapp': true,
        },
        'highTemperatureHumidifierActive': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
        },
      },
    },
    loadedAt: DateTime.utc(2026),
    source: 'test',
  );

  _expect(
    !settings.alerts.highTemperatureHeatingActive.enabled,
    'legacy lowTemperatureHeatingActive feeds new high temperature heating toggle',
  );
  _expect(
    !settings.alerts.highTemperatureHeatingActive.sendWhatsapp,
    'legacy disabled heating toggle prevents whatsapp',
  );
  _expect(
    settings.alerts.lowTemperatureHumidifierActive.sendWhatsapp,
    'legacy highTemperatureHumidifierActive feeds new low temperature humidifier toggle',
  );
}

void _testDefaultEvaluatorFactory() {
  final List<AlertEvaluator> evaluators = buildDefaultAlertEvaluators();
  _expect(
    evaluators.length == AlertMetadataRegistry.all.length,
    'default evaluator factory covers all metadata entries',
  );
  _expect(
    evaluators
            .map((AlertEvaluator evaluator) => evaluator.type)
            .toSet()
            .length ==
        evaluators.length,
    'default evaluator factory has no duplicated alert types',
  );
  for (final AlertMetadata metadata in AlertMetadataRegistry.all) {
    _expect(
      evaluators.any(
        (AlertEvaluator evaluator) => evaluator.type == metadata.type,
      ),
      'default evaluator exists for ${metadata.type}',
    );
  }
}

void _testMetadataRegistry() {
  _expect(
    AlertMetadataRegistry.all.length == AlertType.values.length,
    'metadata covers all alert types',
  );
  final Set<String> codes = <String>{};
  final Set<int> orders = <int>{};
  for (final AlertType type in AlertType.values) {
    final AlertMetadata metadata = AlertMetadataRegistry.metadataFor(type);
    _expect(metadata.code.isNotEmpty, 'metadata code not empty');
    _expect(metadata.defaultLabel.isNotEmpty, 'metadata label not empty');
    _expect(codes.add(metadata.code), 'metadata code unique');
    _expect(orders.add(metadata.order), 'metadata order unique');
  }
  _expect(
    alertPriorityOrder.join(',') ==
        <AlertType>[
          AlertType.muntersDoorOpen,
          AlertType.roomDoorOpen,
          AlertType.highTemperatureHeatingActive,
          AlertType.lowTemperatureHumidifierActive,
          AlertType.highDifferentialPressure,
          AlertType.highHumidity,
          AlertType.dewPointRisk,
        ].join(','),
    'metadata order equals previous priority',
  );
}

void _testDuplicateEvaluatorRejected() {
  bool failed = false;
  try {
    AlertEvaluationEngine(
      evaluators: const <AlertEvaluator>[
        MuntersDoorOpenEvaluator(),
        MuntersDoorOpenEvaluator(),
      ],
    );
  } on StateError {
    failed = true;
  }
  _expect(failed, 'duplicate evaluator rejected');
}

void _testEngineOrdersByMetadata() {
  final AlertEvaluationEngine engine = AlertEvaluationEngine(
    evaluators: const <AlertEvaluator>[
      HighHumidityEvaluator(),
      MuntersDoorOpenEvaluator(),
    ],
  );
  final List<EvaluatedAlert> alerts = engine.evaluate(
    AlertEvaluationContext(
      identity: const AlertIdentity(
        tenantId: 'tenant-a',
        siteId: 'site-a',
        roomId: 'room_1',
        roomNumber: 1,
        muntersId: 'munters1',
      ),
      snapshot: SnapshotRoomData(
        values: <String, Object?>{'puertaMunter': true, 'humInterior': 99},
      ),
      settings: _settings(),
      evaluatedAt: DateTime.utc(2026),
      roomWashStatus: const RoomWashStatus(withinWashWindow: false),
    ),
  );
  _expect(
    alerts.first.type == AlertType.muntersDoorOpen,
    'engine orders by metadata',
  );
  _expect(alerts.last.type == AlertType.highHumidity, 'engine order stable');
}

Future<void> _testBackoff() async {
  final _FailingLoader loader = _FailingLoader();
  final AlertSettingsCache cache = AlertSettingsCache(loader: loader);
  final DateTime t0 = DateTime.utc(2026, 1, 1, 10);

  await _expectThrows(
    () => cache.getOrLoad(tenantId: 'tenant-a', siteId: 'site-a', now: t0),
    'first load fails',
  );
  _expect(loader.calls == 1, 'first failure calls loader once');
  _expect(cache.failureCount == 1, 'first failure tracked');

  await _expectThrowsType<AlertSettingsLoadBackoffException>(
    () => cache.getOrLoad(
      tenantId: 'tenant-a',
      siteId: 'site-a',
      now: t0.add(const Duration(seconds: 29)),
    ),
    'snapshot during first backoff does not call loader',
  );
  _expect(loader.calls == 1, 'backoff prevents repeated load');

  await _expectThrows(
    () => cache.getOrLoad(
      tenantId: 'tenant-a',
      siteId: 'site-a',
      now: t0.add(const Duration(seconds: 30)),
    ),
    'retry after first backoff fails',
  );
  _expect(loader.calls == 2, 'retry after backoff calls loader');

  await _expectThrowsType<AlertSettingsLoadBackoffException>(
    () => cache.getOrLoad(
      tenantId: 'tenant-a',
      siteId: 'site-a',
      now: t0.add(const Duration(seconds: 89)),
    ),
    'second backoff waits 60 seconds',
  );
  _expect(loader.calls == 2, 'second backoff prevents load');

  _expect(
    alertSettingsRetryDelay(1) == const Duration(seconds: 30),
    '30s delay',
  );
  _expect(
    alertSettingsRetryDelay(2) == const Duration(seconds: 60),
    '60s delay',
  );
  _expect(
    alertSettingsRetryDelay(10) == const Duration(minutes: 5),
    'max 5m delay',
  );

  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(),
  );
  _expect(cache.failureCount == 0, 'updateFromPayload clears backoff');
  final CachedAlertSettings? cached = await cache.getOrLoad(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    now: t0.add(const Duration(seconds: 90)),
  );
  _expect(cached != null, 'cached settings returned after update');
  _expect(loader.calls == 2, 'cached settings avoid loader after update');

  await _expectThrows(
    () => cache.getOrLoad(tenantId: 'tenant-a', siteId: 'site-b', now: t0),
    'tenant/site failures are separate',
  );
  _expect(cache.failureCount == 1, 'separate tenant/site failure tracked');
}

Future<void> _testInFlightFailureCountsOnce() async {
  final _SlowFailingLoader loader = _SlowFailingLoader();
  final AlertSettingsCache cache = AlertSettingsCache(loader: loader);
  final Future<CachedAlertSettings?> first = cache.getOrLoad(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    now: DateTime.utc(2026),
  );
  final Future<CachedAlertSettings?> second = cache.getOrLoad(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    now: DateTime.utc(2026),
  );
  await _expectThrows(() => first, 'first shared load fails');
  await _expectThrows(() => second, 'second shared load fails');
  _expect(loader.calls == 1, 'in-flight load shared');
  _expect(cache.failureCount == 1, 'shared failure counts once');
}

Future<void> _testCachedConfigSurvivesFailures() async {
  final _FailingLoader loader = _FailingLoader();
  final AlertSettingsCache cache = AlertSettingsCache(loader: loader);
  cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(),
  );
  final CachedAlertSettings? cached = await cache.getOrLoad(
    tenantId: 'tenant-a',
    siteId: 'site-a',
  );
  _expect(cached != null, 'valid cached settings available');
  _expect(loader.calls == 0, 'cached settings avoid failing loader');
}

CachedAlertSettings _settings() {
  return CachedAlertSettings.fromRaw(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    raw: _settingsRaw(),
    loadedAt: DateTime.utc(2026),
    source: 'test',
  );
}

Map<String, Object?> _settingsRaw() {
  return <String, Object?>{
    'alerts': <String, Object?>{
      'muntersDoorOpen': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
      },
      'highHumidity': <String, Object?>{'enabled': true, 'sendWhatsapp': true},
    },
    'munters': <String, Object?>{
      'munters1': <String, Object?>{
        'humidityInterior': <String, Object?>{
          'alarm': <String, Object?>{'redMinExclusive': 95},
        },
      },
    },
  };
}

class _FailingLoader implements AlertSettingsLoader {
  int calls = 0;

  @override
  Future<Map<String, Object?>?> load(String tenantId, String siteId) async {
    calls += 1;
    throw StateError('boom');
  }
}

class _SlowFailingLoader implements AlertSettingsLoader {
  int calls = 0;

  @override
  Future<Map<String, Object?>?> load(String tenantId, String siteId) async {
    calls += 1;
    await Future<void>.delayed(Duration.zero);
    throw StateError('boom');
  }
}

Future<void> _expectThrows(
  Future<Object?> Function() action,
  String description,
) async {
  bool failed = false;
  try {
    await action();
  } catch (_) {
    failed = true;
  }
  _expect(failed, description);
}

Future<void> _expectThrowsType<T extends Object>(
  Future<Object?> Function() action,
  String description,
) async {
  bool failed = false;
  try {
    await action();
  } catch (error) {
    failed = error is T;
  }
  _expect(failed, description);
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
