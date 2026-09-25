// Etapa B2.5.2 — closes the gap left by B2.5/B2.5.1: FirestoreOperationalTopologyLoader
// (the class that actually speaks the Firestore REST wire protocol —
// _getDocument/_listDocuments/_decodeFirestoreValue) had zero test coverage,
// fake or real. This test spawns a real local Firestore Emulator, seeds real
// documents into it over HTTP, and runs the loader against it end to end —
// the same HTTP + JSON-decode path production uses, not a fake in-memory
// loader and not a hand-built OperationalAlertTopology.
//
// Self-contained: manages its own emulator process (separate scratch project
// + port, isolated from any other emulator instance) and tears it down when
// done. No dependency on `firebase.json`/`firestore.rules` in the repo root
// — a throwaway, fully-permissive ruleset lives only in the temp dir this
// test creates and deletes.
//
// Run with: dart run test/operational_alert_topology_firestore_emulator_test.dart
// Requires: firebase-tools CLI (firebase --version) and a JRE on PATH.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/operational_alert_topology.dart';

const String _projectId = 'demo-topology-emulator-test';
const int _port = 8098;
const String _baseUrl = 'http://127.0.0.1:$_port';
const String _tenantId = 'the-gene-pig';
const String _siteId = 'las-heras';

Future<void> main() async {
  final Directory emulatorProjectDir = await _writeEmulatorProject();
  final StringBuffer emulatorLog = StringBuffer();
  Process? emulatorProcess;

  try {
    emulatorProcess = await _startEmulator(emulatorProjectDir, emulatorLog);
    await _waitForReady(emulatorProcess, emulatorLog);
    await _waitForRestApi();

    await _seedTheGenePigFixture();
    await _seedLaPayanaFixture();

    // These two run against a clean topology (no sibling-site or disabled
    // devices registered yet), so `isValid` is expected to hold.
    await _testTheGenePigThroughRealHttp();
    await _testLaPayanaThroughRealHttp();

    await _seedMismatchedSiteDevice();
    await _testMismatchedSiteDeviceIsExcludedFromTargets();

    await _testMissingTenantReturnsEmptyTopologyWithWarning();
    await _testDisabledDeviceIsExcluded();

    // ignore: avoid_print
    print(
      'operational_alert_topology_firestore_emulator_test: all expectations passed',
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

// ---------------------------------------------------------------------------
// Emulator lifecycle
// ---------------------------------------------------------------------------

Future<Directory> _writeEmulatorProject() async {
  final Directory dir = await Directory.systemTemp.createTemp(
    'topology-emulator-test-',
  );
  await File('${dir.path}/firebase.json').writeAsString(
    jsonEncode(<String, Object?>{
      'firestore': <String, Object?>{'rules': 'firestore.rules'},
      'emulators': <String, Object?>{
        'firestore': <String, Object?>{'port': _port},
      },
    }),
  );
  // Fully permissive, throwaway ruleset — only ever loaded by this local
  // emulator instance, never deployed, never touches the real
  // firestore.rules used in production.
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

Future<void> _waitForReady(Process process, StringBuffer log) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (log.toString().contains('All emulators ready')) {
      return;
    }
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
        if (response.statusCode == 200) {
          return;
        }
      } catch (_) {
        // Not up yet — keep polling.
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  } finally {
    client.close(force: true);
  }
  throw StateError('Firestore emulator REST API never became reachable.');
}

// ---------------------------------------------------------------------------
// Seeding — real HTTP PUT (PATCH) against the emulator's REST API, encoding
// values in the real Firestore typed-value wire format, the same shape
// _decodeFirestoreValue in the loader has to parse back.
// ---------------------------------------------------------------------------

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
      throw StateError('Seed PUT $path failed (${response.statusCode}): $body');
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
  throw ArgumentError.value(value, 'value', 'Unsupported seed value type');
}

Future<void> _seedTheGenePigFixture() async {
  await _putDoc('tenants/$_tenantId', <String, Object?>{
    'name': 'Gene Pig',
    'active': true,
  });
  await _putDoc('tenants/$_tenantId/sites/$_siteId', <String, Object?>{
    'name': 'Las Heras',
    'enabled': true,
    'provisioningStatus': 'ready',
  });
  await _putDoc('tenants/$_tenantId/devices/munters1', <String, Object?>{
    'siteId': _siteId,
    'enabled': true,
    'snapshotUnitKey': 'munters1',
    'name': 'Munters 1',
  });
  await _putDoc('tenants/$_tenantId/devices/munters2', <String, Object?>{
    'siteId': _siteId,
    'enabled': true,
    'snapshotUnitKey': 'munters2',
    'name': 'Munters 2',
  });
}

Future<void> _seedLaPayanaFixture() async {
  const String tenantId = 'la-payana';
  const String siteId = 'maternidad';
  await _putDoc('tenants/$tenantId', <String, Object?>{'name': 'La Payana'});
  await _putDoc('tenants/$tenantId/sites/$siteId', <String, Object?>{
    'name': 'Maternidad',
    'enabled': true,
    'provisioningStatus': 'ready',
  });
  await _putDoc('tenants/$tenantId/devices/plc-maternidad', <String, Object?>{
    'siteId': siteId,
    'enabled': true,
    'snapshotUnitKey': 'plc-maternidad',
    'name': 'PLC Maternidad',
  });
  for (int i = 1; i <= 8; i += 1) {
    // Deliberately break the roomId == snapshotUnitKey assumption for room
    // 1, same guard the B2.5.1 fixture added at the parsing layer — here it
    // has to survive a real Firestore round-trip, not just an in-memory map.
    final String snapshotUnitKey = i == 1 ? 'maternidad-room-1' : 'sala-$i';
    await _putDoc(
      'tenants/$tenantId/devices/plc-maternidad/rooms/sala-$i',
      <String, Object?>{
        'enabled': true,
        'snapshotUnitKey': snapshotUnitKey,
        'roomNumber': i,
      },
    );
  }
}

Future<void> _seedMismatchedSiteDevice() async {
  // A device that belongs to a different site under the same tenant — must
  // be excluded from las-heras' topology and reported as a warning, not
  // silently absorbed. This is precisely the class of drift that caused the
  // real genetica-1/las-heras incident this session resolved.
  await _putDoc(
    'tenants/$_tenantId/devices/genetica-legacy-unit',
    <String, Object?>{
      'siteId': 'genetica-1',
      'enabled': true,
      'snapshotUnitKey': 'genetica-legacy-unit',
      'name': 'Legacy unit on a different site',
    },
  );
}

// ---------------------------------------------------------------------------
// Assertions — run the real loader against the real emulator.
// ---------------------------------------------------------------------------

FirestoreOperationalTopologyLoader _loader() {
  return FirestoreOperationalTopologyLoader(
    projectId: _projectId,
    databaseId: '(default)',
    serviceAccountJsonPath: 'unused-in-emulator-mode',
    baseUrl: _baseUrl,
    accessTokenProvider: () async => '',
  );
}

Future<void> _testTheGenePigThroughRealHttp() async {
  final OperationalTopologyDiscoveryResult result = await _loader().load(
    tenantId: _tenantId,
    siteId: _siteId,
  );
  final OperationalAlertTopology topology = result.topology;
  _expect(
    topology.source == AlertTopologySource.firestore,
    'source is firestore (real HTTP), not fixture/legacy',
  );
  _expect(
    topology.devices.length == 2,
    'the-gene-pig/las-heras has 2 devices over real HTTP '
    '(got ${topology.devices.length})',
  );
  _expect(topology.targets.length == 2, 'the-gene-pig has 2 targets');
  final Set<String> unitKeys = topology.targets
      .map((OperationalAlertTarget t) => t.snapshotUnitKey)
      .toSet();
  _expect(
    unitKeys.containsAll(<String>['munters1', 'munters2']),
    'targets include munters1 and munters2 decoded from real Firestore values',
  );
  _expect(topology.isValid, 'the-gene-pig topology is valid');
  _expect(
    result.readCount >= 4,
    'read count reflects tenant+site+2 devices (got ${result.readCount})',
  );
}

Future<void> _testLaPayanaThroughRealHttp() async {
  final OperationalTopologyDiscoveryResult result = await _loader().load(
    tenantId: 'la-payana',
    siteId: 'maternidad',
  );
  final OperationalAlertTopology topology = result.topology;
  _expect(topology.devices.length == 1, 'la-payana has 1 device');
  _expect(topology.roomCount == 8, 'la-payana has 8 rooms over real HTTP');
  _expect(topology.targets.length == 8, 'la-payana has 8 targets');
  _expect(topology.isValid, 'la-payana topology is valid');

  final OperationalAlertTarget room1 = topology.targets.firstWhere(
    (OperationalAlertTarget t) => t.roomId == 'sala-1',
  );
  _expect(
    room1.snapshotUnitKey == 'maternidad-room-1' &&
        room1.snapshotUnitKey != room1.roomId,
    'roomId != snapshotUnitKey survives a real Firestore round-trip '
    '(roomId=${room1.roomId}, snapshotUnitKey=${room1.snapshotUnitKey})',
  );
}

Future<void> _testMismatchedSiteDeviceIsExcludedFromTargets() async {
  final OperationalTopologyDiscoveryResult result = await _loader().load(
    tenantId: _tenantId,
    siteId: _siteId,
  );
  final bool leaked = result.topology.targets.any(
    (OperationalAlertTarget t) => t.deviceId == 'genetica-legacy-unit',
  );
  _expect(
    !leaked,
    'a device belonging to genetica-1 does not leak into las-heras targets',
  );
  _expect(
    result.topology.warnings.any(
      (String w) => w.startsWith('device_site_mismatch:genetica-legacy-unit'),
    ),
    'the site mismatch is reported as a warning, not silently dropped '
    '(warnings=${result.topology.warnings})',
  );
  _expect(
    !result.topology.isValid,
    'a topology with an operational warning is not valid, per B2.5.1 '
    'semantics — this would surface as valid=false in /health.alertTopology',
  );
}

Future<void> _testMissingTenantReturnsEmptyTopologyWithWarning() async {
  final OperationalTopologyDiscoveryResult result = await _loader().load(
    tenantId: 'nonexistent-tenant',
    siteId: 'nonexistent-site',
  );
  _expect(
    result.topology.devices.isEmpty,
    'a real 404 from Firestore for a missing tenant yields an empty topology',
  );
  _expect(
    result.topology.warnings.any((String w) => w.startsWith('tenant_missing:')),
    'missing tenant is reported as a warning',
  );
}

Future<void> _testDisabledDeviceIsExcluded() async {
  await _putDoc('tenants/$_tenantId/devices/disabled-device', <String, Object?>{
    'siteId': _siteId,
    'enabled': false,
    'snapshotUnitKey': 'disabled-device',
  });
  final OperationalTopologyDiscoveryResult result = await _loader().load(
    tenantId: _tenantId,
    siteId: _siteId,
  );
  final bool leaked = result.topology.targets.any(
    (OperationalAlertTarget t) => t.deviceId == 'disabled-device',
  );
  _expect(!leaked, 'a disabled device does not produce a target');
  _expect(
    result.topology.warnings.any(
      (String w) => w.startsWith('device_disabled:disabled-device'),
    ),
    'disabled device is reported as a warning',
  );
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
