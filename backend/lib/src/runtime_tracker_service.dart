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
        'hbGapThresholdMs=${config.hbGapThresholdMs} '
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
  }

  final RuntimeEventsConfig _config;
  final FirestoreRuntimeEventsRepository _repository;
  final Map<String, _BinaryRuntimeState> _states =
      <String, _BinaryRuntimeState>{};
  final Map<String, _FanRuntimeState> _fanStates = <String, _FanRuntimeState>{};

  bool _initialized = false;
  Future<void> _queue = Future<void>.value();

  bool get isTrackingEnabled => _config.enabled && _config.plcs.isNotEmpty;
  bool get isPersistenceEnabled =>
      isTrackingEnabled && _repository.isConfigured;

  void ingestSnapshot({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) {
    if (!isTrackingEnabled) return;

    if (!_initialized) {
      final List<RuntimeEvent> seedHbs = _seedStateFromSnapshot(
        unitsJson: unitsJson,
        observedAtUtc: observedAtUtc,
      );
      _initialized = true;
      if (isPersistenceEnabled && seedHbs.isNotEmpty) {
        final List<_HbSaveTask> tasks = seedHbs
            .map((RuntimeEvent hb) => _resolveHbTask(hb, _trackingFor(hb)))
            .toList();
        _queue = _queue.then<void>((_) => _saveHeartbeats(tasks)).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          _log('error processing initial heartbeats error=$error');
          _log('error stack=$stackTrace');
        });
      }
      return;
    }

    final List<RuntimeEvent> closedEvents = <RuntimeEvent>[];
    final List<_HbSaveTask> hbTasks = <_HbSaveTask>[];

    for (final RuntimePlcConfig plc in _config.plcs) {
      final Object? unitRaw = unitsJson[plc.unitKey];
      if (unitRaw is! Map) {
        _log('unit not found plc=${plc.plcId} unit=${plc.unitKey}');
        continue;
      }
      final Map<Object?, Object?> unit = unitRaw as Map<Object?, Object?>;

      _collectChanges(
        _processBinaryDevice(
          plc: plc,
          unit: unit,
          deviceType: _DeviceType.humidifierPump,
          signalKey: plc.humidifierPumpSignal,
          now: observedAtUtc,
        ),
        tracking: _states[_stateKey(plc.plcId, _DeviceType.humidifierPump)]!
            .hbTracking,
        closedEvents: closedEvents,
        hbTasks: hbTasks,
      );
      _collectChanges(
        _processBinaryDevice(
          plc: plc,
          unit: unit,
          deviceType: _DeviceType.heater1,
          signalKey: plc.heater1Signal,
          now: observedAtUtc,
        ),
        tracking:
            _states[_stateKey(plc.plcId, _DeviceType.heater1)]!.hbTracking,
        closedEvents: closedEvents,
        hbTasks: hbTasks,
      );
      _collectChanges(
        _processBinaryDevice(
          plc: plc,
          unit: unit,
          deviceType: _DeviceType.heater2,
          signalKey: plc.heater2Signal,
          now: observedAtUtc,
        ),
        tracking:
            _states[_stateKey(plc.plcId, _DeviceType.heater2)]!.hbTracking,
        closedEvents: closedEvents,
        hbTasks: hbTasks,
      );
      _collectChanges(
        _processFans(plc: plc, unit: unit, now: observedAtUtc),
        tracking: _fanStates[plc.plcId]!.hbTracking,
        closedEvents: closedEvents,
        hbTasks: hbTasks,
      );
    }

    if (!isPersistenceEnabled || (closedEvents.isEmpty && hbTasks.isEmpty)) {
      return;
    }

    _queue = _queue
        .then<void>((_) async {
          await _saveHeartbeats(hbTasks);
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

  void _collectChanges(
    _RuntimeTrackerChanges changes, {
    required _HbTracking tracking,
    required List<RuntimeEvent> closedEvents,
    required List<_HbSaveTask> hbTasks,
  }) {
    closedEvents.addAll(changes.closedEvents);
    for (final RuntimeEvent hb in changes.heartbeatEvents) {
      hbTasks.add(_resolveHbTask(hb, tracking));
    }
  }

  // Decides whether to reuse the previous HB document (within gap threshold)
  // or create a new one. Updates tracking in-place.
  _HbSaveTask _resolveHbTask(RuntimeEvent hb, _HbTracking tracking) {
    final DateTime observedAt = hb.endedAt ?? DateTime.now().toUtc();
    final String docId;
    if (tracking.lastDocId != null &&
        tracking.lastObservedAt != null &&
        observedAt.difference(tracking.lastObservedAt!).inMilliseconds.abs() <=
            _config.hbGapThresholdMs) {
      docId = tracking.lastDocId!; // reuse → overwrites same Firestore doc
    } else {
      docId = _makeHbDocId(hb, observedAt); // gap or first HB → new doc
    }
    tracking
      ..lastDocId = docId
      ..lastObservedAt = observedAt;
    return _HbSaveTask(event: hb, docId: docId);
  }

  Future<void> _saveHeartbeats(List<_HbSaveTask> tasks) async {
    for (final _HbSaveTask task in tasks) {
      await _repository.saveHeartbeat(task.event, docId: task.docId);
      _log(
        'heartbeat device=${task.event.deviceType} plc=${task.event.plcId}'
        ' activeDurationSec=${task.event.durationSec} doc=${task.docId}',
      );
    }
  }

  Future<void> dispose() => _queue;

  List<RuntimeEvent> _seedStateFromSnapshot({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) {
    final List<RuntimeEvent> heartbeatEvents = <RuntimeEvent>[];
    for (final RuntimePlcConfig plc in _config.plcs) {
      final Object? unitRaw = unitsJson[plc.unitKey];
      if (unitRaw is! Map) continue;
      final Map<Object?, Object?> unit = unitRaw as Map<Object?, Object?>;
      _seedBinaryDevice(
        plc: plc,
        unit: unit,
        deviceType: _DeviceType.humidifierPump,
        signalKey: plc.humidifierPumpSignal,
        now: observedAtUtc,
        heartbeatEvents: heartbeatEvents,
      );
      _seedBinaryDevice(
        plc: plc,
        unit: unit,
        deviceType: _DeviceType.heater1,
        signalKey: plc.heater1Signal,
        now: observedAtUtc,
        heartbeatEvents: heartbeatEvents,
      );
      _seedBinaryDevice(
        plc: plc,
        unit: unit,
        deviceType: _DeviceType.heater2,
        signalKey: plc.heater2Signal,
        now: observedAtUtc,
        heartbeatEvents: heartbeatEvents,
      );
      final int? powerPercent = _extractFansPowerPercent(plc, unit);
      final _FanRuntimeState fanState = _fanStates[plc.plcId]!;
      fanState.lastPowerPercent = powerPercent;
      if (powerPercent != null && powerPercent > 0) {
        fanState.startedAt = observedAtUtc;
        _log(
          'seed open fan segment plc=${plc.plcId} powerPercent=$powerPercent',
        );
        heartbeatEvents.add(
          _fanHeartbeat(plc, powerPercent, observedAtUtc, observedAtUtc),
        );
      } else {
        _log('seed off fan segment plc=${plc.plcId}');
      }
    }
    _log('initialized from first snapshot');
    return heartbeatEvents;
  }

  void _seedBinaryDevice({
    required RuntimePlcConfig plc,
    required Map<Object?, Object?> unit,
    required String deviceType,
    required String signalKey,
    required DateTime now,
    required List<RuntimeEvent> heartbeatEvents,
  }) {
    final bool? current = _extractBool(unit[signalKey]);
    if (current == null) return;
    final _BinaryRuntimeState state =
        _states[_stateKey(plc.plcId, deviceType)]!;
    state.isOn = current;
    state.startedAt = current ? now : null;
    if (current) {
      _log('seed open binary event plc=${plc.plcId} device=$deviceType');
      heartbeatEvents.add(_binaryHeartbeat(plc, deviceType, now, now));
    } else {
      _log('seed off binary event plc=${plc.plcId} device=$deviceType');
    }
  }

  _RuntimeTrackerChanges _processBinaryDevice({
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
      return const _RuntimeTrackerChanges.empty();
    }

    final _BinaryRuntimeState state =
        _states[_stateKey(plc.plcId, deviceType)]!;
    if (state.isOn == null) {
      state.isOn = current;
      state.startedAt = current ? now : null;
      if (!current) return const _RuntimeTrackerChanges.empty();
      return _RuntimeTrackerChanges(
        heartbeatEvents: <RuntimeEvent>[
          _binaryHeartbeat(plc, deviceType, now, now),
        ],
      );
    }

    if (state.isOn == current) {
      return const _RuntimeTrackerChanges.empty();
    }

    // State changed: OFF → ON
    if (!state.isOn! && current) {
      state
        ..isOn = true
        ..startedAt = now;
      _log('transition off→on plc=${plc.plcId} device=$deviceType');
      return _RuntimeTrackerChanges(
        heartbeatEvents: <RuntimeEvent>[
          _binaryHeartbeat(plc, deviceType, now, now),
        ],
      );
    }

    // State changed: ON → OFF
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
    return _RuntimeTrackerChanges(closedEvents: <RuntimeEvent>[event]);
  }

  _RuntimeTrackerChanges _processFans({
    required RuntimePlcConfig plc,
    required Map<Object?, Object?> unit,
    required DateTime now,
  }) {
    final int? currentPower = _extractFansPowerPercent(plc, unit);
    if (currentPower == null) {
      _log(
        'signal not found plc=${plc.plcId} device=${_DeviceType.fans} signal=${plc.fansPowerSignal}',
      );
      return const _RuntimeTrackerChanges.empty();
    }

    final _FanRuntimeState state = _fanStates[plc.plcId]!;
    final int? previousPower = state.lastPowerPercent;
    if (previousPower == null) {
      state.lastPowerPercent = currentPower;
      state.startedAt = currentPower > 0 ? now : null;
      if (currentPower <= 0) return const _RuntimeTrackerChanges.empty();
      return _RuntimeTrackerChanges(
        heartbeatEvents: <RuntimeEvent>[
          _fanHeartbeat(plc, currentPower, now, now),
        ],
      );
    }

    if (previousPower == currentPower) {
      return const _RuntimeTrackerChanges.empty();
    }

    // Power changed
    final List<RuntimeEvent> closedEvents = <RuntimeEvent>[];
    final List<RuntimeEvent> heartbeatEvents = <RuntimeEvent>[];
    if (previousPower > 0 && state.startedAt != null) {
      final double? powerWatts = _fansPowerWatts(plc, previousPower);
      final RuntimeEvent closedEvent = RuntimeEvent.closed(
        deviceType: _DeviceType.fans,
        startedAt: state.startedAt!,
        endedAt: now,
        plcId: plc.plcId,
        powerPercent: previousPower,
        powerWatts: powerWatts,
      );
      closedEvents.add(closedEvent);
      _log(
        'fan segment closed plc=${plc.plcId} powerPercent=$previousPower durationSec=${closedEvent.durationSec}',
      );
    }

    state.lastPowerPercent = currentPower;
    state.startedAt = currentPower > 0 ? now : null;
    if (currentPower > 0) {
      _log('fan segment opened plc=${plc.plcId} powerPercent=$currentPower');
      heartbeatEvents.add(_fanHeartbeat(plc, currentPower, now, now));
    }
    return _RuntimeTrackerChanges(
      closedEvents: closedEvents,
      heartbeatEvents: heartbeatEvents,
    );
  }

  // ── Lookup helpers ────────────────────────────────────────────────────────

  _HbTracking _trackingFor(RuntimeEvent hb) {
    if (hb.deviceType == _DeviceType.fans) {
      return _fanStates[hb.plcId]!.hbTracking;
    }
    return _states[_stateKey(hb.plcId, hb.deviceType)]!.hbTracking;
  }

  // ── Event builders ────────────────────────────────────────────────────────

  RuntimeEvent _binaryHeartbeat(
    RuntimePlcConfig plc,
    String deviceType,
    DateTime startedAt,
    DateTime observedAt,
  ) {
    return RuntimeEvent.heartbeat(
      deviceType: deviceType,
      startedAt: startedAt,
      observedAt: observedAt,
      plcId: plc.plcId,
      powerWatts: _nominalPowerWatts(plc, deviceType),
    );
  }

  RuntimeEvent _fanHeartbeat(
    RuntimePlcConfig plc,
    int powerPercent,
    DateTime startedAt,
    DateTime observedAt,
  ) {
    return RuntimeEvent.heartbeat(
      deviceType: _DeviceType.fans,
      startedAt: startedAt,
      observedAt: observedAt,
      plcId: plc.plcId,
      powerPercent: powerPercent,
      powerWatts: _fansPowerWatts(plc, powerPercent),
    );
  }

  // ── Signal extractors ─────────────────────────────────────────────────────

  int? _extractFansPowerPercent(
    RuntimePlcConfig plc,
    Map<Object?, Object?> unit,
  ) {
    final Object? raw = unit[plc.fansPowerSignal];
    final double? value = _extractNum(raw);
    if (value == null || !value.isFinite) return null;
    final int normalized =
        ((value * plc.fansPowerMultiplier) + plc.fansPowerOffset).round();
    return normalized.clamp(0, 100);
  }

  bool? _extractBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final String n = raw.trim().toLowerCase();
      if (n == 'true' || n == '1' || n == 'on') return true;
      if (n == 'false' || n == '0' || n == 'off') return false;
    }
    return null;
  }

  double? _extractNum(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  double? _nominalPowerWatts(RuntimePlcConfig plc, String deviceType) {
    final double? value = plc.nominalPowerWatts[deviceType];
    return value != null && value > 0 ? value : null;
  }

  double? _fansPowerWatts(RuntimePlcConfig plc, int powerPercent) {
    final double? maxWatts = _nominalPowerWatts(plc, _DeviceType.fans);
    if (maxWatts == null) return null;
    return maxWatts * (powerPercent / 100);
  }

  String _stateKey(String plcId, String deviceType) => '$plcId::$deviceType';
}

// ── Doc ID generation ─────────────────────────────────────────────────────────

String _makeHbDocId(RuntimeEvent event, DateTime observedAt) {
  final DateTime t = observedAt.toUtc();
  final String y = t.year.toString().padLeft(4, '0');
  final String mo = t.month.toString().padLeft(2, '0');
  final String d = t.day.toString().padLeft(2, '0');
  final String h = t.hour.toString().padLeft(2, '0');
  final String mi = t.minute.toString().padLeft(2, '0');
  final String s = t.second.toString().padLeft(2, '0');
  final String ms = t.millisecond.toString().padLeft(3, '0');
  final String safeDeviceType = event.deviceType.replaceAll(
    RegExp(r'[^A-Za-z0-9_-]'),
    '_',
  );
  return '${y}${mo}${d}_${h}${mi}${s}_${ms}_${safeDeviceType}_hb';
}

// ── State classes ─────────────────────────────────────────────────────────────

class _HbTracking {
  String? lastDocId;
  DateTime? lastObservedAt;
}

class _HbSaveTask {
  _HbSaveTask({required this.event, required this.docId});
  final RuntimeEvent event;
  final String docId;
}

class _BinaryRuntimeState {
  bool? isOn;
  DateTime? startedAt;
  final _HbTracking hbTracking = _HbTracking();
}

class _FanRuntimeState {
  int? lastPowerPercent;
  DateTime? startedAt;
  final _HbTracking hbTracking = _HbTracking();
}

class _RuntimeTrackerChanges {
  const _RuntimeTrackerChanges({
    this.closedEvents = const <RuntimeEvent>[],
    this.heartbeatEvents = const <RuntimeEvent>[],
  });

  const _RuntimeTrackerChanges.empty()
    : closedEvents = const <RuntimeEvent>[],
      heartbeatEvents = const <RuntimeEvent>[];

  final List<RuntimeEvent> closedEvents;
  final List<RuntimeEvent> heartbeatEvents;
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
