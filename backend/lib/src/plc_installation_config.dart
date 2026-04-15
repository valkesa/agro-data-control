class PlcInstallationConfig {
  PlcInstallationConfig({
    required this.backendName,
    required this.clientName,
    required this.siteName,
    required this.plcHost,
    required this.plcPort,
    required this.unitId,
    required this.pollingIntervalMs,
    required this.timeoutMs,
    required this.httpHost,
    required this.httpPort,
    required this.units,
    required this.temperatureHistory,
  });

  factory PlcInstallationConfig.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> unitsJson =
        json['units'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, UnitConfig> units = unitsJson.map(
      (key, value) =>
          MapEntry(key, UnitConfig.fromJson(value as Map<String, dynamic>)),
    );
    final String clientName =
        json['clientName'] as String? ?? 'Cliente no configurado';
    final String defaultSourceUnitKey = _resolveDefaultTemperatureSourceUnitKey(
      units,
    );

    return PlcInstallationConfig(
      backendName: json['backendName'] as String? ?? 'current',
      clientName: clientName,
      siteName: json['siteName'] as String? ?? 'Sitio no configurado',
      plcHost: json['plcHost'] as String? ?? '127.0.0.1',
      plcPort: (json['plcPort'] as num?)?.toInt() ?? 502,
      unitId: (json['unitId'] as num?)?.toInt() ?? 1,
      pollingIntervalMs: (json['pollingIntervalMs'] as num?)?.toInt() ?? 5000,
      timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 1500,
      httpHost: json['httpHost'] as String? ?? '0.0.0.0',
      httpPort: (json['httpPort'] as num?)?.toInt() ?? 8080,
      units: units,
      temperatureHistory: TemperatureHistoryConfig.fromJson(
        json['temperatureHistory'] as Map<String, dynamic>?,
        fallbackTenantId: _sanitizeSegment(clientName) ?? 'default-tenant',
        fallbackSiteId:
            _sanitizeSegment(json['siteName'] as String?) ?? 'default-site',
        fallbackPlcId: _sanitizeSegment(defaultSourceUnitKey) ?? 'default-plc',
        fallbackSourceUnitKey: defaultSourceUnitKey,
      ),
    );
  }

  final String backendName;
  final String clientName;
  final String siteName;
  final String plcHost;
  final int plcPort;
  final int unitId;
  final int pollingIntervalMs;
  final int timeoutMs;
  final String httpHost;
  final int httpPort;
  final Map<String, UnitConfig> units;
  final TemperatureHistoryConfig temperatureHistory;
}

class TemperatureHistoryConfig {
  TemperatureHistoryConfig({
    required this.enabled,
    required this.sourcePath,
    required this.tenantId,
    required this.siteId,
    required this.plcId,
    required this.firestoreProjectId,
    required this.firestoreDatabaseId,
    required this.firestoreServiceAccountPath,
  });

  factory TemperatureHistoryConfig.fromJson(
    Map<String, dynamic>? json, {
    required String fallbackTenantId,
    required String fallbackSiteId,
    required String fallbackPlcId,
    required String fallbackSourceUnitKey,
  }) {
    return TemperatureHistoryConfig(
      enabled: json?['enabled'] as bool? ?? true,
      sourcePath:
          json?['temperatureSource'] as String? ??
          '$fallbackSourceUnitKey.tempInterior',
      tenantId:
          _sanitizeSegment(
            (json?['tenantId'] ?? json?['clientId']) as String?,
          ) ??
          fallbackTenantId,
      siteId:
          _sanitizeSegment(json?['siteId'] as String?) ?? fallbackSiteId,
      plcId: _sanitizeSegment(json?['plcId'] as String?) ?? fallbackPlcId,
      firestoreProjectId: json?['firestoreProjectId'] as String?,
      firestoreDatabaseId:
          json?['firestoreDatabaseId'] as String? ?? '(default)',
      firestoreServiceAccountPath:
          json?['firestoreServiceAccountPath'] as String? ?? '',
    );
  }

  final bool enabled;
  final String sourcePath;
  final String tenantId;
  final String siteId;
  final String plcId;
  final String? firestoreProjectId;
  final String firestoreDatabaseId;
  /// Ruta al archivo JSON del Service Account de Google.
  final String firestoreServiceAccountPath;
}

class UnitConfig {
  UnitConfig({
    required this.name,
    required this.signals,
    this.plcHost,
    this.plcPort,
    this.unitId,
    this.runStopSignal,
  });

  factory UnitConfig.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> signalsJson =
        json['signals'] as Map<String, dynamic>? ?? <String, dynamic>{};

    return UnitConfig(
      name: json['name'] as String? ?? 'Unidad sin nombre',
      signals: signalsJson.map(
        (key, value) =>
            MapEntry(key, SignalConfig.fromJson(value as Map<String, dynamic>)),
      ),
      plcHost: json['plcHost'] as String?,
      plcPort: (json['plcPort'] as num?)?.toInt(),
      unitId: (json['unitId'] as num?)?.toInt(),
      runStopSignal: json['runStopSignal'] is Map<String, dynamic>
          ? SignalConfig.fromJson(json['runStopSignal'] as Map<String, dynamic>)
          : null,
    );
  }

  final String name;
  final Map<String, SignalConfig> signals;
  final String? plcHost;
  final int? plcPort;
  final int? unitId;
  final SignalConfig? runStopSignal;
}

enum SignalArea { holdingRegister, inputRegister, coil, discreteInput }

enum SignalDataType { bool, int, double, string }

enum WordOrder { bigEndian, littleEndian }

class SignalConfig {
  SignalConfig({
    required this.area,
    required this.address,
    required this.dataType,
    required this.wordCount,
    required this.signed,
    required this.scale,
    required this.offset,
    required this.wordOrder,
    required this.enumMap,
    required this.bitIndex,
  });

  factory SignalConfig.fromJson(Map<String, dynamic> json) {
    return SignalConfig(
      area: _parseArea(json['area'] as String?),
      address: (json['address'] as num?)?.toInt() ?? 0,
      dataType: _parseDataType(json['dataType'] as String?),
      wordCount: (json['wordCount'] as num?)?.toInt() ?? 1,
      signed: json['signed'] as bool? ?? false,
      scale: (json['scale'] as num?)?.toDouble() ?? 1,
      offset: (json['offset'] as num?)?.toDouble() ?? 0,
      wordOrder: _parseWordOrder(json['wordOrder'] as String?),
      enumMap: (json['enumMap'] as Map<String, dynamic>? ?? <String, dynamic>{})
          .map((key, value) => MapEntry(key, value.toString())),
      bitIndex: (json['bitIndex'] as num?)?.toInt(),
    );
  }

  final SignalArea area;
  final int address;
  final SignalDataType dataType;
  final int wordCount;
  final bool signed;
  final double scale;
  final double offset;
  final WordOrder wordOrder;
  final Map<String, String> enumMap;
  final int? bitIndex;

  static SignalArea _parseArea(String? raw) {
    return switch (raw) {
      'inputRegister' => SignalArea.inputRegister,
      'coil' => SignalArea.coil,
      'discreteInput' => SignalArea.discreteInput,
      _ => SignalArea.holdingRegister,
    };
  }

  static SignalDataType _parseDataType(String? raw) {
    return switch (raw) {
      'bool' => SignalDataType.bool,
      'int' => SignalDataType.int,
      'string' => SignalDataType.string,
      _ => SignalDataType.double,
    };
  }

  static WordOrder _parseWordOrder(String? raw) {
    return switch (raw) {
      'littleEndian' => WordOrder.littleEndian,
      _ => WordOrder.bigEndian,
    };
  }
}

String _resolveDefaultTemperatureSourceUnitKey(Map<String, UnitConfig> units) {
  for (final MapEntry<String, UnitConfig> entry in units.entries) {
    if (entry.value.signals.containsKey('tempInterior')) {
      return entry.key;
    }
  }
  return units.keys.isNotEmpty ? units.keys.first : 'default-plc';
}

String? _sanitizeSegment(String? raw) {
  if (raw == null) {
    return null;
  }
  final String normalized = raw.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '-',
  );
  final String compact = normalized.replaceAll(RegExp(r'-+'), '-');
  final String cleaned = compact.replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? null : cleaned;
}
