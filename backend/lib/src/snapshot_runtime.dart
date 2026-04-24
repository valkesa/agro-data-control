import 'dart:async';
import 'dart:io';

import 'package:agro_data_control_backend/src/door_openings_tracker.dart';
import 'package:agro_data_control_backend/src/firestore_door_openings_repository.dart';
import 'package:agro_data_control_backend/src/firestore_temperature_history_repository.dart';
import 'package:agro_data_control_backend/src/modbus_tcp_client.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/temperature_history_service.dart';

const List<List<String>> _diagnosticKeySignalGroups = <List<String>>[
  <String>['tempInterior', 'tempInside', 'temperaturaInterior'],
  <String>['humInterior', 'humedadInterior', 'rhInside'],
  <String>['tempExterior', 'tempOutside', 'temperaturaExterior'],
  <String>['humExterior', 'humedadExterior', 'rhOutside'],
];

class SnapshotRuntime {
  SnapshotRuntime(this.config)
    : _startedAt = DateTime.now().toUtc(),
      _state = SnapshotRuntimeState.initial(
        config: config,
        startedAt: DateTime.now().toUtc(),
        doorEventsJson: const <String, Object?>{},
      ) {
    _temperatureHistoryServices = config.temperatureHistories
        .map(
          (TemperatureHistoryConfig historyConfig) => TemperatureHistoryService(
            config: historyConfig,
            repository: FirestoreTemperatureHistoryRepository(
              config: historyConfig,
            ),
          ),
        )
        .toList();
    final DoorOpeningsConfig doorConfig = config.doorOpenings;
    _doorOpeningsTracker = DoorOpeningsTracker(
      config: doorConfig,
      repository: FirestoreDoorOpeningsRepository(config: doorConfig),
    );
    _state = SnapshotRuntimeState.initial(
      config: config,
      startedAt: _startedAt,
      doorEventsJson: _doorOpeningsTracker.snapshotSummaryJson(),
    );
  }

  final PlcInstallationConfig config;
  final DateTime _startedAt;

  SnapshotRuntimeState _state;
  final Map<String, DateTime> _unitLastSuccessfulReadAt = <String, DateTime>{};
  Future<void>? _loopFuture;
  bool _disposed = false;
  final Completer<void> _stopCompleter = Completer<void>();
  late final List<TemperatureHistoryService> _temperatureHistoryServices;
  late final DoorOpeningsTracker _doorOpeningsTracker;

  bool get isHealthy => _state.backendOnline;

  void start() {
    if (_loopFuture != null) {
      return;
    }

    _loopFuture = _runLoop();
  }

  Future<void> dispose() async {
    _disposed = true;
    if (!_stopCompleter.isCompleted) {
      _stopCompleter.complete();
    }
    final Future<void>? loopFuture = _loopFuture;
    if (loopFuture != null) {
      await loopFuture;
    }
    for (final TemperatureHistoryService service in _temperatureHistoryServices) {
      await service.dispose();
    }
    await _doorOpeningsTracker.dispose();
  }

  Map<String, Object?> snapshotJson() => _state.snapshotJson;

  Map<String, Object?> healthJson() => _state.healthJson;

  Future<void> _runLoop() async {
    _logPlc(
      'runtime started pollingIntervalMs=${config.pollingIntervalMs} timeoutMs=${config.timeoutMs}',
    );
    _logSignalMapSummary(config);

    while (!_disposed) {
      await _refreshOnce();

      if (_disposed) {
        break;
      }

      await Future.any(<Future<void>>[
        Future<void>.delayed(Duration(milliseconds: config.pollingIntervalMs)),
        _stopCompleter.future,
      ]);
      if (_disposed) {
        break;
      }
    }

    _logPlc('runtime stopped');
  }

  Future<int?> _measureRouterLatency() async {
    final String? host = config.routerHost;
    if (host == null || host.trim().isEmpty) {
      return null;
    }
    try {
      final ProcessResult result = await Process.run(
        'ping',
        ['-c', '1', '-W', '1', host],
      ).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) {
        _logPlc('router ping failed host=$host exitCode=${result.exitCode}');
        return null;
      }
      final RegExp timeRegex = RegExp(r'time[=<](\d+(?:\.\d+)?)\s*ms');
      final Match? match = timeRegex.firstMatch(result.stdout as String);
      if (match == null) {
        _logPlc('router ping no time found host=$host');
        return null;
      }
      final int ms = double.parse(match.group(1)!).round();
      _logPlc('router ping host=$host latencyMs=$ms');
      return ms;
    } catch (error) {
      _logPlc('router ping failed host=$host error=$error');
      return null;
    }
  }

  Future<void> _refreshOnce() async {
    final DateTime pollStartedAt = DateTime.now().toUtc();
    final Stopwatch stopwatch = Stopwatch()..start();

    _state = _state.copyWith(refreshInProgress: true);
    _logPlc('poll started timeoutMs=${config.timeoutMs}');

    try {
      final int? routerLatencyMs = await _measureRouterLatency();
      final Map<String, Object?> unitsJson = <String, Object?>{};
      for (final MapEntry<String, UnitConfig> entry in config.units.entries) {
        final Map<String, Object?> unitJson = await _refreshUnit(
          entry.key,
          entry.value,
          routerLatencyMs: routerLatencyMs,
        );
        unitsJson[entry.key] = unitJson;
      }
      await _doorOpeningsTracker.initializeIfNeeded(
        unitsJson: unitsJson,
        observedAtUtc: pollStartedAt,
      );
      _doorOpeningsTracker.ingestSnapshot(
        unitsJson: unitsJson,
        observedAtUtc: pollStartedAt,
      );

      stopwatch.stop();
      _state = SnapshotRuntimeState.success(
        config: config,
        startedAt: _startedAt,
        backendOnline: true,
        lastUpdatedAt: pollStartedAt,
        lastPollDurationMs: stopwatch.elapsedMilliseconds,
        unitsJson: unitsJson,
        doorEventsJson: _doorOpeningsTracker.snapshotSummaryJson(),
      );
      _logSnapshotPayload(_state.snapshotJson);
      _logSnapshot('backendOnline=true');
      _logPlc('poll success elapsedMs=${stopwatch.elapsedMilliseconds}');
      for (final TemperatureHistoryService service in _temperatureHistoryServices) {
        service.handleSnapshot(
          unitsJson: unitsJson,
          observedAtUtc: pollStartedAt,
        );
      }
    } on TimeoutException catch (error, stackTrace) {
      stopwatch.stop();
      _logSnapshot('backendOnline=false');
      _logPlc('timeout operation=poll error=$error');
      _logPlc('error operation=poll stack=$stackTrace');
      _state = _state.failure(
        config: config,
        startedAt: _startedAt,
        error: 'PLC timeout: $error',
        pollDurationMs: stopwatch.elapsedMilliseconds,
        doorEventsJson: _extractDoorEvents(_state.snapshotJson),
      );
      _logSnapshotPayload(_state.snapshotJson);
    } catch (error, stackTrace) {
      stopwatch.stop();
      _logSnapshot('backendOnline=false');
      _logPlc('error operation=poll error=$error');
      _logPlc('error operation=poll stack=$stackTrace');
      _state = _state.failure(
        config: config,
        startedAt: _startedAt,
        error: error.toString(),
        pollDurationMs: stopwatch.elapsedMilliseconds,
        doorEventsJson: _extractDoorEvents(_state.snapshotJson),
      );
      _logSnapshotPayload(_state.snapshotJson);
    }
  }

  Future<Map<String, Object?>> _refreshUnit(
    String unitKey,
    UnitConfig unit, {
    int? routerLatencyMs,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final Duration timeout = Duration(milliseconds: config.timeoutMs);
    final String? host = unit.plcHost;
    final int port = unit.plcPort ?? config.plcPort;
    final int unitId = unit.unitId ?? config.unitId;
    final bool hasHost = host != null && host.trim().isNotEmpty;
    final bool hasSignals = unit.signals.isNotEmpty;
    final bool configured = hasHost && hasSignals;

    if (!configured) {
      final String reason = !hasHost ? 'no_config' : 'no_signals';
      final Map<String, Object?> offline =
          SnapshotRuntimeState.offlineUnitPayload(
            unit,
            lastUpdatedAt: null,
            configured: false,
            plcReachable: false,
            plcRunning: false,
            lastError: reason,
            estadoPLC: 'NO_CONFIGURADO',
            estadoEquipo: 'PLC no configurado',
            diagnostics: const _UnitDiagnostics(
              backendAlive: true,
              plcConnectOk: false,
              validKeySignals: 0,
              invalidKeySignals: 0,
              totalKeySignals: 0,
              lastPollAt: null,
              lastSuccessfulReadAt: null,
              stateCode: 'PLC_NOT_CONFIGURED',
              stateLabel: 'PLC no configurado',
              stateReason: 'Unidad sin configuracion PLC.',
            ),
          );
      _logUnitStatus(
        unit.name,
        configured: false,
        ip: hasHost ? host : null,
        plcReachable: false,
        plcRunning: false,
        plcOnline: false,
        reason: reason,
      );
      offline['routerLatencyMs'] = routerLatencyMs;
      return offline;
    }

    final ModbusTcpClient client = ModbusTcpClient(
      host: host,
      port: port,
      unitId: unitId,
      timeout: timeout,
    );

    _logPlc(
      'unit poll started unit=$unitKey host=$host port=$port unitId=$unitId timeoutMs=${timeout.inMilliseconds}',
    );

    try {
      final Stopwatch connectStopwatch = Stopwatch()..start();
      await client.connect();
      connectStopwatch.stop();
      final int plcLatencyMs = connectStopwatch.elapsedMilliseconds;
      _logPlc(
        'unit connect success unit=$unitKey host=$host latencyMs=$plcLatencyMs',
      );
      final Map<String, Object?> result = await _readUnit(
        client,
        unitKey,
        unit,
        readAt: now,
        plcLatencyMs: plcLatencyMs,
        routerLatencyMs: routerLatencyMs,
      );
      _logUnitStatus(
        unit.name,
        configured: true,
        ip: host,
        plcReachable: result['plcReachable'] == true,
        plcRunning: result['plcRunning'] as bool?,
        plcOnline: result['plcOnline'] == true,
        reason: 'read_ok',
      );
      return result;
    } on TimeoutException catch (error, stackTrace) {
      final Map<String, Object?> offline =
          SnapshotRuntimeState.offlineUnitPayload(
            unit,
            lastUpdatedAt: now,
            configured: true,
            plcReachable: false,
            plcRunning: false,
            lastError: 'timeout',
            estadoPLC: 'OFFLINE',
            estadoEquipo: 'PLC fuera de alcance',
            diagnostics: _computeUnitDiagnostics(
              unit: unit,
              signalValues: const <String, Object?>{},
              plcConnectOk: false,
              runStopValue: null,
              lastPollAt: now,
              lastSuccessfulReadAt: _unitLastSuccessfulReadAt[unitKey],
            ),
          );
      _logUnitStatus(
        unit.name,
        configured: true,
        ip: host,
        plcReachable: false,
        plcRunning: false,
        plcOnline: false,
        reason: 'timeout',
      );
      _logPlc(
        'timeout operation=unit_poll unit=$unitKey host=$host error=$error',
      );
      _logPlc('error operation=unit_poll unit=$unitKey stack=$stackTrace');
      offline['routerLatencyMs'] = routerLatencyMs;
      return offline;
    } catch (error, stackTrace) {
      final Map<String, Object?> offline =
          SnapshotRuntimeState.offlineUnitPayload(
            unit,
            lastUpdatedAt: now,
            configured: true,
            plcReachable: false,
            plcRunning: false,
            lastError: error.toString(),
            estadoPLC: 'OFFLINE',
            estadoEquipo: 'PLC fuera de alcance',
            diagnostics: _computeUnitDiagnostics(
              unit: unit,
              signalValues: const <String, Object?>{},
              plcConnectOk: false,
              runStopValue: null,
              lastPollAt: now,
              lastSuccessfulReadAt: _unitLastSuccessfulReadAt[unitKey],
            ),
          );
      _logUnitStatus(
        unit.name,
        configured: true,
        ip: host,
        plcReachable: false,
        plcRunning: false,
        plcOnline: false,
        reason: 'read_failed',
      );
      _logPlc(
        'error operation=unit_poll unit=$unitKey host=$host error=$error',
      );
      _logPlc('error operation=unit_poll unit=$unitKey stack=$stackTrace');
      offline['routerLatencyMs'] = routerLatencyMs;
      return offline;
    } finally {
      await client.close(reason: 'unit_poll_finished');
    }
  }

  Future<Map<String, Object?>> _readUnit(
    ModbusTcpClient client,
    String unitKey,
    UnitConfig unit, {
    required DateTime readAt,
    required int plcLatencyMs,
    int? routerLatencyMs,
  }) async {
    final Map<String, Object?> result = <String, Object?>{
      'name': unit.name,
      'configured': true,
      'signalSources': _buildSignalSources(unit),
    };
    final List<String> readErrors = <String>[];

    for (final MapEntry<String, SignalConfig> entry in unit.signals.entries) {
      final String blockLabel =
          '$unitKey.${entry.key}:${entry.value.area.name}@${entry.value.address}/${entry.value.wordCount}';
      result[entry.key] = await _tryReadSignal(
        client: client,
        signal: entry.value,
        unitName: unit.name,
        signalName: entry.key,
        blockLabel: blockLabel,
        readErrors: readErrors,
      );
    }

    Object? runStopValue;

    if (unit.runStopSignal != null) {
      runStopValue = await _tryReadSignal(
        client: client,
        signal: unit.runStopSignal!,
        unitName: unit.name,
        signalName: 'runStopSignal',
        blockLabel:
            '$unitKey.runStopSignal:${unit.runStopSignal!.area.name}@${unit.runStopSignal!.address}/${unit.runStopSignal!.wordCount}',
        readErrors: readErrors,
      );
      _logUnit(unit.name, 'runStopSignal read value=$runStopValue');
    }

    final _UnitDiagnostics diagnostics = _computeUnitDiagnostics(
      unit: unit,
      signalValues: result,
      plcConnectOk: true,
      runStopValue: runStopValue,
      lastPollAt: readAt,
      lastSuccessfulReadAt: _unitLastSuccessfulReadAt[unitKey],
    );
    if (diagnostics.stateCode == 'PLC_RUN_CONFIRMED' ||
        diagnostics.stateCode == 'PLC_HEALTHY') {
      _unitLastSuccessfulReadAt[unitKey] = readAt;
    }

    final bool plcOnline =
        diagnostics.stateCode == 'PLC_RUN_CONFIRMED' ||
        diagnostics.stateCode == 'PLC_HEALTHY';
    final bool plcRunning = plcOnline;
    final String estadoPLC = plcOnline ? 'RUN' : 'STOP';

    result['plcReachable'] = true;
    result['plcLatencyMs'] = plcLatencyMs;
    result['routerLatencyMs'] = routerLatencyMs;
    result['plcRunning'] = plcRunning;
    result['dataFresh'] = plcRunning;
    result['plcOnline'] = plcOnline;
    result['lastUpdatedAt'] = readAt.toIso8601String();
    result['lastRunStopValue'] = runStopValue;
    result['lastError'] = readErrors.isEmpty ? null : readErrors.join(' | ');
    result['estadoPLC'] = estadoPLC;
    result['estadoEquipo'] = diagnostics.stateLabel;
    result['diagnostics'] = diagnostics.toJson();
    _logValidationBooleanSignals(unit.name, result);
    _logUnit(
      unit.name,
      'connectivity=OK latencyMs=$plcLatencyMs estadoPLC=$estadoPLC diagnostics=${diagnostics.stateCode}',
    );
    return result;
  }

  Future<Object?> _tryReadSignal({
    required ModbusTcpClient client,
    required SignalConfig signal,
    required String unitName,
    required String signalName,
    required String blockLabel,
    required List<String> readErrors,
  }) async {
    try {
      return await _readSignal(
        client,
        signal,
        unitName: unitName,
        signalName: signalName,
        blockLabel: blockLabel,
      );
    } on TimeoutException {
      final String message = 'signal=$signalName timeout';
      readErrors.add(message);
      _logUnit(unitName, message);
      return null;
    } on ModbusException catch (error) {
      final String message = 'signal=$signalName modbus_error=${error.message}';
      readErrors.add(message);
      _logUnit(unitName, message);
      return null;
    } catch (error) {
      final String message = 'signal=$signalName read_error=$error';
      readErrors.add(message);
      _logUnit(unitName, message);
      return null;
    }
  }

  Future<Object?> _readSignal(
    ModbusTcpClient client,
    SignalConfig signal, {
    required String unitName,
    required String signalName,
    required String blockLabel,
  }) async {
    try {
      switch (signal.area) {
        case SignalArea.coil:
          final List<bool> values = await client.readCoils(
            signal.address,
            1,
            operationLabel: blockLabel,
          );
          final Object? exposed = _coerceBit(values.first, signal);
          _logUnit(
            unitName,
            'signal=$signalName source=${_describeSignal(signal)} raw=${values.first} final=$exposed',
          );
          return exposed;
        case SignalArea.discreteInput:
          final List<bool> values = await client.readDiscreteInputs(
            signal.address,
            1,
            operationLabel: blockLabel,
          );
          final Object? exposed = _coerceBit(values.first, signal);
          _logUnit(
            unitName,
            'signal=$signalName source=${_describeSignal(signal)} raw=${values.first} final=$exposed',
          );
          return exposed;
        case SignalArea.holdingRegister:
          final List<int> values = await client.readHoldingRegisters(
            signal.address,
            signal.wordCount,
            operationLabel: blockLabel,
          );
          final Object? exposed = _coerceWords(values, signal);
          _logUnit(
            unitName,
            'signal=$signalName source=${_describeSignal(signal)} raw=${values.join(",")} final=$exposed',
          );
          return exposed;
        case SignalArea.inputRegister:
          final List<int> values = await client.readInputRegisters(
            signal.address,
            signal.wordCount,
            operationLabel: blockLabel,
          );
          final Object? exposed = _coerceWords(values, signal);
          _logUnit(
            unitName,
            'signal=$signalName source=${_describeSignal(signal)} raw=${values.join(",")} final=$exposed',
          );
          return exposed;
      }
    } on ModbusException catch (error) {
      throw ModbusException(
        'signal=$signalName source=${_describeSignal(signal)} area=${signal.area.name} error=${error.message}',
      );
    } on TimeoutException {
      throw TimeoutException(
        'signal=$signalName source=${_describeSignal(signal)} area=${signal.area.name}',
      );
    }
  }

  Object? _coerceBit(bool raw, SignalConfig signal) {
    return switch (signal.dataType) {
      SignalDataType.string => signal.enumMap[raw ? '1' : '0'],
      SignalDataType.int => raw ? 1 : 0,
      SignalDataType.double => raw ? 1.0 : 0.0,
      SignalDataType.bool => raw,
    };
  }

  Object? _coerceWords(List<int> words, SignalConfig signal) {
    int value = _combineWords(words, signal.wordOrder);
    final int bits = words.length * 16;
    if (signal.signed) {
      final int signBit = 1 << (bits - 1);
      if ((value & signBit) != 0) {
        value -= 1 << bits;
      }
    }

    if (signal.bitIndex != null) {
      final bool bitValue = ((value >> signal.bitIndex!) & 0x01) == 1;
      return _coerceBit(bitValue, signal);
    }

    if (signal.dataType == SignalDataType.string) {
      return signal.enumMap[value.toString()];
    }

    final double scaled = (value * signal.scale) + signal.offset;

    return switch (signal.dataType) {
      SignalDataType.bool => value != 0,
      SignalDataType.int => scaled.round(),
      SignalDataType.double => scaled,
      SignalDataType.string => signal.enumMap[value.toString()],
    };
  }

  int _combineWords(List<int> words, WordOrder order) {
    final Iterable<int> effectiveWords = order == WordOrder.bigEndian
        ? words
        : words.reversed;

    int value = 0;
    for (final int word in effectiveWords) {
      value = (value << 16) | (word & 0xFFFF);
    }
    return value;
  }

  Map<String, Object?> _buildSignalSources(UnitConfig unit) {
    return <String, Object?>{
      for (final MapEntry<String, SignalConfig> entry in unit.signals.entries)
        entry.key: _describeSignal(entry.value),
      if (unit.runStopSignal != null)
        'runStopSignal': _describeSignal(unit.runStopSignal!),
    };
  }

  String _describeSignal(SignalConfig signal) {
    final String area = switch (signal.area) {
      SignalArea.coil => 'coil',
      SignalArea.discreteInput => 'discreteInput',
      SignalArea.holdingRegister => 'holdingRegister',
      SignalArea.inputRegister => 'inputRegister',
    };
    return '$area ${signal.address}'
        '${signal.wordCount > 1 ? ' x${signal.wordCount}' : ''}'
        ' ${signal.dataType.name}';
  }

  _UnitDiagnostics _computeUnitDiagnostics({
    required UnitConfig unit,
    required Map<String, Object?> signalValues,
    required bool plcConnectOk,
    required Object? runStopValue,
    required DateTime lastPollAt,
    required DateTime? lastSuccessfulReadAt,
  }) {
    int validKeySignals = 0;
    int totalKeySignals = 0;
    for (final List<String> group in _diagnosticKeySignalGroups) {
      final String? configuredSignal = group.cast<String?>().firstWhere(
        (String? signalName) =>
            signalName != null && unit.signals.containsKey(signalName),
        orElse: () => null,
      );
      if (configuredSignal == null) {
        continue;
      }
      totalKeySignals += 1;
      if (_isUsableKeySignalValue(signalValues[configuredSignal])) {
        validKeySignals += 1;
      }
    }

    // Some installations can publish the same climate signals under alternate
    // keys. If no sentinel group matched the unit config, fall back to a small
    // numeric scan across known measurement aliases before declaring "sin datos".
    if (totalKeySignals == 0) {
      final int fallbackValidSignals = _countFallbackValidSignals(signalValues);
      if (fallbackValidSignals > 0) {
        validKeySignals = fallbackValidSignals;
        totalKeySignals = fallbackValidSignals;
      }
    }

    final int invalidKeySignals = totalKeySignals - validKeySignals;

    if (!plcConnectOk) {
      return _UnitDiagnostics(
        backendAlive: true,
        plcConnectOk: false,
        validKeySignals: validKeySignals,
        invalidKeySignals: invalidKeySignals,
        totalKeySignals: totalKeySignals,
        lastPollAt: lastPollAt,
        lastSuccessfulReadAt: lastSuccessfulReadAt,
        stateCode: 'PLC_UNREACHABLE',
        stateLabel: 'PLC fuera de alcance',
        stateReason: 'Posible problema de energia o red.',
      );
    }

    final bool? runStopBool = runStopValue is bool ? runStopValue : null;
    if (unit.runStopSignal != null && runStopBool != null) {
      return _UnitDiagnostics(
        backendAlive: true,
        plcConnectOk: true,
        validKeySignals: validKeySignals,
        invalidKeySignals: invalidKeySignals,
        totalKeySignals: totalKeySignals,
        lastPollAt: lastPollAt,
        lastSuccessfulReadAt: runStopBool ? lastPollAt : lastSuccessfulReadAt,
        stateCode: runStopBool ? 'PLC_RUN_CONFIRMED' : 'PLC_STOP_CONFIRMED',
        stateLabel: runStopBool ? 'PLC online' : 'PLC Stop',
        stateReason: runStopBool
            ? 'Señal RUN/STOP indica RUN.'
            : 'Señal RUN/STOP indica STOP.',
      );
    }

    // Sin señales clave válidas: PLC alcanzable pero en modo STOP
    // (programa detenido → salidas a 0, registros sin datos útiles).
    if (validKeySignals == 0) {
      return _UnitDiagnostics(
        backendAlive: true,
        plcConnectOk: true,
        validKeySignals: validKeySignals,
        invalidKeySignals: invalidKeySignals,
        totalKeySignals: totalKeySignals,
        lastPollAt: lastPollAt,
        lastSuccessfulReadAt: lastSuccessfulReadAt,
        stateCode: 'PLC_STOP_CONFIRMED',
        stateLabel: 'PLC Stop',
        stateReason:
            'PLC alcanzable pero sin datos válidos. Probable modo STOP.',
      );
    }

    // Señales clave presentes: PLC en RUN y entregando datos.
    return _UnitDiagnostics(
      backendAlive: true,
      plcConnectOk: true,
      validKeySignals: validKeySignals,
      invalidKeySignals: invalidKeySignals,
      totalKeySignals: totalKeySignals,
      lastPollAt: lastPollAt,
      lastSuccessfulReadAt: lastPollAt,
      stateCode: 'PLC_HEALTHY',
      stateLabel: 'PLC online',
      stateReason: '$validKeySignals/$totalKeySignals señales clave válidas.',
    );
  }

  bool _isUsableKeySignalValue(Object? value) {
    // El LOGO! devuelve 0.0 en todos los registros cuando está en STOP.
    // Un valor exactamente 0 en una señal climática nunca es una lectura real.
    return value is num && value.isFinite && value != 0;
  }

  int _countFallbackValidSignals(Map<String, Object?> signalValues) {
    final Set<String> validSignals = <String>{};
    for (final MapEntry<String, Object?> entry in signalValues.entries) {
      final String key = entry.key.toLowerCase();
      if (!_isUsableKeySignalValue(entry.value)) {
        continue;
      }
      final bool isClimateMeasurement =
          ((key.contains('temp') || key.contains('temperatura')) &&
              (key.contains('interior') ||
                  key.contains('inside') ||
                  key.contains('exterior') ||
                  key.contains('outside'))) ||
          ((key.contains('hum') || key.contains('rh')) &&
              (key.contains('interior') ||
                  key.contains('inside') ||
                  key.contains('exterior') ||
                  key.contains('outside')));
      if (isClimateMeasurement) {
        validSignals.add(entry.key);
      }
    }
    return validSignals.length;
  }
}

class _UnitDiagnostics {
  const _UnitDiagnostics({
    required this.backendAlive,
    required this.plcConnectOk,
    required this.validKeySignals,
    required this.invalidKeySignals,
    required this.totalKeySignals,
    required this.lastPollAt,
    required this.lastSuccessfulReadAt,
    required this.stateCode,
    required this.stateLabel,
    required this.stateReason,
  });

  final bool backendAlive;
  final bool plcConnectOk;
  final int validKeySignals;
  final int invalidKeySignals;
  final int totalKeySignals;
  final DateTime? lastPollAt;
  final DateTime? lastSuccessfulReadAt;
  final String stateCode;
  final String stateLabel;
  final String stateReason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backendAlive': backendAlive,
      'plcConnectOk': plcConnectOk,
      'validKeySignals': validKeySignals,
      'invalidKeySignals': invalidKeySignals,
      'totalKeySignals': totalKeySignals,
      'lastPollAt': lastPollAt?.toUtc().toIso8601String(),
      'lastSuccessfulReadAt': lastSuccessfulReadAt?.toUtc().toIso8601String(),
      'stateCode': stateCode,
      'stateLabel': stateLabel,
      'stateReason': stateReason,
    };
  }
}

class SnapshotRuntimeState {
  SnapshotRuntimeState({
    required this.snapshotJson,
    required this.healthJson,
    required this.backendOnline,
    required this.lastUpdatedAt,
    required this.lastError,
    required this.lastPollDurationMs,
    required this.consecutiveFailures,
    required this.refreshInProgress,
    required this.hasFreshSnapshot,
  });

  factory SnapshotRuntimeState.initial({
    required PlcInstallationConfig config,
    required DateTime startedAt,
    required Map<String, Object?> doorEventsJson,
  }) {
    return SnapshotRuntimeState(
      snapshotJson: _buildSnapshotPayload(
        config: config,
        startedAt: startedAt,
        backendOnline: false,
        lastUpdatedAt: null,
        lastError: 'Snapshot not ready yet',
        lastPollDurationMs: null,
        consecutiveFailures: 0,
        refreshInProgress: false,
        hasFreshSnapshot: false,
        unitsJson: <String, Object?>{
          for (final MapEntry<String, UnitConfig> entry in config.units.entries)
            entry.key: offlineUnit(entry.value),
        },
        doorEventsJson: doorEventsJson,
      ),
      healthJson: _buildHealthPayload(
        config: config,
        startedAt: startedAt,
        backendOnline: false,
        lastUpdatedAt: null,
        lastError: 'Snapshot not ready yet',
        lastPollDurationMs: null,
        consecutiveFailures: 0,
        refreshInProgress: false,
        hasFreshSnapshot: false,
      ),
      backendOnline: false,
      lastUpdatedAt: null,
      lastError: 'Snapshot not ready yet',
      lastPollDurationMs: null,
      consecutiveFailures: 0,
      refreshInProgress: false,
      hasFreshSnapshot: false,
    );
  }

  final Map<String, Object?> snapshotJson;
  final Map<String, Object?> healthJson;
  final bool backendOnline;
  final DateTime? lastUpdatedAt;
  final String? lastError;
  final int? lastPollDurationMs;
  final int consecutiveFailures;
  final bool refreshInProgress;
  final bool hasFreshSnapshot;

  SnapshotRuntimeState copyWith({bool? refreshInProgress}) {
    return SnapshotRuntimeState(
      snapshotJson: _copySnapshotWithRefreshFlag(
        snapshotJson,
        refreshInProgress,
      ),
      healthJson: _copyHealthWithRefreshFlag(healthJson, refreshInProgress),
      backendOnline: backendOnline,
      lastUpdatedAt: lastUpdatedAt,
      lastError: lastError,
      lastPollDurationMs: lastPollDurationMs,
      consecutiveFailures: consecutiveFailures,
      refreshInProgress: refreshInProgress ?? this.refreshInProgress,
      hasFreshSnapshot: hasFreshSnapshot,
    );
  }

  SnapshotRuntimeState failure({
    required PlcInstallationConfig config,
    required DateTime startedAt,
    required String error,
    required int pollDurationMs,
    required Map<String, Object?> doorEventsJson,
  }) {
    final int nextFailures = consecutiveFailures + 1;
    return SnapshotRuntimeState(
      snapshotJson: _buildSnapshotPayload(
        config: config,
        startedAt: startedAt,
        backendOnline: false,
        lastUpdatedAt: lastUpdatedAt,
        lastError: error,
        lastPollDurationMs: pollDurationMs,
        consecutiveFailures: nextFailures,
        refreshInProgress: false,
        hasFreshSnapshot: hasFreshSnapshot,
        unitsJson: <String, Object?>{
          for (final MapEntry<String, UnitConfig> entry in config.units.entries)
            entry.key: offlineUnit(entry.value),
        },
        doorEventsJson: doorEventsJson,
      ),
      healthJson: _buildHealthPayload(
        config: config,
        startedAt: startedAt,
        backendOnline: false,
        lastUpdatedAt: lastUpdatedAt,
        lastError: error,
        lastPollDurationMs: pollDurationMs,
        consecutiveFailures: nextFailures,
        refreshInProgress: false,
        hasFreshSnapshot: hasFreshSnapshot,
      ),
      backendOnline: false,
      lastUpdatedAt: lastUpdatedAt,
      lastError: error,
      lastPollDurationMs: pollDurationMs,
      consecutiveFailures: nextFailures,
      refreshInProgress: false,
      hasFreshSnapshot: hasFreshSnapshot,
    );
  }

  static SnapshotRuntimeState success({
    required PlcInstallationConfig config,
    required DateTime startedAt,
    required bool backendOnline,
    required DateTime lastUpdatedAt,
    required int lastPollDurationMs,
    required Map<String, Object?> unitsJson,
    required Map<String, Object?> doorEventsJson,
  }) {
    return SnapshotRuntimeState(
      snapshotJson: _buildSnapshotPayload(
        config: config,
        startedAt: startedAt,
        backendOnline: backendOnline,
        lastUpdatedAt: lastUpdatedAt,
        lastError: null,
        lastPollDurationMs: lastPollDurationMs,
        consecutiveFailures: 0,
        refreshInProgress: false,
        hasFreshSnapshot: true,
        unitsJson: unitsJson,
        doorEventsJson: doorEventsJson,
      ),
      healthJson: _buildHealthPayload(
        config: config,
        startedAt: startedAt,
        backendOnline: backendOnline,
        lastUpdatedAt: lastUpdatedAt,
        lastError: null,
        lastPollDurationMs: lastPollDurationMs,
        consecutiveFailures: 0,
        refreshInProgress: false,
        hasFreshSnapshot: true,
      ),
      backendOnline: backendOnline,
      lastUpdatedAt: lastUpdatedAt,
      lastError: null,
      lastPollDurationMs: lastPollDurationMs,
      consecutiveFailures: 0,
      refreshInProgress: false,
      hasFreshSnapshot: true,
    );
  }

  static Map<String, Object?> _buildSnapshotPayload({
    required PlcInstallationConfig config,
    required DateTime startedAt,
    required bool backendOnline,
    required DateTime? lastUpdatedAt,
    required String? lastError,
    required int? lastPollDurationMs,
    required int consecutiveFailures,
    required bool refreshInProgress,
    required bool hasFreshSnapshot,
    required Map<String, Object?> unitsJson,
    required Map<String, Object?> doorEventsJson,
  }) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'backendName': config.backendName,
      'backendOnline': backendOnline,
      'lastUpdatedAt': lastUpdatedAt?.toUtc().toIso8601String(),
      'clientName': config.clientName,
      'siteName': config.siteName,
      'refreshInProgress': refreshInProgress,
      'status': <String, Object?>{
        'backendName': config.backendName,
        'backendOnline': backendOnline,
        'lastUpdatedAt': lastUpdatedAt?.toUtc().toIso8601String(),
        'clientName': config.clientName,
        'siteName': config.siteName,
        'lastError': lastError,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'lastPollDurationMs': lastPollDurationMs,
        'consecutiveFailures': consecutiveFailures,
        'refreshInProgress': refreshInProgress,
        'hasFreshSnapshot': hasFreshSnapshot,
      },
      'doorEvents': doorEventsJson,
      ...unitsJson,
    });
  }

  static Map<String, Object?> _buildHealthPayload({
    required PlcInstallationConfig config,
    required DateTime startedAt,
    required bool backendOnline,
    required DateTime? lastUpdatedAt,
    required String? lastError,
    required int? lastPollDurationMs,
    required int consecutiveFailures,
    required bool refreshInProgress,
    required bool hasFreshSnapshot,
  }) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'backendName': config.backendName,
      'healthy': backendOnline,
      'backendOnline': backendOnline,
      'lastSuccessAt': lastUpdatedAt?.toUtc().toIso8601String(),
      'lastError': lastError,
      'siteName': config.siteName,
      'clientName': config.clientName,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'lastPollDurationMs': lastPollDurationMs,
      'consecutiveFailures': consecutiveFailures,
      'refreshInProgress': refreshInProgress,
      'hasFreshSnapshot': hasFreshSnapshot,
    });
  }

  static Map<String, Object?> _copySnapshotWithRefreshFlag(
    Map<String, Object?> source,
    bool? refreshInProgress,
  ) {
    final Map<String, Object?> copy = Map<String, Object?>.from(source);
    final Map<String, Object?> status = copy['status'] is Map<String, Object?>
        ? Map<String, Object?>.from(copy['status'] as Map<String, Object?>)
        : <String, Object?>{};

    final bool effectiveRefreshInProgress =
        refreshInProgress ?? (source['refreshInProgress'] as bool? ?? false);
    status['refreshInProgress'] = effectiveRefreshInProgress;
    copy['status'] = status;
    copy['refreshInProgress'] = effectiveRefreshInProgress;
    return Map<String, Object?>.unmodifiable(copy);
  }

  static Map<String, Object?> _copyHealthWithRefreshFlag(
    Map<String, Object?> source,
    bool? refreshInProgress,
  ) {
    final Map<String, Object?> copy = Map<String, Object?>.from(source);
    copy['refreshInProgress'] =
        refreshInProgress ?? (source['refreshInProgress'] as bool? ?? false);
    return Map<String, Object?>.unmodifiable(copy);
  }

  static Map<String, Object?> offlineUnit(UnitConfig unit) =>
      offlineUnitPayload(
        unit,
        lastUpdatedAt: null,
        configured:
            unit.plcHost != null &&
            unit.plcHost!.trim().isNotEmpty &&
            unit.signals.isNotEmpty,
        plcReachable: false,
        plcRunning: false,
        lastError: null,
        estadoPLC: 'NO_CONFIGURADO',
        estadoEquipo: 'PLC no configurado',
        diagnostics: const _UnitDiagnostics(
          backendAlive: true,
          plcConnectOk: false,
          validKeySignals: 0,
          invalidKeySignals: 0,
          totalKeySignals: 0,
          lastPollAt: null,
          lastSuccessfulReadAt: null,
          stateCode: 'PLC_NOT_CONFIGURED',
          stateLabel: 'PLC no configurado',
          stateReason: 'Unidad sin configuracion PLC.',
        ),
      );

  static Map<String, Object?> offlineUnitPayload(
    UnitConfig unit, {
    required DateTime? lastUpdatedAt,
    required bool configured,
    required bool plcReachable,
    required bool? plcRunning,
    required String? lastError,
    required String estadoPLC,
    required String estadoEquipo,
    required _UnitDiagnostics diagnostics,
  }) => <String, Object?>{
    'name': unit.name,
    'configured': configured,
    'signalSources': <String, Object?>{
      for (final MapEntry<String, SignalConfig> entry in unit.signals.entries)
        entry.key: _describeStaticSignal(entry.value),
    },
    'plcReachable': plcReachable,
    'plcLatencyMs': null,
    'routerLatencyMs': null,
    'plcRunning': plcRunning,
    'dataFresh': plcRunning,
    'plcOnline': false,
    'estadoPLC': estadoPLC,
    'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
    'lastError': lastError,
    'estadoEquipo': estadoEquipo,
    'diagnostics': diagnostics.toJson(),
    for (final String key in unit.signals.keys) key: null,
  };
}

String _describeStaticSignal(SignalConfig signal) {
  final String area = switch (signal.area) {
    SignalArea.coil => 'coil',
    SignalArea.discreteInput => 'discreteInput',
    SignalArea.holdingRegister => 'holdingRegister',
    SignalArea.inputRegister => 'inputRegister',
  };
  return '$area ${signal.address}'
      '${signal.wordCount > 1 ? ' x${signal.wordCount}' : ''}'
      ' ${signal.dataType.name}';
}

void _logPlc(String message) {
  stdout.writeln('[PLC] $message');
}

void _logUnit(String unitName, String message) {
  final String compactName = unitName.replaceAll(' ', '');
  stdout.writeln('[$compactName] $message');
}

void _logSnapshot(String message) {
  stdout.writeln('[snapshot] $message');
}

void _logUnitStatus(
  String unitName, {
  required bool configured,
  required String? ip,
  required bool plcReachable,
  required bool? plcRunning,
  required bool plcOnline,
  required String reason,
}) {
  _logUnit(
    unitName,
    'configured=$configured plcReachable=$plcReachable plcRunning=$plcRunning plcOnline=$plcOnline reason=$reason ip=${ip ?? 'null'}',
  );
}

void _logSnapshotPayload(Map<String, Object?> payload) {
  final Object? status = payload['status'];
  final Map<String, Object?> statusMap = status is Map<String, Object?>
      ? status
      : <String, Object?>{};
  final Object? munters1 = payload['munters1'];
  final Map<String, Object?> munters1Map = munters1 is Map<String, Object?>
      ? munters1
      : <String, Object?>{};
  final Object? munters2 = payload['munters2'];
  final Map<String, Object?> munters2Map = munters2 is Map<String, Object?>
      ? munters2
      : <String, Object?>{};

  stdout.writeln(
    '[snapshot-root] plcOnline=${payload['plcOnline']} backendOnline=${payload['backendOnline']}',
  );
  stdout.writeln(
    '[status] plcOnline=${statusMap['plcOnline']} backendOnline=${statusMap['backendOnline']}',
  );
  stdout.writeln(
    '[munters1] configured=${munters1Map['configured']} plcReachable=${munters1Map['plcReachable']} plcRunning=${munters1Map['plcRunning']} plcOnline=${munters1Map['plcOnline']} estadoEquipo=${munters1Map['estadoEquipo']}',
  );
  stdout.writeln(
    '[munters2] configured=${munters2Map['configured']} plcReachable=${munters2Map['plcReachable']} plcRunning=${munters2Map['plcRunning']} plcOnline=${munters2Map['plcOnline']} estadoEquipo=${munters2Map['estadoEquipo']}',
  );
  final Object? doorEventsRaw = payload['doorEvents'];
  if (doorEventsRaw is Map<String, Object?>) {
    doorEventsRaw.forEach((String doorId, Object? value) {
      if (value is Map<String, Object?>) {
        stdout.writeln(
          '[doorEvents.$doorId] isOpen=${value['isOpen']} currentOpenedAt=${value['currentOpenedAt']} lastChangedAt=${value['lastChangedAt']}',
        );
      }
    });
  } else {
    stdout.writeln('[doorEvents] not present or invalid type=${doorEventsRaw?.runtimeType}');
  }
}

void _logSignalMapSummary(PlcInstallationConfig config) {
  for (final MapEntry<String, UnitConfig> unitEntry in config.units.entries) {
    final UnitConfig unit = unitEntry.value;
    if (unit.signals.isEmpty) {
      continue;
    }
    _logPlc('signal map unit=${unitEntry.key} name=${unit.name}');
    for (final MapEntry<String, SignalConfig> signalEntry
        in unit.signals.entries) {
      _logPlc(
        'signal map unit=${unitEntry.key} signal=${signalEntry.key} source=${_describeStaticSignal(signalEntry.value)}',
      );
    }
    if (unit.runStopSignal != null) {
      _logPlc(
        'signal map unit=${unitEntry.key} signal=runStopSignal source=${_describeStaticSignal(unit.runStopSignal!)}',
      );
    }
  }
}

void _logValidationBooleanSignals(
  String unitName,
  Map<String, Object?> payload,
) {
  if (!payload.containsKey('nivelAgua') &&
      !payload.containsKey('puertaSala') &&
      !payload.containsKey('puertaMunter')) {
    return;
  }
  stdout.writeln(
    '[$unitName.validation] '
    'nivelAgua=${payload['nivelAgua']} '
    'puertaSala=${payload['puertaSala']} '
    'puertaMunter=${payload['puertaMunter']}',
  );
}

Map<String, Object?> _extractDoorEvents(Map<String, Object?> snapshotJson) {
  final Object? raw = snapshotJson['doorEvents'];
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map) {
    return Map<String, Object?>.from(raw as Map<Object?, Object?>);
  }
  return const <String, Object?>{};
}
