import 'dart:convert';

import 'demo_scenario.dart';
import 'demo_scenario_draft.dart';
import 'demo_signal_definition.dart';

class DemoScenarioFileException implements Exception {
  const DemoScenarioFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Versioned, device-independent interchange format for confirmed draft data.
/// It deliberately excludes runtime scope, real readings and playback state.
class DemoScenarioFileCodec {
  const DemoScenarioFileCodec._();

  static const String formatId = 'agro-data-control.demo-scenario';
  static const int schemaVersion = 1;
  static const int maxFileBytes = 1024 * 1024;
  static const int maxEvents = 500;

  static String encode(DemoScenarioDraft draft) {
    _validateDraftShape(draft);
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'format': formatId,
      'schemaVersion': schemaVersion,
      'scenario': <String, Object?>{
        'id': draft.id,
        'name': draft.name,
        'durationMs': _milliseconds(draft.durationSeconds),
        'events': <Map<String, Object?>>[
          for (final event in draft.events)
            <String, Object?>{
              'id': event.id,
              'name': event.name,
              'signalKey': event.signalKey.wireName,
              'startTimeMs': _milliseconds(event.startSeconds),
              'durationMs': _milliseconds(event.durationSeconds),
              'transition': event.transition.name,
              if (event.fromValue != null) 'fromValue': event.fromValue,
              'toValue': event.toValue,
              if (event.endMode != DemoEventEndMode.keepApplied)
                'endMode': event.endMode.name,
              if (event.endMode == DemoEventEndMode.setValue)
                'endValue': event.endValue,
            },
        ],
      },
    });
  }

  static DemoScenarioDraft decode(String source) {
    if (utf8.encode(source).length > maxFileBytes) {
      throw const DemoScenarioFileException(
        'El archivo supera el límite de 1 MB.',
      );
    }
    try {
      final root = _map(jsonDecode(source), 'raíz');
      if (root['format'] != formatId) {
        throw const DemoScenarioFileException(
          'El archivo no es un escenario de AgroData Control.',
        );
      }
      final version = root['schemaVersion'];
      if (version is! int) {
        throw const DemoScenarioFileException('schemaVersion debe ser entero.');
      }
      if (version > schemaVersion) {
        throw DemoScenarioFileException(
          'La versión $version todavía no es compatible.',
        );
      }
      if (version != schemaVersion) {
        throw DemoScenarioFileException(
          'La versión $version no es compatible.',
        );
      }
      final scenario = _map(root['scenario'], 'scenario');
      final rawEvents = scenario['events'];
      if (rawEvents is! List) {
        throw const DemoScenarioFileException('events debe ser una lista.');
      }
      if (rawEvents.length > maxEvents) {
        throw const DemoScenarioFileException(
          'El escenario supera el límite de 500 eventos.',
        );
      }
      final draft = DemoScenarioDraft(
        id: _text(scenario['id'], 'scenario.id'),
        name: _text(scenario['name'], 'scenario.name'),
        durationSeconds: _number(scenario['durationMs'], 'durationMs') / 1000,
        events: <DemoEventDraft>[
          for (var i = 0; i < rawEvents.length; i++)
            _decodeEvent(_map(rawEvents[i], 'events[$i]'), i),
        ],
      );
      _validateDraftShape(draft);
      final validation = draft.validate('__imported_device__');
      if (!validation.isValid) {
        throw DemoScenarioFileException(validation.errors.join(' '));
      }
      return draft;
    } on DemoScenarioFileException {
      rethrow;
    } on FormatException catch (error) {
      throw DemoScenarioFileException('JSON inválido: ${error.message}');
    } on Object catch (error) {
      throw DemoScenarioFileException('Escenario inválido: $error');
    }
  }

  static DemoEventDraft _decodeEvent(Map<String, Object?> map, int index) {
    final transitionName = _text(
      map['transition'],
      'events[$index].transition',
    );
    final transition = DemoTransition.values.where(
      (value) => value.name == transitionName,
    );
    if (transition.length != 1) {
      throw DemoScenarioFileException(
        'events[$index].transition no es compatible.',
      );
    }
    final rawEndMode = map['endMode'];
    var resolvedEndMode = DemoEventEndMode.keepApplied;
    if (rawEndMode != null) {
      final matches = DemoEventEndMode.values.where(
        (value) => value.name == rawEndMode,
      );
      if (matches.length != 1) {
        throw DemoScenarioFileException(
          'events[$index].endMode no es compatible.',
        );
      }
      resolvedEndMode = matches.single;
    }
    return DemoEventDraft(
      id: _text(map['id'], 'events[$index].id'),
      name: map['name'] == null
          ? ''
          : _text(map['name'], 'events[$index].name', allowEmpty: true),
      signalKey: DemoSignalCatalog.parseKey(
        _text(map['signalKey'], 'events[$index].signalKey'),
      ),
      startSeconds:
          _number(map['startTimeMs'], 'events[$index].startTimeMs') / 1000,
      durationSeconds:
          _number(map['durationMs'], 'events[$index].durationMs') / 1000,
      transition: transition.single,
      fromValue: map['fromValue'],
      toValue: map['toValue'],
      endMode: resolvedEndMode,
      endValue: resolvedEndMode == DemoEventEndMode.setValue
          ? map['endValue']
          : null,
    );
  }

  static void _validateDraftShape(DemoScenarioDraft draft) {
    if (draft.id.trim().isEmpty || draft.id.length > 120) {
      throw const DemoScenarioFileException(
        'La identidad del escenario es inválida.',
      );
    }
    if (draft.name.trim().isEmpty || draft.name.length > 200) {
      throw const DemoScenarioFileException(
        'El nombre del escenario es inválido.',
      );
    }
    if (draft.events.length > maxEvents) {
      throw const DemoScenarioFileException(
        'El escenario supera el límite de 500 eventos.',
      );
    }
    final ids = <String>{};
    for (final event in draft.events) {
      if (event.id.trim().isEmpty ||
          event.id.length > 120 ||
          !ids.add(event.id)) {
        throw DemoScenarioFileException(
          'Identidad de evento inválida o repetida: ${event.id}.',
        );
      }
      if (event.name.length > 200) {
        throw DemoScenarioFileException(
          'El nombre de ${event.id} es demasiado largo.',
        );
      }
    }
  }

  static int _milliseconds(double seconds) {
    if (!seconds.isFinite) {
      throw const DemoScenarioFileException('Los tiempos deben ser finitos.');
    }
    return (seconds * 1000).round();
  }

  static Map<String, Object?> _map(Object? value, String field) {
    if (value is! Map) {
      throw DemoScenarioFileException('$field debe ser un objeto.');
    }
    return value.map((key, value) {
      if (key is! String) {
        throw DemoScenarioFileException('$field contiene una clave inválida.');
      }
      return MapEntry(key, value);
    });
  }

  static String _text(Object? value, String field, {bool allowEmpty = false}) {
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      throw DemoScenarioFileException(
        '$field debe ser texto${allowEmpty ? '' : ' no vacío'}.',
      );
    }
    return value;
  }

  static double _number(Object? value, String field) {
    if (value is! num || !value.isFinite) {
      throw DemoScenarioFileException('$field debe ser un número finito.');
    }
    return value.toDouble();
  }
}
