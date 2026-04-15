import 'dart:async';
import 'dart:io';

import 'package:agro_data_control_backend/src/modbus_tcp_client.dart';

const String _defaultHost = '192.168.10.51';
const int _defaultPort = 502;
const int _defaultUnitId = 1;
const int _maxColumns = 10;
const Duration _defaultTimeout = Duration(seconds: 3);
const Duration _defaultInterval = Duration(seconds: 1);

const List<_AnalogSignal> _analogSignals = <_AnalogSignal>[
  _AnalogSignal(
    name: 'tempInterior',
    label: 'Temperatura interior',
    vm: 90,
    hr: 45,
    interpretation: _AnalogInterpretation.signed16,
  ),
  _AnalogSignal(
    name: 'humInterior',
    label: 'Humedad interior',
    vm: 106,
    hr: 53,
    interpretation: _AnalogInterpretation.signed16,
  ),
  _AnalogSignal(
    name: 'tempExterior',
    label: 'Temperatura exterior',
    vm: 122,
    hr: 61,
    interpretation: _AnalogInterpretation.signed16,
  ),
  _AnalogSignal(
    name: 'humExterior',
    label: 'Humedad exterior',
    vm: 138,
    hr: 69,
    interpretation: _AnalogInterpretation.signed16,
  ),
  _AnalogSignal(
    name: 'presionDiferencial',
    label: 'Presion diferencial',
    vm: 154,
    hr: 77,
    interpretation: _AnalogInterpretation.signed16,
  ),
  _AnalogSignal(
    name: 'tensionSalidaVentiladores',
    label: 'Tension salida ventiladores',
    vm: 170,
    hr: 85,
    interpretation: _AnalogInterpretation.rawNum,
  ),
];

const List<_BitSignal> _coilSignals = <_BitSignal>[
  _BitSignal(
    name: 'fanQ5',
    label: 'Fan Q5',
    address: 8,
    alias: 'NQ1',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'fanQ6',
    label: 'Fan Q6',
    address: 16,
    alias: 'NQ2',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'fanQ7',
    label: 'Fan Q7',
    address: 24,
    alias: 'NQ3',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'fanQ8',
    label: 'Fan Q8',
    address: 32,
    alias: 'NQ4',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'fanQ9',
    label: 'Fan Q9',
    address: 40,
    alias: 'NQ5',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'fanQ10',
    label: 'Fan Q10',
    address: 48,
    alias: 'NQ6',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'alarmaGeneral',
    label: 'Alarma general',
    address: 64,
    alias: 'NQ8',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'bombaHumidificador',
    label: 'Bomba humidificador',
    address: 192,
    alias: 'NQ11',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'resistencia1',
    label: 'Resistencia 1',
    address: 200,
    alias: 'NQ12',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'resistencia2',
    label: 'Resistencia 2',
    address: 208,
    alias: 'NQ13',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'nivelAguaAlarma',
    label: 'Nivel de agua / alarma',
    address: 216,
    alias: 'NQ14',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'fallaTermicaBomba',
    label: 'Falla termica bomba',
    address: 240,
    alias: 'NQ15',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'salaAbierta',
    label: 'Puerta sala',
    address: 224,
    alias: 'NQ9',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'munterAbierto',
    label: 'Puerta munter',
    address: 232,
    alias: 'NQ10',
    kind: _BitKind.coil,
  ),
  _BitSignal(
    name: 'fallaRed',
    label: 'Falla red',
    address: 1,
    alias: 'DI1',
    kind: _BitKind.discreteInput,
  ),
];

const List<String> _snapshotOnlyFields = <String>[
  'eventosSinAgua',
  'horasMunter',
  'horasFiltroF9',
  'horasFiltroG4',
  'horasPolifosfato',
  'aperturasSala',
  'aperturasMunter',
  'cantidadApagadas',
  'estadoEquipo',
];

Future<void> main(List<String> args) async {
  final String host = _readStringArg(args, '--host') ?? _defaultHost;
  final int port = _readIntArg(args, '--port') ?? _defaultPort;
  final int unitId = _readIntArg(args, '--unit') ?? _defaultUnitId;
  final int timeoutMs =
      _readIntArg(args, '--timeout-ms') ?? _defaultTimeout.inMilliseconds;
  final int intervalMs =
      _readIntArg(args, '--interval-ms') ?? _defaultInterval.inMilliseconds;
  final bool once = args.contains('--once');
  final bool noClear = args.contains('--no-clear');
  final bool help = args.contains('--help') || args.contains('-h');

  if (help) {
    stdout.writeln('''
Uso:
  dart run scripts/test_bomba.dart [--host 192.168.10.51] [--port 502] [--unit 1]

Opciones:
  --host          IP del PLC
  --port          Puerto Modbus TCP
  --unit          Unit ID Modbus
  --timeout-ms    Timeout por operacion
  --interval-ms   Intervalo de refresco
  --once          Hace una sola lectura y sale
  --no-clear      No limpia la pantalla entre refrescos
''');
    return;
  }

  final ModbusTcpClient client = ModbusTcpClient(
    host: host,
    port: port,
    unitId: unitId,
    timeout: Duration(milliseconds: timeoutMs),
  );

  bool cursorHidden = false;
  final List<_ScreenSnapshot> history = <_ScreenSnapshot>[];
  final Map<String, int> changeCountdowns = <String, int>{};

  Future<void> restoreCursor() async {
    if (cursorHidden) {
      stdout.write('\x1B[?25h');
      cursorHidden = false;
    }
  }

  ProcessSignal.sigint.watch().listen((_) async {
    await restoreCursor();
    stdout.writeln('\nInterrumpido por usuario. Cerrando conexion...');
    await client.close(reason: 'sigint');
    exit(0);
  });

  try {
    if (!noClear) {
      stdout.write('\x1B[?25l');
      cursorHidden = true;
    }

    await client.connect();

    do {
      final DateTime now = DateTime.now();
      final _ScreenData data = await _readScreenData(client);
      _updateChangeCountdowns(
        previous: history.isNotEmpty ? history.last.data : null,
        current: data,
        countdowns: changeCountdowns,
      );
      history.add(_ScreenSnapshot(timestamp: now, data: data));
      if (history.length > _maxColumns) {
        history.removeAt(0);
      }
      _renderScreen(
        now: now,
        host: host,
        port: port,
        unitId: unitId,
        history: history,
        changeCountdowns: changeCountdowns,
        clearScreen: !noClear,
      );

      _tickCountdowns(changeCountdowns);

      if (once) {
        break;
      }
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    } while (true);
  } on SocketException catch (error) {
    await restoreCursor();
    stderr.writeln('Error de conexion al PLC ($host:$port): ${error.message}');
    exitCode = 1;
  } on TimeoutException {
    await restoreCursor();
    stderr.writeln(
      'Error de conexion al PLC ($host:$port): timeout al conectar o leer.',
    );
    exitCode = 1;
  } on ModbusException catch (error) {
    await restoreCursor();
    stderr.writeln('Error Modbus: ${error.message}');
    exitCode = 1;
  } catch (error) {
    await restoreCursor();
    stderr.writeln('Error inesperado: $error');
    exitCode = 1;
  } finally {
    await restoreCursor();
    await client.close(reason: 'test_bomba_done');
  }
}

Future<_ScreenData> _readScreenData(ModbusTcpClient client) async {
  final int minHr = _analogSignals
      .map((signal) => signal.hr)
      .reduce((left, right) => left < right ? left : right);
  final int maxHr = _analogSignals
      .map((signal) => signal.hr)
      .reduce((left, right) => left > right ? left : right);
  final List<int> holdingBlock = await client.readHoldingRegisters(
    minHr,
    (maxHr - minHr) + 1,
    operationLabel: 'test_bomba_holding@$minHr/${(maxHr - minHr) + 1}',
  );

  final List<_AnalogValue> analogValues = _analogSignals.map((signal) {
    final int raw = holdingBlock[signal.hr - minHr];
    return _AnalogValue(
      signal: signal,
      raw: raw,
      interpreted: signal.interpret(raw),
    );
  }).toList(growable: false);

  final Map<int, bool> coilValues = <int, bool>{};
  final List<_BitSignal> onlyCoils = _coilSignals
      .where((signal) => signal.kind == _BitKind.coil)
      .toList(growable: false);
  final List<_BitSignal> onlyDiscreteInputs = _coilSignals
      .where((signal) => signal.kind == _BitKind.discreteInput)
      .toList(growable: false);

  if (onlyCoils.isNotEmpty) {
    final int minCoil = onlyCoils
        .map((signal) => signal.address)
        .reduce((left, right) => left < right ? left : right);
    final int maxCoil = onlyCoils
        .map((signal) => signal.address)
        .reduce((left, right) => left > right ? left : right);
    final List<bool> coilBlock = await client.readCoils(
      minCoil,
      (maxCoil - minCoil) + 1,
      operationLabel: 'test_bomba_coils@$minCoil/${(maxCoil - minCoil) + 1}',
    );
    for (final _BitSignal signal in onlyCoils) {
      coilValues[signal.address] = coilBlock[signal.address - minCoil];
    }
  }

  final Map<int, bool> discreteInputValues = <int, bool>{};
  if (onlyDiscreteInputs.isNotEmpty) {
    final int minInput = onlyDiscreteInputs
        .map((signal) => signal.address)
        .reduce((left, right) => left < right ? left : right);
    final int maxInput = onlyDiscreteInputs
        .map((signal) => signal.address)
        .reduce((left, right) => left > right ? left : right);
    final List<bool> inputBlock = await client.readDiscreteInputs(
      minInput,
      (maxInput - minInput) + 1,
      operationLabel:
          'test_bomba_discrete@$minInput/${(maxInput - minInput) + 1}',
    );
    for (final _BitSignal signal in onlyDiscreteInputs) {
      discreteInputValues[signal.address] = inputBlock[signal.address - minInput];
    }
  }

  final List<_BitValue> bitValues = _coilSignals.map((signal) {
    return _BitValue(
      signal: signal,
      value: signal.kind == _BitKind.coil
          ? coilValues[signal.address]
          : discreteInputValues[signal.address],
    );
  }).toList(growable: false);

  return _ScreenData(analogValues: analogValues, bitValues: bitValues);
}

void _renderScreen({
  required DateTime now,
  required String host,
  required int port,
  required int unitId,
  required List<_ScreenSnapshot> history,
  required Map<String, int> changeCountdowns,
  required bool clearScreen,
}) {
  if (clearScreen) {
    stdout.write('\x1B[2J\x1B[H');
  }

  stdout.writeln('TEST BOMBA / VERIFICACION DE MAPEOS');
  stdout.writeln(
    'PLC $host:$port  unitId=$unitId  ${_formatTimestamp(now)}',
  );
  stdout.writeln(
    'Historial horizontal: ${history.length}/$_maxColumns columnas',
  );
  stdout.writeln('');
  stdout.writeln('Analogicos directos');
  _writeHistoryHeader(history);
  for (final _AnalogSignal signal in _analogSignals) {
    final List<_AnalogValue> series = history
        .map(
          (snapshot) => snapshot.data.analogValues
              .firstWhere((value) => value.signal.name == signal.name),
        )
        .toList(growable: false);
    final List<String> values =
        series.map((value) => value.interpretedLabel).toList(growable: false);
    _writeHistoryRow(
      label: _labelWithCountdown(signal.name, changeCountdowns[signal.name]),
      metadata: 'NAQ${signal.naq} HR${signal.hr}/VW${signal.vm}',
      values: values,
      changed: _computeAnalogChanges(series),
    );
  }

  stdout.writeln('');
  stdout.writeln('Bits directos');
  _writeHistoryHeader(history);
  for (final _BitSignal signal in _coilSignals) {
    final List<_BitValue> series = history
        .map(
          (snapshot) => snapshot.data.bitValues
              .firstWhere((value) => value.signal.name == signal.name),
        )
        .toList(growable: false);
    final List<String> values =
        series.map((value) => value.compactStatusLabel).toList(growable: false);
    _writeHistoryRow(
      label: _labelWithCountdown(signal.name, changeCountdowns[signal.name]),
      metadata: '${signal.alias} ${signal.kindLabelAndAddress}',
      values: values,
      changed: _computeBitChanges(series),
    );
  }

  stdout.writeln('');
  stdout.writeln('Campos usados por frontend sin direccion Modbus configurada en default.json');
  for (final String field in _snapshotOnlyFields) {
    stdout.writeln('  - $field');
  }

  stdout.writeln('');
  stdout.writeln(
    'Notas: los analogicos se interpretan igual que el frontend actual; '
    'tensionSalidaVentiladores usa HR85/VW170.',
  );
  stdout.writeln('Marca: `*` indica cambio respecto de la columna anterior.');
  stdout.writeln('Nombre con `*10..1`: cambio reciente persistente por 10 ciclos.');
  stdout.writeln('Ctrl+C para salir.');
}

String _formatTimestamp(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';
}

String _pad(String value, int width) {
  if (value.length >= width) {
    return value.substring(0, width);
  }
  return value.padRight(width);
}

String _labelWithCountdown(String name, int? countdown) {
  if (countdown == null || countdown <= 0) {
    return name;
  }
  return '$name *$countdown';
}

void _updateChangeCountdowns({
  required _ScreenData? previous,
  required _ScreenData current,
  required Map<String, int> countdowns,
}) {
  if (previous == null) {
    return;
  }

  for (final _AnalogValue value in current.analogValues) {
    final _AnalogValue previousValue = previous.analogValues.firstWhere(
      (item) => item.signal.name == value.signal.name,
    );
    if (value.raw != previousValue.raw) {
      countdowns[value.signal.name] = 10;
    }
  }

  for (final _BitValue value in current.bitValues) {
    final _BitValue previousValue = previous.bitValues.firstWhere(
      (item) => item.signal.name == value.signal.name,
    );
    if (value.value != previousValue.value) {
      countdowns[value.signal.name] = 10;
    }
  }
}

void _tickCountdowns(Map<String, int> countdowns) {
  final List<String> keys = countdowns.keys.toList(growable: false);
  for (final String key in keys) {
    final int nextValue = (countdowns[key] ?? 0) - 1;
    if (nextValue <= 0) {
      countdowns.remove(key);
    } else {
      countdowns[key] = nextValue;
    }
  }
}

List<bool> _computeAnalogChanges(List<_AnalogValue> values) {
  final List<bool> changed = List<bool>.filled(values.length, false);
  for (int index = 1; index < values.length; index += 1) {
    changed[index] = values[index].raw != values[index - 1].raw;
  }
  return changed;
}

List<bool> _computeBitChanges(List<_BitValue> values) {
  final List<bool> changed = List<bool>.filled(values.length, false);
  for (int index = 1; index < values.length; index += 1) {
    changed[index] = values[index].value != values[index - 1].value;
  }
  return changed;
}

void _writeHistoryHeader(List<_ScreenSnapshot> history) {
  final StringBuffer header = StringBuffer(
    '${_pad('Campo', 24)} ${_pad('Mapa', 18)}',
  );
  for (int index = 0; index < history.length; index += 1) {
    header.write(' ${_pad('C${index + 1}', 6)}');
  }
  stdout.writeln(header.toString());
}

void _writeHistoryRow({
  required String label,
  required String metadata,
  required List<String> values,
  required List<bool> changed,
}) {
  final StringBuffer row = StringBuffer(
    '${_pad(label, 24)} ${_pad(metadata, 18)}',
  );
  for (int index = 0; index < values.length; index += 1) {
    final String value = changed[index] ? '*${values[index]}' : values[index];
    row.write(' ${_pad(value, 6)}');
  }
  stdout.writeln(row.toString());
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

enum _AnalogInterpretation { signed16, rawNum }

class _AnalogSignal {
  const _AnalogSignal({
    required this.name,
    required this.label,
    required this.vm,
    required this.hr,
    required this.interpretation,
  });

  final String name;
  final String label;
  final int vm;
  final int hr;
  final _AnalogInterpretation interpretation;

  int get naq => ((vm - 90) ~/ 16) + 1;

  double interpret(int raw) {
    return switch (interpretation) {
      _AnalogInterpretation.signed16 => _toSigned16(raw).toDouble(),
      _AnalogInterpretation.rawNum => raw.toDouble(),
    };
  }
}

class _AnalogValue {
  const _AnalogValue({
    required this.signal,
    required this.raw,
    required this.interpreted,
  });

  final _AnalogSignal signal;
  final int raw;
  final double interpreted;

  String get interpretedLabel {
    return signal.interpretation == _AnalogInterpretation.rawNum
        ? interpreted.toStringAsFixed(0)
        : interpreted.toStringAsFixed(1);
  }
}

enum _BitKind { coil, discreteInput }

class _BitSignal {
  const _BitSignal({
    required this.name,
    required this.label,
    required this.address,
    required this.alias,
    required this.kind,
  });

  final String name;
  final String label;
  final int address;
  final String alias;
  final _BitKind kind;

  String get kindLabelAndAddress =>
      '${kind == _BitKind.coil ? 'coil' : 'di'} $address';
}

class _BitValue {
  const _BitValue({required this.signal, required this.value});

  final _BitSignal signal;
  final bool? value;

  String get statusLabel {
    if (value == null) {
      return 'sin dato';
    }
    return value! ? 'ON / true' : 'OFF / false';
  }

  String get compactStatusLabel {
    if (value == null) {
      return 'ND';
    }
    return value! ? 'ON' : 'OFF';
  }
}

class _ScreenData {
  const _ScreenData({required this.analogValues, required this.bitValues});

  final List<_AnalogValue> analogValues;
  final List<_BitValue> bitValues;
}

class _ScreenSnapshot {
  const _ScreenSnapshot({required this.timestamp, required this.data});

  final DateTime timestamp;
  final _ScreenData data;
}

int _toSigned16(int value) {
  final int raw = value & 0xFFFF;
  return raw >= 0x8000 ? raw - 0x10000 : raw;
}
