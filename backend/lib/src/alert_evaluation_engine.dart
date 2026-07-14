import 'alert_models.dart';
import 'alert_priority.dart';
import 'alert_settings_cache.dart';
import 'dew_point.dart';

abstract class AlertEvaluator {
  const AlertEvaluator();

  AlertType get type;

  EvaluatedAlert? evaluate(AlertEvaluationContext context);
}

List<AlertEvaluator> buildDefaultAlertEvaluators() {
  return List<AlertEvaluator>.unmodifiable(<AlertEvaluator>[
    const MuntersDoorOpenEvaluator(),
    const RoomDoorOpenEvaluator(),
    const HighTemperatureHeatingEvaluator(),
    const LowTemperatureHumidifierEvaluator(),
    const HighDifferentialPressureEvaluator(),
    const HighHumidityEvaluator(),
    const DewPointRiskEvaluator(),
  ]);
}

class AlertIdentity {
  const AlertIdentity({
    required this.tenantId,
    required this.siteId,
    required this.roomId,
    required this.roomNumber,
    required this.muntersId,
  });

  final String tenantId;
  final String siteId;
  final String roomId;
  final int roomNumber;
  final String muntersId;

  AlertInstanceKey key(AlertType type) {
    return AlertInstanceKey(
      tenantId: tenantId,
      siteId: siteId,
      roomId: roomId,
      roomNumber: roomNumber,
      muntersId: muntersId,
      alertType: type,
    );
  }
}

class SnapshotRoomData {
  const SnapshotRoomData({required this.values});

  final Map<String, Object?> values;

  Object? operator [](String key) => values[key];
}

class RoomWashStatus {
  const RoomWashStatus({required this.withinWashWindow});

  final bool withinWashWindow;
}

class AlertEvaluationContext {
  const AlertEvaluationContext({
    required this.identity,
    required this.snapshot,
    required this.settings,
    required this.evaluatedAt,
    required this.roomWashStatus,
  });

  final AlertIdentity identity;
  final SnapshotRoomData snapshot;
  final CachedAlertSettings settings;
  final DateTime evaluatedAt;
  final RoomWashStatus roomWashStatus;
}

class AlertEvaluationEngine {
  AlertEvaluationEngine({List<AlertEvaluator>? evaluators})
    : _evaluators = _validateEvaluators(
        List<AlertEvaluator>.unmodifiable(
          evaluators ?? buildDefaultAlertEvaluators(),
        ),
      );

  final List<AlertEvaluator> _evaluators;

  List<EvaluatedAlert> evaluate(AlertEvaluationContext context) {
    final List<EvaluatedAlert> active = <EvaluatedAlert>[];
    for (final AlertEvaluator evaluator in _evaluators) {
      final EvaluatedAlert? alert = evaluator.evaluate(context);
      if (alert != null && alert.isActive) {
        active.add(alert);
      }
    }
    active.sort(
      (EvaluatedAlert a, EvaluatedAlert b) =>
          AlertMetadataRegistry.priorityIndex(
            a.type,
          ).compareTo(AlertMetadataRegistry.priorityIndex(b.type)),
    );
    return List<EvaluatedAlert>.unmodifiable(active);
  }

  static List<AlertEvaluator> _validateEvaluators(
    List<AlertEvaluator> evaluators,
  ) {
    final Set<AlertType> seen = <AlertType>{};
    for (final AlertEvaluator evaluator in evaluators) {
      AlertMetadataRegistry.metadataFor(evaluator.type);
      if (!seen.add(evaluator.type)) {
        throw StateError('Duplicate evaluator for ${evaluator.type}');
      }
    }
    return evaluators;
  }
}

class MuntersDoorOpenEvaluator extends AlertEvaluator {
  const MuntersDoorOpenEvaluator();

  @override
  AlertType get type => AlertType.muntersDoorOpen;

  @override
  EvaluatedAlert? evaluate(AlertEvaluationContext context) {
    final CachedAlertToggle toggle = context.settings.alerts.muntersDoorOpen;
    if (!toggle.enabled || context.snapshot['puertaMunter'] != true) {
      return null;
    }
    return EvaluatedAlert(
      key: context.identity.key(type),
      type: type,
      isActive: true,
      sendWhatsapp: toggle.sendWhatsapp,
      thresholdKind: AlertThresholdKind.none,
      unit: '',
      evaluatedAt: context.evaluatedAt,
    );
  }
}

class RoomDoorOpenEvaluator extends AlertEvaluator {
  const RoomDoorOpenEvaluator();

  @override
  AlertType get type => AlertType.roomDoorOpen;

  @override
  EvaluatedAlert? evaluate(AlertEvaluationContext context) {
    final CachedAlertToggle toggle = context.settings.alerts.roomDoorOpen;
    if (!toggle.enabled || context.snapshot['puertaSala'] != true) {
      return null;
    }
    return EvaluatedAlert(
      key: context.identity.key(type),
      type: type,
      isActive: true,
      sendWhatsapp: toggle.sendWhatsapp,
      thresholdKind: AlertThresholdKind.none,
      unit: '',
      evaluatedAt: context.evaluatedAt,
    );
  }
}

class HighTemperatureHeatingEvaluator extends AlertEvaluator {
  const HighTemperatureHeatingEvaluator();

  @override
  AlertType get type => AlertType.highTemperatureHeatingActive;

  @override
  EvaluatedAlert? evaluate(AlertEvaluationContext context) {
    final CachedAlertToggle toggle =
        context.settings.alerts.highTemperatureHeatingActive;
    final double? temperature = _finiteDouble(context.snapshot['tempInterior']);
    final double? maximum = context.settings.thresholds.temperatureMax;
    final bool heatingActive =
        context.snapshot['resistencia1'] == true ||
        context.snapshot['resistencia2'] == true;
    if (!toggle.enabled ||
        temperature == null ||
        maximum == null ||
        !maximum.isFinite ||
        !heatingActive ||
        temperature <= maximum) {
      return null;
    }
    return EvaluatedAlert(
      key: context.identity.key(type),
      type: type,
      isActive: true,
      sendWhatsapp: toggle.sendWhatsapp,
      measuredValue: temperature,
      thresholdValue: maximum,
      thresholdKind: AlertThresholdKind.maximum,
      unit: '°C',
      evaluatedAt: context.evaluatedAt,
    );
  }
}

class LowTemperatureHumidifierEvaluator extends AlertEvaluator {
  const LowTemperatureHumidifierEvaluator();

  @override
  AlertType get type => AlertType.lowTemperatureHumidifierActive;

  @override
  EvaluatedAlert? evaluate(AlertEvaluationContext context) {
    final CachedAlertToggle toggle =
        context.settings.alerts.lowTemperatureHumidifierActive;
    final double? temperature = _finiteDouble(context.snapshot['tempInterior']);
    final double? minimum = context.settings.thresholds.temperatureMin;
    final bool pumpActive = context.snapshot['bombaHumidificador'] == true;
    if (!toggle.enabled ||
        temperature == null ||
        minimum == null ||
        !minimum.isFinite ||
        !pumpActive ||
        temperature >= minimum) {
      return null;
    }
    return EvaluatedAlert(
      key: context.identity.key(type),
      type: type,
      isActive: true,
      sendWhatsapp: toggle.sendWhatsapp,
      measuredValue: temperature,
      thresholdValue: minimum,
      thresholdKind: AlertThresholdKind.minimum,
      unit: '°C',
      evaluatedAt: context.evaluatedAt,
    );
  }
}

class HighDifferentialPressureEvaluator extends AlertEvaluator {
  const HighDifferentialPressureEvaluator();

  @override
  AlertType get type => AlertType.highDifferentialPressure;

  @override
  EvaluatedAlert? evaluate(AlertEvaluationContext context) {
    final CachedAlertToggle toggle =
        context.settings.alerts.highDifferentialPressure;
    final double? pressure = _finiteDouble(
      context.snapshot['presionDiferencial'],
    );
    final double? maximum = context.settings.thresholds.filterPressureMax;
    if (!toggle.enabled ||
        pressure == null ||
        maximum == null ||
        !maximum.isFinite ||
        pressure <= maximum) {
      return null;
    }
    return EvaluatedAlert(
      key: context.identity.key(type),
      type: type,
      isActive: true,
      sendWhatsapp: toggle.sendWhatsapp,
      measuredValue: pressure,
      thresholdValue: maximum,
      thresholdKind: AlertThresholdKind.maximum,
      unit: 'Pa',
      evaluatedAt: context.evaluatedAt,
    );
  }
}

class HighHumidityEvaluator extends AlertEvaluator {
  const HighHumidityEvaluator();

  @override
  AlertType get type => AlertType.highHumidity;

  @override
  EvaluatedAlert? evaluate(AlertEvaluationContext context) {
    final CachedAlertToggle toggle = context.settings.alerts.highHumidity;
    final double? rawHumidity = _finiteDouble(context.snapshot['humInterior']);
    final double? redMinExclusive =
        context.settings.thresholds.humidityRedMinExclusive;
    if (!toggle.enabled ||
        rawHumidity == null ||
        redMinExclusive == null ||
        !redMinExclusive.isFinite) {
      return null;
    }
    final double humidity = rawHumidity.clamp(0, 100).toDouble();
    final bool withinWashWindow = context.roomWashStatus.withinWashWindow;
    if (withinWashWindow || humidity <= redMinExclusive) {
      return null;
    }
    return EvaluatedAlert(
      key: context.identity.key(type),
      type: type,
      isActive: true,
      sendWhatsapp: toggle.sendWhatsapp,
      measuredValue: humidity,
      thresholdValue: redMinExclusive,
      thresholdKind: AlertThresholdKind.maximum,
      unit: '%',
      evaluatedAt: context.evaluatedAt,
    );
  }
}

class DewPointRiskEvaluator extends AlertEvaluator {
  const DewPointRiskEvaluator();

  @override
  AlertType get type => AlertType.dewPointRisk;

  @override
  EvaluatedAlert? evaluate(AlertEvaluationContext context) {
    final CachedAlertToggle toggle = context.settings.alerts.dewPointRisk;
    final double? temperature = _finiteDouble(context.snapshot['tempInterior']);
    final double? humidity = _finiteDouble(context.snapshot['humInterior']);
    final double? redMaxInclusive =
        context.settings.thresholds.dewPointMarginRedMaxInclusive;
    if (!toggle.enabled ||
        temperature == null ||
        humidity == null ||
        redMaxInclusive == null ||
        !redMaxInclusive.isFinite) {
      return null;
    }
    final double? margin = calculateDewPointMarginC(
      temperatureC: temperature,
      relativeHumidityPercent: humidity,
    );
    if (margin == null || margin > redMaxInclusive) {
      return null;
    }
    return EvaluatedAlert(
      key: context.identity.key(type),
      type: type,
      isActive: true,
      sendWhatsapp: toggle.sendWhatsapp,
      measuredValue: margin,
      thresholdValue: redMaxInclusive,
      thresholdKind: AlertThresholdKind.minimumMargin,
      unit: '°C',
      evaluatedAt: context.evaluatedAt,
    );
  }
}

double? _finiteDouble(Object? value) {
  if (value is num) {
    final double doubleValue = value.toDouble();
    return doubleValue.isFinite ? doubleValue : null;
  }
  if (value is String) {
    final double? parsed = double.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}
