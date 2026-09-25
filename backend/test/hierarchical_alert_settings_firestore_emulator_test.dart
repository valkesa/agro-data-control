import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/alert_configuration_contracts.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/alert_settings_cache.dart';
import 'package:agro_data_control_backend/src/hierarchical_alert_settings.dart';
import 'package:agro_data_control_backend/src/operational_alert_topology.dart';

const String _projectId = 'demo-hierarchical-alert-config-test';
const int _port = 8099;
const String _baseUrl = 'http://127.0.0.1:$_port';

Future<void> main() async {
  final Directory emulatorProjectDir = await _writeEmulatorProject();
  final StringBuffer emulatorLog = StringBuffer();
  Process? emulatorProcess;

  try {
    emulatorProcess = await _startEmulator(emulatorProjectDir, emulatorLog);
    await _waitForReady(emulatorLog);
    await _waitForRestApi();

    await _seedTheGenePigModernPartial();
    await _seedLaPayanaModernHierarchy();

    await _testTheGenePigModernOverrideAndLegacyFallback();
    await _testLaPayanaRoomOverrideThroughRealHttp();
    await _testMissingConfigFallsBackToLegacy();
    await _testGetOrLoadTtlExpiryReloadsChangedFirestoreData();
    await _testRefreshTargetsReloadsChangedFirestoreDataAndKeepsSharedReads();

    // ignore: avoid_print
    print(
      'hierarchical_alert_settings_firestore_emulator_test: all expectations passed',
    );
  } finally {
    if (emulatorProcess != null) {
      emulatorProcess.kill(ProcessSignal.sigterm);
      try {
        await emulatorProcess.exitCode.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        emulatorProcess.kill(ProcessSignal.sigkill);
      }
    }
    if (await emulatorProjectDir.exists()) {
      await emulatorProjectDir.delete(recursive: true);
    }
  }
}

Future<void> _seedTemperatureMax(String tenantId, double max) async {
  await _putDoc(
    'tenants/$tenantId/alertConfig/temperature_interior',
    _alertConfigFields(<String, Object?>{
      'enabled': true,
      'thresholds': <String, Object?>{'max': max},
    }),
  );
}

Future<Directory> _writeEmulatorProject() async {
  final Directory dir = await Directory.systemTemp.createTemp(
    'hierarchical-alert-config-test-',
  );
  await File('${dir.path}/firebase.json').writeAsString(
    jsonEncode(<String, Object?>{
      'firestore': <String, Object?>{'rules': 'firestore.rules'},
      'emulators': <String, Object?>{
        'firestore': <String, Object?>{'port': _port},
      },
    }),
  );
  await File('${dir.path}/firestore.rules').writeAsString('''
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
''');
  return dir;
}

Future<Process> _startEmulator(Directory projectDir, StringBuffer log) async {
  final Process process = await Process.start('firebase', <String>[
    'emulators:start',
    '--only',
    'firestore',
    '--project',
    _projectId,
  ], workingDirectory: projectDir.path);
  process.stdout.transform(utf8.decoder).listen(log.write);
  process.stderr.transform(utf8.decoder).listen(log.write);
  return process;
}

Future<void> _waitForReady(StringBuffer log) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (log.toString().contains('All emulators ready')) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError(
    'Firestore emulator did not report ready within 90s.\n--- emulator log ---\n$log',
  );
}

Future<void> _waitForRestApi() async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
  final HttpClient client = HttpClient();
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final HttpClientRequest request = await client.getUrl(
          Uri.parse(
            '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/tenants',
          ),
        );
        final HttpClientResponse response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) return;
      } catch (_) {
        // Keep polling until the REST endpoint is reachable.
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  } finally {
    client.close(force: true);
  }
  throw StateError('Firestore emulator REST API never became reachable.');
}

Future<void> _putDoc(String path, Map<String, Object?> fields) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/$path',
    );
    final HttpClientRequest request = await client.patchUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    request.write(
      jsonEncode(<String, Object?>{
        'fields': <String, Object?>{
          for (final MapEntry<String, Object?> entry in fields.entries)
            entry.key: _encodeFirestoreValue(entry.value),
        },
      }),
    );
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError(
        'Seed PATCH $path failed (${response.statusCode}): $body',
      );
    }
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> _encodeFirestoreValue(Object? value) {
  if (value == null) return <String, Object?>{'nullValue': null};
  if (value is bool) return <String, Object?>{'booleanValue': value};
  if (value is int) return <String, Object?>{'integerValue': value.toString()};
  if (value is double) return <String, Object?>{'doubleValue': value};
  if (value is String) return <String, Object?>{'stringValue': value};
  if (value is DateTime) {
    return <String, Object?>{'timestampValue': value.toUtc().toIso8601String()};
  }
  if (value is Map) {
    return <String, Object?>{
      'mapValue': <String, Object?>{
        'fields': <String, Object?>{
          for (final MapEntry<Object?, Object?> entry in value.entries)
            entry.key.toString(): _encodeFirestoreValue(entry.value),
        },
      },
    };
  }
  throw ArgumentError.value(value, 'value', 'Unsupported seed value type');
}

Future<void> _seedTheGenePigModernPartial() async {
  await _putDoc(
    'tenants/the-gene-pig/alertConfig/temperature_interior',
    _alertConfigFields(<String, Object?>{
      'enabled': true,
      'whatsappEnabled': true,
      'thresholds': <String, Object?>{'min': 20.0, 'max': 30.0},
    }),
  );
  await _putDoc(
    'tenants/the-gene-pig/sites/las-heras/alertConfig/temperature_interior',
    _alertConfigFields(<String, Object?>{
      'thresholds': <String, Object?>{'max': 28.0},
      'cooldownMinutes': 12,
    }),
  );
  await _putDoc(
    'tenants/the-gene-pig/devices/munters1/alertConfig/temperature_interior',
    _alertConfigFields(<String, Object?>{'whatsappEnabled': false}),
  );
}

Future<void> _seedLaPayanaModernHierarchy() async {
  await _putDoc(
    'tenants/la-payana/alertConfig/high_humidity',
    _alertConfigFields(<String, Object?>{
      'enabled': true,
      'whatsappEnabled': true,
      'thresholds': <String, Object?>{'max': 90.0},
    }),
  );
  await _putDoc(
    'tenants/la-payana/sites/roque-perez/alertConfig/high_humidity',
    _alertConfigFields(<String, Object?>{
      'thresholds': <String, Object?>{'max': 88.0},
    }),
  );
  await _putDoc(
    'tenants/la-payana/devices/plc-maternidad/rooms/sala-3/alertConfig/high_humidity',
    _alertConfigFields(<String, Object?>{
      'thresholds': <String, Object?>{'max': 84.0},
      'order': 3,
    }),
  );
}

Map<String, Object?> _alertConfigFields(Map<String, Object?> overrides) {
  return <String, Object?>{
    'schemaVersion': 1,
    ...overrides,
    'updatedAt': DateTime.utc(2026, 9, 7, 12),
    'updatedBy': 'test-user',
  };
}

Future<void> _testTheGenePigModernOverrideAndLegacyFallback() async {
  final HierarchicalAlertConfigSnapshot snapshot = await _loader().load(
    _target(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'munters1',
      roomId: 'room_1',
      muntersId: 'munters1',
    ),
  );
  final EffectiveAlertConfiguration effective =
      const HierarchicalAlertConfigResolver().resolve(
        target: _target(
          tenantId: 'the-gene-pig',
          siteId: 'las-heras',
          deviceId: 'munters1',
          roomId: 'room_1',
          muntersId: 'munters1',
        ),
        modern: snapshot,
        legacy: _legacySettings(),
      );
  final EffectiveAlertConfig temperature = effective.configFor(
    AlertType.temperatureInterior,
  );
  final EffectiveAlertConfig dewPoint = effective.configFor(
    AlertType.dewPointRisk,
  );
  _expect(temperature.thresholds.min == 20.0, 'tenant min loaded over REST');
  _expect(temperature.thresholds.max == 28.0, 'site max overrides tenant max');
  _expect(!temperature.whatsappEnabled, 'device explicit false survives REST');
  _expect(
    temperature.fieldOrigins['whatsappEnabled'] == AlertConfigOrigin.device,
    'device origin is tracked',
  );
  _expect(
    dewPoint.origin == AlertConfigOrigin.legacy,
    'unmigrated alertId falls back to legacy',
  );
  _expect(dewPoint.thresholds.margin == 2.5, 'legacy threshold is preserved');
}

Future<void> _testLaPayanaRoomOverrideThroughRealHttp() async {
  final AlertConfigurationTarget room3 = _target(
    tenantId: 'la-payana',
    siteId: 'roque-perez',
    deviceId: 'plc-maternidad',
    roomId: 'sala-3',
    muntersId: 'sala-3',
  );
  final EffectiveAlertConfiguration effective =
      const HierarchicalAlertConfigResolver().resolve(
        target: room3,
        modern: await _loader().load(room3),
      );
  final EffectiveAlertConfig humidity = effective.configFor(
    AlertType.highHumidity,
  );
  _expect(
    humidity.thresholds.max == 84.0,
    'room max overrides site and tenant',
  );
  _expect(humidity.order == 3, 'room order loaded');
  _expect(
    humidity.fieldOrigins['thresholds.max'] == AlertConfigOrigin.room,
    'room threshold origin is tracked',
  );
}

Future<void> _testMissingConfigFallsBackToLegacy() async {
  final AlertConfigurationTarget munters2 = _target(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    deviceId: 'munters2',
    roomId: 'room_2',
    muntersId: 'munters1',
  );
  final EffectiveAlertConfiguration effective =
      const HierarchicalAlertConfigResolver().resolve(
        target: munters2,
        modern: await _loader().load(munters2),
        legacy: _legacySettings(),
      );
  final EffectiveAlertConfig pressure = effective.configFor(
    AlertType.highDifferentialPressure,
  );
  _expect(
    pressure.origin == AlertConfigOrigin.legacy,
    'alert without modern config falls back to legacy',
  );
  _expect(pressure.thresholds.max == 125.0, 'legacy pressure max is preserved');
}

Future<void> _testGetOrLoadTtlExpiryReloadsChangedFirestoreData() async {
  const String tenantId = 'ttl-reload-tenant';
  await _seedTemperatureMax(tenantId, 30.0);
  final AlertConfigurationTarget target = _target(
    tenantId: tenantId,
    siteId: 'las-heras',
    deviceId: 'munters1',
    roomId: 'room_1',
    muntersId: 'munters1',
  );
  DateTime now = DateTime.utc(2026, 9, 7, 10);
  final HierarchicalAlertSettingsCache cache = HierarchicalAlertSettingsCache(
    loader: _loader(),
    ttl: const Duration(minutes: 5),
    now: () => now,
  );

  final EffectiveAlertConfiguration first = await cache.getOrLoad(
    target: target,
  );
  _expect(
    first.configFor(AlertType.temperatureInterior).thresholds.max == 30.0,
    'initial getOrLoad reads max 30 from Firestore',
  );
  _expect(cache.lastReadCount > 0, 'initial getOrLoad records real reads');

  await _seedTemperatureMax(tenantId, 28.0);
  now = now.add(const Duration(minutes: 4));
  final EffectiveAlertConfiguration cached = await cache.getOrLoad(
    target: target,
  );
  _expect(
    cached.configFor(AlertType.temperatureInterior).thresholds.max == 30.0,
    'cache hit inside TTL keeps cached max 30',
  );
  _expect(cache.lastReadCount == 0, 'cache hit inside TTL performs 0 reads');

  now = now.add(const Duration(minutes: 2));
  final EffectiveAlertConfiguration reloaded = await cache.getOrLoad(
    target: target,
  );
  _expect(
    reloaded.configFor(AlertType.temperatureInterior).thresholds.max == 28.0,
    'expired TTL getOrLoad reloads changed Firestore max 28',
  );
  _expect(cache.lastReadCount > 0, 'expired TTL getOrLoad performs new reads');
}

Future<void>
_testRefreshTargetsReloadsChangedFirestoreDataAndKeepsSharedReads() async {
  const String tenantId = 'refresh-reload-tenant';
  await _seedTemperatureMax(tenantId, 30.0);
  final FirestoreHierarchicalAlertConfigLoader loader = _loader();
  final HierarchicalAlertSettingsCache cache = HierarchicalAlertSettingsCache(
    loader: loader,
  );
  final List<OperationalAlertTarget> targets = <OperationalAlertTarget>[
    const OperationalAlertTarget(
      tenantId: tenantId,
      siteId: 'las-heras',
      deviceId: 'munters1',
      snapshotUnitKey: 'munters1',
    ),
    const OperationalAlertTarget(
      tenantId: tenantId,
      siteId: 'las-heras',
      deviceId: 'munters2',
      snapshotUnitKey: 'munters2',
    ),
  ];

  await cache.refreshTargets(targets: targets);
  _expect(
    cache.lastReadCount == 4,
    'refresh reads tenant/site once plus 2 devices',
  );
  final EffectiveAlertConfiguration? first = cache.get(
    targets.first.toAlertConfigurationTarget(),
  );
  _expect(
    first?.configFor(AlertType.temperatureInterior).thresholds.max == 30.0,
    'first refresh caches max 30',
  );

  await _seedTemperatureMax(tenantId, 26.0);
  await cache.refreshTargets(targets: targets);
  _expect(
    cache.lastReadCount == 4,
    'second refresh keeps Tenant/Site memoized within the operation',
  );
  final EffectiveAlertConfiguration? reloaded = cache.get(
    targets.first.toAlertConfigurationTarget(),
  );
  _expect(
    reloaded?.configFor(AlertType.temperatureInterior).thresholds.max == 26.0,
    'second refresh sees changed Firestore max 26',
  );
}

FirestoreHierarchicalAlertConfigLoader _loader() {
  return FirestoreHierarchicalAlertConfigLoader(
    projectId: _projectId,
    databaseId: '(default)',
    serviceAccountJsonPath: 'unused-in-emulator-mode',
    baseUrl: _baseUrl,
    accessTokenProvider: () async => '',
  );
}

AlertConfigurationTarget _target({
  required String tenantId,
  required String siteId,
  required String deviceId,
  required String roomId,
  required String muntersId,
}) {
  return AlertConfigurationTarget(
    tenantId: tenantId,
    siteId: siteId,
    scope: AlertConfigurationScope.room,
    deviceId: deviceId,
    roomId: roomId,
    snapshotUnitKey: muntersId,
    muntersId: muntersId,
  );
}

CachedAlertSettings _legacySettings() {
  return CachedAlertSettings.fromRaw(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    raw: <String, Object?>{
      'alerts': <String, Object?>{
        'dewPointRisk': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
          'order': 9,
        },
        'highDifferentialPressure': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
          'order': 7,
        },
      },
      'munters': <String, Object?>{
        'munters1': <String, Object?>{
          'dewPointMargin': <String, Object?>{
            'alarm': <String, Object?>{'redMaxInclusive': 2.5},
          },
          'presionDiferencial': <String, Object?>{'max': 125.0},
        },
      },
    },
    loadedAt: DateTime.utc(2026, 9, 7),
    source: 'legacy-test',
  );
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
