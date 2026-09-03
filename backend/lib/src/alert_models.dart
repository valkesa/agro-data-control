import 'alert_priority.dart';

enum AlertThresholdKind { minimum, maximum, minimumMargin, none }

class AlertInstanceKey {
  const AlertInstanceKey({
    required this.tenantId,
    required this.siteId,
    required this.roomId,
    required this.alertType,
    this.roomNumber,
    this.muntersId,
  });

  final String tenantId;
  final String siteId;
  final String roomId;
  final int? roomNumber;
  final String? muntersId;
  final AlertType alertType;

  bool matchesScope({
    required String tenantId,
    required String siteId,
    required String roomId,
    String? muntersId,
  }) {
    return this.tenantId == tenantId &&
        this.siteId == siteId &&
        this.roomId == roomId &&
        this.muntersId == muntersId;
  }

  @override
  bool operator ==(Object other) {
    return other is AlertInstanceKey &&
        other.tenantId == tenantId &&
        other.siteId == siteId &&
        other.roomId == roomId &&
        other.roomNumber == roomNumber &&
        other.muntersId == muntersId &&
        other.alertType == alertType;
  }

  @override
  int get hashCode =>
      Object.hash(tenantId, siteId, roomId, roomNumber, muntersId, alertType);
}

class EvaluatedAlert {
  const EvaluatedAlert({
    required this.key,
    required this.type,
    required this.isActive,
    required this.sendWhatsapp,
    required this.thresholdKind,
    required this.unit,
    required this.evaluatedAt,
    this.configVersion = 0,
    this.measuredValue,
    this.thresholdValue,
    this.openSinceMinutes,
  });

  final AlertInstanceKey key;
  final AlertType type;
  final bool isActive;
  final bool sendWhatsapp;
  final num? measuredValue;
  final num? thresholdValue;
  final AlertThresholdKind thresholdKind;
  final String unit;
  final DateTime evaluatedAt;
  final int configVersion;

  /// Minutes this door has been continuously open as of [evaluatedAt], set
  /// only when [AlertProcessingCoordinator] promotes a door-open alert to a
  /// WhatsApp candidate (see `_doorAlertsReadyForWhatsapp`) — null for every
  /// other alert type and for door alerts that haven't reached their
  /// configured delay yet.
  final int? openSinceMinutes;

  EvaluatedAlert withOpenSinceMinutes(int minutes) {
    return EvaluatedAlert(
      key: key,
      type: type,
      isActive: isActive,
      sendWhatsapp: sendWhatsapp,
      thresholdKind: thresholdKind,
      unit: unit,
      evaluatedAt: evaluatedAt,
      configVersion: configVersion,
      measuredValue: measuredValue,
      thresholdValue: thresholdValue,
      openSinceMinutes: minutes,
    );
  }
}

class ActiveAlertState {
  const ActiveAlertState({
    required this.key,
    required this.type,
    required this.firstDetectedAt,
    required this.lastEvaluatedAt,
    required this.sendWhatsapp,
    required this.configVersionEvaluated,
    this.latestMeasuredValue,
    this.latestThresholdValue,
  });

  factory ActiveAlertState.fromEvaluated(EvaluatedAlert alert) {
    return ActiveAlertState(
      key: alert.key,
      type: alert.type,
      firstDetectedAt: alert.evaluatedAt,
      lastEvaluatedAt: alert.evaluatedAt,
      latestMeasuredValue: alert.measuredValue,
      latestThresholdValue: alert.thresholdValue,
      sendWhatsapp: alert.sendWhatsapp,
      configVersionEvaluated: alert.configVersion,
    );
  }

  final AlertInstanceKey key;
  final AlertType type;
  final DateTime firstDetectedAt;
  final DateTime lastEvaluatedAt;
  final num? latestMeasuredValue;
  final num? latestThresholdValue;
  final bool sendWhatsapp;
  final int configVersionEvaluated;

  ActiveAlertState updateFrom(EvaluatedAlert alert) {
    return ActiveAlertState(
      key: key,
      type: type,
      firstDetectedAt: firstDetectedAt,
      lastEvaluatedAt: alert.evaluatedAt,
      latestMeasuredValue: alert.measuredValue,
      latestThresholdValue: alert.thresholdValue,
      sendWhatsapp: alert.sendWhatsapp,
      configVersionEvaluated: alert.configVersion,
    );
  }
}

class AlertTransitionBatch {
  const AlertTransitionBatch({
    required this.activated,
    required this.stillActive,
    required this.recovered,
    this.configChangedActivated = const <EvaluatedAlert>[],
  });

  final List<EvaluatedAlert> activated;
  final List<EvaluatedAlert> configChangedActivated;
  final List<EvaluatedAlert> stillActive;
  final List<ActiveAlertState> recovered;
}
