class BackendInstallationConfig {
  const BackendInstallationConfig({
    required this.clientName,
    required this.siteName,
    required this.plcHost,
    required this.plcPort,
    required this.unitId,
    required this.pollingIntervalMs,
    required this.timeoutMs,
  });

  factory BackendInstallationConfig.fromJson(Map<String, dynamic> json) {
    return BackendInstallationConfig(
      clientName: json['clientName'] as String? ?? '',
      siteName: json['siteName'] as String? ?? '',
      plcHost: json['plcHost'] as String? ?? '',
      plcPort: (json['plcPort'] as num?)?.toInt() ?? 502,
      unitId: (json['unitId'] as num?)?.toInt() ?? 1,
      pollingIntervalMs: (json['pollingIntervalMs'] as num?)?.toInt() ?? 5000,
      timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 1500,
    );
  }

  final String clientName;
  final String siteName;
  final String plcHost;
  final int plcPort;
  final int unitId;
  final int pollingIntervalMs;
  final int timeoutMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'clientName': clientName,
    'siteName': siteName,
    'plcHost': plcHost,
    'plcPort': plcPort,
    'unitId': unitId,
    'pollingIntervalMs': pollingIntervalMs,
    'timeoutMs': timeoutMs,
  };
}
