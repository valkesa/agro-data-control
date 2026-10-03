import '../models/dashboard_snapshot.dart';
import '../models/munters_model.dart';
import 'demo_signal_definition.dart';

/// Produces detached in-memory snapshots for presentation. It has no clock,
/// callbacks, persistence or service dependencies, and never mutates the real
/// snapshot supplied by the caller.
class DemoSnapshotBuilder {
  const DemoSnapshotBuilder._();

  static DashboardSnapshot applyOverrides({
    required DashboardSnapshot realSnapshot,
    required String targetSnapshotUnitKey,
    required Map<DemoSignalKey, Object?> overrides,
  }) {
    if (targetSnapshotUnitKey.trim().isEmpty) {
      throw ArgumentError.value(
        targetSnapshotUnitKey,
        'targetSnapshotUnitKey',
        'Must not be empty',
      );
    }
    for (final entry in overrides.entries) {
      DemoSignalCatalog.definitionFor(
        entry.key,
      ).validateValue(entry.value, parameterName: entry.key.wireName);
    }

    final matches = realSnapshot.units
        .where((unit) => unit.historyPlcId == targetSnapshotUnitKey)
        .length;
    if (matches != 1) {
      throw StateError(
        'Expected exactly one snapshot unit with key '
        '"$targetSnapshotUnitKey", found $matches',
      );
    }

    return DashboardSnapshot(
      units: List<MuntersModel>.unmodifiable(<MuntersModel>[
        for (final unit in realSnapshot.units)
          _copyUnit(
            unit,
            unit.historyPlcId == targetSnapshotUnitKey
                ? overrides
                : const <DemoSignalKey, Object?>{},
          ),
      ]),
      doorEvents: Map.unmodifiable(realSnapshot.doorEvents),
      backendOnline: realSnapshot.backendOnline,
      lastUpdatedAt: realSnapshot.lastUpdatedAt,
      startedAt: realSnapshot.startedAt,
      clientName: realSnapshot.clientName,
    );
  }

  static T? _value<T>(
    Map<DemoSignalKey, Object?> values,
    DemoSignalKey key,
    T? fallback,
  ) => values.containsKey(key) ? values[key] as T? : fallback;

  static double? _number(
    Map<DemoSignalKey, Object?> values,
    DemoSignalKey key,
    double? fallback,
  ) => values.containsKey(key) ? (values[key] as num?)?.toDouble() : fallback;

  static MuntersModel _copyUnit(
    MuntersModel source,
    Map<DemoSignalKey, Object?> values,
  ) => MuntersModel(
    name: source.name,
    historyClientId: source.historyClientId,
    historyPlcId: source.historyPlcId,
    diagnostics: source.diagnostics,
    backendOnline: _value(
      values,
      DemoSignalKey.backendOnline,
      source.backendOnline,
    ),
    configured: _value(values, DemoSignalKey.configured, source.configured),
    plcReachable: _value(
      values,
      DemoSignalKey.plcReachable,
      source.plcReachable,
    ),
    plcRunning: _value(values, DemoSignalKey.plcRunning, source.plcRunning),
    dataFresh: _value(values, DemoSignalKey.dataFresh, source.dataFresh),
    plcOnline: _value(values, DemoSignalKey.plcOnline, source.plcOnline),
    plcLatencyMs: source.plcLatencyMs,
    routerLatencyMs: source.routerLatencyMs,
    backendStartedAt: source.backendStartedAt,
    lastUpdatedAt: source.lastUpdatedAt,
    previousLastUpdatedAt: source.previousLastUpdatedAt,
    updateDeltaSeconds: source.updateDeltaSeconds,
    lastHeartbeatValue: source.lastHeartbeatValue,
    lastHeartbeatChangeAt: source.lastHeartbeatChangeAt,
    lastError: source.lastError,
    recentRoomWashEvent: source.recentRoomWashEvent,
    tempInterior: _number(
      values,
      DemoSignalKey.indoorTemperature,
      source.tempInterior,
    ),
    tempIngresoSala: _number(
      values,
      DemoSignalKey.inletTemperature,
      source.tempIngresoSala,
    ),
    humInterior: _number(
      values,
      DemoSignalKey.indoorHumidity,
      source.humInterior,
    ),
    tempExterior: _number(
      values,
      DemoSignalKey.outdoorTemperature,
      source.tempExterior,
    ),
    humExterior: _number(
      values,
      DemoSignalKey.outdoorHumidity,
      source.humExterior,
    ),
    nh3: _number(values, DemoSignalKey.ammonia, source.nh3),
    presionDiferencial: _number(
      values,
      DemoSignalKey.differentialPressure,
      source.presionDiferencial,
    ),
    tensionSalidaVentiladores: _number(
      values,
      DemoSignalKey.ventilationPower,
      source.tensionSalidaVentiladores,
    ),
    fanQ5: _value(values, DemoSignalKey.fanQ5, source.fanQ5),
    fanQ6: _value(values, DemoSignalKey.fanQ6, source.fanQ6),
    fanQ7: _value(values, DemoSignalKey.fanQ7, source.fanQ7),
    fanQ8: _value(values, DemoSignalKey.fanQ8, source.fanQ8),
    fanQ9: _value(values, DemoSignalKey.fanQ9, source.fanQ9),
    fanQ10: _value(values, DemoSignalKey.fanQ10, source.fanQ10),
    bombaHumidificador: _value(
      values,
      DemoSignalKey.humidifier,
      source.bombaHumidificador,
    ),
    resistencia1: _value(
      values,
      DemoSignalKey.heatingStage1,
      source.resistencia1,
    ),
    resistencia2: _value(
      values,
      DemoSignalKey.heatingStage2,
      source.resistencia2,
    ),
    alarmaGeneral: _value(
      values,
      DemoSignalKey.generalAlarm,
      source.alarmaGeneral,
    ),
    fallaRed: _value(values, DemoSignalKey.networkFailure, source.fallaRed),
    nivelAguaAlarma: _value(
      values,
      DemoSignalKey.waterLevelAlarm,
      source.nivelAguaAlarma,
    ),
    fallaTermicaBomba: _value(
      values,
      DemoSignalKey.humidifierThermalFailure,
      source.fallaTermicaBomba,
    ),
    eventosSinAgua: source.eventosSinAgua,
    horasMunter: source.horasMunter,
    horasFiltroF9: source.horasFiltroF9,
    horasFiltroG4: source.horasFiltroG4,
    horasPolifosfato: source.horasPolifosfato,
    salaAbierta: _value(values, DemoSignalKey.roomDoorOpen, source.salaAbierta),
    aperturasSala: source.aperturasSala,
    munterAbierto: _value(
      values,
      DemoSignalKey.equipmentDoorOpen,
      source.munterAbierto,
    ),
    aperturasMunter: source.aperturasMunter,
    cantidadApagadas: source.cantidadApagadas,
    estadoEquipo: _value(
      values,
      DemoSignalKey.equipmentState,
      source.estadoEquipo,
    ),
  );
}
