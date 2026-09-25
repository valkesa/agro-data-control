import 'dart:io';

import 'alert_evaluation_engine.dart';
import 'alert_models.dart';
import 'alert_notifications.dart';
import 'alert_priority.dart';
import 'alert_runtime.dart';
import 'alert_settings_cache.dart';
import 'dew_point.dart';

class AlertProcessingCoordinator {
  AlertProcessingCoordinator({
    required this.tenantId,
    required this.siteId,
    required this.runtime,
    Map<String, String> plcLabelsByMuntersId = const <String, String>{},
    AlertEvaluationEngine? engine,
    NotificationBatchManager? notificationBatchManager,
  }) : _plcLabelsByMuntersId = Map<String, String>.unmodifiable(
         plcLabelsByMuntersId,
       ),
       _engine = engine ?? AlertEvaluationEngine(),
       _notificationBatchManager = notificationBatchManager;

  final String tenantId;
  final String siteId;
  final AlertRuntime runtime;
  final Map<String, String> _plcLabelsByMuntersId;
  final AlertEvaluationEngine _engine;
  final NotificationBatchManager? _notificationBatchManager;
  final Set<String> _loggedConfigErrors = <String>{};

  Future<SnapshotAlertProcessingResult> processSnapshot(
    Map<String, Object?> snapshotJson, {
    DateTime? evaluatedAt,
  }) async {
    final DateTime effectiveEvaluatedAt = evaluatedAt ?? DateTime.now().toUtc();
    final List<RoomAlertEvaluationResult> rooms = <RoomAlertEvaluationResult>[];
    for (final AlertRoomIdentity room in AlertRoomIdentity.defaultRooms) {
      final Object? rawUnit = snapshotJson[room.muntersId];
      final Map<String, Object?>? unitJson = _asStringMap(rawUnit);
      if (unitJson == null) {
        rooms.add(
          RoomAlertEvaluationResult.ignored(
            identity: room,
            tenantId: tenantId,
            siteId: siteId,
            evaluatedAt: effectiveEvaluatedAt,
            ignoredReason: 'missing_unit',
          ),
        );
        continue;
      }
      rooms.add(
        await processRoom(
          room: room,
          unitJson: unitJson,
          evaluatedAt: effectiveEvaluatedAt,
        ),
      );
    }
    return SnapshotAlertProcessingResult(
      evaluatedAt: effectiveEvaluatedAt,
      rooms: List<RoomAlertEvaluationResult>.unmodifiable(rooms),
    );
  }

  Future<RoomAlertEvaluationResult> processRoom({
    required AlertRoomIdentity room,
    required Map<String, Object?> unitJson,
    required DateTime evaluatedAt,
  }) async {
    final String? stateCode = _readStateCode(unitJson);
    if (!runtime.snapshotEvaluationPolicy.isEvaluableStateCode(stateCode)) {
      return RoomAlertEvaluationResult.ignored(
        identity: room,
        tenantId: tenantId,
        siteId: siteId,
        evaluatedAt: evaluatedAt,
        ignoredReason: 'non_evaluable_state:${stateCode ?? 'null'}',
      );
    }

    final CachedAlertSettings? settings;
    try {
      settings = await runtime.settingsCache.getOrLoad(
        tenantId: tenantId,
        siteId: siteId,
        now: evaluatedAt,
      );
    } on AlertSettingsLoadBackoffException {
      return RoomAlertEvaluationResult.ignored(
        identity: room,
        tenantId: tenantId,
        siteId: siteId,
        evaluatedAt: evaluatedAt,
        ignoredReason: 'settings_unavailable_backoff',
      );
    } catch (error) {
      _logConfigErrorOnce(
        'settings_load_failed',
        'alert settings load failed tenant=$tenantId site=$siteId error=$error',
      );
      return RoomAlertEvaluationResult.ignored(
        identity: room,
        tenantId: tenantId,
        siteId: siteId,
        evaluatedAt: evaluatedAt,
        ignoredReason: 'settings_load_failed',
      );
    }
    if (settings == null) {
      _logConfigErrorOnce(
        'settings_missing',
        'alert settings missing tenant=$tenantId site=$siteId',
      );
      return RoomAlertEvaluationResult.ignored(
        identity: room,
        tenantId: tenantId,
        siteId: siteId,
        evaluatedAt: evaluatedAt,
        ignoredReason: 'settings_missing',
      );
    }

    final List<EvaluatedAlert> evaluatedAlerts = _engine.evaluate(
      AlertEvaluationContext(
        identity: AlertIdentity(
          tenantId: tenantId,
          siteId: siteId,
          roomId: room.roomId,
          roomNumber: room.roomNumber,
          muntersId: room.muntersId,
        ),
        snapshot: SnapshotRoomData(values: unitJson),
        settings: settings,
        evaluatedAt: evaluatedAt,
        roomWashStatus: RoomWashStatus(
          withinWashWindow: runtime.roomWashRegistry.isWithinWashWindow(
            tenantId: tenantId,
            siteId: siteId,
            roomId: room.roomId,
            now: evaluatedAt,
          ),
        ),
      ),
    );
    final AlertTransitionBatch transitionBatch = runtime.activeAlertsRegistry
        .syncForRoom(
          tenantId: tenantId,
          siteId: siteId,
          roomId: room.roomId,
          muntersId: room.muntersId,
          evaluatedAlerts: evaluatedAlerts,
          shouldRecover: (ActiveAlertState alert) =>
              _hasRecoveredWithHysteresis(
                alert: alert,
                unitJson: unitJson,
                settings: settings!,
                muntersId: room.muntersId,
              ),
        );
    _logTransitions(transitionBatch, evaluatedAt);

    // Door alerts are re-checked every poll (not just on the open-transition
    // edge) because "send after the door has been open N minutes" can only
    // be known once N minutes have actually elapsed — see
    // _doorAlertsReadyForWhatsapp. Every other alert type keeps the original
    // edge-triggered behavior: only a fresh transitionBatch.activated makes
    // it to WhatsApp.
    final List<EvaluatedAlert> whatsappEligible =
        <EvaluatedAlert>[
          ...transitionBatch.activated.where(
            (EvaluatedAlert alert) =>
                alert.sendWhatsapp && !_isDoorAlertType(alert.type),
          ),
          ..._doorAlertsReadyForWhatsapp(
            evaluatedAlerts: evaluatedAlerts,
            evaluatedAt: evaluatedAt,
            settings: settings,
          ),
        ]..sort(
          (EvaluatedAlert a, EvaluatedAlert b) =>
              settings!.alerts.compareAlertTypes(a.type, b.type),
        );
    final List<EvaluatedAlert> whatsAppCandidates = <EvaluatedAlert>[];
    for (final EvaluatedAlert alert in whatsappEligible) {
      final Duration cooldown = runtime.config.cooldownFor(alert.type);
      if (!runtime.notificationCooldownRegistry.canSend(
        key: alert.key,
        now: evaluatedAt,
        cooldown: cooldown,
      )) {
        final DateTime? lastSentAt = runtime.notificationCooldownRegistry
            .lastSentAt(alert.key);
        stdout.writeln(
          '[alerts] event=notification_cooldown_suppressed tenantId=${alert.key.tenantId} siteId=${alert.key.siteId} roomId=${alert.key.roomId} alertType=${alert.type.id} lastSentAt=${lastSentAt?.toIso8601String() ?? ''} evaluatedAt=${evaluatedAt.toIso8601String()} cooldownMinutes=${cooldown.inMinutes}',
        );
        continue;
      }
      runtime.notificationCooldownRegistry.markPending(
        key: alert.key,
        queuedAt: evaluatedAt,
      );
      whatsAppCandidates.add(alert);
    }

    final Map<AlertType, int> alertOrder = <AlertType, int>{
      for (final AlertType type in alertPriorityOrder)
        type: settings.alerts.effectiveOrder(type),
    };
    final RoomAlertEvaluationResult result =
        RoomAlertEvaluationResult.evaluated(
          identity: room,
          tenantId: tenantId,
          siteId: siteId,
          evaluatedAt: evaluatedAt,
          evaluatedAlerts: evaluatedAlerts,
          transitionBatch: transitionBatch,
          whatsAppCandidates: List<EvaluatedAlert>.unmodifiable(
            whatsAppCandidates,
          ),
          alertOrder: alertOrder,
        );
    _notificationBatchManager?.addCandidates(
      tenantId: tenantId,
      siteId: siteId,
      roomId: room.roomId,
      roomNumber: room.roomNumber,
      muntersId: room.muntersId,
      plcLabel: _plcLabelsByMuntersId[room.muntersId],
      alerts: whatsAppCandidates,
      alertOrder: alertOrder,
    );
    return result;
  }

  static bool _isDoorAlertType(AlertType type) =>
      type == AlertType.muntersDoorOpen || type == AlertType.roomDoorOpen;

  /// Door alerts that are currently open, whatsapp-enabled, and have been
  /// open for at least their configured `whatsappDelayMinutes` — tagged with
  /// how long they've actually been open so
  /// [AlertNotificationFormatter.format] can say so. Sourced from
  /// [evaluatedAlerts] (this poll's currently-active alerts) rather than
  /// [AlertTransitionBatch.activated]/[AlertTransitionBatch.stillActive], so
  /// a door that stays open past the delay gets picked up on the very poll
  /// it crosses the threshold, not only on the (single, immediate) moment it
  /// first opened.
  List<EvaluatedAlert> _doorAlertsReadyForWhatsapp({
    required List<EvaluatedAlert> evaluatedAlerts,
    required DateTime evaluatedAt,
    required CachedAlertSettings settings,
  }) {
    final List<EvaluatedAlert> ready = <EvaluatedAlert>[];
    for (final EvaluatedAlert alert in evaluatedAlerts) {
      if (!alert.sendWhatsapp || !_isDoorAlertType(alert.type)) {
        continue;
      }
      final ActiveAlertState? state = runtime.activeAlertsRegistry
          .activeStateFor(alert.key);
      if (state == null) {
        // Just synced into the registry a few lines above in processRoom —
        // should always be present. Skip defensively rather than crash.
        continue;
      }
      final int openMinutes = evaluatedAt
          .difference(state.firstDetectedAt)
          .inMinutes;
      final int delayMinutes = settings.alerts
          .toggleFor(alert.type)
          .whatsappDelayMinutes;
      if (openMinutes < delayMinutes) {
        continue;
      }
      ready.add(alert.withOpenSinceMinutes(openMinutes));
    }
    return ready;
  }

  void _logTransitions(AlertTransitionBatch batch, DateTime evaluatedAt) {
    for (final EvaluatedAlert alert in batch.activated) {
      final bool configChanged = batch.configChangedActivated.any(
        (EvaluatedAlert configAlert) => configAlert.key == alert.key,
      );
      stdout.writeln(
        '[alerts] event=alert_activated reason=${configChanged ? 'config_changed' : 'measurement'} tenantId=${alert.key.tenantId} siteId=${alert.key.siteId} roomId=${alert.key.roomId} roomNumber=${alert.key.roomNumber ?? ''} muntersId=${alert.key.muntersId ?? ''} alertType=${alert.type.id} measuredValue=${alert.measuredValue ?? ''} thresholdValue=${alert.thresholdValue ?? ''} sendWhatsapp=${alert.sendWhatsapp} configVersion=${alert.configVersion} evaluatedAt=${evaluatedAt.toIso8601String()}',
      );
    }
    for (final ActiveAlertState alert in batch.recovered) {
      final int durationSeconds = evaluatedAt
          .difference(alert.firstDetectedAt)
          .inSeconds;
      stdout.writeln(
        '[alerts] event=alert_recovered tenantId=${alert.key.tenantId} siteId=${alert.key.siteId} roomId=${alert.key.roomId} alertType=${alert.type.id} durationS=$durationSeconds evaluatedAt=${evaluatedAt.toIso8601String()}',
      );
    }
  }

  void _logConfigErrorOnce(String key, String message) {
    final String scopedKey = '$tenantId|$siteId|$key';
    if (_loggedConfigErrors.add(scopedKey)) {
      stdout.writeln('[alerts] $message');
    }
  }

  bool _hasRecoveredWithHysteresis({
    required ActiveAlertState alert,
    required Map<String, Object?> unitJson,
    required CachedAlertSettings settings,
    required String muntersId,
  }) {
    final CachedAlertThresholds thresholds = settings.thresholdsFor(muntersId);
    return switch (alert.type) {
      AlertType.sensorFailure => _recoverMinimum(
        measured: _finiteDouble(unitJson['tempInterior']),
        threshold: thresholds.temperatureSensorFailureMin ?? 0,
        hysteresis: runtime.config.hysteresis.temperatureC,
      ),
      AlertType.temperatureInterior => _recoverTemperatureInterior(
        measured: _finiteDouble(unitJson['tempInterior']),
        minimum: thresholds.temperatureMin,
        maximum: thresholds.temperatureMax,
        hysteresis: runtime.config.hysteresis.temperatureC,
      ),
      AlertType.highTemperatureHeatingActive => _recoverMaximum(
        measured: _finiteDouble(unitJson['tempInterior']),
        threshold: thresholds.temperatureMax,
        hysteresis: runtime.config.hysteresis.temperatureC,
      ),
      AlertType.lowTemperatureHumidifierActive => _recoverMinimum(
        measured: _finiteDouble(unitJson['tempInterior']),
        threshold: thresholds.temperatureMin,
        hysteresis: runtime.config.hysteresis.temperatureC,
      ),
      AlertType.highHumidity => _recoverMaximum(
        measured: _finiteDouble(
          unitJson['humInterior'],
        )?.clamp(0, 100).toDouble(),
        threshold: thresholds.humidityRedMinExclusive,
        hysteresis: runtime.config.hysteresis.humidityPercent,
      ),
      AlertType.dewPointRisk => _recoverMinimumMargin(
        margin: _currentDewPointMargin(unitJson),
        threshold: thresholds.dewPointMarginRedMaxInclusive,
        hysteresis: runtime.config.hysteresis.dewPointRiskC,
      ),
      AlertType.highDifferentialPressure => _recoverMaximum(
        measured: _finiteDouble(unitJson['presionDiferencial']),
        threshold: thresholds.filterPressureMax,
        hysteresis: runtime.config.hysteresis.differentialPressurePa,
      ),
      AlertType.muntersDoorOpen || AlertType.roomDoorOpen => true,
    };
  }
}

// Fail-safe by design: if a reading can't be computed this cycle (e.g. a
// transient Modbus read failure leaves a signal null), we must NOT treat
// that as "recovered". Doing so would let a single bad read silently clear
// an active alert while the real condition never changed, defeating
// hysteresis entirely — the alert would immediately reactivate on the next
// good read, gated only by the notification cooldown. Missing/invalid data
// means "we don't know", so the alert stays active (`false`) until we can
// actually confirm recovery.
bool _recoverTemperatureInterior({
  required double? measured,
  required double? minimum,
  required double? maximum,
  required double hysteresis,
}) {
  if (measured == null ||
      minimum == null ||
      maximum == null ||
      !minimum.isFinite ||
      !maximum.isFinite) {
    return false;
  }
  return measured >= minimum + hysteresis && measured <= maximum - hysteresis;
}

bool _recoverMaximum({
  required double? measured,
  required double? threshold,
  required double hysteresis,
}) {
  if (measured == null || threshold == null || !threshold.isFinite) {
    return false;
  }
  return measured <= threshold - hysteresis;
}

bool _recoverMinimum({
  required double? measured,
  required double? threshold,
  required double hysteresis,
}) {
  if (measured == null || threshold == null || !threshold.isFinite) {
    return false;
  }
  return measured >= threshold + hysteresis;
}

bool _recoverMinimumMargin({
  required double? margin,
  required double? threshold,
  required double hysteresis,
}) {
  if (margin == null || threshold == null || !threshold.isFinite) {
    return false;
  }
  return margin >= threshold + hysteresis;
}

double? _currentDewPointMargin(Map<String, Object?> unitJson) {
  final double? temperature = _finiteDouble(unitJson['tempInterior']);
  final double? humidity = _finiteDouble(unitJson['humInterior']);
  if (temperature == null || humidity == null) {
    return null;
  }
  return calculateDewPointMarginC(
    temperatureC: temperature,
    relativeHumidityPercent: humidity,
  );
}

double? _finiteDouble(Object? value) {
  if (value is num) {
    final double doubleValue = value.toDouble();
    return doubleValue.isFinite ? doubleValue : null;
  }
  if (value is String) {
    final double? parsed = double.tryParse(value.replaceAll(',', '.'));
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}

class AlertRoomIdentity {
  const AlertRoomIdentity({
    required this.roomId,
    required this.roomNumber,
    required this.muntersId,
  });

  static const List<AlertRoomIdentity> defaultRooms = <AlertRoomIdentity>[
    AlertRoomIdentity(roomId: 'room_1', roomNumber: 1, muntersId: 'munters1'),
    AlertRoomIdentity(roomId: 'room_2', roomNumber: 2, muntersId: 'munters2'),
  ];

  final String roomId;
  final int roomNumber;
  final String muntersId;
}

class SnapshotAlertProcessingResult {
  const SnapshotAlertProcessingResult({
    required this.evaluatedAt,
    required this.rooms,
  });

  final DateTime evaluatedAt;
  final List<RoomAlertEvaluationResult> rooms;

  List<EvaluatedAlert> get whatsAppCandidates {
    final List<EvaluatedAlert> candidates = <EvaluatedAlert>[
      for (final RoomAlertEvaluationResult room in rooms)
        ...room.whatsAppCandidates,
    ];
    candidates.sort((EvaluatedAlert a, EvaluatedAlert b) {
      final int orderA = _configuredOrderFor(a.type);
      final int orderB = _configuredOrderFor(b.type);
      final int orderComparison = orderA.compareTo(orderB);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return AlertMetadataRegistry.priorityIndex(
        a.type,
      ).compareTo(AlertMetadataRegistry.priorityIndex(b.type));
    });
    return List<EvaluatedAlert>.unmodifiable(candidates);
  }

  int _configuredOrderFor(AlertType type) {
    for (final RoomAlertEvaluationResult room in rooms) {
      final int? order = room.alertOrder?[type];
      if (order != null) {
        return order;
      }
    }
    return alertPriorityIndex(type) + 1;
  }
}

class RoomAlertEvaluationResult {
  const RoomAlertEvaluationResult._({
    required this.tenantId,
    required this.siteId,
    required this.roomId,
    required this.roomNumber,
    required this.muntersId,
    required this.evaluatedAt,
    required this.snapshotEvaluable,
    required this.evaluatedAlerts,
    required this.whatsAppCandidates,
    this.alertOrder,
    this.ignoredReason,
    this.transitionBatch,
  });

  factory RoomAlertEvaluationResult.ignored({
    required AlertRoomIdentity identity,
    required String tenantId,
    required String siteId,
    required DateTime evaluatedAt,
    required String ignoredReason,
  }) {
    return RoomAlertEvaluationResult._(
      tenantId: tenantId,
      siteId: siteId,
      roomId: identity.roomId,
      roomNumber: identity.roomNumber,
      muntersId: identity.muntersId,
      evaluatedAt: evaluatedAt,
      snapshotEvaluable: false,
      ignoredReason: ignoredReason,
      evaluatedAlerts: const <EvaluatedAlert>[],
      whatsAppCandidates: const <EvaluatedAlert>[],
      alertOrder: null,
    );
  }

  factory RoomAlertEvaluationResult.evaluated({
    required AlertRoomIdentity identity,
    required String tenantId,
    required String siteId,
    required DateTime evaluatedAt,
    required List<EvaluatedAlert> evaluatedAlerts,
    required AlertTransitionBatch transitionBatch,
    required List<EvaluatedAlert> whatsAppCandidates,
    required Map<AlertType, int> alertOrder,
  }) {
    return RoomAlertEvaluationResult._(
      tenantId: tenantId,
      siteId: siteId,
      roomId: identity.roomId,
      roomNumber: identity.roomNumber,
      muntersId: identity.muntersId,
      evaluatedAt: evaluatedAt,
      snapshotEvaluable: true,
      evaluatedAlerts: evaluatedAlerts,
      transitionBatch: transitionBatch,
      whatsAppCandidates: whatsAppCandidates,
      alertOrder: Map<AlertType, int>.unmodifiable(alertOrder),
    );
  }

  final String tenantId;
  final String siteId;
  final String roomId;
  final int roomNumber;
  final String muntersId;
  final DateTime evaluatedAt;
  final bool snapshotEvaluable;
  final String? ignoredReason;
  final List<EvaluatedAlert> evaluatedAlerts;
  final AlertTransitionBatch? transitionBatch;
  final List<EvaluatedAlert> whatsAppCandidates;
  final Map<AlertType, int>? alertOrder;
}

String? _readStateCode(Map<String, Object?> unitJson) {
  final Object? diagnostics = unitJson['diagnostics'];
  if (diagnostics is Map) {
    return diagnostics['stateCode']?.toString();
  }
  return null;
}

Map<String, Object?>? _asStringMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value as Map<Object?, Object?>);
  }
  return null;
}
