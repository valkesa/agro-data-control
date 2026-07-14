enum SnapshotEvaluationDecision { evaluable, nonEvaluable }

class SnapshotEvaluationPolicy {
  const SnapshotEvaluationPolicy();

  SnapshotEvaluationDecision decisionForStateCode(String? stateCode) {
    return switch (stateCode) {
      'PLC_HEALTHY' ||
      'PLC_RUN_CONFIRMED' => SnapshotEvaluationDecision.evaluable,
      'PLC_STOP_CONFIRMED' ||
      'PLC_UNREACHABLE' ||
      'PLC_NOT_CONFIGURED' ||
      null => SnapshotEvaluationDecision.nonEvaluable,
      _ => SnapshotEvaluationDecision.nonEvaluable,
    };
  }

  bool isEvaluableStateCode(String? stateCode) {
    return decisionForStateCode(stateCode) ==
        SnapshotEvaluationDecision.evaluable;
  }
}
