import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:agro_data_control_backend/src/modbus_tcp_client.dart';

const String _defaultHost = '192.168.10.51';
const int _defaultPort = 502;
const int _defaultUnitId = 1;
const int _defaultStart = 0;
const int _defaultCount = 60;
const int _defaultSamples = 30;
const int _defaultIntervalMs = 1000;
const int _defaultTimeoutMs = 3000;
const String _defaultCsvOut = 'backend/tmp/hr_scan.csv';

Future<void> main(List<String> args) async {
  final _ScanOptions options = parseArgs(args);
  if (options.hasValidationError) {
    stderr.writeln(options.validationError);
    exitCode = 64;
    return;
  }

  final ModbusTcpClient client = ModbusTcpClient(
    host: options.host,
    port: options.port,
    unitId: options.unitId,
    timeout: Duration(milliseconds: options.timeoutMs),
  );

  StreamSubscription<ProcessSignal>? sigintSubscription;
  sigintSubscription = ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nInterrumpido por usuario. Cerrando conexion...');
    await sigintSubscription?.cancel();
    await client.close(reason: 'sigint');
    exit(0);
  });

  final List<_SampleRecord> successfulSamples = <_SampleRecord>[];
  List<int>? previousValues;

  try {
    _printEffectiveParameters(options);
    await client.connect();
    stdout.writeln('Conexion OK.');

    for (int sampleIndex = 0; sampleIndex < options.samples; sampleIndex += 1) {
      final DateTime readAt = DateTime.now();

      try {
        final List<int> values = await readHoldingRange(
          client: client,
          start: options.start,
          count: options.count,
        );

        successfulSamples.add(
          _SampleRecord(
            sampleIndex: sampleIndex,
            timestamp: readAt,
            values: values,
          ),
        );

        final List<_RegisterChange> changes = <_RegisterChange>[];
        if (previousValues != null) {
          for (int offset = 0; offset < values.length; offset += 1) {
            final int before = previousValues[offset];
            final int after = values[offset];
            if (before != after) {
              changes.add(
                _RegisterChange(
                  address: options.start + offset,
                  before: before,
                  after: after,
                ),
              );
            }
          }
        }

        _printSampleProgress(
          sampleNumber: sampleIndex + 1,
          totalSamples: options.samples,
          changes: changes,
        );
        previousValues = values;
      } on SocketException catch (error) {
        stderr.writeln(
          '[sample ${sampleIndex + 1}/${options.samples}] '
          'error de conexion: ${error.message}',
        );
        final bool reconnected = await _attemptReconnect(
          client: client,
          options: options,
          sampleNumber: sampleIndex + 1,
        );
        if (!reconnected) {
          stderr.writeln(
            'No se pudo restablecer la conexion. Abortando escaneo.',
          );
          exitCode = 1;
          break;
        }
      } on TimeoutException {
        stderr.writeln(
          '[sample ${sampleIndex + 1}/${options.samples}] '
          'timeout leyendo holding registers.',
        );
        final bool reconnected = await _attemptReconnect(
          client: client,
          options: options,
          sampleNumber: sampleIndex + 1,
        );
        if (!reconnected) {
          stderr.writeln(
            'No se pudo restablecer la conexion despues del timeout. Abortando escaneo.',
          );
          exitCode = 1;
          break;
        }
      } on ModbusException catch (error) {
        stderr.writeln(
          '[sample ${sampleIndex + 1}/${options.samples}] '
          'error Modbus: ${error.message}',
        );
        final bool reconnected = await _attemptReconnect(
          client: client,
          options: options,
          sampleNumber: sampleIndex + 1,
        );
        if (!reconnected) {
          stderr.writeln(
            'No se pudo restablecer la conexion despues del error Modbus. Abortando escaneo.',
          );
          exitCode = 1;
          break;
        }
      } catch (error) {
        stderr.writeln(
          '[sample ${sampleIndex + 1}/${options.samples}] error inesperado: $error',
        );
        exitCode = 1;
        break;
      }

      if (sampleIndex + 1 < options.samples) {
        await Future<void>.delayed(Duration(milliseconds: options.intervalMs));
      }
    }

    if (successfulSamples.isEmpty) {
      stderr.writeln('No se obtuvieron lecturas exitosas del PLC.');
      exitCode = exitCode == 0 ? 1 : exitCode;
      return;
    }

    final List<_RegisterAnalysis> analysis = analyzeSeries(
      startAddress: options.start,
      samples: successfulSamples,
    );

    stdout.writeln('');
    printSummary(analysis: analysis, showAll: options.showAll);
    stdout.writeln('');
    _printHeartbeatCandidates(analysis);

    if (options.csv) {
      await exportCsv(
        samples: successfulSamples,
        startAddress: options.start,
        outputPath: options.outPath,
      );
      stdout.writeln('');
      stdout.writeln('CSV exportado en ${options.outPath}');
    }
  } finally {
    await sigintSubscription.cancel();
    await client.close(reason: 'logo_scan_changing_holding_registers_done');
  }
}

_ScanOptions parseArgs(List<String> args) {
  final String host = _readStringArg(args, '--host') ?? _defaultHost;
  final int port = _readIntArg(args, '--port') ?? _defaultPort;
  final int unitId = _readIntArg(args, '--unit-id') ?? _defaultUnitId;
  final int start = _readIntArg(args, '--start') ?? _defaultStart;
  final int count = _readIntArg(args, '--count') ?? _defaultCount;
  final int samples = _readIntArg(args, '--samples') ?? _defaultSamples;
  final int intervalMs =
      _readIntArg(args, '--interval-ms') ?? _defaultIntervalMs;
  final int timeoutMs = _readIntArg(args, '--timeout-ms') ?? _defaultTimeoutMs;
  final bool showAll = args.contains('--show-all');
  final bool csv = args.contains('--csv');
  final String outPath = _readStringArg(args, '--out') ?? _defaultCsvOut;

  if (port <= 0 || port > 65535) {
    return _ScanOptions.invalid('Error: --port fuera de rango.');
  }
  if (unitId < 0 || unitId > 255) {
    return _ScanOptions.invalid('Error: --unit-id debe estar entre 0 y 255.');
  }
  if (start < 0) {
    return _ScanOptions.invalid('Error: --start debe ser >= 0.');
  }
  if (count <= 0) {
    return _ScanOptions.invalid('Error: --count debe ser > 0.');
  }
  if (samples <= 0) {
    return _ScanOptions.invalid('Error: --samples debe ser > 0.');
  }
  if (intervalMs <= 0) {
    return _ScanOptions.invalid('Error: --interval-ms debe ser > 0.');
  }
  if (timeoutMs <= 0) {
    return _ScanOptions.invalid('Error: --timeout-ms debe ser > 0.');
  }

  return _ScanOptions(
    host: host,
    port: port,
    unitId: unitId,
    start: start,
    count: count,
    samples: samples,
    intervalMs: intervalMs,
    timeoutMs: timeoutMs,
    showAll: showAll,
    csv: csv,
    outPath: outPath,
  );
}

Future<List<int>> readHoldingRange({
  required ModbusTcpClient client,
  required int start,
  required int count,
}) async {
  return client.readHoldingRegisters(
    start,
    count,
    operationLabel: 'logo_scan_changing_holding_registers@$start/$count',
  );
}

List<_RegisterAnalysis> analyzeSeries({
  required int startAddress,
  required List<_SampleRecord> samples,
}) {
  final int registerCount = samples.first.values.length;
  final List<_RegisterAnalysis> result = <_RegisterAnalysis>[];

  for (int offset = 0; offset < registerCount; offset += 1) {
    final List<int> observedValues = <int>[
      for (final _SampleRecord sample in samples) sample.values[offset],
    ];
    final LinkedHashSet<int> distinctValues = LinkedHashSet<int>.from(
      observedValues,
    );

    int changes = 0;
    for (int index = 1; index < observedValues.length; index += 1) {
      if (observedValues[index] != observedValues[index - 1]) {
        changes += 1;
      }
    }

    final int initialValue = observedValues.first;
    final int lastValue = observedValues.last;
    final int minValue = observedValues.reduce(
      (left, right) => left < right ? left : right,
    );
    final int maxValue = observedValues.reduce(
      (left, right) => left > right ? left : right,
    );

    final String suspectedPattern = inferPattern(
      values: observedValues,
      changes: changes,
      distinctValues: distinctValues.toList(growable: false),
    );

    result.add(
      _RegisterAnalysis(
        address: startAddress + offset,
        initialValue: initialValue,
        lastValue: lastValue,
        minValue: minValue,
        maxValue: maxValue,
        changes: changes,
        distinctValues: distinctValues.toList(growable: false),
        suspectedPattern: suspectedPattern,
      ),
    );
  }

  result.sort((left, right) {
    final int byChanges = right.changes.compareTo(left.changes);
    if (byChanges != 0) {
      return byChanges;
    }
    final int byDistinct = right.distinctValues.length.compareTo(
      left.distinctValues.length,
    );
    if (byDistinct != 0) {
      return byDistinct;
    }
    return left.address.compareTo(right.address);
  });

  return result;
}

String inferPattern({
  required List<int> values,
  required int changes,
  required List<int> distinctValues,
}) {
  if (changes == 0) {
    return 'stable';
  }

  final int positiveSteps = _countStepDirection(values, positive: true);
  final int negativeSteps = _countStepDirection(values, positive: false);

  if (distinctValues.length <= 2 && changes >= 2) {
    return 'possible_toggle';
  }

  if (positiveSteps >= negativeSteps * 2 &&
      distinctValues.length >= 3 &&
      changes >= 2) {
    return 'possible_counter';
  }

  if (distinctValues.length >= 5 || (positiveSteps > 0 && negativeSteps > 0)) {
    return 'dynamic';
  }

  if (distinctValues.length <= 4 && changes >= 2) {
    return 'possible_toggle';
  }

  return 'stable';
}

void printSummary({
  required List<_RegisterAnalysis> analysis,
  required bool showAll,
}) {
  final List<_RegisterAnalysis> visible = showAll
      ? analysis
      : analysis.where((item) => item.changes > 0).toList(growable: false);

  stdout.writeln('Resumen final');
  stdout.writeln(
    'address | initial | last | min | max | changes | distinctValues | suspectedPattern',
  );
  stdout.writeln(
    '------- | ------- | ---- | --- | --- | ------- | -------------- | ----------------',
  );

  for (final _RegisterAnalysis item in visible) {
    stdout.writeln(
      'HR${item.address.toString().padLeft(4)}'
      ' | ${item.initialValue.toString().padLeft(7)}'
      ' | ${item.lastValue.toString().padLeft(4)}'
      ' | ${item.minValue.toString().padLeft(3)}'
      ' | ${item.maxValue.toString().padLeft(3)}'
      ' | ${item.changes.toString().padLeft(7)}'
      ' | ${_formatDistinctValues(item.distinctValues).padRight(14)}'
      ' | ${item.suspectedPattern}',
    );
  }

  if (visible.isEmpty) {
    stdout.writeln('No se detectaron cambios en el rango analizado.');
  }
}

Future<void> exportCsv({
  required List<_SampleRecord> samples,
  required int startAddress,
  required String outputPath,
}) async {
  final File outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);

  final int registerCount = samples.first.values.length;
  final StringBuffer buffer = StringBuffer();
  buffer.write('sampleIndex,timestamp');
  for (int offset = 0; offset < registerCount; offset += 1) {
    buffer.write(',HR${startAddress + offset}');
  }
  buffer.writeln();

  for (final _SampleRecord sample in samples) {
    buffer.write('${sample.sampleIndex},${sample.timestamp.toIso8601String()}');
    for (final int value in sample.values) {
      buffer.write(',$value');
    }
    buffer.writeln();
  }

  await outputFile.writeAsString(buffer.toString());
}

void _printEffectiveParameters(_ScanOptions options) {
  stdout.writeln('Logo scan changing holding registers');
  stdout.writeln('host=${options.host}');
  stdout.writeln('port=${options.port}');
  stdout.writeln('unitId=${options.unitId}');
  stdout.writeln('start=${options.start}');
  stdout.writeln('count=${options.count}');
  stdout.writeln('samples=${options.samples}');
  stdout.writeln('intervalMs=${options.intervalMs}');
  stdout.writeln('timeoutMs=${options.timeoutMs}');
  stdout.writeln('showAll=${options.showAll}');
  stdout.writeln('csv=${options.csv}');
  stdout.writeln('out=${options.outPath}');
  stdout.writeln('');
}

void _printSampleProgress({
  required int sampleNumber,
  required int totalSamples,
  required List<_RegisterChange> changes,
}) {
  if (changes.isEmpty) {
    stdout.writeln('[sample $sampleNumber/$totalSamples] changed=0');
    return;
  }

  final String detail = changes
      .map((change) => 'HR${change.address} ${change.before}->${change.after}')
      .join(', ');
  stdout.writeln(
    '[sample $sampleNumber/$totalSamples] changed=${changes.length} registers: $detail',
  );
}

Future<bool> _attemptReconnect({
  required ModbusTcpClient client,
  required _ScanOptions options,
  required int sampleNumber,
}) async {
  try {
    await client.close(reason: 'scan_read_error');
    stdout.writeln(
      '[sample $sampleNumber/${options.samples}] intentando reconectar...',
    );
    await client.connect();
    stdout.writeln('[sample $sampleNumber/${options.samples}] reconexion OK.');
    return true;
  } catch (error) {
    stderr.writeln(
      '[sample $sampleNumber/${options.samples}] fallo reconexion: $error',
    );
    return false;
  }
}

void _printHeartbeatCandidates(List<_RegisterAnalysis> analysis) {
  stdout.writeln('Top candidates for heartbeat');

  final List<_RegisterAnalysis> candidates = analysis
      .where((item) {
        final int distinctCount = item.distinctValues.length;
        if (item.changes < 2) {
          return false;
        }
        if (item.suspectedPattern == 'possible_toggle' && distinctCount <= 4) {
          return true;
        }
        if (item.suspectedPattern == 'possible_counter' &&
            distinctCount <= 12) {
          return true;
        }
        return false;
      })
      .take(8)
      .toList(growable: false);

  if (candidates.isEmpty) {
    stdout.writeln(
      '  No se encontraron candidatos claros. Proba aumentar --samples o --count.',
    );
    return;
  }

  for (final _RegisterAnalysis item in candidates) {
    stdout.writeln(
      '  HR${item.address}: pattern=${item.suspectedPattern} '
      'changes=${item.changes} distinct=${item.distinctValues.length} '
      'values=${_formatDistinctValues(item.distinctValues)}',
    );
    stdout.writeln('    ${_explainCandidate(item)}');
  }
}

String _explainCandidate(_RegisterAnalysis item) {
  switch (item.suspectedPattern) {
    case 'possible_toggle':
      return 'Alterna entre pocos valores y cambia varias veces; podria ser un flag o heartbeat toggle.';
    case 'possible_counter':
      return 'Muestra incrementos frecuentes con rango acotado; podria ser un contador ciclico de vida.';
    case 'dynamic':
      return 'Cambia seguido pero con muchos valores distintos; probablemente sea una variable dinamica, no un heartbeat simple.';
    case 'stable':
      return 'Practicamente no cambia durante la ventana observada.';
  }

  return 'Sin clasificacion.';
}

String _formatDistinctValues(List<int> values) {
  const int maxPreview = 8;
  if (values.isEmpty) {
    return '-';
  }
  if (values.length <= maxPreview) {
    return values.join('/');
  }
  return '${values.take(maxPreview).join('/')}...(+${values.length - maxPreview})';
}

int _countStepDirection(List<int> values, {required bool positive}) {
  int count = 0;
  for (int index = 1; index < values.length; index += 1) {
    final int delta = values[index] - values[index - 1];
    if (positive && delta > 0) {
      count += 1;
    } else if (!positive && delta < 0) {
      count += 1;
    }
  }
  return count;
}

String? _readStringArg(List<String> args, String name) {
  final int index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

int? _readIntArg(List<String> args, String name) {
  final String? raw = _readStringArg(args, name);
  if (raw == null) {
    return null;
  }
  return int.tryParse(raw);
}

class _ScanOptions {
  const _ScanOptions({
    required this.host,
    required this.port,
    required this.unitId,
    required this.start,
    required this.count,
    required this.samples,
    required this.intervalMs,
    required this.timeoutMs,
    required this.showAll,
    required this.csv,
    required this.outPath,
  }) : validationError = null;

  const _ScanOptions.invalid(this.validationError)
    : host = '',
      port = 0,
      unitId = 0,
      start = 0,
      count = 0,
      samples = 0,
      intervalMs = 0,
      timeoutMs = 0,
      showAll = false,
      csv = false,
      outPath = '';

  final String host;
  final int port;
  final int unitId;
  final int start;
  final int count;
  final int samples;
  final int intervalMs;
  final int timeoutMs;
  final bool showAll;
  final bool csv;
  final String outPath;
  final String? validationError;

  bool get hasValidationError => validationError != null;
}

class _SampleRecord {
  const _SampleRecord({
    required this.sampleIndex,
    required this.timestamp,
    required this.values,
  });

  final int sampleIndex;
  final DateTime timestamp;
  final List<int> values;
}

class _RegisterChange {
  const _RegisterChange({
    required this.address,
    required this.before,
    required this.after,
  });

  final int address;
  final int before;
  final int after;
}

class _RegisterAnalysis {
  const _RegisterAnalysis({
    required this.address,
    required this.initialValue,
    required this.lastValue,
    required this.minValue,
    required this.maxValue,
    required this.changes,
    required this.distinctValues,
    required this.suspectedPattern,
  });

  final int address;
  final int initialValue;
  final int lastValue;
  final int minValue;
  final int maxValue;
  final int changes;
  final List<int> distinctValues;
  final String suspectedPattern;
}
