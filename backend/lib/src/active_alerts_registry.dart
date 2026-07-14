import 'alert_models.dart';

typedef AlertRecoveryPredicate = bool Function(ActiveAlertState activeAlert);

class ActiveAlertsRegistry {
  final Map<AlertInstanceKey, ActiveAlertState> _active =
      <AlertInstanceKey, ActiveAlertState>{};

  int get activeCount => _active.length;

  int get size => _active.length;

  List<ActiveAlertState> get activeAlerts =>
      List<ActiveAlertState>.unmodifiable(_active.values);

  int sizeForTenantSite({required String tenantId, required String siteId}) {
    return _active.keys
        .where(
          (AlertInstanceKey key) =>
              key.tenantId == tenantId && key.siteId == siteId,
        )
        .length;
  }

  int sizeForRoom({
    required String tenantId,
    required String siteId,
    required String roomId,
    String? muntersId,
  }) {
    return _active.keys
        .where(
          (AlertInstanceKey key) => key.matchesScope(
            tenantId: tenantId,
            siteId: siteId,
            roomId: roomId,
            muntersId: muntersId,
          ),
        )
        .length;
  }

  AlertTransitionBatch syncForRoom({
    required String tenantId,
    required String siteId,
    required String roomId,
    String? muntersId,
    required List<EvaluatedAlert> evaluatedAlerts,
    AlertRecoveryPredicate? shouldRecover,
  }) {
    final Map<AlertInstanceKey, EvaluatedAlert> activeNow =
        <AlertInstanceKey, EvaluatedAlert>{
          for (final EvaluatedAlert alert in evaluatedAlerts)
            if (alert.isActive) alert.key: alert,
        };
    final List<EvaluatedAlert> activated = <EvaluatedAlert>[];
    final List<EvaluatedAlert> stillActive = <EvaluatedAlert>[];
    final List<ActiveAlertState> recovered = <ActiveAlertState>[];

    for (final EvaluatedAlert alert in activeNow.values) {
      final ActiveAlertState? previous = _active[alert.key];
      if (previous == null) {
        _active[alert.key] = ActiveAlertState.fromEvaluated(alert);
        activated.add(alert);
      } else {
        _active[alert.key] = previous.updateFrom(alert);
        stillActive.add(alert);
      }
    }

    final List<AlertInstanceKey> scopedKeys = _active.keys
        .where(
          (AlertInstanceKey key) => key.matchesScope(
            tenantId: tenantId,
            siteId: siteId,
            roomId: roomId,
            muntersId: muntersId,
          ),
        )
        .toList(growable: false);
    for (final AlertInstanceKey key in scopedKeys) {
      if (activeNow.containsKey(key)) {
        continue;
      }
      final ActiveAlertState? activeAlert = _active[key];
      if (activeAlert != null &&
          shouldRecover != null &&
          !shouldRecover(activeAlert)) {
        continue;
      }
      final ActiveAlertState? removed = _active.remove(key);
      if (removed != null) {
        recovered.add(removed);
      }
    }

    return AlertTransitionBatch(
      activated: List<EvaluatedAlert>.unmodifiable(activated),
      stillActive: List<EvaluatedAlert>.unmodifiable(stillActive),
      recovered: List<ActiveAlertState>.unmodifiable(recovered),
    );
  }

  void clearAll() {
    _active.clear();
  }

  void clearForTenantSite({required String tenantId, required String siteId}) {
    _active.removeWhere(
      (AlertInstanceKey key, _) =>
          key.tenantId == tenantId && key.siteId == siteId,
    );
  }

  void clearForRoom({
    required String tenantId,
    required String siteId,
    required String roomId,
    String? muntersId,
  }) {
    _active.removeWhere(
      (AlertInstanceKey key, _) => key.matchesScope(
        tenantId: tenantId,
        siteId: siteId,
        roomId: roomId,
        muntersId: muntersId,
      ),
    );
  }
}
