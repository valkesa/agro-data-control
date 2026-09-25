import 'package:agro_data_control_backend/src/alert_configuration_contracts.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/alert_settings_cache.dart';
import 'package:agro_data_control_backend/src/hierarchical_alert_settings.dart';
import 'package:agro_data_control_backend/src/operational_alert_topology.dart';

Future<void> main() async {
  _testHierarchicalPrecedenceAndExplicitFalse();
  _testPartialThresholdInheritanceByField();
  _testLegacyFallbackPerAlertId();
  _testFirestoreDocumentContract();
  await _testCacheHitDoesNotReload();
  await _testRefreshTargetsFromOperationalTopology();

  // ignore: avoid_print
  print('hierarchical_alert_settings_test: all expectations passed');
}

void _testFirestoreDocumentContract() {
  final AlertConfigFirestoreDocument document = AlertConfigFirestoreDocument(
    alertId: 'temperature_interior',
    patch: const AlertConfigPatch(
      alertId: 'temperature_interior',
      origin: AlertConfigOrigin.tenant,
      whatsappEnabled: false,
      thresholds: AlertThresholdConfig(max: 28),
    ),
    updatedAt: DateTime.utc(2026, 9, 7, 12),
    updatedBy: 'owner-uid',
  );
  final Map<String, Object?> serialized = document.toFirestoreMap();
  _expect(
    serialized['whatsappEnabled'] == false,
    'explicit false is serialized as a real override',
  );
  _expect(
    (serialized['thresholds'] as Map<String, Object?>)['max'] == 28,
    'partial threshold serializes only max',
  );

  _expectThrows(
    () => AlertConfigFirestoreDocument(
      alertId: 'invalid_alert',
      patch: const AlertConfigPatch(
        alertId: 'invalid_alert',
        origin: AlertConfigOrigin.tenant,
        enabled: true,
      ),
      updatedAt: DateTime.utc(2026, 9, 7),
      updatedBy: 'owner-uid',
    ).validate(),
    'invalid alertId is rejected',
  );
  _expectThrows(
    () => AlertConfigFirestoreDocument(
      alertId: 'temperature_interior',
      patch: const AlertConfigPatch(
        alertId: 'temperature_interior',
        origin: AlertConfigOrigin.tenant,
      ),
      updatedAt: DateTime.utc(2026, 9, 7),
      updatedBy: 'owner-uid',
    ).validate(),
    'functionally empty modern docs are rejected',
  );
  _expectThrows(
    () => AlertConfigFirestoreDocument(
      alertId: 'temperature_interior',
      patch: const AlertConfigPatch(
        alertId: 'temperature_interior',
        origin: AlertConfigOrigin.tenant,
        enabled: true,
      ),
      updatedAt: DateTime.utc(2026, 9, 7),
      updatedBy: 'owner-uid',
      schemaVersion: 2,
    ).validate(),
    'unsupported schemaVersion is rejected',
  );
}

void _testHierarchicalPrecedenceAndExplicitFalse() {
  final EffectiveAlertConfiguration effective =
      const HierarchicalAlertConfigResolver().resolve(
        target: _roomTarget(),
        modern: HierarchicalAlertConfigSnapshot(
          tenant: <String, AlertConfigPatch>{
            'temperature_interior': AlertConfigPatch(
              alertId: 'temperature_interior',
              origin: AlertConfigOrigin.tenant,
              enabled: true,
              visualEnabled: true,
              whatsappEnabled: true,
              whatsappDelay: Duration(minutes: 5),
              cooldown: Duration(minutes: 20),
              order: 8,
            ),
          },
          site: <String, AlertConfigPatch>{
            'temperature_interior': AlertConfigPatch(
              alertId: 'temperature_interior',
              origin: AlertConfigOrigin.site,
              cooldown: Duration(minutes: 12),
            ),
          },
          device: <String, AlertConfigPatch>{
            'temperature_interior': AlertConfigPatch(
              alertId: 'temperature_interior',
              origin: AlertConfigOrigin.device,
              whatsappEnabled: false,
            ),
          },
          room: <String, AlertConfigPatch>{
            'temperature_interior': AlertConfigPatch(
              alertId: 'temperature_interior',
              origin: AlertConfigOrigin.room,
              order: 2,
            ),
          },
        ),
      );

  final EffectiveAlertConfig temperature = effective.configFor(
    AlertType.temperatureInterior,
  );
  _expect(temperature.enabled, 'tenant enabled is inherited');
  _expect(!temperature.whatsappEnabled, 'device explicit false is preserved');
  _expect(
    temperature.cooldown == const Duration(minutes: 12),
    'site cooldown overrides tenant',
  );
  _expect(temperature.order == 2, 'room order overrides tenant');
  _expect(
    temperature.fieldOrigins['whatsappEnabled'] == AlertConfigOrigin.device,
    'whatsapp origin is tracked at field level',
  );
  _expect(
    temperature.fieldOrigins['order'] == AlertConfigOrigin.room,
    'room origin is tracked at field level',
  );
}

void _testPartialThresholdInheritanceByField() {
  final EffectiveAlertConfiguration effective =
      const HierarchicalAlertConfigResolver().resolve(
        target: _roomTarget(),
        modern: HierarchicalAlertConfigSnapshot(
          tenant: <String, AlertConfigPatch>{
            'temperature_interior': AlertConfigPatch(
              alertId: 'temperature_interior',
              origin: AlertConfigOrigin.tenant,
              thresholds: AlertThresholdConfig(min: 20, max: 30),
            ),
          },
          device: <String, AlertConfigPatch>{
            'temperature_interior': AlertConfigPatch(
              alertId: 'temperature_interior',
              origin: AlertConfigOrigin.device,
              thresholds: AlertThresholdConfig(max: 28),
            ),
          },
          room: <String, AlertConfigPatch>{
            'temperature_interior': AlertConfigPatch(
              alertId: 'temperature_interior',
              origin: AlertConfigOrigin.room,
              thresholds: AlertThresholdConfig(sensorFailureMin: 1.5),
            ),
          },
        ),
      );

  final AlertThresholdConfig thresholds = effective
      .configFor(AlertType.temperatureInterior)
      .thresholds;
  _expect(thresholds.min == 20, 'tenant min is inherited');
  _expect(thresholds.max == 28, 'device max overrides only max');
  _expect(
    thresholds.sensorFailureMin == 1.5,
    'room sensor failure min overrides only that field',
  );
  final EffectiveAlertConfig temperature = effective.configFor(
    AlertType.temperatureInterior,
  );
  _expect(
    temperature.fieldOrigins['thresholds.min'] == AlertConfigOrigin.tenant,
    'threshold min origin is tenant',
  );
  _expect(
    temperature.fieldOrigins['thresholds.max'] == AlertConfigOrigin.device,
    'threshold max origin is device',
  );
  _expect(
    temperature.fieldOrigins['thresholds.sensorFailureMin'] ==
        AlertConfigOrigin.room,
    'sensor failure origin is room',
  );
}

void _testLegacyFallbackPerAlertId() {
  final CachedAlertSettings legacy = CachedAlertSettings.fromRaw(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    raw: <String, Object?>{
      'alerts': <String, Object?>{
        'dewPointRisk': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
          'order': 9,
        },
      },
      'munters': <String, Object?>{
        'munters1': <String, Object?>{
          'dewPointMargin': <String, Object?>{
            'alarm': <String, Object?>{'redMaxInclusive': 2.5},
          },
        },
      },
    },
    loadedAt: DateTime.utc(2026, 9, 7),
    source: 'legacy-test',
    configVersion: 4,
  );

  final EffectiveAlertConfiguration effective =
      const HierarchicalAlertConfigResolver().resolve(
        target: _roomTarget(),
        legacy: legacy,
        modern: const HierarchicalAlertConfigSnapshot(
          tenant: <String, AlertConfigPatch>{
            'temperature_interior': AlertConfigPatch(
              alertId: 'temperature_interior',
              origin: AlertConfigOrigin.tenant,
              whatsappEnabled: true,
              thresholds: AlertThresholdConfig(min: 21, max: 29),
            ),
          },
        ),
      );

  final EffectiveAlertConfig temperature = effective.configFor(
    AlertType.temperatureInterior,
  );
  final EffectiveAlertConfig dewPoint = effective.configFor(
    AlertType.dewPointRisk,
  );
  _expect(
    temperature.origin == AlertConfigOrigin.tenant,
    'migrated alert uses modern chain',
  );
  _expect(
    temperature.thresholds.min == 21,
    'migrated alert does not borrow legacy thresholds',
  );
  _expect(
    dewPoint.origin == AlertConfigOrigin.legacy,
    'unmigrated alert falls back to legacy independently',
  );
  _expect(
    dewPoint.thresholds.margin == 2.5,
    'legacy fallback still preserves current settings',
  );
}

Future<void> _testCacheHitDoesNotReload() async {
  final _FakeHierarchicalLoader loader = _FakeHierarchicalLoader(
    const HierarchicalAlertConfigSnapshot(),
  );
  final HierarchicalAlertSettingsCache cache = HierarchicalAlertSettingsCache(
    loader: loader,
    now: () => DateTime.utc(2026, 9, 7, 10),
  );
  await cache.getOrLoad(target: _roomTarget());
  await cache.getOrLoad(target: _roomTarget());
  _expect(loader.loadCount == 1, 'cache hit does not reload');
  _expect(cache.lastReadCount == 0, 'cache hit has zero Firestore reads');
}

Future<void> _testRefreshTargetsFromOperationalTopology() async {
  final _FakeHierarchicalLoader loader = _FakeHierarchicalLoader(
    const HierarchicalAlertConfigSnapshot(
      tenant: <String, AlertConfigPatch>{
        'temperature_interior': AlertConfigPatch(
          alertId: 'temperature_interior',
          origin: AlertConfigOrigin.tenant,
          enabled: true,
        ),
      },
      readCount: 4,
    ),
  );
  final HierarchicalAlertSettingsCache cache = HierarchicalAlertSettingsCache(
    loader: loader,
  );
  final OperationalAlertTopology topology = OperationalAlertTopology(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    devices: <OperationalAlertDevice>[
      OperationalAlertDevice(
        deviceId: 'munters1',
        siteId: 'las-heras',
        enabled: true,
        snapshotUnitKey: 'munters1',
      ),
      OperationalAlertDevice(
        deviceId: 'munters2',
        siteId: 'las-heras',
        enabled: true,
        snapshotUnitKey: 'munters2',
      ),
    ],
  );

  await cache.refreshTargets(targets: topology.targets);
  _expect(cache.size == 2, 'cache stores one effective config per target');
  _expect(loader.loadCount == 2, 'refresh loads each topology target');
  _expect(cache.healthJson()['loaded'] == 2, 'health reports loaded targets');
}

AlertConfigurationTarget _roomTarget() {
  return const AlertConfigurationTarget(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    scope: AlertConfigurationScope.room,
    deviceId: 'munters1',
    roomId: 'room_1',
    snapshotUnitKey: 'munters1',
    muntersId: 'munters1',
  );
}

class _FakeHierarchicalLoader implements HierarchicalAlertConfigLoader {
  _FakeHierarchicalLoader(this.snapshot);

  final HierarchicalAlertConfigSnapshot snapshot;
  int loadCount = 0;

  @override
  Future<HierarchicalAlertConfigSnapshot> load(
    AlertConfigurationTarget target,
  ) async {
    loadCount += 1;
    return snapshot;
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}

void _expectThrows(void Function() body, String description) {
  try {
    body();
  } catch (_) {
    return;
  }
  throw StateError('Expected throw: $description');
}
