import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'alert_configuration_contracts.dart';
import 'alert_priority.dart';
import 'alert_runtime_config.dart';
import 'alert_settings_cache.dart';
import 'operational_alert_topology.dart';
import 'service_account_auth.dart';

class AlertConfigPatch {
  const AlertConfigPatch({
    required this.alertId,
    required this.origin,
    this.enabled,
    this.visualEnabled,
    this.whatsappEnabled,
    this.whatsappDelay,
    this.thresholds = const AlertThresholdConfig(),
    this.cooldown,
    this.order,
  });

  factory AlertConfigPatch.fromRaw({
    required String alertId,
    required AlertConfigOrigin origin,
    required Map<String, Object?> raw,
  }) {
    return AlertConfigPatch(
      alertId: alertId,
      origin: origin,
      enabled: _readOptionalBool(raw, 'enabled'),
      visualEnabled: _readOptionalBool(raw, 'visualEnabled'),
      whatsappEnabled: _readOptionalBool(raw, 'whatsappEnabled'),
      whatsappDelay: _readOptionalDurationMinutes(raw, 'whatsappDelayMinutes'),
      thresholds: _readThresholds(raw['thresholds']),
      cooldown: _readOptionalDurationMinutes(raw, 'cooldownMinutes'),
      order: _readOptionalPositiveInt(raw['order']),
    );
  }

  final String alertId;
  final AlertConfigOrigin origin;
  final bool? enabled;
  final bool? visualEnabled;
  final bool? whatsappEnabled;
  final Duration? whatsappDelay;
  final AlertThresholdConfig thresholds;
  final Duration? cooldown;
  final int? order;

  bool get hasAnyValue =>
      enabled != null ||
      visualEnabled != null ||
      whatsappEnabled != null ||
      whatsappDelay != null ||
      cooldown != null ||
      order != null ||
      thresholds.min != null ||
      thresholds.max != null ||
      thresholds.threshold != null ||
      thresholds.margin != null ||
      thresholds.sensorFailureMin != null;
}

class AlertConfigFirestoreDocument {
  const AlertConfigFirestoreDocument({
    required this.alertId,
    required this.patch,
    required this.updatedAt,
    required this.updatedBy,
    this.createdAt,
    this.createdBy,
    this.schemaVersion = 1,
  });

  factory AlertConfigFirestoreDocument.fromRaw({
    required String alertId,
    required AlertConfigOrigin origin,
    required Map<String, Object?> raw,
  }) {
    final int? schemaVersion = _readOptionalNonNegativeInt(
      raw['schemaVersion'],
    );
    final AlertConfigPatch patch = AlertConfigPatch.fromRaw(
      alertId: alertId,
      origin: origin,
      raw: raw,
    );
    final AlertConfigFirestoreDocument document = AlertConfigFirestoreDocument(
      alertId: alertId,
      patch: patch,
      schemaVersion: schemaVersion ?? 0,
      createdAt: _readOptionalDateTime(raw['createdAt']),
      createdBy: raw['createdBy']?.toString(),
      updatedAt: _readOptionalDateTime(raw['updatedAt']),
      updatedBy: raw['updatedBy']?.toString() ?? '',
    );
    document.validate();
    return document;
  }

  final String alertId;
  final AlertConfigPatch patch;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String updatedBy;
  final int schemaVersion;

  Map<String, Object?> toFirestoreMap() {
    validate();
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      if (patch.enabled != null) 'enabled': patch.enabled,
      if (patch.visualEnabled != null) 'visualEnabled': patch.visualEnabled,
      if (patch.whatsappEnabled != null)
        'whatsappEnabled': patch.whatsappEnabled,
      if (patch.whatsappDelay != null)
        'whatsappDelayMinutes': patch.whatsappDelay!.inMinutes,
      if (_thresholdsMap(patch.thresholds).isNotEmpty)
        'thresholds': _thresholdsMap(patch.thresholds),
      if (patch.cooldown != null) 'cooldownMinutes': patch.cooldown!.inMinutes,
      if (patch.order != null) 'order': patch.order,
      if (createdAt != null) 'createdAt': createdAt!.toUtc(),
      if (createdBy != null) 'createdBy': createdBy,
      'updatedAt': updatedAt?.toUtc(),
      'updatedBy': updatedBy,
    };
  }

  void validate() {
    if (!AlertDefinitionCatalog.definitions.any(
      (AlertDefinition definition) => definition.id == alertId,
    )) {
      throw AlertConfigDocumentException('Unknown alertId: $alertId');
    }
    if (schemaVersion != 1) {
      throw AlertConfigDocumentException(
        'Unsupported alertConfig schemaVersion: $schemaVersion',
      );
    }
    if (!patch.hasAnyValue) {
      throw const AlertConfigDocumentException(
        'AlertConfig document must contain at least one functional override',
      );
    }
    if (updatedAt == null) {
      throw const AlertConfigDocumentException('updatedAt is required');
    }
    if (updatedBy.trim().isEmpty) {
      throw const AlertConfigDocumentException('updatedBy is required');
    }
    if (patch.whatsappDelay != null && patch.whatsappDelay!.isNegative) {
      throw const AlertConfigDocumentException(
        'whatsappDelayMinutes must be >= 0',
      );
    }
    if (patch.cooldown != null && patch.cooldown!.isNegative) {
      throw const AlertConfigDocumentException('cooldownMinutes must be >= 0');
    }
    if (patch.order != null && patch.order! < 0) {
      throw const AlertConfigDocumentException('order must be >= 0');
    }
  }
}

class HierarchicalAlertConfigSnapshot {
  const HierarchicalAlertConfigSnapshot({
    this.tenant = const <String, AlertConfigPatch>{},
    this.site = const <String, AlertConfigPatch>{},
    this.device = const <String, AlertConfigPatch>{},
    this.room = const <String, AlertConfigPatch>{},
    this.readCount = 0,
  });

  final Map<String, AlertConfigPatch> tenant;
  final Map<String, AlertConfigPatch> site;
  final Map<String, AlertConfigPatch> device;
  final Map<String, AlertConfigPatch> room;
  final int readCount;

  bool hasModernConfigFor(String alertId) =>
      tenant.containsKey(alertId) ||
      site.containsKey(alertId) ||
      device.containsKey(alertId) ||
      room.containsKey(alertId);

  Iterable<AlertConfigPatch> patchesFor(String alertId) sync* {
    final AlertConfigPatch? tenantPatch = tenant[alertId];
    final AlertConfigPatch? sitePatch = site[alertId];
    final AlertConfigPatch? devicePatch = device[alertId];
    final AlertConfigPatch? roomPatch = room[alertId];
    if (tenantPatch != null) yield tenantPatch;
    if (sitePatch != null) yield sitePatch;
    if (devicePatch != null) yield devicePatch;
    if (roomPatch != null) yield roomPatch;
  }
}

class HierarchicalAlertConfigResolver {
  const HierarchicalAlertConfigResolver({
    this.runtimeConfig = const AlertRuntimeConfig(),
    this.legacyAdapter = const LegacyAlertSettingsAdapter(),
  });

  final AlertRuntimeConfig runtimeConfig;
  final LegacyAlertSettingsAdapter legacyAdapter;

  EffectiveAlertConfiguration resolve({
    required AlertConfigurationTarget target,
    required HierarchicalAlertConfigSnapshot modern,
    CachedAlertSettings? legacy,
    int configVersion = 0,
  }) {
    final EffectiveAlertConfiguration? legacyEffective = legacy == null
        ? null
        : legacyAdapter.fromCachedSettings(settings: legacy, target: target);
    final List<EffectiveAlertConfig> alerts = <EffectiveAlertConfig>[];
    for (final AlertDefinition definition
        in AlertDefinitionCatalog.definitions) {
      if (!modern.hasModernConfigFor(definition.id)) {
        if (legacyEffective != null) {
          alerts.add(legacyEffective.configFor(definition.type));
        } else {
          alerts.add(_catalogDefault(definition, target));
        }
        continue;
      }
      alerts.add(
        _resolveModern(definition, target, modern.patchesFor(definition.id)),
      );
    }
    final bool hasModern = alerts.any(
      (EffectiveAlertConfig alert) => alert.origin != AlertConfigOrigin.legacy,
    );
    return EffectiveAlertConfiguration(
      tenantId: target.tenantId,
      siteId: target.siteId,
      target: target,
      alerts: List<EffectiveAlertConfig>.unmodifiable(alerts),
      origin: hasModern
          ? AlertConfigOrigin.catalogDefault
          : AlertConfigOrigin.legacy,
      configVersion: legacy?.configVersion ?? configVersion,
    );
  }

  EffectiveAlertConfig _resolveModern(
    AlertDefinition definition,
    AlertConfigurationTarget target,
    Iterable<AlertConfigPatch> patches,
  ) {
    bool enabled = true;
    bool visualEnabled = definition.supportsVisual;
    bool whatsappEnabled = false;
    Duration whatsappDelay = Duration.zero;
    Duration cooldown = runtimeConfig.cooldownFor(definition.type);
    int order = AlertMetadataRegistry.metadataFor(definition.type).order;
    AlertThresholdConfig thresholds = const AlertThresholdConfig();
    AlertConfigOrigin origin = AlertConfigOrigin.catalogDefault;
    final Map<String, AlertConfigOrigin> fieldOrigins =
        <String, AlertConfigOrigin>{
          'enabled': AlertConfigOrigin.catalogDefault,
          'visualEnabled': AlertConfigOrigin.catalogDefault,
          'whatsappEnabled': AlertConfigOrigin.catalogDefault,
          'whatsappDelay': AlertConfigOrigin.catalogDefault,
          'cooldown': AlertConfigOrigin.catalogDefault,
          'order': AlertConfigOrigin.catalogDefault,
          'thresholds.min': AlertConfigOrigin.catalogDefault,
          'thresholds.max': AlertConfigOrigin.catalogDefault,
          'thresholds.threshold': AlertConfigOrigin.catalogDefault,
          'thresholds.margin': AlertConfigOrigin.catalogDefault,
          'thresholds.sensorFailureMin': AlertConfigOrigin.catalogDefault,
        };

    for (final AlertConfigPatch patch in patches) {
      if (patch.enabled != null) {
        enabled = patch.enabled!;
        fieldOrigins['enabled'] = patch.origin;
        origin = patch.origin;
      }
      if (patch.visualEnabled != null) {
        visualEnabled = patch.visualEnabled!;
        fieldOrigins['visualEnabled'] = patch.origin;
        origin = patch.origin;
      }
      if (patch.whatsappEnabled != null) {
        whatsappEnabled = patch.whatsappEnabled!;
        fieldOrigins['whatsappEnabled'] = patch.origin;
        origin = patch.origin;
      }
      if (patch.whatsappDelay != null) {
        whatsappDelay = patch.whatsappDelay!;
        fieldOrigins['whatsappDelay'] = patch.origin;
        origin = patch.origin;
      }
      if (patch.cooldown != null) {
        cooldown = patch.cooldown!;
        fieldOrigins['cooldown'] = patch.origin;
        origin = patch.origin;
      }
      if (patch.order != null) {
        order = patch.order!;
        fieldOrigins['order'] = patch.origin;
        origin = patch.origin;
      }
      thresholds = _mergeThresholds(
        parent: thresholds,
        child: patch.thresholds,
        origin: patch.origin,
        fieldOrigins: fieldOrigins,
      );
    }

    return EffectiveAlertConfig(
      alertId: definition.id,
      type: definition.type,
      enabled: enabled,
      visualEnabled: enabled && definition.supportsVisual && visualEnabled,
      whatsappEnabled:
          enabled && definition.supportsWhatsapp && whatsappEnabled,
      whatsappDelay: definition.supportsWhatsappDelay
          ? whatsappDelay
          : Duration.zero,
      thresholds: thresholds,
      cooldown: cooldown,
      order: order,
      target: target,
      metricBindings: <String, String>{
        for (final AlertMetricBinding binding in definition.metricBindings)
          binding.role: binding.metricKey,
      },
      origin: origin,
      usesRoomWashSuppression: definition.usesRoomWashSuppression,
      fieldOrigins: Map<String, AlertConfigOrigin>.unmodifiable(fieldOrigins),
    );
  }

  EffectiveAlertConfig _catalogDefault(
    AlertDefinition definition,
    AlertConfigurationTarget target,
  ) {
    return EffectiveAlertConfig(
      alertId: definition.id,
      type: definition.type,
      enabled: true,
      visualEnabled: definition.supportsVisual,
      whatsappEnabled: false,
      whatsappDelay: Duration.zero,
      thresholds: const AlertThresholdConfig(),
      cooldown: runtimeConfig.cooldownFor(definition.type),
      order: AlertMetadataRegistry.metadataFor(definition.type).order,
      target: target,
      metricBindings: <String, String>{
        for (final AlertMetricBinding binding in definition.metricBindings)
          binding.role: binding.metricKey,
      },
      origin: AlertConfigOrigin.catalogDefault,
      usesRoomWashSuppression: definition.usesRoomWashSuppression,
    );
  }
}

AlertThresholdConfig _mergeThresholds({
  required AlertThresholdConfig parent,
  required AlertThresholdConfig child,
  required AlertConfigOrigin origin,
  required Map<String, AlertConfigOrigin> fieldOrigins,
}) {
  if (child.min != null) fieldOrigins['thresholds.min'] = origin;
  if (child.max != null) fieldOrigins['thresholds.max'] = origin;
  if (child.threshold != null) fieldOrigins['thresholds.threshold'] = origin;
  if (child.margin != null) fieldOrigins['thresholds.margin'] = origin;
  if (child.sensorFailureMin != null) {
    fieldOrigins['thresholds.sensorFailureMin'] = origin;
  }
  return AlertThresholdConfig(
    min: child.min ?? parent.min,
    max: child.max ?? parent.max,
    threshold: child.threshold ?? parent.threshold,
    margin: child.margin ?? parent.margin,
    sensorFailureMin: child.sensorFailureMin ?? parent.sensorFailureMin,
  );
}

abstract class HierarchicalAlertConfigLoader {
  Future<HierarchicalAlertConfigSnapshot> load(AlertConfigurationTarget target);
}

class FirestoreHierarchicalAlertConfigLoader
    implements HierarchicalAlertConfigLoader {
  FirestoreHierarchicalAlertConfigLoader({
    required String projectId,
    required String databaseId,
    required String serviceAccountJsonPath,
    HttpClient? httpClient,
    String? baseUrl,
    Future<String> Function()? accessTokenProvider,
  }) : _projectId = projectId,
       _databaseId = databaseId,
       _auth = ServiceAccountAuth(
         serviceAccountJsonPath: serviceAccountJsonPath,
       ),
       _httpClient = httpClient ?? HttpClient(),
       _baseUrl = baseUrl ?? 'https://firestore.googleapis.com',
       _accessTokenProvider = accessTokenProvider;

  final String _projectId;
  final String _databaseId;
  final ServiceAccountAuth _auth;
  final HttpClient _httpClient;
  final String _baseUrl;
  final Future<String> Function()? _accessTokenProvider;

  // Operation-scoped memoization only. This avoids repeating shared
  // Tenant/Site reads while one cache refresh is in progress, but callers must
  // clear it before starting an independent load so it never behaves like a
  // persistent runtime cache.
  final Map<String, Future<_ListedAlertConfig>> _memoizedCollections =
      <String, Future<_ListedAlertConfig>>{};

  bool get isConfigured =>
      _projectId.trim().isNotEmpty &&
      _databaseId.trim().isNotEmpty &&
      (_accessTokenProvider != null ||
          _auth.serviceAccountJsonPath.trim().isNotEmpty);

  void clearMemoizedCollectionCache() {
    _memoizedCollections.clear();
  }

  @override
  Future<HierarchicalAlertConfigSnapshot> load(
    AlertConfigurationTarget target,
  ) async {
    if (!isConfigured) {
      throw const HierarchicalAlertConfigLoaderException(
        'Firestore hierarchical alert config loader is not configured',
      );
    }
    final String token = await (_accessTokenProvider ?? _auth.getAccessToken)();
    int readCount = 0;
    final _ListedAlertConfig tenantResult = await _listAlertConfig(
      token: token,
      collectionPath: 'tenants/${target.tenantId}/alertConfig',
      origin: AlertConfigOrigin.tenant,
    );
    final Map<String, AlertConfigPatch> tenant = tenantResult.configs;
    readCount += tenantResult.readCount;
    final _ListedAlertConfig siteResult = await _listAlertConfig(
      token: token,
      collectionPath:
          'tenants/${target.tenantId}/sites/${target.siteId}/alertConfig',
      origin: AlertConfigOrigin.site,
      allowMissing: true,
    );
    final Map<String, AlertConfigPatch> site = siteResult.configs;
    readCount += siteResult.readCount;
    Map<String, AlertConfigPatch> device = const <String, AlertConfigPatch>{};
    final String? deviceId = target.deviceId;
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      final _ListedAlertConfig deviceResult = await _listAlertConfig(
        token: token,
        collectionPath:
            'tenants/${target.tenantId}/devices/$deviceId/alertConfig',
        origin: AlertConfigOrigin.device,
        allowMissing: true,
      );
      device = deviceResult.configs;
      readCount += deviceResult.readCount;
    }
    Map<String, AlertConfigPatch> room = const <String, AlertConfigPatch>{};
    final String? roomId = target.roomId;
    if (deviceId != null &&
        deviceId.trim().isNotEmpty &&
        roomId != null &&
        roomId.trim().isNotEmpty) {
      final _ListedAlertConfig roomResult = await _listAlertConfig(
        token: token,
        collectionPath:
            'tenants/${target.tenantId}/devices/$deviceId/rooms/$roomId/alertConfig',
        origin: AlertConfigOrigin.room,
        allowMissing: true,
      );
      room = roomResult.configs;
      readCount += roomResult.readCount;
    }
    return HierarchicalAlertConfigSnapshot(
      tenant: tenant,
      site: site,
      device: device,
      room: room,
      readCount: readCount,
    );
  }

  Future<_ListedAlertConfig> _listAlertConfig({
    required String token,
    required String collectionPath,
    required AlertConfigOrigin origin,
    bool allowMissing = false,
  }) async {
    final String cacheKey = '$origin|$collectionPath';
    final Future<_ListedAlertConfig>? memoized = _memoizedCollections[cacheKey];
    if (memoized != null) {
      final _ListedAlertConfig result = await memoized;
      return _ListedAlertConfig(configs: result.configs, readCount: 0);
    }
    final Future<_ListedAlertConfig> future = _listAlertConfigUncached(
      token: token,
      collectionPath: collectionPath,
      origin: origin,
      allowMissing: allowMissing,
    );
    _memoizedCollections[cacheKey] = future;
    return future;
  }

  Future<_ListedAlertConfig> _listAlertConfigUncached({
    required String token,
    required String collectionPath,
    required AlertConfigOrigin origin,
    required bool allowMissing,
  }) async {
    final Uri uri = _documentUri(collectionPath);
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    if (token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound && allowMissing) {
      return const _ListedAlertConfig(
        configs: <String, AlertConfigPatch>{},
        readCount: 1,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HierarchicalAlertConfigLoaderException(
        'Firestore alertConfig LIST failed status=${response.statusCode} path=$collectionPath body=${_compact(body)}',
      );
    }
    final Map<String, dynamic> payload =
        jsonDecode(body) as Map<String, dynamic>;
    final Object? documentsRaw = payload['documents'];
    if (documentsRaw is! List) {
      return const _ListedAlertConfig(
        configs: <String, AlertConfigPatch>{},
        readCount: 1,
      );
    }
    return _ListedAlertConfig(
      configs: <String, AlertConfigPatch>{
        for (final Map<String, dynamic> document
            in documentsRaw.whereType<Map<String, dynamic>>())
          _docId(document): AlertConfigFirestoreDocument.fromRaw(
            alertId: _docId(document),
            origin: origin,
            raw: _decodeFields(document),
          ).patch,
      },
      readCount: 1,
    );
  }

  Uri _documentUri(String documentPath) {
    return Uri.parse(
      '$_baseUrl/v1/projects/$_projectId'
      '/databases/$_databaseId/documents/$documentPath',
    );
  }
}

class HierarchicalAlertSettingsCache {
  HierarchicalAlertSettingsCache({
    required this.loader,
    this.resolver = const HierarchicalAlertConfigResolver(),
    this.ttl = const Duration(hours: 6),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final HierarchicalAlertConfigLoader loader;
  final HierarchicalAlertConfigResolver resolver;
  final Duration ttl;
  final DateTime Function() _now;
  final Map<HierarchicalAlertSettingsCacheKey, EffectiveAlertConfiguration>
  _cache = <HierarchicalAlertSettingsCacheKey, EffectiveAlertConfiguration>{};
  final Map<HierarchicalAlertSettingsCacheKey, DateTime> _loadedAt =
      <HierarchicalAlertSettingsCacheKey, DateTime>{};
  final Map<
    HierarchicalAlertSettingsCacheKey,
    Future<EffectiveAlertConfiguration>
  >
  _inFlight =
      <
        HierarchicalAlertSettingsCacheKey,
        Future<EffectiveAlertConfiguration>
      >{};
  Object? _lastError;
  DateTime? _lastRefreshAt;
  int _lastReadCount = 0;
  int _legacyFallbackAlerts = 0;
  int _modernAlerts = 0;

  int get size => _cache.length;

  int get lastReadCount => _lastReadCount;

  Object? get lastError => _lastError;

  EffectiveAlertConfiguration? get(AlertConfigurationTarget target) {
    return _cache[HierarchicalAlertSettingsCacheKey.fromTarget(target)];
  }

  Future<EffectiveAlertConfiguration> getOrLoad({
    required AlertConfigurationTarget target,
    CachedAlertSettings? legacy,
    int configVersion = 0,
  }) async {
    final HierarchicalAlertSettingsCacheKey key =
        HierarchicalAlertSettingsCacheKey.fromTarget(target);
    final EffectiveAlertConfiguration? cached = _cache[key];
    final DateTime? loadedAt = _loadedAt[key];
    if (cached != null &&
        loadedAt != null &&
        _now().toUtc().difference(loadedAt) < ttl) {
      _lastReadCount = 0;
      return cached;
    }
    final Future<EffectiveAlertConfiguration>? inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    _clearLoaderOperationMemoizationIfNeeded();
    final Future<EffectiveAlertConfiguration> future = _loadOne(
      target: target,
      legacy: legacy,
      configVersion: configVersion,
    );
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> refreshTargets({
    required Iterable<OperationalAlertTarget> targets,
    CachedAlertSettings? legacy,
    int configVersion = 0,
  }) async {
    _clearLoaderOperationMemoizationIfNeeded();
    int loaded = 0;
    int reads = 0;
    int modern = 0;
    int legacyFallback = 0;
    try {
      for (final OperationalAlertTarget operationalTarget in targets) {
        final EffectiveAlertConfiguration effective = await _loadOne(
          target: operationalTarget.toAlertConfigurationTarget(),
          legacy: legacy,
          configVersion: configVersion,
        );
        loaded += 1;
        reads += _lastReadCount;
        modern += effective.alerts
            .where(
              (EffectiveAlertConfig alert) =>
                  alert.origin != AlertConfigOrigin.legacy,
            )
            .length;
        legacyFallback += effective.alerts
            .where(
              (EffectiveAlertConfig alert) =>
                  alert.origin == AlertConfigOrigin.legacy,
            )
            .length;
      }
      _lastReadCount = reads;
      _modernAlerts = modern;
      _legacyFallbackAlerts = legacyFallback;
      _lastError = null;
      _lastRefreshAt = _now().toUtc();
      _logHierarchicalSettings(
        'refresh loadedTargets=$loaded reads=$reads modernAlerts=$modern legacyFallbackAlerts=$legacyFallback',
      );
    } catch (error) {
      _lastError = error;
      _lastRefreshAt = _now().toUtc();
      _logHierarchicalSettings('refresh failed error=$error');
      rethrow;
    }
  }

  Map<String, Object?> healthJson() {
    return <String, Object?>{
      'targets': _cache.length,
      'loaded': _cache.length,
      'sourceSummary': <String, Object?>{
        'modernAlerts': _modernAlerts,
        'legacyFallbackAlerts': _legacyFallbackAlerts,
      },
      'lastRefreshAt': _lastRefreshAt?.toUtc().toIso8601String(),
      'lastError': _lastError?.toString(),
      'lastReadCount': _lastReadCount,
    };
  }

  Future<EffectiveAlertConfiguration> _loadOne({
    required AlertConfigurationTarget target,
    CachedAlertSettings? legacy,
    required int configVersion,
  }) async {
    final HierarchicalAlertConfigSnapshot snapshot = await loader.load(target);
    final EffectiveAlertConfiguration effective = resolver.resolve(
      target: target,
      modern: snapshot,
      legacy: legacy,
      configVersion: configVersion,
    );
    final HierarchicalAlertSettingsCacheKey key =
        HierarchicalAlertSettingsCacheKey.fromTarget(target);
    _cache[key] = effective;
    _loadedAt[key] = _now().toUtc();
    _lastReadCount = snapshot.readCount;
    _lastRefreshAt = _now().toUtc();
    _lastError = null;
    _modernAlerts = effective.alerts
        .where(
          (EffectiveAlertConfig alert) =>
              alert.origin != AlertConfigOrigin.legacy,
        )
        .length;
    _legacyFallbackAlerts = effective.alerts.length - _modernAlerts;
    return effective;
  }

  void _clearLoaderOperationMemoizationIfNeeded() {
    if (loader
        case final FirestoreHierarchicalAlertConfigLoader firestoreLoader) {
      firestoreLoader.clearMemoizedCollectionCache();
    }
  }
}

class _ListedAlertConfig {
  const _ListedAlertConfig({required this.configs, required this.readCount});

  final Map<String, AlertConfigPatch> configs;
  final int readCount;
}

class HierarchicalAlertSettingsCacheKey {
  const HierarchicalAlertSettingsCacheKey({
    required this.tenantId,
    required this.siteId,
    required this.deviceId,
    required this.roomId,
  });

  factory HierarchicalAlertSettingsCacheKey.fromTarget(
    AlertConfigurationTarget target,
  ) {
    return HierarchicalAlertSettingsCacheKey(
      tenantId: target.tenantId,
      siteId: target.siteId,
      deviceId: target.deviceId ?? '',
      roomId: target.roomId ?? '',
    );
  }

  final String tenantId;
  final String siteId;
  final String deviceId;
  final String roomId;

  @override
  bool operator ==(Object other) {
    return other is HierarchicalAlertSettingsCacheKey &&
        other.tenantId == tenantId &&
        other.siteId == siteId &&
        other.deviceId == deviceId &&
        other.roomId == roomId;
  }

  @override
  int get hashCode => Object.hash(tenantId, siteId, deviceId, roomId);
}

bool? _readOptionalBool(Map<String, Object?> raw, String key) {
  if (!raw.containsKey(key)) return null;
  final Object? value = raw[key];
  if (value is bool) return value;
  return null;
}

Duration? _readOptionalDurationMinutes(Map<String, Object?> raw, String key) {
  if (!raw.containsKey(key)) return null;
  final int? minutes = _readOptionalNonNegativeInt(raw[key]);
  return minutes == null ? null : Duration(minutes: minutes);
}

int? _readOptionalNonNegativeInt(Object? raw) {
  if (raw is int && raw >= 0) return raw;
  if (raw is num && raw.isFinite && raw >= 0) return raw.toInt();
  if (raw is String) {
    final int? parsed = int.tryParse(raw.trim());
    if (parsed != null && parsed >= 0) return parsed;
  }
  return null;
}

int? _readOptionalPositiveInt(Object? raw) {
  final int? value = _readOptionalNonNegativeInt(raw);
  if (value != null && value > 0) return value;
  return null;
}

AlertThresholdConfig _readThresholds(Object? raw) {
  if (raw is! Map) return const AlertThresholdConfig();
  final Map<Object?, Object?> data = raw;
  return AlertThresholdConfig(
    min: _readOptionalDouble(data['min']),
    max: _readOptionalDouble(data['max']),
    threshold: _readOptionalDouble(data['threshold']),
    margin: _readOptionalDouble(data['margin']),
    sensorFailureMin: _readOptionalDouble(data['sensorFailureMin']),
  );
}

double? _readOptionalDouble(Object? raw) {
  if (raw is num && raw.isFinite) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim());
  return null;
}

DateTime? _readOptionalDateTime(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

Map<String, Object?> _thresholdsMap(AlertThresholdConfig thresholds) {
  return <String, Object?>{
    if (thresholds.min != null) 'min': thresholds.min,
    if (thresholds.max != null) 'max': thresholds.max,
    if (thresholds.threshold != null) 'threshold': thresholds.threshold,
    if (thresholds.margin != null) 'margin': thresholds.margin,
    if (thresholds.sensorFailureMin != null)
      'sensorFailureMin': thresholds.sensorFailureMin,
  };
}

String _docId(Map<String, dynamic> document) =>
    (document['name']?.toString() ?? '').split('/').last;

Map<String, Object?> _decodeFields(Map<String, dynamic> document) {
  final Map<String, dynamic> fields =
      document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
  return fields.map(
    (String key, dynamic value) => MapEntry(key, _decodeFirestoreValue(value)),
  );
}

Object? _decodeFirestoreValue(Object? value) {
  if (value is! Map) return null;
  final Map<Object?, Object?> field = value;
  if (field.containsKey('nullValue')) return null;
  if (field.containsKey('stringValue')) return field['stringValue']?.toString();
  if (field.containsKey('booleanValue')) return field['booleanValue'] == true;
  if (field.containsKey('integerValue')) {
    return int.tryParse(field['integerValue'].toString());
  }
  if (field.containsKey('doubleValue')) {
    return double.tryParse(field['doubleValue'].toString());
  }
  if (field.containsKey('timestampValue')) {
    return field['timestampValue']?.toString();
  }
  if (field['mapValue'] is Map) {
    final Object? rawFields = (field['mapValue'] as Map)['fields'];
    if (rawFields is Map) {
      return rawFields.map(
        (Object? key, Object? nestedValue) =>
            MapEntry(key.toString(), _decodeFirestoreValue(nestedValue)),
      );
    }
    return const <String, Object?>{};
  }
  if (field['arrayValue'] is Map) {
    final Object? values = (field['arrayValue'] as Map)['values'];
    if (values is List) {
      return values.map(_decodeFirestoreValue).toList(growable: false);
    }
    return const <Object?>[];
  }
  return null;
}

String _compact(Object value) {
  final String compacted = value
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compacted.length <= 240) return compacted;
  return '${compacted.substring(0, 240)}...';
}

void _logHierarchicalSettings(String message) {
  stdout.writeln('[hierarchical-alert-settings] $message');
}

class HierarchicalAlertConfigLoaderException implements Exception {
  const HierarchicalAlertConfigLoaderException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AlertConfigDocumentException implements Exception {
  const AlertConfigDocumentException(this.message);

  final String message;

  @override
  String toString() => message;
}
