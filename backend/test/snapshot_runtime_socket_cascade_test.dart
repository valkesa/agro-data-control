// Regression test for Etapa 1 of the "microcortes" fix: a single read
// failure that tears down the Modbus TCP socket must not cascade into a
// synthetic "Socket not connected" failure for every remaining signal in
// the unit. Exercised end-to-end (real TCP loopback) against the public
// SnapshotRuntime API, since the affected methods are private to
// snapshot_runtime.dart.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/snapshot_runtime.dart';

Future<void> main() async {
  await _testFailureStopsTheLoopInsteadOfCascading();
  await _testHealthyUnitStillReadsEverySignal();
  // ignore: avoid_print
  print('All snapshot_runtime_socket_cascade tests passed.');
}

Future<void> _testFailureStopsTheLoopInsteadOfCascading() async {
  final List<int> requestedAddresses = <int>[];

  final ServerSocket server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((Socket client) {
    // Our own client always tears connections down with an abortive
    // Socket.destroy() (see ModbusTcpClient._destroySocket), which sends a
    // TCP RST rather than a clean FIN. A real PLC's stack absorbs that
    // silently; a plain ServerSocket in a test surfaces it as an
    // asynchronous SocketException on this side's IOSink — harmless here,
    // just noise from the test harness, not from SnapshotRuntime.
    unawaited(client.done.catchError((Object _) {}));
    final List<int> buffer = <int>[];
    client.listen((Uint8List data) {
      buffer.addAll(data);
      while (buffer.length >= 12) {
        final Uint8List request = Uint8List.fromList(buffer.sublist(0, 12));
        buffer.removeRange(0, 12);
        final int address = _addressOf(request);
        requestedAddresses.add(address);
        if (address == 1) {
          // sigB: simulate a torn connection instead of responding — this is
          // what ModbusTcpClient._runRead reacts to by closing its own
          // socket.
          client.destroy();
          return;
        }
        client.add(_buildResponse(request, value: 100 + address));
      }
    }, onError: (Object error) {});
  }, onError: (Object error) {});

  try {
    final PlcInstallationConfig config = _buildConfig(server.port);
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

    final Map<String, Object?> unit1 =
        snapshot['unit1'] as Map<String, Object?>;

    _expect(unit1['sigA'] == 100, 'signal read before the failure');
    _expect(unit1['sigB'] == null, 'the signal that failed');
    _expect(
      unit1['sigC'] == null,
      'signal after the failure — must be skipped, not attempted',
    );

    // sigC's address (2) must never reach the wire: the fix stops the loop
    // instead of retrying/reconnecting.
    _expect(
      requestedAddresses.length == 2 &&
          requestedAddresses[0] == 0 &&
          requestedAddresses[1] == 1,
      'expected exactly 2 requests on the wire (sigA, sigB), got '
      '$requestedAddresses',
    );

    final String? lastError = unit1['lastError'] as String?;
    _expect(lastError != null, 'expected a lastError describing the failure');
    _expect(
      !lastError!.contains(' | '),
      'exactly one real error (sigB) is expected — a second " | "-joined '
      'entry would mean sigC was also attempted and produced a cascade '
      '"Socket not connected" failure. Got: $lastError',
    );
    _expect(
      !lastError.contains('Socket not connected'),
      'this message should never be produced anymore — it was always an '
      'artifact of reusing an already-closed socket. Got: $lastError',
    );
  } finally {
    await server.close();
  }
}

Future<void> _testHealthyUnitStillReadsEverySignal() async {
  final List<int> requestedAddresses = <int>[];

  final ServerSocket server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((Socket client) {
    // Our own client always tears connections down with an abortive
    // Socket.destroy() (see ModbusTcpClient._destroySocket), which sends a
    // TCP RST rather than a clean FIN. A real PLC's stack absorbs that
    // silently; a plain ServerSocket in a test surfaces it as an
    // asynchronous SocketException on this side's IOSink — harmless here,
    // just noise from the test harness, not from SnapshotRuntime.
    unawaited(client.done.catchError((Object _) {}));
    final List<int> buffer = <int>[];
    client.listen((Uint8List data) {
      buffer.addAll(data);
      while (buffer.length >= 12) {
        final Uint8List request = Uint8List.fromList(buffer.sublist(0, 12));
        buffer.removeRange(0, 12);
        final int address = _addressOf(request);
        requestedAddresses.add(address);
        client.add(_buildResponse(request, value: 100 + address));
      }
    }, onError: (Object error) {});
  }, onError: (Object error) {});

  try {
    final PlcInstallationConfig config = _buildConfig(server.port);
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

    final Map<String, Object?> unit1 =
        snapshot['unit1'] as Map<String, Object?>;
    _expect(unit1['sigA'] == 100, 'sigA should read through');
    _expect(unit1['sigB'] == 101, 'sigB should read through');
    _expect(unit1['sigC'] == 102, 'sigC should read through');
    _expect(unit1['lastError'] == null, 'no error expected on a clean poll');
    _expect(
      requestedAddresses.length == 3 &&
          requestedAddresses[0] == 0 &&
          requestedAddresses[1] == 1 &&
          requestedAddresses[2] == 2,
      'expected all 3 signals requested in order, got $requestedAddresses',
    );
  } finally {
    await server.close();
  }
}

PlcInstallationConfig _buildConfig(int port) {
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

  final Map<String, SignalConfig> signals = <String, SignalConfig>{
    'sigA': signalAt(0),
    'sigB': signalAt(1),
    'sigC': signalAt(2),
  };

  final UnitConfig unit = UnitConfig(
    name: 'Unidad Test',
    signals: signals,
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
    // Long enough that the runtime only completes one poll cycle during the
    // test's lifetime — we drive it manually via onSnapshotUpdated.
    pollingIntervalMs: 3600000,
    timeoutMs: 800,
    httpHost: '127.0.0.1',
    httpPort: 0,
    units: <String, UnitConfig>{'unit1': unit},
    temperatureHistories: <TemperatureHistoryConfig>[
      TemperatureHistoryConfig(
        enabled: false,
        sourcePath: 'unit1.tempInterior',
        tenantId: 'test-tenant',
        siteId: 'test-site',
        plcId: 'unit1',
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
  );
}

int _addressOf(Uint8List request) {
  final ByteData view = ByteData.sublistView(request);
  return view.getUint16(8, Endian.big);
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
