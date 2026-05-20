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
    required this.temperatureHistories,
    required this.differentialPressureHistories,
    required this.doorOpenings,
    required this.runtimeEvents,
    this.routerHost,
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
    final String fallbackTenantId =
        _sanitizeSegment(clientName) ?? 'default-tenant';
    final String fallbackSiteId =
        _sanitizeSegment(json['siteName'] as String?) ?? 'default-site';
    final String fallbackPlcId =
        _sanitizeSegment(defaultSourceUnitKey) ?? 'default-plc';
    final List<TemperatureHistoryConfig> temperatureHistories =
        _parseTemperatureHistories(
          json,
          fallbackTenantId: fallbackTenantId,
          fallbackSiteId: fallbackSiteId,
          fallbackPlcId: fallbackPlcId,
          fallbackSourceUnitKey: defaultSourceUnitKey,
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
      temperatureHistories: temperatureHistories,
      differentialPressureHistories: _parseDifferentialPressureHistories(
        json,
        units: units,
        fallbackTenantId: fallbackTenantId,
        fallbackSiteId: fallbackSiteId,
        temperatureHistories: temperatureHistories,
      ),
      doorOpenings: DoorOpeningsConfig.fromJson(
        json['doorOpenings'] as Map<String, dynamic>?,
        fallbackTenantId: fallbackTenantId,
        fallbackSiteId: fallbackSiteId,
      ),
      runtimeEvents: RuntimeEventsConfig.fromJson(
        json['runtimeEvents'] as Map<String, dynamic>?,
        fallbackTenantId: fallbackTenantId,
        fallbackSiteId: fallbackSiteId,
        fallbackPlcId: fallbackPlcId,
        fallbackPollingIntervalMs:
            (json['pollingIntervalMs'] as num?)?.toInt() ?? 5000,
      ),
      routerHost: json['routerHost'] as String?,
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
  final List<TemperatureHistoryConfig> temperatureHistories;
  final List<DifferentialPressureHistoryConfig> differentialPressureHistories;
  final DoorOpeningsConfig doorOpenings;
  final RuntimeEventsConfig runtimeEvents;
  final String? routerHost;
}

class DifferentialPressureHistoryConfig {
  DifferentialPressureHistoryConfig({
    required this.enabled,
    required this.sourcePath,
    required this.tenantId,
    required this.siteId,
    required this.plcId,
    required this.firestoreProjectId,
    required this.firestoreDatabaseId,
    required this.firestoreServiceAccountPath,
  });

  factory DifferentialPressureHistoryConfig.fromJson(
    Map<String, dynamic>? json, {
    required String fallbackTenantId,
    required String fallbackSiteId,
    required String fallbackPlcId,
    required String fallbackSourcePath,
    String? fallbackFirestoreProjectId,
    String fallbackFirestoreDatabaseId = '(default)',
    String fallbackFirestoreServiceAccountPath = '',
  }) {
    return DifferentialPressureHistoryConfig(
      enabled: json?['enabled'] as bool? ?? true,
      sourcePath:
          json?['pressureDifferentialSource'] as String? ??
          json?['differentialPressureSource'] as String? ??
          fallbackSourcePath,
      tenantId:
          _sanitizeSegment(
            (json?['tenantId'] ?? json?['clientId']) as String?,
          ) ??
          fallbackTenantId,
      siteId: _sanitizeSegment(json?['siteId'] as String?) ?? fallbackSiteId,
      plcId: _sanitizeSegment(json?['plcId'] as String?) ?? fallbackPlcId,
      firestoreProjectId:
          json?['firestoreProjectId'] as String? ?? fallbackFirestoreProjectId,
      firestoreDatabaseId:
          json?['firestoreDatabaseId'] as String? ??
          fallbackFirestoreDatabaseId,
      firestoreServiceAccountPath:
          json?['firestoreServiceAccountPath'] as String? ??
          fallbackFirestoreServiceAccountPath,
    );
  }

  final bool enabled;
  final String sourcePath;
  final String tenantId;
  final String siteId;
  final String plcId;
  final String? firestoreProjectId;
  final String firestoreDatabaseId;
  final String firestoreServiceAccountPath;
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
      siteId: _sanitizeSegment(json?['siteId'] as String?) ?? fallbackSiteId,
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

class DoorOpeningsConfig {
  DoorOpeningsConfig({
    required this.enabled,
    required this.tenantId,
    required this.siteId,
    required this.doors,
    required this.firestoreProjectId,
    required this.firestoreDatabaseId,
    required this.firestoreServiceAccountPath,
  });

  factory DoorOpeningsConfig.fromJson(
    Map<String, dynamic>? json, {
    required String fallbackTenantId,
    required String fallbackSiteId,
  }) {
    final List<dynamic> doorsRaw =
        json?['doors'] as List<dynamic>? ?? <dynamic>[];
    return DoorOpeningsConfig(
      enabled: json?['enabled'] as bool? ?? false,
      tenantId:
          _sanitizeSegment(
            (json?['tenantId'] ?? json?['clientId']) as String?,
          ) ??
          fallbackTenantId,
      siteId: _sanitizeSegment(json?['siteId'] as String?) ?? fallbackSiteId,
      doors: doorsRaw
          .map((Object? d) => DoorConfig.fromJson(d as Map<String, dynamic>))
          .toList(),
      firestoreProjectId: json?['firestoreProjectId'] as String?,
      firestoreDatabaseId:
          json?['firestoreDatabaseId'] as String? ?? '(default)',
      firestoreServiceAccountPath:
          json?['firestoreServiceAccountPath'] as String? ?? '',
    );
  }

  final bool enabled;
  final String tenantId;
  final String siteId;
  final List<DoorConfig> doors;
  final String? firestoreProjectId;
  final String firestoreDatabaseId;

  /// Ruta al archivo JSON del Service Account de Google.
  final String firestoreServiceAccountPath;
}

class DoorConfig {
  DoorConfig({
    required this.doorId,
    required this.unitKey,
    required this.signalKey,
    required this.label,
  });

  factory DoorConfig.fromJson(Map<String, dynamic> json) {
    final String doorId = json['doorId'] as String? ?? '';
    return DoorConfig(
      doorId: doorId,
      unitKey: json['unitKey'] as String? ?? '',
      signalKey: json['signalKey'] as String? ?? '',
      label: json['label'] as String? ?? doorId,
    );
  }

  final String doorId;
  final String unitKey;
  final String signalKey;
  final String label;
}

class RuntimeEventsConfig {
  RuntimeEventsConfig({
    required this.enabled,
    required this.tenantId,
    required this.siteId,
    required this.plcs,
    required this.firestoreProjectId,
    required this.firestoreDatabaseId,
    required this.firestoreServiceAccountPath,
    required this.hbGapThresholdMs,
  });

  factory RuntimeEventsConfig.fromJson(
    Map<String, dynamic>? json, {
    required String fallbackTenantId,
    required String fallbackSiteId,
    required String fallbackPlcId,
    int fallbackPollingIntervalMs = 5000,
  }) {
    final List<dynamic> plcsRaw =
        json?['plcs'] as List<dynamic>? ?? <dynamic>[];
    // Default gap threshold = 3 × polling interval. A gap larger than this
    // means the backend or connection was down, so a new HB doc is created.
    final int defaultGapThresholdMs = fallbackPollingIntervalMs * 3;
    return RuntimeEventsConfig(
      enabled: json?['enabled'] as bool? ?? false,
      tenantId:
          _sanitizeSegment(
            (json?['tenantId'] ?? json?['clientId']) as String?,
          ) ??
          fallbackTenantId,
      siteId: _sanitizeSegment(json?['siteId'] as String?) ?? fallbackSiteId,
      plcs: plcsRaw
          .map(
            (Object? plc) => RuntimePlcConfig.fromJson(
              plc as Map<String, dynamic>,
              fallbackPlcId: fallbackPlcId,
            ),
          )
          .toList(),
      firestoreProjectId: json?['firestoreProjectId'] as String?,
      firestoreDatabaseId:
          json?['firestoreDatabaseId'] as String? ?? '(default)',
      firestoreServiceAccountPath:
          json?['firestoreServiceAccountPath'] as String? ?? '',
      hbGapThresholdMs:
          json?['hbGapThresholdMs'] as int? ?? defaultGapThresholdMs,
    );
  }

  final bool enabled;
  final String tenantId;
  final String siteId;
  final List<RuntimePlcConfig> plcs;
  final String? firestoreProjectId;
  final String firestoreDatabaseId;
  // If two consecutive HBs for the same event are more than this apart, a new
  // Firestore document is created (gap marker). Otherwise the previous doc is
  // overwritten in-place (deduplication). Defaults to 3 × pollingIntervalMs.
  final int hbGapThresholdMs;

  /// Ruta al archivo JSON del Service Account de Google.
  final String firestoreServiceAccountPath;
}

class RuntimePlcConfig {
  RuntimePlcConfig({
    required this.unitKey,
    required this.plcId,
    required this.humidifierPumpSignal,
    required this.heater1Signal,
    required this.heater2Signal,
    required this.fansPowerSignal,
    required this.fansPowerMultiplier,
    required this.fansPowerOffset,
    required this.nominalPowerWatts,
  });

  factory RuntimePlcConfig.fromJson(
    Map<String, dynamic> json, {
    required String fallbackPlcId,
  }) {
    final String unitKey = json['unitKey'] as String? ?? fallbackPlcId;
    final Map<String, dynamic> nominalPowerRaw =
        json['nominalPowerWatts'] as Map<String, dynamic>? ??
        <String, dynamic>{};
    return RuntimePlcConfig(
      unitKey: unitKey,
      plcId:
          _sanitizeSegment(json['plcId'] as String?) ??
          _sanitizeSegment(unitKey) ??
          fallbackPlcId,
      humidifierPumpSignal:
          json['humidifierPumpSignal'] as String? ?? 'bombaHumidificador',
      heater1Signal: json['heater1Signal'] as String? ?? 'resistencia1',
      heater2Signal: json['heater2Signal'] as String? ?? 'resistencia2',
      fansPowerSignal:
          json['fansPowerSignal'] as String? ?? 'tensionSalidaVentiladores',
      fansPowerMultiplier:
          (json['fansPowerMultiplier'] as num?)?.toDouble() ?? 1,
      fansPowerOffset: (json['fansPowerOffset'] as num?)?.toDouble() ?? 0,
      nominalPowerWatts: nominalPowerRaw.map(
        (String key, dynamic value) => MapEntry(
          key,
          value is num ? value.toDouble() : double.tryParse(value.toString()),
        ),
      ),
    );
  }

  final String unitKey;
  final String plcId;
  final String humidifierPumpSignal;
  final String heater1Signal;
  final String heater2Signal;
  final String fansPowerSignal;
  final double fansPowerMultiplier;
  final double fansPowerOffset;
  final Map<String, double?> nominalPowerWatts;
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

List<TemperatureHistoryConfig> _parseTemperatureHistories(
  Map<String, dynamic> json, {
  required String fallbackTenantId,
  required String fallbackSiteId,
  required String fallbackPlcId,
  required String fallbackSourceUnitKey,
}) {
  final Object? list = json['temperatureHistories'];
  if (list is List && list.isNotEmpty) {
    return list
        .map(
          (Object? e) => TemperatureHistoryConfig.fromJson(
            e as Map<String, dynamic>?,
            fallbackTenantId: fallbackTenantId,
            fallbackSiteId: fallbackSiteId,
            fallbackPlcId: fallbackPlcId,
            fallbackSourceUnitKey: fallbackSourceUnitKey,
          ),
        )
        .toList();
  }
  return <TemperatureHistoryConfig>[
    TemperatureHistoryConfig.fromJson(
      json['temperatureHistory'] as Map<String, dynamic>?,
      fallbackTenantId: fallbackTenantId,
      fallbackSiteId: fallbackSiteId,
      fallbackPlcId: fallbackPlcId,
      fallbackSourceUnitKey: fallbackSourceUnitKey,
    ),
  ];
}

List<DifferentialPressureHistoryConfig> _parseDifferentialPressureHistories(
  Map<String, dynamic> json, {
  required Map<String, UnitConfig> units,
  required String fallbackTenantId,
  required String fallbackSiteId,
  required List<TemperatureHistoryConfig> temperatureHistories,
}) {
  final Map<String, TemperatureHistoryConfig> tempByPlc =
      <String, TemperatureHistoryConfig>{
        for (final TemperatureHistoryConfig config in temperatureHistories)
          config.plcId: config,
      };
  final Object? list = json['differentialPressureHistories'];
  if (list is List && list.isNotEmpty) {
    return list.map((Object? e) {
      final Map<String, dynamic>? entry = e as Map<String, dynamic>?;
      final String sourcePath =
          entry?['pressureDifferentialSource'] as String? ??
          entry?['differentialPressureSource'] as String? ??
          'munters2.presionDiferencial';
      final String unitKey = sourcePath.split('.').first;
      final String plcId =
          _sanitizeSegment(entry?['plcId'] as String?) ??
          _sanitizeSegment(unitKey) ??
          'default-plc';
      final TemperatureHistoryConfig? tempConfig = tempByPlc[plcId];
      return DifferentialPressureHistoryConfig.fromJson(
        entry,
        fallbackTenantId: fallbackTenantId,
        fallbackSiteId: fallbackSiteId,
        fallbackPlcId: plcId,
        fallbackSourcePath: sourcePath,
        fallbackFirestoreProjectId: tempConfig?.firestoreProjectId,
        fallbackFirestoreDatabaseId:
            tempConfig?.firestoreDatabaseId ?? '(default)',
        fallbackFirestoreServiceAccountPath:
            tempConfig?.firestoreServiceAccountPath ?? '',
      );
    }).toList();
  }

  return units.entries
      .where(
        (MapEntry<String, UnitConfig> entry) =>
            entry.value.signals.containsKey('presionDiferencial') ||
            entry.value.signals.containsKey('pressureDifferential') ||
            entry.value.signals.containsKey('differentialPressure'),
      )
      .map((MapEntry<String, UnitConfig> entry) {
        final String plcId = _sanitizeSegment(entry.key) ?? 'default-plc';
        final TemperatureHistoryConfig? tempConfig = tempByPlc[plcId];
        return DifferentialPressureHistoryConfig.fromJson(
          null,
          fallbackTenantId: tempConfig?.tenantId ?? fallbackTenantId,
          fallbackSiteId: tempConfig?.siteId ?? fallbackSiteId,
          fallbackPlcId: plcId,
          fallbackSourcePath: '${entry.key}.presionDiferencial',
          fallbackFirestoreProjectId: tempConfig?.firestoreProjectId,
          fallbackFirestoreDatabaseId:
              tempConfig?.firestoreDatabaseId ?? '(default)',
          fallbackFirestoreServiceAccountPath:
              tempConfig?.firestoreServiceAccountPath ?? '',
        );
      })
      .toList();
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
