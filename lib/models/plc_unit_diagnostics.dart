class PlcUnitDiagnostics {
  const PlcUnitDiagnostics({
    required this.backendAlive,
    required this.plcConnectOk,
    required this.validKeySignals,
    required this.invalidKeySignals,
    required this.totalKeySignals,
    required this.lastPollAt,
    required this.lastSuccessfulReadAt,
    required this.stateCode,
    required this.stateLabel,
    required this.stateReason,
  });

  static const String backendDown = 'BACKEND_DOWN';
  // Extra fallback state kept for units that still exist in UI but are not
  // wired in config; operational backend-down is still resolved in frontend.
  static const String plcNotConfigured = 'PLC_NOT_CONFIGURED';
  static const String plcUnreachable = 'PLC_UNREACHABLE';
  static const String plcReachableNoValidData =
      'PLC_REACHABLE_NO_VALID_DATA';
  static const String plcRunConfirmed = 'PLC_RUN_CONFIRMED';
  static const String plcStopConfirmed = 'PLC_STOP_CONFIRMED';
  static const String plcStateUnknown = 'PLC_STATE_UNKNOWN';
  static const String plcReachableStateUnknown =
      'PLC_REACHABLE_STATE_UNKNOWN';
  static const String plcHealthy = 'PLC_HEALTHY';

  final bool backendAlive;
  final bool plcConnectOk;
  final int? validKeySignals;
  final int? invalidKeySignals;
  final int? totalKeySignals;
  final DateTime? lastPollAt;
  final DateTime? lastSuccessfulReadAt;
  final String stateCode;
  final String stateLabel;
  final String stateReason;

  PlcUnitDiagnostics copyWith({
    bool? backendAlive,
    bool? plcConnectOk,
    int? validKeySignals,
    int? invalidKeySignals,
    int? totalKeySignals,
    DateTime? lastPollAt,
    DateTime? lastSuccessfulReadAt,
    String? stateCode,
    String? stateLabel,
    String? stateReason,
  }) {
    return PlcUnitDiagnostics(
      backendAlive: backendAlive ?? this.backendAlive,
      plcConnectOk: plcConnectOk ?? this.plcConnectOk,
      validKeySignals: validKeySignals ?? this.validKeySignals,
      invalidKeySignals: invalidKeySignals ?? this.invalidKeySignals,
      totalKeySignals: totalKeySignals ?? this.totalKeySignals,
      lastPollAt: lastPollAt ?? this.lastPollAt,
      lastSuccessfulReadAt: lastSuccessfulReadAt ?? this.lastSuccessfulReadAt,
      stateCode: stateCode ?? this.stateCode,
      stateLabel: stateLabel ?? this.stateLabel,
      stateReason: stateReason ?? this.stateReason,
    );
  }
}
