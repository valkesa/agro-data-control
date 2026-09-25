import 'package:agro_data_control_backend/src/alert_configuration_contracts.dart';
import 'package:agro_data_control_backend/src/operational_alert_topology.dart';

Future<void> main() async {
  _testDeviceWithoutRooms();
  _testDeviceWithMultipleRooms();
  _testDisabledAndInvalidEntries();
  _testDuplicateSnapshotUnitKey();
  _testValidateModeComparison();
  _testTargetConversion();
  await _testLegacyModeDoesNotInvokeLoader();
  await _testCacheFirstLoadAndHit();
  await _testCacheExplicitRefresh();
  await _testCacheTtlRefresh();
  await _testCacheErrorFallback();
  await _testHealthSerialization();
  _testRefreshAuthPolicy();
  _testTheGenePigFixture();
  _testLaPayanaFixture();
}

void _testDeviceWithoutRooms() {
  final OperationalTopologyDiscoveryResult result = parseOperationalTopology(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    tenantExists: true,
    site: _site(),
    devices: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'device-a',
        'siteId': 'site-a',
        'enabled': true,
        'snapshotUnitKey': 'unit-a',
      },
    ],
  );

  _expect(result.topology.devices.length == 1, 'keeps enabled device');
  _expect(
    result.topology.devices.single.rooms.isEmpty,
    'device without rooms stays without artificial room docs',
  );
  _expect(result.topology.targets.length == 1, 'device creates one target');
  _expect(
    result.topology.targets.single.roomId == null,
    'device target has null roomId',
  );
  _expect(
    result.topology.targets.single.snapshotUnitKey == 'unit-a',
    'device target uses device snapshotUnitKey',
  );
  _expect(result.readCount == 3, 'read count includes tenant site and device');
}

void _testDeviceWithMultipleRooms() {
  final OperationalTopologyDiscoveryResult result = parseOperationalTopology(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    tenantExists: true,
    site: _site(),
    devices: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'device-a',
        'siteId': 'site-a',
        'enabled': true,
        'snapshotUnitKey': 'ignored-when-rooms-exist',
      },
    ],
    roomsByDeviceId: <String, List<Map<String, Object?>>>{
      'device-a': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'room-1',
          'enabled': true,
          'snapshotUnitKey': 'sala-1',
          'roomNumber': 1,
        },
        <String, Object?>{
          'id': 'room-2',
          'enabled': true,
          'snapshotUnitKey': 'sala-2',
          'roomNumber': 2,
        },
      ],
    },
  );

  _expect(result.topology.targets.length == 2, 'rooms create two targets');
  _expect(
    result.topology.targets.first.deviceId == 'device-a' &&
        result.topology.targets.first.roomId == 'room-1' &&
        result.topology.targets.first.snapshotUnitKey == 'sala-1',
    'first room target preserves identifiers',
  );
  _expect(result.topology.roomCount == 2, 'room count is explicit rooms only');
  _expect(result.readCount == 5, 'read count includes rooms read');
}

void _testDisabledAndInvalidEntries() {
  final OperationalTopologyDiscoveryResult result = parseOperationalTopology(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    tenantExists: true,
    site: _site(),
    devices: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'missing-site',
        'enabled': true,
        'snapshotUnitKey': 'missing-site',
      },
      <String, Object?>{
        'id': 'other-site',
        'siteId': 'site-b',
        'enabled': true,
        'snapshotUnitKey': 'other',
      },
      <String, Object?>{
        'id': 'disabled-device',
        'siteId': 'site-a',
        'enabled': false,
        'snapshotUnitKey': 'disabled',
      },
      <String, Object?>{
        'id': 'missing-unit',
        'siteId': 'site-a',
        'enabled': true,
      },
      <String, Object?>{
        'id': 'with-disabled-room',
        'siteId': 'site-a',
        'enabled': true,
        'snapshotUnitKey': 'fallback-unit',
      },
    ],
    roomsByDeviceId: <String, List<Map<String, Object?>>>{
      'with-disabled-room': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'room-disabled',
          'enabled': false,
          'snapshotUnitKey': 'disabled-room',
        },
        <String, Object?>{'id': 'room-missing-unit', 'enabled': true},
      ],
    },
  );

  _expect(result.topology.targets.isEmpty, 'invalid entries are excluded');
  _expect(!result.topology.isValid, 'warnings make topology inconsistent');
  _expect(
    result.topology.warnings.contains('device_missing_site_id:missing-site'),
    'detects device without siteId',
  );
  _expect(
    result.topology.warnings.contains('device_site_mismatch:other-site:site-b'),
    'detects device from another site',
  );
  _expect(
    result.topology.warnings.contains('device_disabled:disabled-device'),
    'detects disabled device',
  );
  _expect(
    result.topology.warnings.contains(
      'device_missing_snapshot_unit_key:missing-unit',
    ),
    'detects missing device snapshotUnitKey',
  );
  _expect(
    result.topology.warnings.contains(
      'room_disabled:with-disabled-room/room-disabled',
    ),
    'detects disabled room',
  );
  _expect(
    result.topology.warnings.contains(
      'room_missing_snapshot_unit_key:with-disabled-room/room-missing-unit',
    ),
    'detects missing room snapshotUnitKey',
  );
  _expect(
    result.topology.warnings.contains(
      'device_without_valid_rooms:with-disabled-room',
    ),
    'detects device with rooms but none valid',
  );
}

void _testDuplicateSnapshotUnitKey() {
  final OperationalAlertTopology topology = OperationalAlertTopology(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    devices: <OperationalAlertDevice>[
      OperationalAlertDevice(
        deviceId: 'device-a',
        siteId: 'site-a',
        enabled: true,
        snapshotUnitKey: 'duplicated',
      ),
      OperationalAlertDevice(
        deviceId: 'device-b',
        siteId: 'site-a',
        enabled: true,
        snapshotUnitKey: 'duplicated',
      ),
    ],
  );

  _expect(!topology.isValid, 'duplicate snapshotUnitKey invalidates topology');
  _expect(
    topology.validate().invalidReasons.any(
      (String reason) => reason.startsWith('duplicate_snapshot_unit_key:'),
    ),
    'duplicate snapshotUnitKey is reported',
  );
}

void _testValidateModeComparison() {
  final OperationalAlertTopology legacy = legacyOperationalAlertTopology(
    tenantId: 'tenant-a',
    siteId: 'site-a',
  );
  final OperationalAlertTopology matching = _topologyForUnitKeys(<String>[
    'munters1',
    'munters2',
  ]);
  _expect(
    compareLegacyAndDynamicTopologies(
      legacy: legacy,
      dynamic: matching,
    ).matches,
    'matching dynamic topology compares equal to legacy by snapshotUnitKey',
  );

  final TopologyValidationComparison missing =
      compareLegacyAndDynamicTopologies(
        legacy: legacy,
        dynamic: _topologyForUnitKeys(<String>['munters1']),
      );
  _expect(
    missing.missingInDynamic.contains('munters2'),
    'validate reports legacy unit missing in dynamic',
  );

  final TopologyValidationComparison additional =
      compareLegacyAndDynamicTopologies(
        legacy: legacy,
        dynamic: _topologyForUnitKeys(<String>[
          'munters1',
          'munters2',
          'room_3',
        ]),
      );
  _expect(
    additional.missingInLegacy.contains('room_3'),
    'validate reports dynamic unit missing in legacy',
  );

  final TopologyValidationComparison duplicate =
      compareLegacyAndDynamicTopologies(
        legacy: legacy,
        dynamic: _topologyForUnitKeys(<String>['munters1', 'munters1']),
      );
  _expect(
    duplicate.duplicateDynamicUnitKeys.contains('munters1'),
    'validate reports duplicate dynamic unit',
  );
}

void _testTargetConversion() {
  const OperationalAlertTarget target = OperationalAlertTarget(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    deviceId: 'device-a',
    roomId: 'room-a',
    snapshotUnitKey: 'unit-a',
    roomNumber: 4,
  );
  final AlertConfigurationTarget configTarget = target
      .toAlertConfigurationTarget();
  _expect(configTarget.tenantId == 'tenant-a', 'tenantId preserved');
  _expect(configTarget.siteId == 'site-a', 'siteId preserved');
  _expect(configTarget.deviceId == 'device-a', 'deviceId preserved');
  _expect(configTarget.roomId == 'room-a', 'roomId preserved');
  _expect(
    configTarget.snapshotUnitKey == 'unit-a',
    'snapshotUnitKey preserved',
  );
  _expect(
    configTarget.scope == AlertConfigurationScope.room,
    'room target becomes room scope',
  );
}

Future<void> _testLegacyModeDoesNotInvokeLoader() async {
  final _CountingTopologyLoader loader = _CountingTopologyLoader(
    result: _discoveryForUnitKeys(<String>['munters99']),
  );
  final OperationalTopologyCache cache = OperationalTopologyCache(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    mode: AlertTopologyMode.legacy,
    loader: loader,
  );
  final OperationalAlertTopology topology = await cache.getOrRefresh();
  _expect(loader.calls == 0, 'legacy mode does not invoke loader');
  _expect(
    topology.source == AlertTopologySource.legacyFallback,
    'legacy mode uses legacy fallback',
  );
  _expect(
    topology.targets
            .map((OperationalAlertTarget target) {
              return target.snapshotUnitKey;
            })
            .join(',') ==
        'munters1,munters2',
    'legacy mode uses AlertRoomIdentity.defaultRooms',
  );
  _expect(cache.lastReadCount == 0, 'legacy mode introduces no reads');
}

Future<void> _testCacheFirstLoadAndHit() async {
  int nowTicks = 0;
  final _CountingTopologyLoader loader = _CountingTopologyLoader(
    result: _discoveryForUnitKeys(<String>['munters1', 'munters2']),
  );
  final OperationalTopologyCache cache = OperationalTopologyCache(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    mode: AlertTopologyMode.validate,
    loader: loader,
    now: () => DateTime.utc(2026, 1, 1, nowTicks++),
  );
  await cache.getOrRefresh();
  await cache.getOrRefresh();
  _expect(loader.calls == 1, 'cache hit does not reload topology');
  _expect(cache.lastReadCount == 4, 'cache stores last read count');
  final int readsAfterHit = cache.lastReadCount;
  await cache.getOrRefresh();
  _expect(
    cache.lastReadCount == readsAfterHit,
    'cache hit has 0 additional polling reads',
  );
}

Future<void> _testCacheExplicitRefresh() async {
  final _CountingTopologyLoader loader = _CountingTopologyLoader(
    result: _discoveryForUnitKeys(<String>['munters1']),
  );
  final OperationalTopologyCache cache = OperationalTopologyCache(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    mode: AlertTopologyMode.validate,
    loader: loader,
  );
  await cache.refresh();
  await cache.refresh();
  _expect(loader.calls == 2, 'explicit refresh reloads topology');
  _expect(cache.lastRefreshAt != null, 'explicit refresh updates timestamp');
}

Future<void> _testCacheTtlRefresh() async {
  int hour = 0;
  final _CountingTopologyLoader loader = _CountingTopologyLoader(
    result: _discoveryForUnitKeys(<String>['munters1', 'munters2']),
  );
  final OperationalTopologyCache cache = OperationalTopologyCache(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    mode: AlertTopologyMode.validate,
    loader: loader,
    ttl: const Duration(hours: 1),
    now: () => DateTime.utc(2026, 1, 1, hour),
  );
  await cache.getOrRefresh();
  await cache.getOrRefresh();
  _expect(loader.calls == 1, 'TTL not expired keeps cache hit');
  hour = 2;
  await cache.getOrRefresh();
  _expect(loader.calls == 2, 'TTL expiry refreshes topology');
}

Future<void> _testCacheErrorFallback() async {
  final OperationalTopologyCache cache = OperationalTopologyCache(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    mode: AlertTopologyMode.dynamic,
    loader: const _ThrowingTopologyLoader(),
  );
  final OperationalAlertTopology topology = await cache.refresh();
  _expect(
    topology.source == AlertTopologySource.legacyFallback,
    'discovery error falls back to legacy topology',
  );
  _expect(cache.lastError != null, 'cache stores last error');
  _expect(
    cache.healthJson()['source'] == AlertTopologySource.legacyFallback.name,
    'health exposes fallback source',
  );
}

Future<void> _testHealthSerialization() async {
  final OperationalTopologyCache legacyCache = OperationalTopologyCache(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    mode: AlertTopologyMode.legacy,
    loader: const _ThrowingTopologyLoader(),
  );
  await legacyCache.refresh();
  final Map<String, Object?> legacyHealth = legacyCache.healthJson();
  _expect(legacyHealth['mode'] == 'legacy', 'health exposes legacy mode');
  _expect(
    legacyHealth['source'] == AlertTopologySource.legacyFallback.name,
    'health exposes legacy fallback source',
  );
  _expect(legacyHealth['tenantId'] == 'tenant-a', 'health exposes tenantId');
  _expect(legacyHealth['siteId'] == 'site-a', 'health exposes siteId');
  _expect(legacyHealth['deviceCount'] == 2, 'health exposes deviceCount');
  _expect(legacyHealth['roomCount'] == 2, 'health exposes roomCount');
  _expect(legacyHealth['targetCount'] == 2, 'health exposes targetCount');
  _expect(legacyHealth['valid'] == true, 'health exposes valid legacy state');
  _expect(
    legacyHealth.containsKey('lastRefreshAt'),
    'health exposes lastRefreshAt',
  );

  final OperationalTopologyCache validateCache = OperationalTopologyCache(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    mode: AlertTopologyMode.validate,
    loader: _CountingTopologyLoader(
      result: _discoveryForUnitKeys(<String>['munters1']),
    ),
  );
  await validateCache.refresh();
  final Map<String, Object?> validateHealth = validateCache.healthJson();
  _expect(
    validateHealth['source'] == AlertTopologySource.legacyFallback.name,
    'validate mode active source remains legacy',
  );
  final Map<String, Object?> comparison =
      validateHealth['validate'] as Map<String, Object?>;
  _expect(comparison['matches'] == false, 'health exposes validate mismatch');
  _expect(
    (comparison['missingInDynamic'] as List).contains('munters2'),
    'health exposes missingInDynamic',
  );
  _expect(
    (comparison['missingInLegacy'] as List).isEmpty,
    'health exposes missingInLegacy',
  );
  _expect(
    comparison['duplicateDynamicUnitKeys'] is List,
    'health exposes duplicates list',
  );
}

void _testRefreshAuthPolicy() {
  _expect(canRefreshAlertTopology('owner'), 'owner can refresh topology');
  _expect(
    !canRefreshAlertTopology('tenant_admin'),
    'tenant_admin cannot refresh topology',
  );
  _expect(!canRefreshAlertTopology('tenant_operator'), 'operator rejected');
  _expect(!canRefreshAlertTopology(null), 'missing token/role rejected');
}

void _testTheGenePigFixture() {
  final OperationalTopologyDiscoveryResult result = parseOperationalTopology(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    tenantExists: true,
    site: _site(),
    devices: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'munters1',
        'siteId': 'las-heras',
        'enabled': true,
        'snapshotUnitKey': 'munters1',
      },
      <String, Object?>{
        'id': 'munters2',
        'siteId': 'las-heras',
        'enabled': true,
        'snapshotUnitKey': 'munters2',
      },
    ],
  );
  _expect(result.topology.targets.length == 2, 'The Gene Pig has two targets');
  _expect(result.topology.isValid, 'The Gene Pig fixture is valid');
}

void _testLaPayanaFixture() {
  final OperationalTopologyDiscoveryResult result = parseOperationalTopology(
    tenantId: 'la-payana',
    siteId: 'maternidad',
    tenantExists: true,
    site: _site(),
    devices: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'plc-maternidad',
        'siteId': 'maternidad',
        'enabled': true,
        'snapshotUnitKey': 'plc-maternidad',
      },
    ],
    roomsByDeviceId: <String, List<Map<String, Object?>>>{
      'plc-maternidad': <Map<String, Object?>>[
        for (int i = 1; i <= 8; i += 1)
          <String, Object?>{
            'id': 'sala-$i',
            'enabled': true,
            'snapshotUnitKey': i == 1 ? 'maternidad-room-$i' : 'sala-$i',
            'roomNumber': i,
          },
      ],
    },
  );
  _expect(result.topology.devices.length == 1, 'La Payana has one device');
  _expect(result.topology.roomCount == 8, 'La Payana has eight rooms');
  _expect(result.topology.targets.length == 8, 'La Payana has eight targets');
  _expect(result.topology.isValid, 'La Payana fixture is valid');
  _expect(
    result.topology.targets.first.roomId !=
        result.topology.targets.first.snapshotUnitKey,
    'roomId can differ from snapshotUnitKey',
  );
}

Map<String, Object?> _site() {
  return <String, Object?>{
    'name': 'Site A',
    'enabled': true,
    'provisioningStatus': 'ready',
  };
}

OperationalAlertTopology _topologyForUnitKeys(List<String> unitKeys) {
  return OperationalAlertTopology(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    source: AlertTopologySource.fixture,
    devices: <OperationalAlertDevice>[
      for (int i = 0; i < unitKeys.length; i += 1)
        OperationalAlertDevice(
          deviceId: 'device-$i',
          siteId: 'site-a',
          enabled: true,
          snapshotUnitKey: unitKeys[i],
        ),
    ],
  );
}

OperationalTopologyDiscoveryResult _discoveryForUnitKeys(
  List<String> unitKeys,
) {
  return OperationalTopologyDiscoveryResult(
    readCount: 2 + unitKeys.length,
    topology: _topologyForUnitKeys(unitKeys),
  );
}

class _CountingTopologyLoader implements OperationalTopologyLoader {
  _CountingTopologyLoader({required this.result});

  final OperationalTopologyDiscoveryResult result;
  int calls = 0;

  @override
  Future<OperationalTopologyDiscoveryResult> load({
    required String tenantId,
    required String siteId,
  }) async {
    calls += 1;
    return result;
  }
}

class _ThrowingTopologyLoader implements OperationalTopologyLoader {
  const _ThrowingTopologyLoader();

  @override
  Future<OperationalTopologyDiscoveryResult> load({
    required String tenantId,
    required String siteId,
  }) async {
    throw StateError('firestore unavailable');
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
