import 'package:agro_data_control_backend/src/active_alerts_registry.dart';
import 'package:agro_data_control_backend/src/alert_notification_cooldown_registry.dart';
import 'package:agro_data_control_backend/src/alert_models.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/alert_runtime.dart';
import 'package:agro_data_control_backend/src/alert_settings_cache.dart';
import 'package:agro_data_control_backend/src/dew_point.dart';
import 'package:agro_data_control_backend/src/firebase_request_auth.dart';
import 'package:agro_data_control_backend/src/room_wash_authorization.dart';
import 'package:agro_data_control_backend/src/room_wash_registry.dart';
import 'package:agro_data_control_backend/src/snapshot_evaluation_policy.dart';

Future<void> main() async {
  _testActiveAlertsRegistry();
  await _testAlertSettingsCache();
  _testRoomWashRegistry();
  _testDewPoint();
  _testSnapshotPolicy();
  _testNotificationCooldownKeyIgnoresHardwareIdentity();
  _testAlertRuntimeMetrics();
  _testRoomWashAuthorization();
}

void _testNotificationCooldownKeyIgnoresHardwareIdentity() {
  final AlertNotificationCooldownRegistry registry =
      AlertNotificationCooldownRegistry();
  final DateTime sentAt = DateTime.utc(2026, 1, 1, 10);
  registry.markSent(
    key: _alert(roomId: 'room_1', muntersId: 'munters1').key,
    sentAt: sentAt,
  );

  final AlertInstanceKey changedHardwareKey = const AlertInstanceKey(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    roomNumber: 99,
    muntersId: 'replacement_controller',
    alertType: AlertType.highHumidity,
  );

  _expect(registry.size == 1, 'cooldown stores one logical room key');
  _expect(
    registry.lastSentAt(changedHardwareKey) == sentAt,
    'cooldown ignores roomNumber and muntersId',
  );
  _expect(
    !registry.canSend(
      key: changedHardwareKey,
      now: sentAt.add(const Duration(minutes: 1)),
      cooldown: const Duration(minutes: 10),
    ),
    'cooldown blocks same tenant/site/room/alert despite hardware change',
  );
}

void _testActiveAlertsRegistry() {
  final ActiveAlertsRegistry registry = ActiveAlertsRegistry();
  final DateTime t0 = DateTime.utc(2026, 1, 1, 10);
  final EvaluatedAlert alert = _alert(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    type: AlertType.highHumidity,
    evaluatedAt: t0,
  );

  AlertTransitionBatch batch = registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: <EvaluatedAlert>[alert],
  );
  _expect(batch.activated.length == 1, 'normal -> alert activates once');
  _expect(registry.activeCount == 1, 'registry keeps active alert');

  batch = registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: <EvaluatedAlert>[
      _alert(
        tenantId: 'tenant-a',
        siteId: 'site-a',
        roomId: 'room_1',
        type: AlertType.highHumidity,
        evaluatedAt: t0.add(const Duration(seconds: 5)),
        measuredValue: 98,
      ),
    ],
  );
  _expect(batch.activated.isEmpty, 'persistent alert does not reactivate');
  _expect(batch.stillActive.length == 1, 'persistent alert is stillActive');

  batch = registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: const <EvaluatedAlert>[],
  );
  _expect(batch.recovered.length == 1, 'alert -> normal recovers');
  _expect(registry.activeCount == 0, 'recovered alert is removed');

  registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: <EvaluatedAlert>[alert],
  );
  batch = registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: <EvaluatedAlert>[alert],
  );
  _expect(batch.activated.isEmpty, 'same active alert does not reactivate');
  registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: const <EvaluatedAlert>[],
  );
  batch = registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: <EvaluatedAlert>[alert],
  );
  _expect(batch.activated.length == 1, 'reactivation creates new activation');

  registry.syncForRoom(
    tenantId: 'tenant-b',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: <EvaluatedAlert>[
      _alert(tenantId: 'tenant-b', siteId: 'site-a', roomId: 'room_1'),
    ],
  );
  registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-b',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: <EvaluatedAlert>[
      _alert(tenantId: 'tenant-a', siteId: 'site-b', roomId: 'room_1'),
    ],
  );
  registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_2',
    muntersId: 'munters2',
    evaluatedAlerts: <EvaluatedAlert>[
      _alert(
        tenantId: 'tenant-a',
        siteId: 'site-a',
        roomId: 'room_2',
        muntersId: 'munters2',
      ),
    ],
  );
  _expect(registry.activeCount == 4, 'tenant/site/room scopes do not mix');
  _expect(registry.size == 4, 'size exposes active alert count');
  _expect(
    registry.sizeForTenantSite(tenantId: 'tenant-a', siteId: 'site-a') == 2,
    'sizeForTenantSite filters active alerts',
  );
  _expect(
    registry.sizeForRoom(
          tenantId: 'tenant-a',
          siteId: 'site-a',
          roomId: 'room_2',
          muntersId: 'munters2',
        ) ==
        1,
    'sizeForRoom filters active alerts',
  );
  registry.clearForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_2',
    muntersId: 'munters2',
  );
  _expect(registry.activeCount == 3, 'clearForRoom removes scoped room');
  registry.clearForTenantSite(tenantId: 'tenant-a', siteId: 'site-a');
  _expect(registry.activeCount == 2, 'clearForTenantSite removes scoped site');
  registry.clearAll();
  _expect(registry.activeCount == 0, 'clearAll removes all alerts');
}

Future<void> _testAlertSettingsCache() async {
  final _FakeAlertSettingsLoader loader = _FakeAlertSettingsLoader(
    _settingsRaw(),
  );
  final AlertSettingsCache cache = AlertSettingsCache(loader: loader);
  final CachedAlertSettings? first = await cache.getOrLoad(
    tenantId: 'tenant-a',
    siteId: 'site-a',
  );
  _expect(first != null, 'cache miss loads settings');
  _expect(cache.size == 1, 'cache size counts loaded settings');
  _expect(
    cache.contains(tenantId: 'tenant-a', siteId: 'site-a'),
    'contains detects loaded tenant/site settings',
  );
  _expect(loader.calls == 1, 'cache miss reads once');
  final CachedAlertSettings? second = await cache.getOrLoad(
    tenantId: 'tenant-a',
    siteId: 'site-a',
  );
  _expect(identical(first, second), 'cache hit returns cached instance');
  _expect(loader.calls == 1, 'cache hit does not read');

  await cache.getOrLoad(tenantId: 'tenant-a', siteId: 'site-b');
  _expect(loader.calls == 2, 'tenant/site caches are separated');
  _expect(cache.size == 2, 'cache size counts tenant/site entries');

  final CachedAlertSettings updated = cache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(sendWhatsapp: true),
  );
  _expect(
    updated.alerts.highHumidity.sendWhatsapp,
    'explicit update replaces cache',
  );
  _expect(cache.size == 2, 'updating existing settings does not grow cache');
  bool failed = false;
  try {
    cache.updateFromPayload(
      tenantId: 'tenant-a',
      siteId: 'site-a',
      payload: const <String, Object?>{'bad': true},
    );
  } on FormatException {
    failed = true;
  }
  _expect(failed, 'invalid payload is rejected');
  _expect(
    cache
            .get(tenantId: 'tenant-a', siteId: 'site-a')!
            .alerts
            .highHumidity
            .sendWhatsapp ==
        true,
    'invalid payload does not replace valid cache',
  );
}

void _testRoomWashRegistry() {
  final RoomWashRegistry registry = RoomWashRegistry();
  final DateTime wash = DateTime.utc(2026, 1, 1, 10);
  registry.registerWash(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    roomNumber: 1,
    washedAt: wash,
  );
  _expect(registry.size == 1, 'room wash size counts room states');
  _expect(
    registry.sizeForTenantSite(tenantId: 'tenant-a', siteId: 'site-a') == 1,
    'room wash sizeForTenantSite filters room states',
  );
  _expect(
    registry
            .latestWashFor(
              tenantId: 'tenant-a',
              siteId: 'site-a',
              roomId: 'room_1',
            )
            ?.washedAt ==
        wash,
    'registers latest wash',
  );
  registry.registerWash(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    washedAt: wash.subtract(const Duration(minutes: 5)),
  );
  _expect(
    registry.size == 1,
    'older wash for same room does not create another state',
  );
  _expect(
    registry
            .latestWashFor(
              tenantId: 'tenant-a',
              siteId: 'site-a',
              roomId: 'room_1',
            )
            ?.washedAt ==
        wash,
    'older wash does not replace newer wash',
  );
  _expect(
    registry.isWithinWashWindow(
      tenantId: 'tenant-a',
      siteId: 'site-a',
      roomId: 'room_1',
      now: wash.add(const Duration(minutes: 30)),
    ),
    'wash is active inside two hour window',
  );
  _expect(
    !registry.isWithinWashWindow(
      tenantId: 'tenant-a',
      siteId: 'site-a',
      roomId: 'room_1',
      now: wash.add(const Duration(hours: 2)),
    ),
    'wash is inactive at two hour boundary',
  );
  _expect(
    !registry.isWithinWashWindow(
      tenantId: 'tenant-a',
      siteId: 'site-a',
      roomId: 'room_1',
      now: wash.subtract(const Duration(seconds: 1)),
    ),
    'future wash is not active before washedAt',
  );
  registry.registerWash(
    tenantId: 'tenant-b',
    siteId: 'site-a',
    roomId: 'room_1',
    washedAt: wash,
  );
  _expect(registry.count == 2, 'tenant/site/room washes are separated');
  _expect(registry.size == 2, 'room wash size counts separated rooms');
  registry.clearForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
  );
  _expect(registry.count == 1, 'clearForRoom clears one room');
  registry.clearForTenantSite(tenantId: 'tenant-b', siteId: 'site-a');
  _expect(registry.count == 0, 'clearForTenantSite clears tenant/site');
}

void _testDewPoint() {
  final double? dewPoint = calculateDewPointC(
    temperatureC: 22,
    relativeHumidityPercent: 75,
  );
  _expect(dewPoint != null, 'dew point calculates known value');
  _closeTo(
    dewPoint!,
    17.362,
    0.01,
    '22C 75% dew point matches frontend formula',
  );
  final double? margin = calculateDewPointMarginC(
    temperatureC: 22,
    relativeHumidityPercent: 75,
  );
  _closeTo(
    margin!,
    22 - dewPoint,
    0.000001,
    'margin is temperature - dew point',
  );
  _expect(
    calculateDewPointC(temperatureC: 22, relativeHumidityPercent: 0) != null,
    'humidity 0 is clamped to 1',
  );
  _closeTo(
    calculateDewPointC(temperatureC: 22, relativeHumidityPercent: 150)!,
    22,
    0.000001,
    'humidity over 100 is clamped to 100',
  );
  _expect(
    calculateDewPointC(temperatureC: null, relativeHumidityPercent: 75) == null,
    'null temperature returns null',
  );
  _expect(
    calculateDewPointC(temperatureC: 22, relativeHumidityPercent: null) == null,
    'null humidity returns null',
  );
  _expect(
    calculateDewPointC(temperatureC: double.nan, relativeHumidityPercent: 75) ==
        null,
    'NaN returns null',
  );
  _expect(
    calculateDewPointC(
          temperatureC: double.infinity,
          relativeHumidityPercent: 75,
        ) ==
        null,
    'infinity returns null',
  );
}

void _testSnapshotPolicy() {
  const SnapshotEvaluationPolicy policy = SnapshotEvaluationPolicy();
  _expect(policy.isEvaluableStateCode('PLC_HEALTHY'), 'PLC_HEALTHY evaluable');
  _expect(
    policy.isEvaluableStateCode('PLC_RUN_CONFIRMED'),
    'PLC_RUN_CONFIRMED evaluable',
  );
  _expect(
    !policy.isEvaluableStateCode('PLC_STOP_CONFIRMED'),
    'PLC_STOP_CONFIRMED non evaluable',
  );
  final ActiveAlertsRegistry registry = ActiveAlertsRegistry();
  registry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: <EvaluatedAlert>[_alert()],
  );
  if (policy.isEvaluableStateCode('PLC_STOP_CONFIRMED')) {
    registry.syncForRoom(
      tenantId: 'tenant-a',
      siteId: 'site-a',
      roomId: 'room_1',
      muntersId: 'munters1',
      evaluatedAlerts: const <EvaluatedAlert>[],
    );
  }
  _expect(
    registry.activeCount == 1,
    'PLC_STOP_CONFIRMED does not recover active alerts by itself',
  );
  _expect(
    !policy.isEvaluableStateCode('PLC_UNREACHABLE'),
    'PLC_UNREACHABLE non evaluable',
  );
  _expect(
    !policy.isEvaluableStateCode('PLC_NOT_CONFIGURED'),
    'PLC_NOT_CONFIGURED non evaluable',
  );
  _expect(!policy.isEvaluableStateCode(null), 'null state is non evaluable');
  _expect(
    !policy.isEvaluableStateCode('UNKNOWN_STATE'),
    'unknown state is non evaluable',
  );
}

void _testAlertRuntimeMetrics() {
  final AlertRuntime runtime = AlertRuntime();
  runtime.settingsCache.updateFromPayload(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    payload: _settingsRaw(),
  );
  runtime.roomWashRegistry.registerWash(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    roomNumber: 1,
    washedAt: DateTime.utc(2026, 1, 1, 10),
  );
  runtime.activeAlertsRegistry.syncForRoom(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    muntersId: 'munters1',
    evaluatedAlerts: <EvaluatedAlert>[_alert()],
  );
  runtime.notificationCooldownRegistry.markSent(
    key: _alert().key,
    sentAt: DateTime.utc(2026, 1, 1, 10),
  );

  final AlertRuntimeMetrics metrics = runtime.snapshotMetrics(
    capturedAt: DateTime.utc(2026, 1, 1, 11),
  );
  _expect(metrics.settingsCacheEntries == 1, 'runtime counts settings cache');
  _expect(metrics.roomWashEntries == 1, 'runtime counts room wash registry');
  _expect(metrics.activeAlertEntries == 1, 'runtime counts active alerts');
  _expect(metrics.cooldownEntries == 1, 'runtime counts cooldown entries');
  _expect(
    metrics.settingsLoadFailuresCurrent == 0,
    'runtime counts settings failures',
  );
  _expect(
    metrics.settingsBackoffEntries == 0,
    'runtime counts settings backoff',
  );
  _expect(
    metrics.capturedAt == DateTime.utc(2026, 1, 1, 11),
    'runtime metrics keep capture time',
  );
}

void _testRoomWashAuthorization() {
  for (final String role in <String>[
    'owner',
    'tenant_admin',
    'tenant_operator',
  ]) {
    final RoomWashAuthorizationResult result = canRegisterRoomWash(
      user: _user(role: role, tenantId: 'tenant-a'),
      siteId: 'site-a',
    );
    _expect(result.allowed, '$role can register room wash');
  }

  _expect(
    canRegisterRoomWash(
          user: _user(
            role: 'tenant_operator',
            tenantId: 'tenant-a',
            allowedSiteIds: const <String>['site-a'],
          ),
          siteId: 'site-a',
        ).siteValidation ==
        RoomWashSiteValidation.allowedSitesClaim,
    'site claim validation is reported when available',
  );
  _expect(
    canRegisterRoomWash(
          user: _user(role: 'tenant_operator', tenantId: 'tenant-a'),
          siteId: 'site-a',
        ).siteValidation ==
        RoomWashSiteValidation.tenantOnly,
    'tenant-only validation is reported when site claims are missing',
  );

  for (final String role in <String>['valke_technician', 'pending', '']) {
    final RoomWashAuthorizationResult result = canRegisterRoomWash(
      user: _user(role: role, tenantId: 'tenant-a'),
      siteId: 'site-a',
    );
    _expect(!result.allowed, '$role cannot register room wash');
  }

  _expect(
    !canRegisterRoomWash(
      user: _user(role: 'tenant_operator', tenantId: ''),
      siteId: 'site-a',
    ).allowed,
    'missing tenant is rejected',
  );
  _expect(
    !canRegisterRoomWash(
      user: _user(role: 'tenant_operator', tenantId: 'tenant-a'),
      siteId: '',
    ).allowed,
    'missing site is rejected',
  );
  _expect(
    !canRegisterRoomWash(
      user: _user(
        role: 'tenant_operator',
        tenantId: 'tenant-a',
        allowedSiteIds: const <String>['site-b'],
      ),
      siteId: 'site-a',
    ).allowed,
    'site outside claim is rejected',
  );
}

AuthenticatedBackendUser _user({
  required String role,
  required String tenantId,
  List<String> allowedSiteIds = const <String>[],
}) {
  return AuthenticatedBackendUser(
    uid: 'uid-1',
    role: role,
    tenantId: tenantId,
    allowedSiteIds: allowedSiteIds,
  );
}

EvaluatedAlert _alert({
  String tenantId = 'tenant-a',
  String siteId = 'site-a',
  String roomId = 'room_1',
  String muntersId = 'munters1',
  AlertType type = AlertType.highHumidity,
  DateTime? evaluatedAt,
  num measuredValue = 97,
}) {
  return EvaluatedAlert(
    key: AlertInstanceKey(
      tenantId: tenantId,
      siteId: siteId,
      roomId: roomId,
      roomNumber: roomId == 'room_2' ? 2 : 1,
      muntersId: muntersId,
      alertType: type,
    ),
    type: type,
    isActive: true,
    sendWhatsapp: true,
    measuredValue: measuredValue,
    thresholdValue: 95,
    thresholdKind: AlertThresholdKind.maximum,
    unit: '%',
    evaluatedAt: evaluatedAt ?? DateTime.utc(2026),
  );
}

Map<String, Object?> _settingsRaw({bool sendWhatsapp = false}) {
  return <String, Object?>{
    'alerts': <String, Object?>{
      'highHumidity': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': sendWhatsapp,
      },
      'muntersDoorOpen': <String, Object?>{
        'enabled': false,
        'sendWhatsapp': true,
      },
    },
    'munters': <String, Object?>{
      'munters1': <String, Object?>{
        'tempInterior': <String, Object?>{'min': 15, 'max': 32},
        'humidityInterior': <String, Object?>{
          'alarm': <String, Object?>{'redMinExclusive': 95},
        },
        'dewPointMargin': <String, Object?>{
          'alarm': <String, Object?>{'redMaxInclusive': 1},
        },
        'presionDiferencial': <String, Object?>{'max': 30},
      },
    },
  };
}

class _FakeAlertSettingsLoader implements AlertSettingsLoader {
  _FakeAlertSettingsLoader(this.raw);

  final Map<String, Object?> raw;
  int calls = 0;

  @override
  Future<Map<String, Object?>?> load(String tenantId, String siteId) async {
    calls += 1;
    return raw;
  }
}

void _closeTo(
  double actual,
  double expected,
  double tolerance,
  String message,
) {
  _expect((actual - expected).abs() <= tolerance, message);
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
