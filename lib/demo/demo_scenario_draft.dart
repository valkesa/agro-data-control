import 'demo_scenario.dart';
import 'demo_signal_definition.dart';

class DemoEventDraft {
  const DemoEventDraft({
    required this.id,
    this.name = '',
    required this.signalKey,
    required this.startSeconds,
    required this.durationSeconds,
    required this.transition,
    this.fromValue,
    this.toValue,
  });
  final String id;
  final String name;
  final DemoSignalKey signalKey;
  final double startSeconds;
  final double durationSeconds;
  final DemoTransition transition;
  final Object? fromValue;
  final Object? toValue;
  DemoEventDraft copyWith({
    String? name,
    DemoSignalKey? signalKey,
    double? startSeconds,
    double? durationSeconds,
    DemoTransition? transition,
    Object? fromValue = _unset,
    Object? toValue = _unset,
  }) => DemoEventDraft(
    id: id,
    name: name ?? this.name,
    signalKey: signalKey ?? this.signalKey,
    startSeconds: startSeconds ?? this.startSeconds,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    transition: transition ?? this.transition,
    fromValue: identical(fromValue, _unset) ? this.fromValue : fromValue,
    toValue: identical(toValue, _unset) ? this.toValue : toValue,
  );
  static const _unset = Object();
}

class DemoDraftValidation {
  const DemoDraftValidation({
    required this.errors,
    required this.warnings,
    this.scenario,
  });
  final List<String> errors;
  final List<String> warnings;
  final DemoScenario? scenario;
  bool get isValid => errors.isEmpty && scenario != null;
}

class DemoScenarioDraft {
  DemoScenarioDraft({
    required this.id,
    required this.name,
    required this.durationSeconds,
    Iterable<DemoEventDraft> events = const [],
  }) : events = List<DemoEventDraft>.from(events);
  final String id;
  String name;
  double durationSeconds;
  final List<DemoEventDraft> events;
  int _nextId = 1;

  String addEvent({required DemoSignalKey signalKey}) {
    String id;
    do {
      id = 'event-${_nextId++}';
    } while (events.any((e) => e.id == id));
    final d = DemoSignalCatalog.definitionFor(signalKey);
    events.add(
      DemoEventDraft(
        id: id,
        signalKey: signalKey,
        startSeconds: 0,
        durationSeconds: 0,
        transition: DemoTransition.instant,
        toValue: d.kind == DemoSignalKind.number
            ? (d.min ?? 0)
            : d.kind == DemoSignalKind.boolean
            ? false
            : d.allowedTextValues.firstOrNull,
      ),
    );
    return id;
  }

  void updateEvent(DemoEventDraft event) {
    final i = events.indexWhere((e) => e.id == event.id);
    if (i < 0) throw ArgumentError('Unknown event id ${event.id}');
    events[i] = event;
  }

  void removeEvent(String id) => events.removeWhere((e) => e.id == id);
  void moveEvent(String id, int newIndex) {
    final old = events.indexWhere((e) => e.id == id);
    if (old < 0 || newIndex < 0 || newIndex >= events.length) {
      throw ArgumentError('Invalid reorder');
    }
    final event = events.removeAt(old);
    events.insert(newIndex, event);
  }

  DemoDraftValidation validate(String snapshotUnitKey) {
    final errors = <String>[];
    final built = <DemoEvent>[];
    if (name.trim().isEmpty) {
      errors.add('El nombre es obligatorio.');
    }
    if (!durationSeconds.isFinite || durationSeconds <= 0) {
      errors.add('La duración total debe ser positiva y finita.');
    }
    for (final e in events) {
      try {
        if (!e.startSeconds.isFinite || !e.durationSeconds.isFinite) {
          throw ArgumentError('tiempo no finito');
        }
        built.add(
          DemoEvent(
            id: e.id,
            targetSnapshotUnitKey: snapshotUnitKey,
            signalKey: e.signalKey,
            startTime: Duration(
              microseconds: (e.startSeconds * 1000000).round(),
            ),
            duration: Duration(
              microseconds: (e.durationSeconds * 1000000).round(),
            ),
            fromValue: e.fromValue,
            toValue: e.toValue,
            transition: e.transition,
          ),
        );
      } catch (error) {
        errors.add('${e.id}: $error');
      }
    }
    DemoScenario? scenario;
    if (errors.isEmpty) {
      try {
        scenario = DemoScenario(
          id: id,
          name: name.trim(),
          duration: Duration(microseconds: (durationSeconds * 1000000).round()),
          events: built,
        );
      } catch (error) {
        errors.add(error.toString());
      }
    }
    final warnings = <String>[];
    for (var i = 0; i < built.length; i++) {
      for (var j = i + 1; j < built.length; j++) {
        final a = built[i], b = built[j];
        if (a.signalKey == b.signalKey &&
            a.startTime < b.endTime &&
            b.startTime < a.endTime) {
          warnings.add(
            '${a.id} y ${b.id} se solapan; gana el inicio más reciente y luego el ID mayor.',
          );
        }
      }
    }
    return DemoDraftValidation(
      errors: List.unmodifiable(errors),
      warnings: List.unmodifiable(warnings),
      scenario: scenario,
    );
  }

  factory DemoScenarioDraft.fromScenario(DemoScenario scenario) =>
      DemoScenarioDraft(
        id: '${scenario.id}-draft',
        name: '${scenario.name} (copia)',
        durationSeconds: scenario.duration.inMicroseconds / 1000000,
        events: [
          for (final e in scenario.events)
            DemoEventDraft(
              id: e.id,
              name: '',
              signalKey: e.signalKey,
              startSeconds: e.startTime.inMicroseconds / 1000000,
              durationSeconds: e.duration.inMicroseconds / 1000000,
              transition: e.transition,
              fromValue: e.fromValue,
              toValue: e.toValue,
            ),
        ],
      );
}

DemoScenario buildTechnicalDemoScenario({
  required String snapshotUnitKey,
  required double temperature,
  required double humidity,
}) => DemoScenario(
  id: 'technical-sequence-2d',
  name: 'Secuencia técnica 2D',
  duration: const Duration(seconds: 25),
  events: <DemoEvent>[
    DemoEvent(
      id: 'temperature-rise',
      targetSnapshotUnitKey: snapshotUnitKey,
      signalKey: DemoSignalKey.indoorTemperature,
      startTime: Duration.zero,
      duration: const Duration(seconds: 10),
      fromValue: temperature,
      toValue: 40.0,
      transition: DemoTransition.linear,
    ),
    DemoEvent(
      id: 'humidity-rise',
      targetSnapshotUnitKey: snapshotUnitKey,
      signalKey: DemoSignalKey.indoorHumidity,
      startTime: const Duration(seconds: 5),
      duration: const Duration(seconds: 10),
      fromValue: humidity,
      toValue: 90.0,
      transition: DemoTransition.linear,
    ),
    DemoEvent(
      id: 'heating-on',
      targetSnapshotUnitKey: snapshotUnitKey,
      signalKey: DemoSignalKey.heatingStage1,
      startTime: const Duration(seconds: 10),
      duration: Duration.zero,
      toValue: true,
    ),
    DemoEvent(
      id: 'heating-off',
      targetSnapshotUnitKey: snapshotUnitKey,
      signalKey: DemoSignalKey.heatingStage1,
      startTime: const Duration(seconds: 18),
      duration: Duration.zero,
      toValue: false,
    ),
  ],
);
