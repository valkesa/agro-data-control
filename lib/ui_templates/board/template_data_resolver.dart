import '../../models/munters_model.dart';
import '../models/metric_definition.dart';
import '../models/template_data_context.dart';
import '../transforms/environment_calculations.dart';
import '../transforms/metric_transforms.dart';

class TemplateDataResolver {
  const TemplateDataResolver();

  Object? resolveMetric(MetricDefinition metric, Object? deviceData) {
    final Object? rawValue = resolveSourceField(metric.sourceField, deviceData);
    return applyMetricTransform(rawValue, metric.transform);
  }

  Object? resolveSourceField(String sourceField, Object? deviceData) {
    if (sourceField.startsWith('pending.')) {
      return null;
    }
    if (deviceData is TemplateDataContext) {
      if (deviceData.extras.containsKey(sourceField)) {
        return deviceData.extras[sourceField];
      }
      return resolveSourceField(sourceField, deviceData.source);
    }
    if (sourceField == 'computed.dewPointDelta') {
      final double? temperature = _asDouble(
        resolveSourceField('tempInterior', deviceData),
      );
      final double? humidity = _asDouble(
        resolveSourceField('humInterior', deviceData),
      );
      final double? dewPoint = calculateDewPointC(
        temperatureC: temperature,
        relativeHumidityPercent: humidity,
      );
      return calculateDewPointDeltaC(
        temperatureC: temperature,
        dewPointC: dewPoint,
      );
    }
    if (deviceData is Map<String, Object?>) {
      return deviceData[sourceField];
    }
    if (deviceData is MuntersModel) {
      return _resolveMuntersField(sourceField, deviceData);
    }
    return null;
  }

  Object? _resolveMuntersField(String sourceField, MuntersModel unit) {
    return switch (sourceField) {
      'name' => unit.name,
      'historyClientId' => unit.historyClientId,
      'historyPlcId' => unit.historyPlcId,
      'backendOnline' => unit.backendOnline,
      'configured' => unit.configured,
      'plcReachable' => unit.plcReachable,
      'plcRunning' => unit.plcRunning,
      'dataFresh' => unit.dataFresh,
      'plcOnline' => unit.plcOnline,
      'plcLatencyMs' => unit.plcLatencyMs,
      'routerLatencyMs' => unit.routerLatencyMs,
      'lastError' => unit.lastError,
      'recentRoomWashEvent' => unit.recentRoomWashEvent,
      'tempInterior' => unit.tempInterior,
      'tempIngresoSala' => unit.tempIngresoSala,
      'humInterior' => unit.humInterior,
      'displayHumInterior' => unit.displayHumInterior,
      'tempExterior' => unit.tempExterior,
      'humExterior' => unit.humExterior,
      'displayHumExterior' => unit.displayHumExterior,
      'nh3' => unit.nh3,
      'presionDiferencial' => unit.presionDiferencial,
      'tensionSalidaVentiladores' => unit.tensionSalidaVentiladores,
      'fanQ5' => unit.fanQ5,
      'fanQ6' => unit.fanQ6,
      'fanQ7' => unit.fanQ7,
      'fanQ8' => unit.fanQ8,
      'fanQ9' => unit.fanQ9,
      'fanQ10' => unit.fanQ10,
      'bombaHumidificador' => unit.bombaHumidificador,
      'resistencia1' => unit.resistencia1,
      'resistencia2' => unit.resistencia2,
      'alarmaGeneral' => unit.alarmaGeneral,
      'fallaRed' => unit.fallaRed,
      'nivelAguaAlarma' => unit.nivelAguaAlarma,
      'fallaTermicaBomba' => unit.fallaTermicaBomba,
      'eventosSinAgua' => unit.eventosSinAgua,
      'horasMunter' => unit.horasMunter,
      'horasFiltroF9' => unit.horasFiltroF9,
      'horasFiltroG4' => unit.horasFiltroG4,
      'horasPolifosfato' => unit.horasPolifosfato,
      'salaAbierta' => unit.salaAbierta,
      'aperturasSala' => unit.aperturasSala,
      'munterAbierto' => unit.munterAbierto,
      'aperturasMunter' => unit.aperturasMunter,
      'cantidadApagadas' => unit.cantidadApagadas,
      'estadoEquipo' => unit.estadoEquipo,
      _ => null,
    };
  }
}

double? _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}
