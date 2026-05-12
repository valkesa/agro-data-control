import 'dart:async';
import 'dart:io';

import 'package:agro_data_control_backend/src/firestore_runtime_events_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/runtime_event.dart';

class RuntimeTrackerService {
  RuntimeTrackerService({
    required RuntimeEventsConfig config,
    required FirestoreRuntimeEventsRepository repository,
  }) : _config = config,
       _repository = repository {
    if (!config.enabled) {
      _log('disabled by config');
    } else if (!_repository.isConfigured) {
      _log('disabled: ${_repository.missingConfigurationReason}');
    } else {
      final String plcIds = config.plcs
          .map((RuntimePlcConfig plc) => plc.plcId)
          .join(', ');
      _log(
        'enabled plcs=[$plcIds] '
        'path=tenants/${config.tenantId}/sites/${config.siteId}/plcs/{plcId}/runtimeEvents/{eventId}',
      );
    }

    for (final RuntimePlcConfig plc in config.plcs) {
      _states[_stateKey(plc.plcId, _DeviceType.humidifierPump)] =
          _BinaryRuntimeState();
      _states[_stateKey(plc.plcId, _DeviceType.heater1)] =
          _BinaryRuntimeState();
      _states[_stateKey(plc.plcId, _DeviceType.heater2)] =
          _BinaryRuntimeState();
      _fanStates[plc.plcId] = _FanRuntimeState();
    }

    if (config.enabled && config.plcs.isNotEmpty) {
      _heartbeatTimer = Timer.periodic(
        const Duration(hours: 1),
        (_) => _scheduleHeartbeats(),
      );
    }
  }

  final RuntimeEventsConfig _config;
  final FirestoreRuntimeEventsRepository _repository;
  final Map<String, _BinaryRuntimeState> _states =
      <String, _BinaryRuntimeState>{};
  final Map<String, _FanRuntimeState> _fanStates = <String, _FanRuntimeState>{};
  Timer? _heartbeatTimer;

  bool _initialized = false;
  Future<void> _queue = Future<void>.value();

  bool get isTrackingEnabled => _config.enabled && _config.plcs.isNotEmpty;
  bool get isPersistenceEnabled =>
      isTrackingEnabled && _repository.isConfigured;

  void ingestSnapshot({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) {
    if (!isTrackingEnabled) {
      return;
    }

    if (!_initialized) {
      _seedStateFromSnapshot(
        unitsJson: unitsJson,
        observedAtUtc: observedAtUtc,
      );
      _initialized = true;
      return;
    }

    final List<RuntimeEvent> closedEvents = <RuntimeEvent>[];
    for (final RuntimePlcConfig plc in _config.plcs) {
      final Object? unitRaw = unitsJson[plc.unitKey];
      if (unitRaw is! Map) {
        _log('unit not found plc=${plc.plcId} unit=${plc.unitKey}');
        continue;
      }
      final Map<Object?, Object?> unit = unitRaw as Map<Object?, Object?>;
      closedEvents.addAll(
        _processBinaryDevice(
          plc: plc,
          unit: unit,
          deviceType: _DeviceType.humidifierPump,
          signalKey: plc.humidifierPumpSignal,
          now: observedAtUtc,
        ),
      );
      closedEvents.addAll(
        _processBinaryDevice(
          plc: plc,
          unit: unit,
          deviceType: _DeviceType.heater1,
          signalKey: plc.heater1Signal,
          now: observedAtUtc,
        ),
      );
      closedEvents.addAll(
        _processBinaryDevice(
          plc: plc,
          unit: unit,
          deviceType: _DeviceType.heater2,
          signalKey: plc.heater2Signal,
          now: observedAtUtc,
        ),
      );
      final RuntimeEvent? fanEvent = _processFans(
        plc: plc,
        unit: unit,
        now: observedAtUtc,
      );
      if (fanEvent != null) {
        closedEvents.add(fanEvent);
      }
    }

    if (!isPersistenceEnabled || closedEvents.isEmpty) {
      return;
    }

    _queue = _queue
        .then<void>((_) async {
          for (final RuntimeEvent event in closedEvents) {
            await _repository.saveClosed(event);
            _log(
              'persisted device=${event.deviceType} plc=${event.plcId} durationSec=${event.durationSec}',
            );
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          _log('error processing snapshot error=$error');
          _log('error stack=$stackTrace');
        });
  }

  Future<void> dispose() {
    _heartbeatTimer?.cancel();
    return _queue;
  }

  void _scheduleHeartbeats() {
    if (!isPersistenceEnabled || !_initialized) return;

    final DateTime now = DateTime.now().toUtc();
    final List<RuntimeEvent> heartbeats = <RuntimeEvent>[];

    for (final RuntimePlcConfig plc in _config.plcs) {
      _collectBinaryHeartbeat(
        heartbeats, plc, _DeviceType.humidifierPump, now,
      );
      _collectBinaryHeartbeat(heartbeats, plc, _DeviceType.heater1, now);
      _collectBinaryHeartbeat(heartbeats, plc, _DeviceType.heater2, now);
      _collectFanHeartbeat(heartbeats, plc, now);
    }

    _log('heartbeat tick activeDevices=${heartbeats.length}');
    if (heartbeats.isEmpty) return;

    _queue = _queue
        .then<void>((_) async {
          for (final RuntimeEvent hb in heartbeats) {
            await _repository.saveHeartbeat(hb);
            _log(
              'heartbeat saved device=${hb.deviceType} plc=${hb.plcId}'
              ' activeDurationSec=${hb.durationSec}',
            );
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          _log('error saving heartbeats error=$error');
          _log('error stack=$stackTrace');
        });
  }

  void _collectBinaryHeartbeat(
    List<RuntimeEvent> out,
    RuntimePlcConfig plc,
    String deviceType,
    DateTime now,
  ) {
    final _BinaryRuntimeState? state = _states[_stateKey(plc.plcId, deviceType)];
    if (state == null || state.isOn != true || state.startedAt == null) return;
    out.add(
      RuntimeEvent.heartbeat(
        deviceType: deviceType,
        startedAt: state.startedAt!,
        observedAt: now,
        plcId: plc.plcId,
        powerWatts: _nominalPowerWatts(plc, deviceType),
      ),
    );
  }

  void _collectFanHeartbeat(
    List<RuntimeEvent> out,
    RuntimePlcConfig plc,
    DateTime now,
  ) {
    final _FanRuntimeState? fanState = _fanStates[plc.plcId];
    final int? power = fanState?.lastPowerPercent;
    if (fanState?.startedAt == null || power == null || power <= 0) return;
    out.add(
      RuntimeEvent.heartbeat(
        deviceType: _DeviceType.fans,
        startedAt: fanState!.startedAt!,
        observedAt: now,
        plcId: plc.plcId,
        powerPercent: power,
        powerWatts: _fansPowerWatts(plc, power),
      ),
    );
  }

  void _seedStateFromSnapshot({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) {
    for (final RuntimePlcConfig plc in _config.plcs) {
      final Object? unitRaw = unitsJson[plc.unitKey];
      if (unitRaw is! Map) {
        continue;
      }
      final Map<Object?, Object?> unit = unitRaw as Map<Object?, Object?>;
      _seedBinaryDevice(
        plc: plc,
        unit: unit,
        deviceType: _DeviceType.humidifierPump,
        signalKey: plc.humidifierPumpSignal,
        now: observedAtUtc,
      );
      _seedBinaryDevice(
        plc: plc,
        unit: unit,
        deviceType: _DeviceType.heater1,
        signalKey: plc.heater1Signal,
        now: observedAtUtc,
      );
      _seedBinaryDevice(
        plc: plc,
        unit: unit,
        deviceType: _DeviceType.heater2,
        signalKey: plc.heater2Signal,
        now: observedAtUtc,
      );
      final int? powerPercent = _extractFansPowerPercent(plc, unit);
      final _FanRuntimeState fanState = _fanStates[plc.plcId]!;
      fanState.lastPowerPercent = powerPercent;
      if (powerPercent != null && powerPercent > 0) {
        fanState.startedAt = observedAtUtc;
        _log(
          'seed open fan segment plc=${plc.plcId} powerPercent=$powerPercent',
        );
      }
    }
    _log('initialized from first snapshot');
  }

  void _seedBinaryDevice({
    required RuntimePlcConfig plc,
    required Map<Object?, Object?> unit,
    required String deviceType,
    required String signalKey,
    required DateTime now,
  }) {
    final bool? current = _extractBool(unit[signalKey]);
    if (current == null) {
      return;
    }
    final _BinaryRuntimeState state =
        _states[_stateKey(plc.plcId, deviceType)]!;
    state.isOn = current;
    state.startedAt = current ? now : null;
    if (current) {
      _log('seed open binary event plc=${plc.plcId} device=$deviceType');
    }
  }

  List<RuntimeEvent> _processBinaryDevice({
    required RuntimePlcConfig plc,
    required Map<Object?, Object?> unit,
    required String deviceType,
    required String signalKey,
    required DateTime now,
  }) {
    final bool? current = _extractBool(unit[signalKey]);
    if (current == null) {
      _log(
        'signal not found plc=${plc.plcId} device=$deviceType signal=$signalKey',
      );
      return const <RuntimeEvent>[];
    }

    final _BinaryRuntimeState state =
        _states[_stateKey(plc.plcId, deviceType)]!;
    if (state.isOn == null) {
      state.isOn = current;
      state.startedAt = current ? now : null;
      return const <RuntimeEvent>[];
    }
    if (state.isOn == current) {
      return const <RuntimeEvent>[];
    }

    if (!state.isOn! && current) {
      state
        ..isOn = true
        ..startedAt = now;
      _log('transition off→on plc=${plc.plcId} device=$deviceType');
      return const <RuntimeEvent>[];
    }

    final DateTime startedAt = state.startedAt ?? now;
    final double? powerWatts = _nominalPowerWatts(plc, deviceType);
    final RuntimeEvent event = RuntimeEvent.closed(
      deviceType: deviceType,
      startedAt: startedAt,
      endedAt: now,
      plcId: plc.plcId,
      powerWatts: powerWatts,
    );
    state
      ..isOn = false
      ..startedAt = null;
    _log(
      'transition on→off plc=${plc.plcId} device=$deviceType durationSec=${event.durationSec}',
    );
    return <RuntimeEvent>[event];
  }

  RuntimeEvent? _processFans({
    required RuntimePlcConfig plc,
    required Map<Object?, Object?> unit,
    required DateTime now,
  }) {
    final int? currentPower = _extractFansPowerPercent(plc, unit);
    if (currentPower == null) {
      _log(
        'signal not found plc=${plc.plcId} device=${_DeviceType.fans} signal=${plc.fansPowerSignal}',
      );
      return null;
    }

    final _FanRuntimeState state = _fanStates[plc.plcId]!;
    final int? previousPower = state.lastPowerPercent;
    if (previousPower == null) {
      state.lastPowerPercent = currentPower;
      state.startedAt = currentPower > 0 ? now : null;
      return null;
    }
    if (previousPower == currentPower) {
      return null;
    }

    RuntimeEvent? closedEvent;
    if (previousPower > 0 && state.startedAt != null) {
      final double? powerWatts = _fansPowerWatts(plc, previousPower);
      closedEvent = RuntimeEvent.closed(
        deviceType: _DeviceType.fans,
        startedAt: state.startedAt!,
        endedAt: now,
        plcId: plc.plcId,
        powerPercent: previousPower,
        powerWatts: powerWatts,
      );
      _log(
        'fan segment closed plc=${plc.plcId} powerPercent=$previousPower durationSec=${closedEvent.durationSec}',
      );
    }

    state.lastPowerPercent = currentPower;
    state.startedAt = currentPower > 0 ? now : null;
    if (currentPower > 0) {
      _log('fan segment opened plc=${plc.plcId} powerPercent=$currentPower');
    }
    return closedEvent;
  }

  int? _extractFansPowerPercent(
    RuntimePlcConfig plc,
    Map<Object?, Object?> unit,
  ) {
    final Object? raw = unit[plc.fansPowerSignal];
    final double? value = _extractNum(raw);
    if (value == null || !value.isFinite) {
      return null;
    }
    final int normalized =
        ((value * plc.fansPowerMultiplier) + plc.fansPowerOffset).round();
    return normalized.clamp(0, 100);
  }

  bool? _extractBool(Object? raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    if (raw is String) {
      final String normalized = raw.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'on') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'off') {
        return false;
      }
    }
    return null;
  }

  double? _extractNum(Object? raw) {
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw is String) {
      return double.tryParse(raw.trim());
    }
    return null;
  }

  double? _nominalPowerWatts(RuntimePlcConfig plc, String deviceType) {
    final double? value = plc.nominalPowerWatts[deviceType];
    return value != null && value > 0 ? value : null;
  }

  double? _fansPowerWatts(RuntimePlcConfig plc, int powerPercent) {
    final double? maxWatts = _nominalPowerWatts(plc, _DeviceType.fans);
    if (maxWatts == null) {
      return null;
    }
    return maxWatts * (powerPercent / 100);
  }

  String _stateKey(String plcId, String deviceType) => '$plcId::$deviceType';
}

class _BinaryRuntimeState {
  bool? isOn;
  DateTime? startedAt;
}

class _FanRuntimeState {
  int? lastPowerPercent;
  DateTime? startedAt;
}

class _DeviceType {
  static const String humidifierPump = 'humidifierPump';
  static const String heater1 = 'heater1';
  static const String heater2 = 'heater2';
  static const String fans = 'fans';
}

void _log(String message) {
  stdout.writeln('[runtime-events] $message');
}
