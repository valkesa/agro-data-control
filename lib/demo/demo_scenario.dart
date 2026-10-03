import 'demo_signal_definition.dart';

enum DemoTransition { instant, linear }

/// One validated, side-effect-free change in a demo scenario.
class DemoEvent {
  DemoEvent({
    required this.id,
    required this.targetSnapshotUnitKey,
    required this.signalKey,
    required this.startTime,
    required this.duration,
    required this.toValue,
    this.fromValue,
    this.transition = DemoTransition.instant,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty');
    }
    if (targetSnapshotUnitKey.trim().isEmpty) {
      throw ArgumentError.value(
        targetSnapshotUnitKey,
        'targetSnapshotUnitKey',
        'Must not be empty',
      );
    }
    if (startTime.isNegative) {
      throw ArgumentError.value(startTime, 'startTime', 'Must not be negative');
    }
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative');
    }

    final definition = DemoSignalCatalog.definitionFor(signalKey);
    definition.validateValue(toValue, parameterName: 'toValue');
    if (fromValue != null) {
      definition.validateValue(fromValue, parameterName: 'fromValue');
    }
    if (transition == DemoTransition.linear) {
      if (!definition.interpolable) {
        throw ArgumentError.value(
          signalKey.wireName,
          'signalKey',
          'Signal does not support linear interpolation',
        );
      }
      if (duration == Duration.zero) {
        throw ArgumentError.value(
          duration,
          'duration',
          'Linear transitions require a positive duration',
        );
      }
      if (fromValue is! num || toValue is! num) {
        throw ArgumentError(
          'Linear transitions require numeric fromValue and toValue',
        );
      }
    }
  }

  factory DemoEvent.fromMap(Map<String, Object?> map) {
    final transitionName = map['transition'] as String? ?? 'instant';
    final transition = DemoTransition.values.where(
      (value) => value.name == transitionName,
    );
    if (transition.isEmpty) {
      throw ArgumentError.value(
        transitionName,
        'transition',
        'Unsupported demo transition',
      );
    }
    return DemoEvent(
      id: map['id'] as String,
      targetSnapshotUnitKey: map['targetSnapshotUnitKey'] as String,
      signalKey: DemoSignalCatalog.parseKey(map['signalKey'] as String),
      startTime: Duration(milliseconds: map['startTimeMs'] as int),
      duration: Duration(milliseconds: map['durationMs'] as int),
      fromValue: map['fromValue'],
      toValue: map['toValue'],
      transition: transition.single,
    );
  }

  final String id;
  final String targetSnapshotUnitKey;
  final DemoSignalKey signalKey;
  final Duration startTime;
  final Duration duration;
  final Object? fromValue;
  final Object? toValue;
  final DemoTransition transition;

  Duration get endTime => startTime + duration;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'targetSnapshotUnitKey': targetSnapshotUnitKey,
    'signalKey': signalKey.wireName,
    'startTimeMs': startTime.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    if (fromValue != null) 'fromValue': fromValue,
    'toValue': toValue,
    'transition': transition.name,
  };
}

/// Validated scenario definition. Stage 2A stores data only; it has no clock,
/// timers, playback state or persistence.
class DemoScenario {
  DemoScenario({
    required this.id,
    required this.name,
    required this.duration,
    Iterable<DemoEvent> events = const <DemoEvent>[],
  }) : events = List<DemoEvent>.unmodifiable(events) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty');
    }
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive');
    }
    final ids = <String>{};
    for (final event in this.events) {
      if (!ids.add(event.id)) {
        throw ArgumentError('Duplicate event id "${event.id}"');
      }
      if (event.endTime > duration) {
        throw ArgumentError(
          'Event "${event.id}" ends after the scenario duration',
        );
      }
    }
  }

  final String id;
  final String name;
  final Duration duration;
  final List<DemoEvent> events;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'durationMs': duration.inMilliseconds,
    'events': events.map((event) => event.toMap()).toList(growable: false),
  };
}
