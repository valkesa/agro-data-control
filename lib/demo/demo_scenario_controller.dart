import '../models/dashboard_snapshot.dart';
import 'demo_runtime_selector.dart';
import 'demo_scenario.dart';
import 'demo_signal_definition.dart';

abstract interface class DemoMonotonicClock {
  Duration get elapsed;
}

enum DemoPlaybackState { stopped, running, paused, completed, disposed }

/// Pure deterministic evaluator. Final values persist after an event ends.
/// For overlaps on one signal, the event with the latest start wins; equal
/// starts are ordered by id and the lexicographically greatest id wins.
class DemoScenarioEvaluator {
  const DemoScenarioEvaluator._();

  static Map<DemoSignalKey, Object?> overridesAt(
    DemoScenario scenario,
    Duration elapsed,
  ) {
    final started =
        scenario.events
            .where((event) => event.startTime <= elapsed)
            .toList(growable: false)
          ..sort((a, b) {
            final byTime = a.startTime.compareTo(b.startTime);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    final result = <DemoSignalKey, Object?>{};
    for (final event in started) {
      result[event.signalKey] = _valueAt(event, elapsed);
    }
    return result;
  }

  static Object? _valueAt(DemoEvent event, Duration elapsed) {
    if (event.transition == DemoTransition.instant ||
        elapsed >= event.endTime) {
      return event.toValue;
    }
    final from = (event.fromValue as num).toDouble();
    final to = (event.toValue as num).toDouble();
    final progress =
        (elapsed - event.startTime).inMicroseconds /
        event.duration.inMicroseconds;
    return from + (to - from) * progress.clamp(0.0, 1.0);
  }

  static List<DemoEvent> activeEventsAt(
    DemoScenario scenario,
    Duration elapsed,
  ) => List<DemoEvent>.unmodifiable(
    scenario.events.where(
      (event) =>
          event.startTime <= elapsed &&
          (event.duration == Duration.zero
              ? elapsed == event.startTime
              : elapsed < event.endTime),
    ),
  );
}

class DemoScenarioController {
  DemoScenarioController({
    required DemoRuntimeSelector selector,
    required DemoMonotonicClock clock,
    this.onChanged,
  }) : _selector = selector,
       _clock = clock;

  final DemoRuntimeSelector _selector;
  final DemoMonotonicClock _clock;
  final void Function()? onChanged;
  DemoPlaybackState _state = DemoPlaybackState.stopped;
  DemoScenario? _scenario;
  DashboardSnapshot? _baseline;
  DemoRuntimeScope? _scope;
  String? _role;
  final Map<DemoSignalKey, Object?> _manualOverrides =
      <DemoSignalKey, Object?>{};
  Duration _position = Duration.zero;
  Duration _anchorClock = Duration.zero;
  double _speed = 1;

  DemoPlaybackState get state => _state;
  bool get isActive =>
      _state == DemoPlaybackState.running || _state == DemoPlaybackState.paused;
  Duration get position => _computedPosition();
  Duration get duration => _scenario?.duration ?? Duration.zero;
  double get speed => _speed;
  DemoRuntimeScope? get scope => _scope;
  Map<DemoSignalKey, Object?> get manualOverrides =>
      Map<DemoSignalKey, Object?>.unmodifiable(_manualOverrides);
  List<DemoEvent> get activeEvents => _scenario == null
      ? const <DemoEvent>[]
      : DemoScenarioEvaluator.activeEventsAt(_scenario!, position);

  bool start({
    required String? role,
    required DashboardSnapshot realSnapshot,
    required DemoRuntimeScope scope,
    required DemoScenario scenario,
  }) {
    _ensureUsable();
    stop();
    for (final event in scenario.events) {
      if (event.targetSnapshotUnitKey != scope.snapshotUnitKey) {
        throw ArgumentError.value(
          event.targetSnapshotUnitKey,
          'scenario.events.targetSnapshotUnitKey',
          'Every event must target the active scope snapshotUnitKey',
        );
      }
    }
    final activated = _selector.activate(
      role: role,
      realSnapshot: realSnapshot,
      scope: scope,
      overrides: DemoScenarioEvaluator.overridesAt(scenario, Duration.zero),
    );
    if (!activated) return false;
    _scenario = scenario;
    _manualOverrides.clear();
    _baseline = _selector.baselineSnapshot;
    _scope = scope;
    _role = role;
    _position = Duration.zero;
    _anchorClock = _clock.elapsed;
    _speed = 1;
    _state = DemoPlaybackState.running;
    onChanged?.call();
    return true;
  }

  bool startManual({
    required String? role,
    required DashboardSnapshot realSnapshot,
    required DemoRuntimeScope scope,
  }) {
    _ensureUsable();
    stop();
    final activated = _selector.activate(
      role: role,
      realSnapshot: realSnapshot,
      scope: scope,
      overrides: const <DemoSignalKey, Object?>{},
    );
    if (!activated) return false;
    _scenario = null;
    _baseline = _selector.baselineSnapshot;
    _scope = scope;
    _role = role;
    _manualOverrides.clear();
    _position = Duration.zero;
    _state = DemoPlaybackState.paused;
    onChanged?.call();
    return true;
  }

  void setManualOverride(DemoSignalKey key, Object? value) {
    _ensureUsable();
    if (!isActive) throw StateError('Demo is not active');
    DemoSignalCatalog.definitionFor(
      key,
    ).validateValue(value, parameterName: key.wireName);
    _manualOverrides[key] = value;
    _renderCurrent();
    onChanged?.call();
  }

  void releaseManualOverride(DemoSignalKey key) {
    _ensureUsable();
    if (!_manualOverrides.containsKey(key)) return;
    _manualOverrides.remove(key);
    _renderCurrent();
    onChanged?.call();
  }

  void releaseAllManualOverrides() {
    _ensureUsable();
    if (_manualOverrides.isEmpty) return;
    _manualOverrides.clear();
    _renderCurrent();
    onChanged?.call();
  }

  void tick() {
    _ensureUsable();
    if (_state != DemoPlaybackState.running) return;
    final current = _computedPosition();
    if (current >= duration) {
      _position = duration;
      _state = DemoPlaybackState.completed;
      _manualOverrides.clear();
      _selector.stop();
      onChanged?.call();
      return;
    }
    _renderCurrent(at: current);
    onChanged?.call();
  }

  void pause() {
    _ensureUsable();
    if (_state != DemoPlaybackState.running) return;
    _position = _computedPosition();
    _state = DemoPlaybackState.paused;
    onChanged?.call();
  }

  void resume() {
    _ensureUsable();
    if (_state != DemoPlaybackState.paused) return;
    _anchorClock = _clock.elapsed;
    _state = DemoPlaybackState.running;
    onChanged?.call();
  }

  void setSpeed(double value) {
    _ensureUsable();
    if (!const <double>[0.5, 1, 2, 4].contains(value)) {
      throw ArgumentError.value(value, 'value', 'Expected 0.5, 1, 2 or 4');
    }
    if (_state == DemoPlaybackState.running) {
      _position = _computedPosition();
      _anchorClock = _clock.elapsed;
    }
    _speed = value;
    onChanged?.call();
  }

  bool restart() {
    _ensureUsable();
    final scenario = _scenario;
    final baseline = _baseline;
    final scope = _scope;
    if (scenario == null || baseline == null || scope == null) return false;
    final activated = _selector.activate(
      role: _role,
      realSnapshot: baseline,
      scope: scope,
      overrides: DemoScenarioEvaluator.overridesAt(scenario, Duration.zero),
    );
    if (!activated) return false;
    _position = Duration.zero;
    _manualOverrides.clear();
    _anchorClock = _clock.elapsed;
    _state = DemoPlaybackState.running;
    onChanged?.call();
    return true;
  }

  void onRoleChanged(String? role) {
    if (!_selector.isAvailableForRole(role)) stop();
  }

  void onTenantChanged(String tenantId) {
    if (_scope?.tenantId != tenantId) stop();
  }

  void onSiteChanged(String siteId) {
    if (_scope?.siteId != siteId) stop();
  }

  void onDeviceChanged({
    required String deviceId,
    required String snapshotUnitKey,
  }) {
    final scope = _scope;
    if (scope != null &&
        (scope.deviceId != deviceId ||
            scope.snapshotUnitKey != snapshotUnitKey)) {
      stop();
    }
  }

  void onLogout() => stop();

  void stop() {
    if (_state == DemoPlaybackState.disposed) return;
    _selector.stop();
    _state = DemoPlaybackState.stopped;
    _scenario = null;
    _baseline = null;
    _scope = null;
    _role = null;
    _manualOverrides.clear();
    _position = Duration.zero;
    onChanged?.call();
  }

  void dispose() {
    stop();
    _state = DemoPlaybackState.disposed;
  }

  Duration _computedPosition() {
    if (_state != DemoPlaybackState.running) return _position;
    final clockNow = _clock.elapsed;
    if (clockNow < _anchorClock) {
      // A DemoMonotonicClock must never move backwards. Re-anchor defensively
      // if an adapter is reset so the session does not wait through a
      // negative interval.
      _anchorClock = clockNow;
      return _position;
    }
    final deltaMicros = clockNow.inMicroseconds - _anchorClock.inMicroseconds;
    return _position + Duration(microseconds: (deltaMicros * _speed).round());
  }

  void _renderCurrent({Duration? at}) {
    final temporal = _scenario == null
        ? const <DemoSignalKey, Object?>{}
        : DemoScenarioEvaluator.overridesAt(
            _scenario!,
            at ?? _computedPosition(),
          );
    _selector.updatePresentation(<DemoSignalKey, Object?>{
      ...temporal,
      ..._manualOverrides,
    });
  }

  void _ensureUsable() {
    if (_state == DemoPlaybackState.disposed) {
      throw StateError('DemoScenarioController has been disposed');
    }
  }
}
