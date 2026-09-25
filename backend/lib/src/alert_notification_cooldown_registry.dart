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
  final Map<AlertNotificationCooldownKey, _CooldownEntry> _entries =
      <AlertNotificationCooldownKey, _CooldownEntry>{};

  int get size => _entries.length;

  DateTime? lastSentAt(AlertInstanceKey key) {
    return _entries[AlertNotificationCooldownKey.fromAlertKey(key)]?.at;
  }

  bool canSend({
    required AlertInstanceKey key,
    required DateTime now,
    required Duration cooldown,
  }) {
    final _CooldownEntry? previous =
        _entries[AlertNotificationCooldownKey.fromAlertKey(key)];
    if (previous == null) {
      return true;
    }
    return !now.difference(previous.at).isNegative &&
        now.difference(previous.at) >= cooldown;
  }

  void markPending({
    required AlertInstanceKey key,
    required DateTime queuedAt,
  }) {
    _entries[AlertNotificationCooldownKey.fromAlertKey(key)] = _CooldownEntry(
      at: queuedAt.toUtc(),
      confirmedSent: false,
    );
  }

  void markSent({required AlertInstanceKey key, required DateTime sentAt}) {
    _entries[AlertNotificationCooldownKey.fromAlertKey(key)] = _CooldownEntry(
      at: sentAt.toUtc(),
      confirmedSent: true,
    );
  }

  void releasePending(AlertInstanceKey key) {
    final AlertNotificationCooldownKey cooldownKey =
        AlertNotificationCooldownKey.fromAlertKey(key);
    final _CooldownEntry? entry = _entries[cooldownKey];
    if (entry != null && !entry.confirmedSent) {
      _entries.remove(cooldownKey);
    }
  }

  void clearAll() {
    _entries.clear();
  }
}

class _CooldownEntry {
  const _CooldownEntry({required this.at, required this.confirmedSent});

  final DateTime at;
  final bool confirmedSent;
}
