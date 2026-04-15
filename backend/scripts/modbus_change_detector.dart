import 'dart:async';
import 'dart:io';

import 'package:agro_data_control_backend/src/modbus_tcp_client.dart';

const String _defaultHost = '192.168.10.51';
const int _defaultPort = 502;
const int _defaultUnitId = 1;
const int _defaultCoilsStart = 0;
const int _defaultCoilsCount = 32;
const int _defaultDiscreteStart = 0;
const int _defaultDiscreteCount = 32;
const int _defaultHoldingStart = 0;
const int _defaultHoldingCount = 16;
const int _defaultPollMs = 1000;
const int _defaultTimeoutMs = 1500;

Future<void> main(List<String> args) async {
  final String host = _readStringArg(args, '--host') ?? _defaultHost;
  final int port = _readIntArg(args, '--port') ?? _defaultPort;
  final int unitId = _readIntArg(args, '--unit-id') ?? _defaultUnitId;
  final int coilsStart =
      _readIntArg(args, '--coils-start') ?? _defaultCoilsStart;
  final int coilsCount =
      _readIntArg(args, '--coils-count') ?? _defaultCoilsCount;
  final int discreteStart =
      _readIntArg(args, '--discrete-start') ?? _defaultDiscreteStart;
  final int discreteCount =
      _readIntArg(args, '--discrete-count') ?? _defaultDiscreteCount;
  final int holdingStart =
      _readIntArg(args, '--holding-start') ?? _defaultHoldingStart;
  final int holdingCount =
      _readIntArg(args, '--holding-count') ?? _defaultHoldingCount;
  final int pollMs = _readIntArg(args, '--poll-ms') ?? _defaultPollMs;
  final int timeoutMs = _readIntArg(args, '--timeout-ms') ?? _defaultTimeoutMs;
  final bool once = args.contains('--once');
  final bool showInitial = args.contains('--show-initial');

  if (port <= 0 || port > 65535) {
    stderr.writeln('Error: --port fuera de rango.');
    exitCode = 64;
    return;
  }
  if (unitId < 0 || unitId > 255) {
    stderr.writeln('Error: --unit-id debe estar entre 0 y 255.');
    exitCode = 64;
    return;
  }
  if (!_isValidRange(coilsStart, coilsCount) ||
      !_isValidRange(discreteStart, discreteCount) ||
      !_isValidRange(holdingStart, holdingCount)) {
    stderr.writeln(
      'Error: todos los rangos deben tener start >= 0 y count > 0.',
    );
    exitCode = 64;
    return;
  }
  if (pollMs <= 0 || timeoutMs <= 0) {
    stderr.writeln('Error: --poll-ms y --timeout-ms deben ser positivos.');
    exitCode = 64;
    return;
  }

  final _SnapshotReader reader = _SnapshotReader(
    host: host,
    port: port,
    unitId: unitId,
    timeout: Duration(milliseconds: timeoutMs),
  );

  StreamSubscription<ProcessSignal>? sigintSubscription;
  sigintSubscription = ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nInterrumpido por usuario. Cerrando conexion...');
    await sigintSubscription?.cancel();
    await reader.close();
    exit(0);
  });

  try {
    stdout.writeln('Modbus Change Detector');
    stdout.writeln('host=$host port=$port unitId=$unitId');
    stdout.writeln('coils: start=$coilsStart count=$coilsCount');
    stdout.writeln('discretes: start=$discreteStart count=$discreteCount');
    stdout.writeln('holdings: start=$holdingStart count=$holdingCount');
    stdout.writeln('pollMs=$pollMs timeoutMs=$timeoutMs');
    stdout.writeln('');

    await reader.connect();
    final _Snapshot baseline = await readSnapshot(
      reader: reader,
      coilsStart: coilsStart,
      coilsCount: coilsCount,
      discreteStart: discreteStart,
      discreteCount: discreteCount,
      holdingStart: holdingStart,
      holdingCount: holdingCount,
    );

    if (showInitial || once) {
      stdout.writeln('Baseline inicial');
      printSnapshot(baseline);
    }

    if (once) {
      return;
    }

    _Snapshot previous = baseline;
    while (true) {
      await Future<void>.delayed(Duration(milliseconds: pollMs));
      final _Snapshot current = await readSnapshot(
        reader: reader,
        coilsStart: coilsStart,
        coilsCount: coilsCount,
        discreteStart: discreteStart,
        discreteCount: discreteCount,
        holdingStart: holdingStart,
        holdingCount: holdingCount,
      );
      final List<String> changes = diffSnapshots(previous, current);
      for (final String change in changes) {
        stdout.writeln('[${_timeStampNow()}] $change');
      }
      previous = current;
    }
  } on SocketException catch (error) {
    stderr.writeln(
      'Error de conexion al PLC ($host:$port): ${error.message}',
    );
    exitCode = 1;
  } on TimeoutException {
    stderr.writeln(
      'Error de conexion al PLC ($host:$port): timeout al conectar o leer.',
    );
    exitCode = 1;
  } on ModbusException catch (error) {
    stderr.writeln('Error Modbus: ${error.message}');
    exitCode = 1;
  } catch (error) {
    stderr.writeln('Error inesperado: $error');
    exitCode = 1;
  } finally {
    await sigintSubscription.cancel();
    await reader.close();
  }
}

bool _isValidRange(int start, int count) => start >= 0 && count > 0;

Future<_Snapshot> readSnapshot({
  required _SnapshotReader reader,
  required int coilsStart,
  required int coilsCount,
  required int discreteStart,
  required int discreteCount,
  required int holdingStart,
  required int holdingCount,
}) async {
  final List<bool?> coils = List<bool?>.filled(coilsCount, null);
  final List<bool?> discretes = List<bool?>.filled(discreteCount, null);
  final List<int?> holdings = List<int?>.filled(holdingCount, null);

  for (int index = 0; index < coilsCount; index += 1) {
    coils[index] = await reader.readCoil(coilsStart + index);
  }
  for (int index = 0; index < discreteCount; index += 1) {
    discretes[index] = await reader.readDiscrete(discreteStart + index);
  }
  for (int index = 0; index < holdingCount; index += 1) {
    holdings[index] = await reader.readHolding(holdingStart + index);
  }

  return _Snapshot(
    coilsStart: coilsStart,
    discreteStart: discreteStart,
    holdingStart: holdingStart,
    coils: coils,
    discretes: discretes,
    holdings: holdings,
  );
}

List<String> diffSnapshots(_Snapshot previous, _Snapshot current) {
  final List<String> changes = <String>[];

  for (int index = 0; index < current.coils.length; index += 1) {
    final bool? before = previous.coils[index];
    final bool? after = current.coils[index];
    if (before != after) {
      changes.add(
        'COIL ${current.coilsStart + index}: '
        '${_formatBoolValue(before)} -> ${_formatBoolValue(after)}',
      );
    }
  }

  for (int index = 0; index < current.discretes.length; index += 1) {
    final bool? before = previous.discretes[index];
    final bool? after = current.discretes[index];
    if (before != after) {
      changes.add(
        'DISCRETE ${current.discreteStart + index}: '
        '${_formatBoolValue(before)} -> ${_formatBoolValue(after)}',
      );
    }
  }

  for (int index = 0; index < current.holdings.length; index += 1) {
    final int? before = previous.holdings[index];
    final int? after = current.holdings[index];
    if (before != after) {
      changes.add(
        'HOLDING ${current.holdingStart + index}: '
        '${_formatIntValue(before)} -> ${_formatIntValue(after)}',
      );
    }
  }

  return changes;
}

void printSnapshot(_Snapshot snapshot) {
  stdout.writeln('Coils');
  for (int index = 0; index < snapshot.coils.length; index += 1) {
    stdout.writeln(
      '  ${snapshot.coilsStart + index}: ${_formatBoolValue(snapshot.coils[index])}',
    );
  }

  stdout.writeln('Discrete Inputs');
  for (int index = 0; index < snapshot.discretes.length; index += 1) {
    stdout.writeln(
      '  ${snapshot.discreteStart + index}: ${_formatBoolValue(snapshot.discretes[index])}',
    );
  }

  stdout.writeln('Holding Registers');
  for (int index = 0; index < snapshot.holdings.length; index += 1) {
    stdout.writeln(
      '  ${snapshot.holdingStart + index}: ${_formatIntValue(snapshot.holdings[index])}',
    );
  }
}

String _formatBoolValue(bool? value) {
  if (value == null) {
    return 'ERR';
  }
  return value.toString();
}

String _formatIntValue(int? value) {
  if (value == null) {
    return 'ERR';
  }
  return value.toString();
}

String _timeStampNow() {
  final DateTime now = DateTime.now();
  final String hh = now.hour.toString().padLeft(2, '0');
  final String mm = now.minute.toString().padLeft(2, '0');
  final String ss = now.second.toString().padLeft(2, '0');
  final String ms = now.millisecond.toString().padLeft(3, '0');
  return '$hh:$mm:$ss.$ms';
}

class _Snapshot {
  const _Snapshot({
    required this.coilsStart,
    required this.discreteStart,
    required this.holdingStart,
    required this.coils,
    required this.discretes,
    required this.holdings,
  });

  final int coilsStart;
  final int discreteStart;
  final int holdingStart;
  final List<bool?> coils;
  final List<bool?> discretes;
  final List<int?> holdings;
}

class _SnapshotReader {
  _SnapshotReader({
    required this.host,
    required this.port,
    required this.unitId,
    required this.timeout,
  }) : _client = ModbusTcpClient(
         host: host,
         port: port,
         unitId: unitId,
         timeout: timeout,
       );

  final String host;
  final int port;
  final int unitId;
  final Duration timeout;
  final ModbusTcpClient _client;

  bool _connected = false;

  Future<void> connect() async {
    await _client.connect();
    _connected = true;
  }

  Future<void> close() async {
    await _client.close(reason: 'change_detector_close');
    _connected = false;
  }

  Future<bool?> readCoil(int address) {
    return _readWithReconnect<bool?>(
      () async => (await _client.readCoils(
        address,
        1,
        operationLabel: 'detector.coil@$address',
      )).first,
    );
  }

  Future<bool?> readDiscrete(int address) {
    return _readWithReconnect<bool?>(
      () async => (await _client.readDiscreteInputs(
        address,
        1,
        operationLabel: 'detector.discrete@$address',
      )).first,
    );
  }

  Future<int?> readHolding(int address) {
    return _readWithReconnect<int?>(() async {
      final int raw = (await _client.readHoldingRegisters(
        address,
        1,
        operationLabel: 'detector.holding@$address',
      )).first;
      return raw > 0x7FFF ? raw - 0x10000 : raw;
    });
  }

  Future<T?> _readWithReconnect<T>(Future<T> Function() action) async {
    for (int attempt = 0; attempt < 2; attempt += 1) {
      try {
        if (!_connected) {
          await connect();
        }
        return await action();
      } catch (_) {
        _connected = false;
        try {
          await _client.close(reason: 'change_detector_read_error');
        } catch (_) {}
        if (attempt == 1) {
          return null;
        }
        try {
          await connect();
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }
}

String? _readStringArg(List<String> args, String flag) {
  final int index = args.indexOf(flag);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

int? _readIntArg(List<String> args, String flag) {
  final String? value = _readStringArg(args, flag);
  if (value == null) {
    return null;
  }
  return int.tryParse(value);
}
