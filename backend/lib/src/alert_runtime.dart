import 'active_alerts_registry.dart';
import 'alert_notification_cooldown_registry.dart';
import 'alert_runtime_config.dart';
import 'alert_settings_cache.dart';
import 'room_wash_registry.dart';
import 'snapshot_evaluation_policy.dart';

class AlertRuntime {
  AlertRuntime({
    AlertSettingsCache? settingsCache,
    RoomWashRegistry? roomWashRegistry,
    ActiveAlertsRegistry? activeAlertsRegistry,
    AlertNotificationCooldownRegistry? notificationCooldownRegistry,
    SnapshotEvaluationPolicy? snapshotEvaluationPolicy,
    AlertRuntimeConfig config = const AlertRuntimeConfig(),
  }) : settingsCache = settingsCache ?? AlertSettingsCache(),
       roomWashRegistry = roomWashRegistry ?? RoomWashRegistry(),
       activeAlertsRegistry = activeAlertsRegistry ?? ActiveAlertsRegistry(),
       notificationCooldownRegistry =
           notificationCooldownRegistry ?? AlertNotificationCooldownRegistry(),
       snapshotEvaluationPolicy =
           snapshotEvaluationPolicy ?? const SnapshotEvaluationPolicy(),
       config = config;

  final AlertSettingsCache settingsCache;
  final RoomWashRegistry roomWashRegistry;
  final ActiveAlertsRegistry activeAlertsRegistry;
  final AlertNotificationCooldownRegistry notificationCooldownRegistry;
  final SnapshotEvaluationPolicy snapshotEvaluationPolicy;
  final AlertRuntimeConfig config;

  AlertRuntimeMetrics snapshotMetrics({DateTime? capturedAt}) {
    return AlertRuntimeMetrics(
      settingsCacheEntries: settingsCache.size,
      roomWashEntries: roomWashRegistry.size,
      activeAlertEntries: activeAlertsRegistry.size,
      cooldownEntries: notificationCooldownRegistry.size,
      settingsLoadFailuresCurrent: settingsCache.failureCount,
      settingsBackoffEntries: settingsCache.backoffEntryCount,
      capturedAt: capturedAt ?? DateTime.now().toUtc(),
    );
  }
}

class AlertRuntimeMetrics {
  const AlertRuntimeMetrics({
    required this.settingsCacheEntries,
    required this.roomWashEntries,
    required this.activeAlertEntries,
    required this.cooldownEntries,
    required this.settingsLoadFailuresCurrent,
    required this.settingsBackoffEntries,
    required this.capturedAt,
  });

  final int settingsCacheEntries;
  final int roomWashEntries;
  final int activeAlertEntries;
  final int cooldownEntries;
  final int settingsLoadFailuresCurrent;
  final int settingsBackoffEntries;
  final DateTime capturedAt;
}
