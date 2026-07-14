import 'alert_models.dart';
import 'alert_priority.dart';

class AlertNotificationCooldownKey {
  const AlertNotificationCooldownKey({
    required this.tenantId,
    required this.siteId,
    required this.roomId,
    required this.alertType,
  });

  factory AlertNotificationCooldownKey.fromAlertKey(AlertInstanceKey key) {
    return AlertNotificationCooldownKey(
      tenantId: key.tenantId,
      siteId: key.siteId,
      roomId: key.roomId,
      alertType: key.alertType,
    );
  }

  final String tenantId;
  final String siteId;
  final String roomId;
  final AlertType alertType;

  @override
  bool operator ==(Object other) {
    return other is AlertNotificationCooldownKey &&
        other.tenantId == tenantId &&
        other.siteId == siteId &&
        other.roomId == roomId &&
        other.alertType == alertType;
  }

  @override
  int get hashCode => Object.hash(tenantId, siteId, roomId, alertType);
}

class AlertNotificationCooldownRegistry {
  final Map<AlertNotificationCooldownKey, DateTime> _lastSentAt =
      <AlertNotificationCooldownKey, DateTime>{};

  int get size => _lastSentAt.length;

  DateTime? lastSentAt(AlertInstanceKey key) {
    return _lastSentAt[AlertNotificationCooldownKey.fromAlertKey(key)];
  }

  bool canSend({
    required AlertInstanceKey key,
    required DateTime now,
    required Duration cooldown,
  }) {
    final DateTime? previous =
        _lastSentAt[AlertNotificationCooldownKey.fromAlertKey(key)];
    if (previous == null) {
      return true;
    }
    return !now.difference(previous).isNegative &&
        now.difference(previous) >= cooldown;
  }

  void markSent({required AlertInstanceKey key, required DateTime sentAt}) {
    _lastSentAt[AlertNotificationCooldownKey.fromAlertKey(key)] = sentAt;
  }

  void clearAll() {
    _lastSentAt.clear();
  }
}
