import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:agro_data_control_backend/src/modbus_tcp_client.dart';

const String _defaultHost = '192.168.10.51';
const int _defaultPort = 502;
const int _defaultUnitId = 1;
const int _defaultHrStart = 0;
const int _defaultHrCount = 80;
const int _defaultCoilStart = 0;
const int _defaultCoilCount = 80;
const int _defaultDiStart = 0;
const int _defaultDiCount = 40;
const int _defaultSamples = 120;
const int _defaultIntervalMs = 500;
const int _defaultTimeoutMs = 3000;
const String _defaultOutPath = 'backend/tmp/modbus_activity_scan.csv';

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

  final List<_SampleRecord> samples = <_SampleRecord>[];
  _SampleValues? previous;

  try {
    _printEffectiveParameters(options);
    await client.connect();
    stdout.writeln('Conexion OK.');

    for (int sampleIndex = 0; sampleIndex < options.samples; sampleIndex += 1) {
      final int sampleNumber = sampleIndex + 1;
      final DateTime timestamp = DateTime.now();
      final _SampleValues values = await _readAreasForSample(
        client: client,
        options: options,
        sampleNumber: sampleNumber,
      );

      if (!values.hasAnyData && sampleIndex == 0) {
        stderr.writeln(
          'No se pudo leer ninguna area en la primera muestra. Abortando.',
        );
        exitCode = 1;
        return;
      }

      final List<String> changes = _describeChanges(
        options: options,
        previous: previous,
        current: values,
      );

      if (changes.isEmpty) {
        stdout.writeln('[sample $sampleNumber/${options.samples}] changed=0');
      } else {
        stdout.writeln(
          '[sample $sampleNumber/${options.samples}] '
          'changed=${changes.length} signals: ${changes.join(', ')}',
        );
      }

      samples.add(
        _SampleRecord(
          sampleIndex: sampleIndex,
          timestamp: timestamp,
          values: values,
        ),
      );
      previous = values;

      if (sampleNumber < options.samples) {
        await Future<void>.delayed(Duration(milliseconds: options.intervalMs));
      }
    }

    final _AnalysisBundle analysis = analyzeSeries(
      options: options,
      samples: samples,
    );

    stdout.writeln('');
    printSummary(
      title: 'Holding Registers',
      prefix: 'HR',
      analysis: analysis.holdingRegisters,
      showAll: options.showAll,
      enabled: options.hrEnabled,
    );
    stdout.writeln('');
    printSummary(
      title: 'Coils',
      prefix: 'COIL',
      analysis: analysis.coils,
      showAll: options.showAll,
      enabled: options.coilEnabled,
    );
    stdout.writeln('');
    printSummary(
      title: 'Discrete Inputs',
      prefix: 'DI',
      analysis: analysis.discreteInputs,
      showAll: options.showAll,
      enabled: options.diEnabled,
    );
    stdout.writeln('');
    _printTopActivityCandidates(analysis);

    if (options.csv) {
      await exportCsv(samples: samples, options: options);
      stdout.writeln('');
      stdout.writeln('CSV exportado en ${options.outPath}');
    }
  } on SocketException catch (error) {
    stderr.writeln(
      'Error de conexion al PLC (${options.host}:${options.port}): ${error.message}',
    );
    exitCode = 1;
  } on TimeoutException {
    stderr.writeln(
      'Error de conexion al PLC (${options.host}:${options.port}): timeout al conectar o leer.',
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
    await client.close(reason: 'logo_scan_modbus_activity_done');
  }
}

_ScanOptions parseArgs(List<String> args) {
  final String host = _readStringArg(args, '--host') ?? _defaultHost;
  final int port = _readIntArg(args, '--port') ?? _defaultPort;
  final int unitId = _readIntArg(args, '--unit-id') ?? _defaultUnitId;
  final int hrStart = _readIntArg(args, '--hr-start') ?? _defaultHrStart;
  final int hrCount = _readIntArg(args, '--hr-count') ?? _defaultHrCount;
  final int coilStart = _readIntArg(args, '--coil-start') ?? _defaultCoilStart;
  final int coilCount = _readIntArg(args, '--coil-count') ?? _defaultCoilCount;
  final int diStart = _readIntArg(args, '--di-start') ?? _defaultDiStart;
  final int diCount = _readIntArg(args, '--di-count') ?? _defaultDiCount;
  final int samples = _readIntArg(args, '--samples') ?? _defaultSamples;
  final int intervalMs =
      _readIntArg(args, '--interval-ms') ?? _defaultIntervalMs;
  final int timeoutMs = _readIntArg(args, '--timeout-ms') ?? _defaultTimeoutMs;
  final bool csv = args.contains('--csv');
  final bool showAll = args.contains('--show-all');
  final String outPath = _readStringArg(args, '--out') ?? _defaultOutPath;

  if (port <= 0 || port > 65535) {
    return _ScanOptions.invalid('Error: --port fuera de rango.');
  }
  if (unitId < 0 || unitId > 255) {
    return _ScanOptions.invalid('Error: --unit-id debe estar entre 0 y 255.');
  }
  if (!_isValidRange(hrStart, hrCount)) {
    return _ScanOptions.invalid(
      'Error: --hr-start debe ser >= 0 y --hr-count >= 0.',
    );
  }
  if (!_isValidRange(coilStart, coilCount)) {
    return _ScanOptions.invalid(
      'Error: --coil-start debe ser >= 0 y --coil-count >= 0.',
    );
  }
  if (!_isValidRange(diStart, diCount)) {
    return _ScanOptions.invalid(
      'Error: --di-start debe ser >= 0 y --di-count >= 0.',
    );
  }
  if (hrCount == 0 && coilCount == 0 && diCount == 0) {
    return _ScanOptions.invalid(
      'ERROR: al menos una area debe tener count > 0',
    );
  }
  if (samples <= 0) {
    return _ScanOptions.invalid('Error: --samples debe ser > 0.');
  }
  if (intervalMs <= 0 || timeoutMs <= 0) {
    return _ScanOptions.invalid(
      'Error: --interval-ms y --timeout-ms deben ser positivos.',
    );
  }

  return _ScanOptions(
    host: host,
    port: port,
    unitId: unitId,
    hrStart: hrStart,
    hrCount: hrCount,
    coilStart: coilStart,
    coilCount: coilCount,
    diStart: diStart,
    diCount: diCount,
    samples: samples,
    intervalMs: intervalMs,
    timeoutMs: timeoutMs,
    csv: csv,
    outPath: outPath,
    showAll: showAll,
  );
}

Future<_SampleValues> _readAreasForSample({
  required ModbusTcpClient client,
  required _ScanOptions options,
  required int sampleNumber,
}) async {
  List<int>? holdingValues;
  List<bool>? coilValues;
  List<bool>? discreteValues;

  if (options.hrEnabled) {
    try {
      holdingValues = await readHoldingRange(
        client: client,
        start: options.hrStart,
        count: options.hrCount,
      );
    } on Object catch (error) {
      stderr.writeln(
        '[sample $sampleNumber/${options.samples}] '
        'HR read error (${options.hrStart}..${options.hrStart + options.hrCount - 1}): '
        '${_formatReadError(error)}',
      );
    }
  }

  if (options.coilEnabled) {
    try {
      coilValues = await readCoilRange(
        client: client,
        start: options.coilStart,
        count: options.coilCount,
      );
    } on Object catch (error) {
      stderr.writeln(
        '[sample $sampleNumber/${options.samples}] '
        'COIL read error (${options.coilStart}..${options.coilStart + options.coilCount - 1}): '
        '${_formatReadError(error)}',
      );
    }
  }

  if (options.diEnabled) {
    try {
      discreteValues = await readDiscreteInputRange(
        client: client,
        start: options.diStart,
        count: options.diCount,
      );
    } on Object catch (error) {
      stderr.writeln(
        '[sample $sampleNumber/${options.samples}] '
        'DI read error (${options.diStart}..${options.diStart + options.diCount - 1}): '
        '${_formatReadError(error)}',
      );
    }
  }

  return _SampleValues(
    holdingRegisters: holdingValues,
    coils: coilValues,
    discreteInputs: discreteValues,
  );
}

Future<List<int>> readHoldingRange({
  required ModbusTcpClient client,
  required int start,
  required int count,
}) {
  return client.readHoldingRegisters(
    start,
    count,
    operationLabel: 'logo_scan_modbus_activity.hr@$start/$count',
  );
}

Future<List<bool>> readCoilRange({
  required ModbusTcpClient client,
  required int start,
  required int count,
}) {
  return client.readCoils(
    start,
    count,
    operationLabel: 'logo_scan_modbus_activity.coil@$start/$count',
  );
}

Future<List<bool>> readDiscreteInputRange({
  required ModbusTcpClient client,
  required int start,
  required int count,
}) {
  return client.readDiscreteInputs(
    start,
    count,
    operationLabel: 'logo_scan_modbus_activity.di@$start/$count',
  );
}

_AnalysisBundle analyzeSeries({
  required _ScanOptions options,
  required List<_SampleRecord> samples,
}) {
  return _AnalysisBundle(
    holdingRegisters: options.hrEnabled
        ? _analyzeArea<int>(
            area: _SignalArea.holdingRegister,
            startAddress: options.hrStart,
            expectedCount: options.hrCount,
            samples: samples,
            extractor: (_SampleValues values) => values.holdingRegisters,
          )
        : const <_SignalAnalysis>[],
    coils: options.coilEnabled
        ? _analyzeArea<bool>(
            area: _SignalArea.coil,
            startAddress: options.coilStart,
            expectedCount: options.coilCount,
            samples: samples,
            extractor: (_SampleValues values) => values.coils,
          )
        : const <_SignalAnalysis>[],
    discreteInputs: options.diEnabled
        ? _analyzeArea<bool>(
            area: _SignalArea.discreteInput,
            startAddress: options.diStart,
            expectedCount: options.diCount,
            samples: samples,
            extractor: (_SampleValues values) => values.discreteInputs,
          )
        : const <_SignalAnalysis>[],
  );
}

List<_SignalAnalysis> _analyzeArea<T>({
  required _SignalArea area,
  required int startAddress,
  required int expectedCount,
  required List<_SampleRecord> samples,
  required List<T>? Function(_SampleValues values) extractor,
}) {
  final List<_SignalAnalysis> result = <_SignalAnalysis>[];

  for (int offset = 0; offset < expectedCount; offset += 1) {
    final List<T> observedValues = <T>[];
    for (final _SampleRecord sample in samples) {
      final List<T>? values = extractor(sample.values);
      if (values == null || offset >= values.length) {
        continue;
      }
      observedValues.add(values[offset]);
    }

    if (observedValues.isEmpty) {
      result.add(
        _SignalAnalysis.empty(area: area, address: startAddress + offset),
      );
      continue;
    }

    final LinkedHashSet<String> distinctText = LinkedHashSet<String>.from(
      observedValues.map((value) => value.toString()),
    );

    int changes = 0;
    for (int index = 1; index < observedValues.length; index += 1) {
      if (observedValues[index] != observedValues[index - 1]) {
        changes += 1;
      }
    }

    final List<int>? numericValues = observedValues.first is int
        ? observedValues.cast<int>()
        : null;

    result.add(
      _SignalAnalysis(
        area: area,
        address: startAddress + offset,
        initialValue: observedValues.first.toString(),
        lastValue: observedValues.last.toString(),
        minValue: numericValues == null
            ? null
            : numericValues
                  .reduce((left, right) => left < right ? left : right)
                  .toString(),
        maxValue: numericValues == null
            ? null
            : numericValues
                  .reduce((left, right) => left > right ? left : right)
                  .toString(),
        changes: changes,
        distinctValues: distinctText.toList(growable: false),
        suspectedPattern: inferPattern(
          rawValues: observedValues.map((value) => value.toString()).toList(),
          numericValues: numericValues,
          changes: changes,
          distinctCount: distinctText.length,
        ),
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
  required List<String> rawValues,
  required List<int>? numericValues,
  required int changes,
  required int distinctCount,
}) {
  if (changes == 0) {
    return 'stable';
  }

  if (distinctCount <= 2 && changes >= 2) {
    return 'possible_toggle';
  }

  if (numericValues != null) {
    final int positiveSteps = _countNumericDirection(
      numericValues,
      positive: true,
    );
    final int negativeSteps = _countNumericDirection(
      numericValues,
      positive: false,
    );

    if (positiveSteps >= negativeSteps * 2 &&
        distinctCount >= 3 &&
        changes >= 2) {
      return 'possible_counter';
    }

    if (distinctCount >= 5 || (positiveSteps > 0 && negativeSteps > 0)) {
      return 'dynamic';
    }
  } else if (distinctCount >= 3) {
    return 'dynamic';
  }

  if (distinctCount <= 4 && changes >= 2) {
    return 'possible_toggle';
  }

  return 'stable';
}

void printSummary({
  required String title,
  required String prefix,
  required List<_SignalAnalysis> analysis,
  required bool showAll,
  required bool enabled,
}) {
  stdout.writeln(title);
  if (!enabled) {
    stdout.writeln('Area disabled');
    return;
  }
  stdout.writeln(
    'address | initial | last | min | max | changes | distinctValues | suspectedPattern',
  );
  stdout.writeln(
    '------- | ------- | ---- | --- | --- | ------- | -------------- | ----------------',
  );

  final Iterable<_SignalAnalysis> visible = showAll
      ? analysis
      : analysis.where((item) => item.changes > 0);

  int printed = 0;
  for (final _SignalAnalysis item in visible) {
    printed += 1;
    stdout.writeln(
      '${prefix.padRight(4)} ${item.address.toString().padLeft(3)}'
      ' | ${item.initialValue.padLeft(7)}'
      ' | ${item.lastValue.padLeft(4)}'
      ' | ${(item.minValue ?? '-').padLeft(3)}'
      ' | ${(item.maxValue ?? '-').padLeft(3)}'
      ' | ${item.changes.toString().padLeft(7)}'
      ' | ${_formatDistinctValues(item.distinctValues).padRight(14)}'
      ' | ${item.suspectedPattern}',
    );
  }

  if (printed == 0) {
    stdout.writeln('No se detectaron cambios en esta area.');
  }
}

Future<void> exportCsv({
  required List<_SampleRecord> samples,
  required _ScanOptions options,
}) async {
  final File outFile = File(options.outPath);
  await outFile.parent.create(recursive: true);

  final StringBuffer buffer = StringBuffer();
  buffer.write('sampleIndex,timestamp');
  for (int offset = 0; offset < options.hrCount; offset += 1) {
    buffer.write(',HR${options.hrStart + offset}');
  }
  for (int offset = 0; offset < options.coilCount; offset += 1) {
    buffer.write(',COIL${options.coilStart + offset}');
  }
  for (int offset = 0; offset < options.diCount; offset += 1) {
    buffer.write(',DI${options.diStart + offset}');
  }
  buffer.writeln();

  for (final _SampleRecord sample in samples) {
    buffer.write('${sample.sampleIndex},${sample.timestamp.toIso8601String()}');
    _appendAreaCsv(
      buffer: buffer,
      values: sample.values.holdingRegisters,
      expectedCount: options.hrCount,
    );
    _appendAreaCsv(
      buffer: buffer,
      values: sample.values.coils,
      expectedCount: options.coilCount,
    );
    _appendAreaCsv(
      buffer: buffer,
      values: sample.values.discreteInputs,
      expectedCount: options.diCount,
    );
    buffer.writeln();
  }

  await outFile.writeAsString(buffer.toString());
}

void _appendAreaCsv<T>({
  required StringBuffer buffer,
  required List<T>? values,
  required int expectedCount,
}) {
  for (int index = 0; index < expectedCount; index += 1) {
    if (values == null || index >= values.length) {
      buffer.write(',');
    } else {
      buffer.write(',${values[index]}');
    }
  }
}

List<String> _describeChanges({
  required _ScanOptions options,
  required _SampleValues? previous,
  required _SampleValues current,
}) {
  if (previous == null) {
    return const <String>[];
  }

  final List<String> changes = <String>[];
  changes.addAll(
    _collectAreaChanges<int>(
      previous: previous.holdingRegisters,
      current: current.holdingRegisters,
      startAddress: options.hrStart,
      labelBuilder: (int address, int before, int after) =>
          'HR$address $before->$after',
    ),
  );
  changes.addAll(
    _collectAreaChanges<bool>(
      previous: previous.coils,
      current: current.coils,
      startAddress: options.coilStart,
      labelBuilder: (int address, bool before, bool after) =>
          'COIL$address $before->$after',
    ),
  );
  changes.addAll(
    _collectAreaChanges<bool>(
      previous: previous.discreteInputs,
      current: current.discreteInputs,
      startAddress: options.diStart,
      labelBuilder: (int address, bool before, bool after) =>
          'DI$address $before->$after',
    ),
  );
  return changes;
}

List<String> _collectAreaChanges<T>({
  required List<T>? previous,
  required List<T>? current,
  required int startAddress,
  required String Function(int address, T before, T after) labelBuilder,
}) {
  if (previous == null || current == null) {
    return const <String>[];
  }

  final int safeCount = previous.length < current.length
      ? previous.length
      : current.length;
  final List<String> changes = <String>[];
  for (int index = 0; index < safeCount; index += 1) {
    final T before = previous[index];
    final T after = current[index];
    if (before != after) {
      changes.add(labelBuilder(startAddress + index, before, after));
    }
  }
  return changes;
}

void _printTopActivityCandidates(_AnalysisBundle analysis) {
  stdout.writeln('Top activity candidates');

  final List<_SignalAnalysis> candidates =
      <_SignalAnalysis>[
        ...analysis.holdingRegisters,
        ...analysis.coils,
        ...analysis.discreteInputs,
      ]..sort((left, right) {
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
        final int byArea = left.area.name.compareTo(right.area.name);
        if (byArea != 0) {
          return byArea;
        }
        return left.address.compareTo(right.address);
      });

  final List<_SignalAnalysis> top = candidates
      .where((item) => item.changes > 0)
      .take(10)
      .toList(growable: false);

  if (top.isEmpty) {
    stdout.writeln(
      '  No se detecto actividad significativa. Proba aumentar --samples o ampliar rangos.',
    );
    return;
  }

  for (final _SignalAnalysis item in top) {
    stdout.writeln(
      '  ${item.area.displayName} ${item.address}: '
      'pattern=${item.suspectedPattern} '
      'changes=${item.changes} '
      'distinct=${item.distinctValues.length} '
      'values=${_formatDistinctValues(item.distinctValues)}',
    );
  }
}

void _printEffectiveParameters(_ScanOptions options) {
  stdout.writeln('Logo scan modbus activity');
  stdout.writeln('host=${options.host}');
  stdout.writeln('port=${options.port}');
  stdout.writeln('unitId=${options.unitId}');
  stdout.writeln('hrStart=${options.hrStart} hrCount=${options.hrCount}');
  if (!options.hrEnabled) {
    stdout.writeln('HR scan disabled');
  }
  stdout.writeln(
    'coilStart=${options.coilStart} coilCount=${options.coilCount}',
  );
  if (!options.coilEnabled) {
    stdout.writeln('COIL scan disabled');
  }
  stdout.writeln('diStart=${options.diStart} diCount=${options.diCount}');
  if (!options.diEnabled) {
    stdout.writeln('DI scan disabled');
  }
  stdout.writeln('samples=${options.samples}');
  stdout.writeln('intervalMs=${options.intervalMs}');
  stdout.writeln('timeoutMs=${options.timeoutMs}');
  stdout.writeln('csv=${options.csv}');
  stdout.writeln('out=${options.outPath}');
  stdout.writeln('showAll=${options.showAll}');
  stdout.writeln('');
}

String _formatReadError(Object error) {
  if (error is TimeoutException) {
    return 'timeout';
  }
  if (error is SocketException) {
    return error.message;
  }
  if (error is ModbusException) {
    return error.message;
  }
  return error.toString();
}

String _formatDistinctValues(List<String> values) {
  const int maxPreview = 8;
  if (values.isEmpty) {
    return '-';
  }
  if (values.length <= maxPreview) {
    return values.join('/');
  }
  return '${values.take(maxPreview).join('/')}...(+${values.length - maxPreview})';
}

int _countNumericDirection(List<int> values, {required bool positive}) {
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

bool _isValidRange(int start, int count) => start >= 0 && count >= 0;

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
    required this.hrStart,
    required this.hrCount,
    required this.coilStart,
    required this.coilCount,
    required this.diStart,
    required this.diCount,
    required this.samples,
    required this.intervalMs,
    required this.timeoutMs,
    required this.csv,
    required this.outPath,
    required this.showAll,
  }) : validationError = null;

  const _ScanOptions.invalid(this.validationError)
    : host = '',
      port = 0,
      unitId = 0,
      hrStart = 0,
      hrCount = 0,
      coilStart = 0,
      coilCount = 0,
      diStart = 0,
      diCount = 0,
      samples = 0,
      intervalMs = 0,
      timeoutMs = 0,
      csv = false,
      outPath = '',
      showAll = false;

  final String host;
  final int port;
  final int unitId;
  final int hrStart;
  final int hrCount;
  final int coilStart;
  final int coilCount;
  final int diStart;
  final int diCount;
  final int samples;
  final int intervalMs;
  final int timeoutMs;
  final bool csv;
  final String outPath;
  final bool showAll;
  final String? validationError;

  bool get hasValidationError => validationError != null;
  bool get hrEnabled => hrCount > 0;
  bool get coilEnabled => coilCount > 0;
  bool get diEnabled => diCount > 0;
}

class _SampleRecord {
  const _SampleRecord({
    required this.sampleIndex,
    required this.timestamp,
    required this.values,
  });

  final int sampleIndex;
  final DateTime timestamp;
  final _SampleValues values;
}

class _SampleValues {
  const _SampleValues({
    required this.holdingRegisters,
    required this.coils,
    required this.discreteInputs,
  });

  final List<int>? holdingRegisters;
  final List<bool>? coils;
  final List<bool>? discreteInputs;

  bool get hasAnyData =>
      holdingRegisters != null || coils != null || discreteInputs != null;
}

class _AnalysisBundle {
  const _AnalysisBundle({
    required this.holdingRegisters,
    required this.coils,
    required this.discreteInputs,
  });

  final List<_SignalAnalysis> holdingRegisters;
  final List<_SignalAnalysis> coils;
  final List<_SignalAnalysis> discreteInputs;
}

enum _SignalArea {
  holdingRegister('HR'),
  coil('COIL'),
  discreteInput('DI');

  const _SignalArea(this.displayName);

  final String displayName;
}

class _SignalAnalysis {
  const _SignalAnalysis({
    required this.area,
    required this.address,
    required this.initialValue,
    required this.lastValue,
    required this.minValue,
    required this.maxValue,
    required this.changes,
    required this.distinctValues,
    required this.suspectedPattern,
  });

  factory _SignalAnalysis.empty({
    required _SignalArea area,
    required int address,
  }) {
    return _SignalAnalysis(
      area: area,
      address: address,
      initialValue: '-',
      lastValue: '-',
      minValue: null,
      maxValue: null,
      changes: 0,
      distinctValues: const <String>[],
      suspectedPattern: 'stable',
    );
  }

  final _SignalArea area;
  final int address;
  final String initialValue;
  final String lastValue;
  final String? minValue;
  final String? maxValue;
  final int changes;
  final List<String> distinctValues;
  final String suspectedPattern;
}
