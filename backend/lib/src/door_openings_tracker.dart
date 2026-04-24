import 'dart:async';
import 'dart:io';

import 'package:agro_data_control_backend/src/firestore_door_openings_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';

/// Detecta transiciones de estado (cerrada↔abierta) en cada poll del PLC
/// y persiste los eventos en Firestore sin escribir en cada snapshot.
///
/// Uso:
///   1. Crear una instancia en SnapshotRuntime.
///   2. Llamar a [handleSnapshot] tras cada poll exitoso.
///   3. Llamar a [dispose] al cerrar el runtime.
///
/// La primera llamada a [handleSnapshot] ejecuta la lógica de recovery:
/// compara el estado Firestore con el snapshot actual y cierra/abre
/// aperturas huérfanas si el backend fue reiniciado con la puerta abierta.
class DoorOpeningsTracker {
  DoorOpeningsTracker({
    required DoorOpeningsConfig config,
    required FirestoreDoorOpeningsRepository repository,
  }) : _config = config,
       _repository = repository {
    if (!config.enabled) {
      _log('disabled by config');
    } else if (!_repository.isConfigured) {
      _log('disabled: ${_repository.missingConfigurationReason}');
    } else {
      final String doorIds = config.doors
          .map((DoorConfig d) => d.doorId)
          .join(', ');
      _log(
        'enabled doors=[$doorIds] '
        'path=tenants/${config.tenantId}/sites/${config.siteId}/doors/{doorId}',
      );
    }
    for (final DoorConfig door in config.doors) {
      _states[door.doorId] = _DoorState();
    }
  }

  final DoorOpeningsConfig _config;
  final FirestoreDoorOpeningsRepository _repository;

  /// Estado en memoria por doorId.
  final Map<String, _DoorState> _states = <String, _DoorState>{};

  bool _initialized = false;

  /// Cola FIFO para serializar escrituras a Firestore y evitar duplicados
  /// por polls sucesivos concurrentes.
  Future<void> _queue = Future<void>.value();

  bool get isTrackingEnabled => _config.enabled && _config.doors.isNotEmpty;
  bool get isPersistenceEnabled =>
      isTrackingEnabled && _repository.isConfigured;

  // ---------------------------------------------------------------------------
  // API pública
  // ---------------------------------------------------------------------------

  /// Inicializa el estado en memoria una sola vez.
  /// Si Firestore está configurado, ejecuta la recuperación al arranque.
  Future<void> initializeIfNeeded({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) async {
    if (!isTrackingEnabled || _initialized) {
      return;
    }

    if (!isPersistenceEnabled) {
      _seedStateFromSnapshot(
        unitsJson: unitsJson,
        observedAtUtc: observedAtUtc,
      );
      _initialized = true;
      return;
    }

    await _initialize(unitsJson: unitsJson, now: observedAtUtc);
    _initialized = true;
  }

  /// Actualiza el resumen en memoria usando el snapshot actual y encola
  /// sólo las escrituras Firestore necesarias por transición.
  void ingestSnapshot({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) {
    if (!isTrackingEnabled) {
      return;
    }
    final List<_DoorTransitionEvent> events = _applySnapshot(
      unitsJson: unitsJson,
      observedAtUtc: observedAtUtc,
    );
    if (!isPersistenceEnabled || events.isEmpty) {
      return;
    }
    _queue = _queue
        .then<void>((_) async {
          for (final _DoorTransitionEvent event in events) {
            await _persistTransition(event);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          _log('error processing snapshot error=$error');
          _log('error stack=$stackTrace');
        });
  }

  /// Resumen liviano listo para inyectar en el snapshot HTTP actual.
  Map<String, Object?> snapshotSummaryJson() {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final DoorConfig door in _config.doors)
        door.doorId: _stateToSnapshotJson(_states[door.doorId]),
    });
  }

  /// Espera a que se vacíe la cola de escrituras pendientes.
  Future<void> dispose() => _queue;

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  List<_DoorTransitionEvent> _applySnapshot({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) {
    final List<_DoorTransitionEvent> events = <_DoorTransitionEvent>[];
    for (final DoorConfig door in _config.doors) {
      final bool? current = _extractDoorSignal(door, unitsJson);
      if (current == null) {
        _log(
          'signal not found door=${door.doorId} unit=${door.unitKey} signal=${door.signalKey}',
        );
        continue;
      }
      final _DoorTransitionEvent? event = _processDoor(
        door,
        current,
        observedAtUtc,
      );
      if (event != null) {
        events.add(event);
      }
    }
    return events;
  }

  /// Recovery al arrancar el backend:
  ///   - Firestore=open  + PLC=closed  → cierra la apertura huérfana (recoveredClosure=true)
  ///   - Firestore=closed + PLC=open   → crea nueva apertura (recoveredOpen=true)
  ///   - Firestore=open  + PLC=open    → restaura el tracking en memoria
  ///   - Firestore=closed + PLC=closed → nada que hacer
  ///   - Sin documento Firestore       → arranque limpio
  Future<void> _initialize({
    required Map<String, Object?> unitsJson,
    required DateTime now,
  }) async {
    _log('recovery: checking ${_config.doors.length} door(s)');

    for (final DoorConfig door in _config.doors) {
      final bool? currentIsOpen = _extractDoorSignal(door, unitsJson);

      PersistedDoorState? persisted;
      try {
        persisted = await _repository.loadLastState(door);
      } on Object catch (error) {
        _log(
          'recovery: load failed door=${door.doorId} error=$error — starting fresh',
        );
        if (currentIsOpen != null) {
          _states[door.doorId]!.lastKnown = currentIsOpen;
        }
        continue;
      }

      if (persisted == null) {
        // Sin documento previo — arranque desde cero.
        _log('recovery: no prior state door=${door.doorId}');
        if (currentIsOpen == true) {
          // Puerta ya abierta al arrancar sin historial → crear apertura recuperada.
          final String openingId = _newOpeningId(now);
          try {
            await _repository.recordOpened(
              door: door,
              openingId: openingId,
              openedAt: now,
              recoveredOpen: true,
            );
          } on Object catch (writeError) {
            _log(
              'recovery: recordOpened failed door=${door.doorId} error=$writeError — estado actualizado solo en memoria',
            );
          }
          _states[door.doorId]!
            ..lastKnown = true
            ..activeOpeningId = openingId
            ..activeOpenedAt = now
            ..lastOpeningId = openingId
            ..lastChangedAt = now;
          _log(
            'recovery: created recovered opening door=${door.doorId} openingId=$openingId',
          );
        } else {
          _states[door.doorId]!
            ..lastKnown = currentIsOpen ?? false
            ..lastOpeningId = null
            ..lastChangedAt = null;
          _log('recovery: door closed, nothing to do door=${door.doorId}');
        }
        continue;
      }

      // Tenemos estado persistido — comparar con snapshot actual.
      if (persisted.isOpen && currentIsOpen == false) {
        // Firestore=open, PLC=cerrado → cerrar apertura huérfana.
        final String? openingId = persisted.lastOpeningId;
        final DateTime openedAt = persisted.lastOpenedAt ?? now;
        _log(
          'recovery: closing orphaned opening door=${door.doorId} openingId=$openingId',
        );
        try {
          await _repository.recordClosed(
            door: door,
            openingId: openingId,
            openedAt: openedAt,
            closedAt: now,
            recoveredClosure: true,
          );
        } on Object catch (writeError) {
          _log(
            'recovery: recordClosed failed door=${door.doorId} error=$writeError — estado actualizado solo en memoria',
          );
        }
        _states[door.doorId]!
          ..lastKnown = false
          ..activeOpeningId = null
          ..activeOpenedAt = null
          ..lastOpeningId = openingId
          ..lastChangedAt = now;
      } else if (!persisted.isOpen && currentIsOpen == true) {
        // Firestore=closed, PLC=abierto → crear apertura recuperada.
        final String openingId = _newOpeningId(now);
        _log(
          'recovery: door already open with no active record door=${door.doorId} openingId=$openingId',
        );
        try {
          await _repository.recordOpened(
            door: door,
            openingId: openingId,
            openedAt: now,
            recoveredOpen: true,
          );
        } on Object catch (writeError) {
          _log(
            'recovery: recordOpened failed door=${door.doorId} error=$writeError — estado actualizado solo en memoria',
          );
        }
        _states[door.doorId]!
          ..lastKnown = true
          ..activeOpeningId = openingId
          ..activeOpenedAt = now
          ..lastOpeningId = openingId
          ..lastChangedAt = now;
      } else if (persisted.isOpen && currentIsOpen == true) {
        // Ambos abiertos → restaurar tracking en memoria.
        _states[door.doorId]!
          ..lastKnown = true
          ..activeOpeningId = persisted.lastOpeningId
          ..activeOpenedAt = persisted.lastOpenedAt
          ..lastOpeningId = persisted.lastOpeningId
          ..lastChangedAt = persisted.lastChangedAt;
        _log(
          'recovery: door still open door=${door.doorId} '
          'openingId=${persisted.lastOpeningId} — resuming tracking',
        );
      } else if (persisted.isOpen && currentIsOpen == null) {
        // Firestore=open, señal PLC no disponible → conservar estado persistido.
        _states[door.doorId]!
          ..lastKnown = true
          ..activeOpeningId = persisted.lastOpeningId
          ..activeOpenedAt = persisted.lastOpenedAt
          ..lastOpeningId = persisted.lastOpeningId
          ..lastChangedAt = persisted.lastChangedAt;
        _log(
          'recovery: PLC signal unavailable, door was open door=${door.doorId} — usando estado persistido',
        );
      } else {
        // Ambos cerrados → nada que hacer.
        _states[door.doorId]!
          ..lastKnown = false
          ..activeOpeningId = null
          ..activeOpenedAt = null
          ..lastOpeningId = persisted.lastOpeningId
          ..lastChangedAt = persisted.lastChangedAt;
        _log('recovery: door closed door=${door.doorId} — nothing to do');
      }
    }

    _log('recovery: complete');
  }

  /// Evalúa si hubo transición para una puerta y escribe en Firestore.
  _DoorTransitionEvent? _processDoor(
    DoorConfig door,
    bool currentIsOpen,
    DateTime now,
  ) {
    final _DoorState state = _states[door.doorId]!;
    final bool? lastKnown = state.lastKnown;

    // Sin estado previo — sólo registrar (no debería ocurrir después del init).
    if (lastKnown == null) {
      state.lastKnown = currentIsOpen;
      if (currentIsOpen) {
        final String openingId = _newOpeningId(now);
        state
          ..activeOpeningId = openingId
          ..activeOpenedAt = now
          ..lastOpeningId = openingId
          ..lastChangedAt = now;
      }
      return null;
    }

    // Sin cambio → no escribir nada.
    if (lastKnown == currentIsOpen) {
      return null;
    }

    if (!lastKnown && currentIsOpen) {
      // ── Transición: cerrada → abierta ──────────────────────────────────────
      final String openingId = _newOpeningId(now);
      _log('transition: closed→open door=${door.doorId} openingId=$openingId');
      state
        ..lastKnown = true
        ..activeOpeningId = openingId
        ..activeOpenedAt = now
        ..lastOpeningId = openingId
        ..lastChangedAt = now;
      return _DoorTransitionEvent.opened(
        door: door,
        openingId: openingId,
        openedAt: now,
      );
    } else {
      // ── Transición: abierta → cerrada ──────────────────────────────────────
      final String openingId =
          state.activeOpeningId ??
          state.lastOpeningId ??
          _newOpeningId(openedAtOrNow(state.activeOpenedAt, now));
      final DateTime openedAt = state.activeOpenedAt ?? now;
      final int durationS = now.difference(openedAt).inSeconds.abs();
      _log(
        'transition: open→closed door=${door.doorId} openingId=$openingId durationS=$durationS',
      );
      state
        ..lastKnown = false
        ..activeOpeningId = null
        ..activeOpenedAt = null
        ..lastOpeningId = openingId
        ..lastChangedAt = now;
      return _DoorTransitionEvent.closed(
        door: door,
        openingId: openingId,
        openedAt: openedAt,
        closedAt: now,
      );
    }
  }

  DateTime openedAtOrNow(DateTime? openedAt, DateTime now) => openedAt ?? now;

  Future<void> _persistTransition(_DoorTransitionEvent event) async {
    if (event.isOpenTransition) {
      await _repository.recordOpened(
        door: event.door,
        openingId: event.openingId!,
        openedAt: event.openedAt,
      );
      return;
    }
    await _repository.recordClosed(
      door: event.door,
      openingId: event.openingId,
      openedAt: event.openedAt,
      closedAt: event.closedAt!,
    );
  }

  void _seedStateFromSnapshot({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) {
    for (final DoorConfig door in _config.doors) {
      final bool? current = _extractDoorSignal(door, unitsJson);
      final _DoorState state = _states[door.doorId]!;
      if (current == null) {
        continue;
      }
      state.lastKnown = current;
      if (current) {
        final String openingId = _newOpeningId(observedAtUtc);
        state
          ..activeOpeningId = openingId
          ..activeOpenedAt = observedAtUtc
          ..lastOpeningId = openingId
          ..lastChangedAt = observedAtUtc;
      } else {
        state
          ..activeOpeningId = null
          ..activeOpenedAt = null
          ..lastOpeningId = null
          ..lastChangedAt = null;
      }
    }
  }

  Map<String, Object?> _stateToSnapshotJson(_DoorState? state) {
    return <String, Object?>{
      'isOpen': state?.lastKnown ?? false,
      'currentOpenedAt': state?.activeOpenedAt?.toUtc().toIso8601String(),
      'lastChangedAt': state?.lastChangedAt?.toUtc().toIso8601String(),
      'lastOpeningId': state?.lastOpeningId,
    };
  }

  /// Extrae el valor booleano de una señal de puerta del snapshot de unidades.
  bool? _extractDoorSignal(DoorConfig door, Map<String, Object?> unitsJson) {
    final Object? unitRaw = unitsJson[door.unitKey];
    if (unitRaw is! Map) {
      return null;
    }
    final Object? raw = (unitRaw as Map<Object?, Object?>)[door.signalKey];
    if (raw is bool) {
      return raw;
    }
    if (raw is String) {
      if (raw == 'true') return true;
      if (raw == 'false') return false;
    }
    return null;
  }

  /// Genera un ID de apertura único basado en timestamp UTC.
  /// Formato: yyyyMMdd_HHmmss_mmm  (legible + ordenable + único a escala de ms).
  String _newOpeningId(DateTime now) {
    final DateTime t = now.toUtc();
    final String y = t.year.toString().padLeft(4, '0');
    final String mo = t.month.toString().padLeft(2, '0');
    final String d = t.day.toString().padLeft(2, '0');
    final String h = t.hour.toString().padLeft(2, '0');
    final String mi = t.minute.toString().padLeft(2, '0');
    final String s = t.second.toString().padLeft(2, '0');
    final String ms = t.millisecond.toString().padLeft(3, '0');
    return '${y}${mo}${d}_${h}${mi}${s}_${ms}';
  }
}

// ---------------------------------------------------------------------------
// Estado en memoria por puerta
// ---------------------------------------------------------------------------

class _DoorState {
  /// Último estado booleano conocido. null = todavía no inicializado.
  bool? lastKnown;

  /// ID de la apertura activa (si la puerta está abierta).
  String? activeOpeningId;

  /// Timestamp de cuando se abrió la apertura activa.
  DateTime? activeOpenedAt;

  /// Último openingId conocido, incluso si la puerta ya cerró.
  String? lastOpeningId;

  /// Momento del último cambio observado o recuperado.
  DateTime? lastChangedAt;
}

class _DoorTransitionEvent {
  const _DoorTransitionEvent._({
    required this.door,
    required this.openingId,
    required this.openedAt,
    required this.closedAt,
    required this.isOpenTransition,
  });

  factory _DoorTransitionEvent.opened({
    required DoorConfig door,
    required String openingId,
    required DateTime openedAt,
  }) {
    return _DoorTransitionEvent._(
      door: door,
      openingId: openingId,
      openedAt: openedAt,
      closedAt: null,
      isOpenTransition: true,
    );
  }

  factory _DoorTransitionEvent.closed({
    required DoorConfig door,
    required String openingId,
    required DateTime openedAt,
    required DateTime closedAt,
  }) {
    return _DoorTransitionEvent._(
      door: door,
      openingId: openingId,
      openedAt: openedAt,
      closedAt: closedAt,
      isOpenTransition: false,
    );
  }

  final DoorConfig door;
  final String? openingId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final bool isOpenTransition;
}

void _log(String message) {
  stdout.writeln('[door-openings] $message');
}
