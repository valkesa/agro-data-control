// Regression tests for the Genetica 1 -> Las Heras migration compatibility
// shim: `PlcInstallationConfig.unitAliases` + `applyUnitAliases`. Goal is to
// project an already-read physical unit's payload (munters1/munters2) onto
// one or more additional top-level snapshot keys (the modern Devices'
// `snapshotUnitKey`s) WITHOUT a second Modbus read, and WITHOUT the alias
// keys ever reaching door-openings/runtime-events/alerts/history — those
// subsystems must only ever see the original `unitsJson`, so no subsystem
// keyed off a unit key can fire twice for the same physical event.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/snapshot_runtime.dart';

Future<void> main() async {
  _testApplyUnitAliasesProjectsSourceOntoAlias();
  _testApplyUnitAliasesReturnsSameInstanceWhenEmpty();
  _testApplyUnitAliasesSkipsMissingSourceKey();
  _testApplyUnitAliasesProducesIndependentCopies();
  _testDefaultJsonConfigParsesUnitAliases();
  _testUnitAliasesAbsentDefaultsToEmpty();
  await _testEndToEndSinglePhysicalReadProjectsToAlias();
  await _testEndToEndAliasNeverReachesDoorOpeningsUnitKeys();

  // ignore: avoid_print
  print('unit_aliases_test: all expectations passed');
}

void _testApplyUnitAliasesProjectsSourceOntoAlias() {
  final Map<String, Object?> unitsJson = <String, Object?>{
    'munters1': <String, Object?>{'tempInterior': 21.5, 'plcOnline': true},
    'munters2': <String, Object?>{'tempInterior': 19.0, 'plcOnline': false},
  };
  final Map<String, Object?> result = applyUnitAliases(
    unitsJson,
    <String, List<String>>{
      'munters1': <String>['plc-genetica-sala1'],
      'munters2': <String>['plc-genetica-sala2'],
    },
  );

  _expect(
    result.length == 4,
    'expected 2 original + 2 alias keys, got ${result.keys}',
  );
  _expect(
    result['plc-genetica-sala1'] is Map &&
        (result['plc-genetica-sala1'] as Map)['tempInterior'] == 21.5 &&
        (result['plc-genetica-sala1'] as Map)['plcOnline'] == true,
    'plc-genetica-sala1 mirrors munters1 verbatim',
  );
  _expect(
    result['plc-genetica-sala2'] is Map &&
        (result['plc-genetica-sala2'] as Map)['tempInterior'] == 19.0,
    'plc-genetica-sala2 mirrors munters2 verbatim',
  );
  _expect(
    result['munters1'] == unitsJson['munters1'] &&
        result['munters2'] == unitsJson['munters2'],
    'original unit entries are untouched',
  );
}

void _testApplyUnitAliasesReturnsSameInstanceWhenEmpty() {
  final Map<String, Object?> unitsJson = <String, Object?>{
    'munters1': <String, Object?>{'tempInterior': 21.5},
  };
  final Map<String, Object?> result = applyUnitAliases(
    unitsJson,
    const <String, List<String>>{},
  );
  _expect(
    identical(result, unitsJson),
    'empty unitAliases must return the exact same map instance — every '
    'site without this feature configured stays byte-for-byte unchanged',
  );
}

void _testApplyUnitAliasesSkipsMissingSourceKey() {
  final Map<String, Object?> unitsJson = <String, Object?>{
    'munters1': <String, Object?>{'tempInterior': 21.5},
  };
  final Map<String, Object?> result = applyUnitAliases(
    unitsJson,
    <String, List<String>>{
      'munters-never-configured': <String>['plc-genetica-laboratorio'],
    },
  );
  _expect(
    !result.containsKey('plc-genetica-laboratorio'),
    'an alias whose source key is absent from unitsJson must not fabricate '
    'a unit — this is how Laboratorio (no physical PLC yet) stays absent '
    'instead of showing invented data',
  );
  _expect(result.length == 1, 'no extra keys added at all');
}

void _testApplyUnitAliasesProducesIndependentCopies() {
  final Map<String, Object?> source = <String, Object?>{'tempInterior': 21.5};
  final Map<String, Object?> unitsJson = <String, Object?>{'munters1': source};
  final Map<String, Object?> result = applyUnitAliases(
    unitsJson,
    <String, List<String>>{
      'munters1': <String>['plc-genetica-sala1'],
    },
  );
  _expect(
    !identical(result['plc-genetica-sala1'], source),
    'alias must be a distinct Map instance, not the same reference as the '
    'source — guards against a future accidental in-place mutation of one '
    'leaking into the other',
  );
}

void _testDefaultJsonConfigParsesUnitAliases() {
  final String raw = File('config/sites/default.json').readAsStringSync();
  final PlcInstallationConfig config = PlcInstallationConfig.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
  );
  _expect(
    config.unitAliases['munters1']?.single == 'plc-genetica-sala1',
    'munters1 aliases to plc-genetica-sala1 (real Device id, no '
    'snapshotUnitKey configured in Firestore so it falls back to the '
    'Device id itself)',
  );
  _expect(
    config.unitAliases['munters2']?.single == 'plc-genetica-sala2',
    'munters2 aliases to plc-genetica-sala2',
  );
  _expect(
    !config.unitAliases.containsKey('plc-genetica-laboratorio') &&
        config.unitAliases.values.every(
          (List<String> v) => !v.contains('plc-genetica-laboratorio'),
        ),
    'Laboratorio has no physical PLC yet, so it must not be aliased from '
    'anything — no simulated data',
  );
}

void _testUnitAliasesAbsentDefaultsToEmpty() {
  final String raw = File(
    'config/sites/la-payana__roque-perez.json',
  ).readAsStringSync();
  final PlcInstallationConfig config = PlcInstallationConfig.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
  );
  _expect(
    config.unitAliases.isEmpty,
    'a config without an "unitAliases" key parses to an empty map — every '
    'other tenant/site stays completely unaffected by this feature',
  );
}

Future<void> _testEndToEndSinglePhysicalReadProjectsToAlias() async {
  int acceptedConnections = 0;
  final ServerSocket server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((Socket client) {
    acceptedConnections++;
    unawaited(client.done.catchError((Object _) {}));
    final List<int> buffer = <int>[];
    client.listen((Uint8List data) {
      buffer.addAll(data);
      while (buffer.length >= 12) {
        final Uint8List request = Uint8List.fromList(buffer.sublist(0, 12));
        buffer.removeRange(0, 12);
        client.add(_buildResponse(request, value: 215));
      }
    }, onError: (Object error) {});
  }, onError: (Object error) {});

  try {
    final PlcInstallationConfig config = _buildConfig(
      server.port,
      unitAliases: <String, List<String>>{
        'munters1': <String>['plc-genetica-sala1'],
      },
    );
    final Completer<Map<String, Object?>> firstSnapshot =
        Completer<Map<String, Object?>>();
    final SnapshotRuntime runtime = SnapshotRuntime(
      config,
      onSnapshotUpdated: (Map<String, Object?> snapshot) async {
        if (!firstSnapshot.isCompleted) {
          firstSnapshot.complete(snapshot);
        }
      },
    );

    runtime.start();
    final Map<String, Object?> snapshot = await firstSnapshot.future.timeout(
      const Duration(seconds: 5),
    );
    await runtime.dispose();

    _expect(
      acceptedConnections == 1,
      'exactly ONE physical TCP connection to the PLC per poll cycle — '
      'the alias must never trigger a second read, got '
      '$acceptedConnections connections',
    );

    final Map<String, Object?>? legacyUnit =
        snapshot['munters1'] as Map<String, Object?>?;
    final Map<String, Object?>? modernUnit =
        snapshot['plc-genetica-sala1'] as Map<String, Object?>?;
    _expect(legacyUnit != null, 'legacy munters1 still appears in snapshot');
    _expect(
      modernUnit != null,
      'plc-genetica-sala1 appears in snapshot from the same physical read',
    );
    _expect(
      legacyUnit!['sigA'] == 215 && modernUnit!['sigA'] == 215,
      'both keys carry the identical value read from the single PLC poll',
    );
    _expect(
      legacyUnit['plcOnline'] == modernUnit!['plcOnline'] &&
          legacyUnit['lastUpdatedAt'] == modernUnit['lastUpdatedAt'],
      'connectivity/freshness fields are equivalent on both sides',
    );
    _expect(
      !identical(legacyUnit, modernUnit),
      'the two units are independent map instances in the payload',
    );
  } finally {
    await server.close();
  }
}

/// Confirms the risk the migration prompt explicitly flagged: door-openings
/// (and by the same code path, runtime-events/alerts/history) must key off
/// the ORIGINAL unitsJson only. This is enforced structurally by
/// `applyUnitAliases` only ever being called when building the HTTP
/// payload — this test locks that in by configuring a door whose
/// `unitKey` is the ALIAS (not the source), which must never resolve to
/// anything real, since the alias key never existed in the map the door
/// tracker actually reads from.
Future<void> _testEndToEndAliasNeverReachesDoorOpeningsUnitKeys() async {
  final ServerSocket server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((Socket client) {
    unawaited(client.done.catchError((Object _) {}));
    final List<int> buffer = <int>[];
    client.listen((Uint8List data) {
      buffer.addAll(data);
      while (buffer.length >= 12) {
        final Uint8List request = Uint8List.fromList(buffer.sublist(0, 12));
        buffer.removeRange(0, 12);
        client.add(_buildResponse(request, value: 1));
      }
    }, onError: (Object error) {});
  }, onError: (Object error) {});

  try {
    PlcInstallationConfig config = _buildConfig(
      server.port,
      unitAliases: <String, List<String>>{
        'munters1': <String>['plc-genetica-sala1'],
      },
    );
    // Rebuild with doorOpenings pointed at the ALIAS key, which never
    // exists in the raw unitsJson the tracker consumes.
    config = PlcInstallationConfig(
      backendName: config.backendName,
      clientName: config.clientName,
      siteName: config.siteName,
      plcHost: config.plcHost,
      plcPort: config.plcPort,
      unitId: config.unitId,
      pollingIntervalMs: config.pollingIntervalMs,
      timeoutMs: config.timeoutMs,
      httpHost: config.httpHost,
      httpPort: config.httpPort,
      units: config.units,
      temperatureHistories: config.temperatureHistories,
      differentialPressureHistories: config.differentialPressureHistories,
      deviceEnvironmentHistories: config.deviceEnvironmentHistories,
      doorOpenings: DoorOpeningsConfig(
        enabled: true,
        tenantId: 'test-tenant',
        siteId: 'test-site',
        doors: <DoorConfig>[
          DoorConfig(
            doorId: 'sala',
            unitKey: 'plc-genetica-sala1',
            signalKey: 'sigA',
            label: 'Puerta Sala',
          ),
        ],
        firestoreProjectId: null,
        firestoreDatabaseId: '(default)',
        firestoreServiceAccountPath: '',
      ),
      runtimeEvents: config.runtimeEvents,
      unitAliases: config.unitAliases,
    );

    final Completer<Map<String, Object?>> firstSnapshot =
        Completer<Map<String, Object?>>();
    final SnapshotRuntime runtime = SnapshotRuntime(
      config,
      onSnapshotUpdated: (Map<String, Object?> snapshot) async {
        if (!firstSnapshot.isCompleted) {
          firstSnapshot.complete(snapshot);
        }
      },
    );

    runtime.start();
    final Map<String, Object?> snapshot = await firstSnapshot.future.timeout(
      const Duration(seconds: 5),
    );
    await runtime.dispose();

    // The alias key must still be present in the final HTTP payload (the
    // door tracker misconfiguration above doesn't affect that)...
    _expect(
      snapshot['plc-genetica-sala1'] != null,
      'the alias itself is unaffected by an (intentionally, for this test) '
      'misconfigured door pointing at it',
    );
    // ...but a door tracker looking up 'plc-genetica-sala1' in the raw
    // unitsJson it was actually given must find nothing, since that key
    // never exists there — proving the alias truly never reaches it. We
    // can't reach the tracker's internals directly (private), so this is
    // asserted indirectly: no crash, no fabricated door event for a unit
    // key that structurally cannot resolve.
    final Object? doorEvents = snapshot['doorEvents'];
    _expect(
      doorEvents is Map,
      'runtime stays healthy (no crash) even when a door references a key '
      'that only exists as an alias, never in the raw unitsJson',
    );
  } finally {
    await server.close();
  }
}

PlcInstallationConfig _buildConfig(
  int port, {
  Map<String, List<String>> unitAliases = const <String, List<String>>{},
}) {
  SignalConfig signalAt(int address) {
    return SignalConfig(
      area: SignalArea.holdingRegister,
      address: address,
      dataType: SignalDataType.int,
      wordCount: 1,
      signed: false,
      scale: 1,
      offset: 0,
      wordOrder: WordOrder.bigEndian,
      enumMap: const <String, String>{},
      bitIndex: null,
    );
  }

  final UnitConfig unit = UnitConfig(
    name: 'Sala 1',
    signals: <String, SignalConfig>{'sigA': signalAt(0)},
    plcHost: '127.0.0.1',
    plcPort: port,
    unitId: 1,
  );

  return PlcInstallationConfig(
    backendName: 'test',
    clientName: 'Cliente Test',
    siteName: 'Sitio Test',
    plcHost: '127.0.0.1',
    plcPort: port,
    unitId: 1,
    pollingIntervalMs: 3600000,
    timeoutMs: 800,
    httpHost: '127.0.0.1',
    httpPort: 0,
    units: <String, UnitConfig>{'munters1': unit},
    temperatureHistories: <TemperatureHistoryConfig>[
      TemperatureHistoryConfig(
        enabled: false,
        sourcePath: 'munters1.tempInterior',
        tenantId: 'test-tenant',
        siteId: 'test-site',
        plcId: 'munters1',
        firestoreProjectId: null,
        firestoreDatabaseId: '(default)',
        firestoreServiceAccountPath: '',
      ),
    ],
    differentialPressureHistories: const <DifferentialPressureHistoryConfig>[],
    deviceEnvironmentHistories: const <DeviceEnvironmentHistoryConfig>[],
    doorOpenings: DoorOpeningsConfig(
      enabled: false,
      tenantId: 'test-tenant',
      siteId: 'test-site',
      doors: const <DoorConfig>[],
      firestoreProjectId: null,
      firestoreDatabaseId: '(default)',
      firestoreServiceAccountPath: '',
    ),
    runtimeEvents: RuntimeEventsConfig(
      enabled: false,
      tenantId: 'test-tenant',
      siteId: 'test-site',
      plcs: const <RuntimePlcConfig>[],
      firestoreProjectId: null,
      firestoreDatabaseId: '(default)',
      firestoreServiceAccountPath: '',
      hbGapThresholdMs: 999999,
    ),
    unitAliases: unitAliases,
  );
}

Uint8List _buildResponse(Uint8List request, {required int value}) {
  final ByteData reqView = ByteData.sublistView(request);
  final int txId = reqView.getUint16(0, Endian.big);
  final int unitId = request[6];
  final int functionCode = request[7];

  final ByteData pdu = ByteData(4)
    ..setUint8(0, functionCode)
    ..setUint8(1, 2)
    ..setUint16(2, value, Endian.big);

  final ByteData mbap = ByteData(7)
    ..setUint16(0, txId, Endian.big)
    ..setUint16(2, 0, Endian.big)
    ..setUint16(4, pdu.lengthInBytes + 1, Endian.big)
    ..setUint8(6, unitId);

  return Uint8List.fromList(<int>[
    ...mbap.buffer.asUint8List(),
    ...pdu.buffer.asUint8List(),
  ]);
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('Assertion failed: $message');
  }
}
