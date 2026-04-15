import 'dart:async';
import 'dart:io';

import 'package:agro_data_control_backend/src/modbus_tcp_client.dart';

const String _defaultHost = '192.168.10.51';
const int _defaultPort = 502;
const int _defaultUnitId = 1;
const int _defaultStart = 0;
const int _defaultCount = 102;
const int _maxHistory = 10;
const Duration _defaultTimeout = Duration(seconds: 3);
const Duration _defaultInterval = Duration(seconds: 1);

const List<_AnalogProbePoint> _analogProbePoints = <_AnalogProbePoint>[
  _AnalogProbePoint(
    key: 'NAQ1',
    vm: 90,
    hr: 45,
    description: 'Temperatura interior',
  ),
  _AnalogProbePoint(
    key: 'NAQ2',
    vm: 106,
    hr: 53,
    description: 'Humedad interior',
  ),
  _AnalogProbePoint(
    key: 'NAQ3',
    vm: 122,
    hr: 61,
    description: 'Temperatura exterior',
  ),
  _AnalogProbePoint(
    key: 'NAQ4',
    vm: 138,
    hr: 69,
    description: 'Humedad exterior',
  ),
  _AnalogProbePoint(
    key: 'NAQ5',
    vm: 154,
    hr: 77,
    description: 'Presion diferencial',
  ),
  _AnalogProbePoint(
    key: 'NAQ8',
    vm: 170,
    hr: 85,
    description: 'Potencia de salida AQ1/AQ2',
  ),
];

Future<void> main(List<String> args) async {
  final bool watch = args.contains('--watch');
  final String host = _readStringArg(args, '--host') ?? _defaultHost;
  final int port = _readIntArg(args, '--port') ?? _defaultPort;
  final int unitId = _readIntArg(args, '--unit') ?? _defaultUnitId;
  final int start = _readIntArg(args, '--start') ?? _defaultStart;
  final int count = _readIntArg(args, '--count') ?? _defaultCount;
  final int timeoutMs =
      _readIntArg(args, '--timeout-ms') ?? _defaultTimeout.inMilliseconds;
  final int intervalMs =
      _readIntArg(args, '--interval-ms') ?? _defaultInterval.inMilliseconds;

  if (count <= 0) {
    stderr.writeln('Error: --count debe ser mayor que 0.');
    exitCode = 64;
    return;
  }
  if (start < 0) {
    stderr.writeln('Error: --start no puede ser negativo.');
    exitCode = 64;
    return;
  }
  if (port <= 0 || port > 65535) {
    stderr.writeln('Error: --port fuera de rango.');
    exitCode = 64;
    return;
  }
  if (unitId < 0 || unitId > 255) {
    stderr.writeln('Error: --unit debe estar entre 0 y 255.');
    exitCode = 64;
    return;
  }
  if (timeoutMs <= 0 || intervalMs <= 0) {
    stderr.writeln('Error: --timeout-ms y --interval-ms deben ser positivos.');
    exitCode = 64;
    return;
  }

  final ModbusTcpClient client = ModbusTcpClient(
    host: host,
    port: port,
    unitId: unitId,
    timeout: Duration(milliseconds: timeoutMs),
  );
  final List<_ProbeReading> history = <_ProbeReading>[];
  int readingNumber = 0;

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nInterrumpido por usuario. Cerrando conexion...');
    await client.close(reason: 'sigint');
    exit(0);
  });

  try {
    stdout.writeln(
      'Conectando a $host:$port unitId=$unitId y leyendo coils '
      '$start..${start + count - 1}...',
    );
    stdout.writeln(
      'Probe analogicas: '
      '${_analogProbePoints.map((point) => '${point.key}=HR${point.hr}').join(', ')}',
    );
    await client.connect();
    stdout.writeln('Conexion OK.');

    do {
      final DateTime now = DateTime.now();
      final List<bool> coilValues = await _readCoils(
        client: client,
        start: start,
        count: count,
      );
      final List<_AnalogReading> analogReadings = await _readAnalogReadings(
        client: client,
      );

      final _ProbeReading reading = _ProbeReading(
        label: 'L${readingNumber + 1}',
        timestamp: now,
        coilValues: coilValues,
        analogReadings: analogReadings,
      );
      readingNumber += 1;

      if (!watch) {
        _printSingleRead(reading: reading, start: start, count: count);
      } else {
        history.add(reading);
        if (history.length > _maxHistory) {
          history.removeAt(0);
        }
        _redrawWatchTable(
          history: history,
          host: host,
          port: port,
          unitId: unitId,
          start: start,
          count: count,
        );
      }

      if (!watch) {
        break;
      }
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    } while (true);
  } on SocketException catch (error) {
    stderr.writeln('Error de conexion al PLC ($host:$port): ${error.message}');
    exitCode = 1;
  } on TimeoutException {
    stderr.writeln(
      'Error de conexion al PLC ($host:$port): timeout al conectar o leer.',
    );
    exitCode = 1;
  } on _ProbeReadException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on ModbusException catch (error) {
    stderr.writeln('Error Modbus: ${error.message}');
    exitCode = 1;
  } catch (error) {
    stderr.writeln('Error inesperado: $error');
    exitCode = 1;
  } finally {
    await client.close(reason: 'logo_coils_probe_done');
  }
}

Future<List<bool>> _readCoils({
  required ModbusTcpClient client,
  required int start,
  required int count,
}) async {
  try {
    return await client.readCoils(
      start,
      count,
      operationLabel: 'logo_coils_probe@$start/$count',
    );
  } on ModbusException catch (error) {
    throw _ProbeReadException('Error Modbus leyendo coils: ${error.message}');
  } on TimeoutException {
    throw _ProbeReadException('Error timeout leyendo coils.');
  }
}

Future<List<_AnalogReading>> _readAnalogReadings({
  required ModbusTcpClient client,
}) async {
  final int minHr = _analogProbePoints
      .map((point) => point.hr)
      .reduce((left, right) => left < right ? left : right);
  final int maxHr = _analogProbePoints
      .map((point) => point.hr)
      .reduce((left, right) => left > right ? left : right);
  final int blockCount = (maxHr - minHr) + 1;

  try {
    final List<int> block = await client.readHoldingRegisters(
      minHr,
      blockCount,
      operationLabel: 'logo_analog_probe@$minHr/$blockCount',
    );

    return _analogProbePoints
        .map((point) {
          final int raw = block[point.hr - minHr];
          return _AnalogReading(
            point: point,
            raw: raw,
            intValue: raw,
            doubleValue: raw.toDouble(),
          );
        })
        .toList(growable: false);
  } on ModbusException catch (error) {
    throw _ProbeReadException(
      'Error Modbus leyendo holding registers: ${error.message}',
    );
  } on TimeoutException {
    throw _ProbeReadException('Error timeout leyendo holding registers.');
  }
}

void _printSingleRead({
  required _ProbeReading reading,
  required int start,
  required int count,
}) {
  stdout.writeln(
    '\n[${reading.timestamp.toIso8601String()}] Lectura coils '
    '$start..${start + count - 1}',
  );
  for (int index = 0; index < reading.coilValues.length; index += 1) {
    stdout.writeln('coil ${start + index} = ${reading.coilValues[index]}');
  }

  stdout.writeln(
    '\n[${reading.timestamp.toIso8601String()}] Lectura analogicas',
  );
  stdout.writeln(
    'variable | VM    | HR   | descripcion                       | raw   | int   | double',
  );
  for (final _AnalogReading analog in reading.analogReadings) {
    stdout.writeln(
      '${analog.point.key.padRight(8)} | '
      'VM${analog.point.vm.toString().padRight(3)} | '
      'HR${analog.point.hr.toString().padRight(3)} | '
      '${analog.point.description.padRight(33)} | '
      'raw=${analog.raw.toString().padLeft(5)} | '
      'int=${analog.intValue.toString().padLeft(5)} | '
      'double=${analog.doubleValue.toStringAsFixed(1)}',
    );
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

class _ProbeReading {
  const _ProbeReading({
    required this.label,
    required this.timestamp,
    required this.coilValues,
    required this.analogReadings,
  });

  final String label;
  final DateTime timestamp;
  final List<bool> coilValues;
  final List<_AnalogReading> analogReadings;
}

class _AnalogProbePoint {
  const _AnalogProbePoint({
    required this.key,
    required this.vm,
    required this.hr,
    required this.description,
  });

  final String key;
  final int vm;
  final int hr;
  final String description;
}

class _AnalogReading {
  const _AnalogReading({
    required this.point,
    required this.raw,
    required this.intValue,
    required this.doubleValue,
  });

  final _AnalogProbePoint point;
  final int raw;
  final int intValue;
  final double doubleValue;
}

class _ProbeReadException implements Exception {
  const _ProbeReadException(this.message);

  final String message;
}

void _redrawWatchTable({
  required List<_ProbeReading> history,
  required String host,
  required int port,
  required int unitId,
  required int start,
  required int count,
}) {
  stdout.write('\x1B[2J\x1B[H');
  final DateTime lastTimestamp = history.last.timestamp;
  final List<String> changedCoils = _buildChangedCoils(
    history: history,
    start: start,
    count: count,
  );
  final List<String> changedAnalogs = _buildChangedAnalogs(history: history);

  stdout.writeln(
    'LOGO coils probe  host=$host  port=$port  unitId=$unitId  '
    'range=$start..${start + count - 1}',
  );
  stdout.writeln('Ultima actualizacion: ${lastTimestamp.toIso8601String()}');
  stdout.writeln(
    'Mostrando ultimas ${history.length} de $_maxHistory lecturas',
  );
  stdout.writeln(
    changedCoils.isEmpty
        ? 'Cambios coils: Sin cambios'
        : 'Cambios coils: ${changedCoils.join(', ')}',
  );
  stdout.writeln(
    changedAnalogs.isEmpty
        ? 'Cambios analogicas: Sin cambios'
        : 'Cambios analogicas: ${changedAnalogs.join(', ')}',
  );
  stdout.writeln('');

  _printCoilsWatchTable(history: history, start: start, count: count);
  stdout.writeln('');
  _printAnalogsWatchTable(history: history);
}

void _printCoilsWatchTable({
  required List<_ProbeReading> history,
  required int start,
  required int count,
}) {
  final int leftCount = count > 51 ? 51 : (count + 1) ~/ 2;
  final int rightStart = leftCount;
  final int rightCount = count - leftCount;
  final String leftHeader = _buildCoilHeader(history: history);
  final String rightHeader = rightCount > 0
      ? _buildCoilHeader(history: history)
      : '';

  stdout.writeln(rightCount > 0 ? '$leftHeader |  $rightHeader' : leftHeader);

  for (int row = 0; row < leftCount; row += 1) {
    final String leftLine = _buildCoilRow(
      history: history,
      absoluteIndex: row,
      coilNumber: start + row,
    );
    final int rightRow = rightStart + row;
    if (rightRow < count) {
      final String rightLine = _buildCoilRow(
        history: history,
        absoluteIndex: rightRow,
        coilNumber: start + rightRow,
      );
      stdout.writeln('$leftLine |  $rightLine');
    } else {
      stdout.writeln(leftLine);
    }
  }
}

String _buildCoilHeader({required List<_ProbeReading> history}) {
  final StringBuffer header = StringBuffer('coil   ');
  for (final _ProbeReading reading in history) {
    header.write('${reading.label.padLeft(4)} ');
  }
  return header.toString();
}

String _buildCoilRow({
  required List<_ProbeReading> history,
  required int absoluteIndex,
  required int coilNumber,
}) {
  final StringBuffer line = StringBuffer(
    'coil ${coilNumber.toString().padLeft(2)} ',
  );
  for (int column = 0; column < history.length; column += 1) {
    final _ProbeReading reading = history[column];
    final bool currentValue = reading.coilValues[absoluteIndex];
    final String cellValue = _formatCoilCellValue(
      currentValue: currentValue,
      previousValue: column > 0
          ? history[column - 1].coilValues[absoluteIndex]
          : null,
    );
    line.write('${cellValue.padLeft(4)} ');
  }
  return line.toString();
}

void _printAnalogsWatchTable({required List<_ProbeReading> history}) {
  stdout.writeln('Analogicas:');
  final StringBuffer header = StringBuffer(
    '${'variable'.padRight(8)} '
    '${'VM'.padLeft(4)} '
    '${'HR'.padLeft(4)} '
    '${'descripcion'.padRight(33)} ',
  );
  for (final _ProbeReading reading in history) {
    header.write('${reading.label.padLeft(7)} ');
  }
  stdout.writeln(header.toString());

  for (int row = 0; row < _analogProbePoints.length; row += 1) {
    final _AnalogProbePoint point = _analogProbePoints[row];
    final StringBuffer line = StringBuffer(
      '${point.key.padRight(8)} '
      '${point.vm.toString().padLeft(4)} '
      '${point.hr.toString().padLeft(4)} '
      '${point.description.padRight(33)} ',
    );
    for (int column = 0; column < history.length; column += 1) {
      final _AnalogReading current = history[column].analogReadings[row];
      final int? previous = column > 0
          ? history[column - 1].analogReadings[row].raw
          : null;
      final String cellValue = _formatAnalogCellValue(
        currentValue: current.raw,
        previousValue: previous,
      );
      line.write('${cellValue.padLeft(7)} ');
    }
    stdout.writeln(line.toString());
  }
}

List<String> _buildChangedCoils({
  required List<_ProbeReading> history,
  required int start,
  required int count,
}) {
  if (history.length < 2) {
    return const <String>[];
  }

  final List<bool> previous = history[history.length - 2].coilValues;
  final List<bool> current = history.last.coilValues;
  final List<String> changed = <String>[];
  for (int index = 0; index < count; index += 1) {
    if (previous[index] != current[index]) {
      changed.add('coil ${start + index}');
    }
  }
  return changed;
}

List<String> _buildChangedAnalogs({required List<_ProbeReading> history}) {
  if (history.length < 2) {
    return const <String>[];
  }

  final List<_AnalogReading> previous =
      history[history.length - 2].analogReadings;
  final List<_AnalogReading> current = history.last.analogReadings;
  final List<String> changed = <String>[];
  for (int index = 0; index < current.length; index += 1) {
    if (previous[index].raw != current[index].raw) {
      changed.add(current[index].point.key);
    }
  }
  return changed;
}

String _formatCoilCellValue({
  required bool currentValue,
  required bool? previousValue,
}) {
  if (previousValue == null || previousValue == currentValue) {
    return currentValue ? '1' : '0';
  }
  if (!previousValue && currentValue) {
    return '1↑';
  }
  return '0↓';
}

String _formatAnalogCellValue({
  required int currentValue,
  required int? previousValue,
}) {
  if (previousValue == null || previousValue == currentValue) {
    return currentValue.toString();
  }
  if (currentValue > previousValue) {
    return '${currentValue}↑';
  }
  return '${currentValue}↓';
}
