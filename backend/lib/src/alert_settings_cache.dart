import 'dart:async';
import 'dart:io';

import 'alert_priority.dart';

class AlertSettingsCache {
  AlertSettingsCache({AlertSettingsLoader? loader}) : _loader = loader;

  final AlertSettingsLoader? _loader;
  final Map<AlertSettingsCacheKey, CachedAlertSettings> _cache =
      <AlertSettingsCacheKey, CachedAlertSettings>{};
  final Map<AlertSettingsCacheKey, Future<CachedAlertSettings?>>
  _inFlightLoads = <AlertSettingsCacheKey, Future<CachedAlertSettings?>>{};
  final Map<AlertSettingsCacheKey, AlertSettingsLoadFailureState> _failures =
      <AlertSettingsCacheKey, AlertSettingsLoadFailureState>{};
  int loadCount = 0;

  int get count => _cache.length;

  int get size => _cache.length;

  int get failureCount => _failures.length;

  int get backoffEntryCount {
    final DateTime now = DateTime.now().toUtc();
    return _failures.values
        .where(
          (AlertSettingsLoadFailureState failure) =>
              failure.nextRetryAt.isAfter(now),
        )
        .length;
  }

  bool contains({required String tenantId, required String siteId}) {
    return _cache.containsKey(
      AlertSettingsCacheKey(tenantId: tenantId, siteId: siteId),
    );
  }

  CachedAlertSettings? get({required String tenantId, required String siteId}) {
    return _cache[AlertSettingsCacheKey(tenantId: tenantId, siteId: siteId)];
  }

  Future<CachedAlertSettings?> getOrLoad({
    required String tenantId,
    required String siteId,
    DateTime? now,
  }) async {
    final AlertSettingsCacheKey key = AlertSettingsCacheKey(
      tenantId: tenantId,
      siteId: siteId,
    );
    final CachedAlertSettings? cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    final DateTime effectiveNow = now ?? DateTime.now().toUtc();
    final AlertSettingsLoadFailureState? failure = _failures[key];
    if (failure != null && failure.nextRetryAt.isAfter(effectiveNow)) {
      throw AlertSettingsLoadBackoffException(
        tenantId: tenantId,
        siteId: siteId,
        retryAfter: failure.nextRetryAt,
        consecutiveFailures: failure.consecutiveFailures,
      );
    }
    final Future<CachedAlertSettings?>? inFlight = _inFlightLoads[key];
    if (inFlight != null) {
      return inFlight;
    }
    final AlertSettingsLoader? loader = _loader;
    if (loader == null) {
      return null;
    }
    final Future<CachedAlertSettings?> loadFuture = _loadAndCache(
      key: key,
      loader: loader,
      tenantId: tenantId,
      siteId: siteId,
      now: now,
    );
    _inFlightLoads[key] = loadFuture;
    try {
      return await loadFuture;
    } finally {
      _inFlightLoads.remove(key);
    }
  }

  CachedAlertSettings updateFromPayload({
    required String tenantId,
    required String siteId,
    required Map<String, Object?> payload,
    DateTime? now,
    String source = 'frontendPush',
  }) {
    if (!_looksLikeAlertSettingsPayload(payload)) {
      throw const FormatException('Invalid alert settings payload');
    }
    final CachedAlertSettings parsed = CachedAlertSettings.fromRaw(
      tenantId: tenantId,
      siteId: siteId,
      raw: payload,
      loadedAt: now ?? DateTime.now().toUtc(),
      source: source,
    );
    final AlertSettingsCacheKey key = AlertSettingsCacheKey(
      tenantId: tenantId,
      siteId: siteId,
    );
    _cache[key] = parsed;
    _failures.remove(key);
    _inFlightLoads.remove(key);
    return parsed;
  }

  void clearAll() {
    _cache.clear();
    _inFlightLoads.clear();
    _failures.clear();
  }

  Future<CachedAlertSettings?> _loadAndCache({
    required AlertSettingsCacheKey key,
    required AlertSettingsLoader loader,
    required String tenantId,
    required String siteId,
    DateTime? now,
  }) async {
    loadCount += 1;
    try {
      final Map<String, Object?>? raw = await loader.load(tenantId, siteId);
      if (raw == null) {
        return null;
      }
      final CachedAlertSettings parsed = CachedAlertSettings.fromRaw(
        tenantId: tenantId,
        siteId: siteId,
        raw: raw,
        loadedAt: now ?? DateTime.now().toUtc(),
        source: 'firestore',
      );
      _cache[key] = parsed;
      final AlertSettingsLoadFailureState? previousFailure = _failures.remove(
        key,
      );
      if (previousFailure != null) {
        _logSettingsCache(
          'settings load recovered tenant=$tenantId site=$siteId previousFailures=${previousFailure.consecutiveFailures}',
        );
      }
      return parsed;
    } catch (error) {
      final DateTime failedAt = now ?? DateTime.now().toUtc();
      final AlertSettingsLoadFailureState? previous = _failures[key];
      final int consecutiveFailures = (previous?.consecutiveFailures ?? 0) + 1;
      final Duration retryDelay = alertSettingsRetryDelay(consecutiveFailures);
      final AlertSettingsLoadFailureState failure =
          AlertSettingsLoadFailureState(
            failedAt: failedAt,
            consecutiveFailures: consecutiveFailures,
            retryAfter: failedAt.add(retryDelay),
            errorType: error.runtimeType.toString(),
          );
      _failures[key] = failure;
      _logSettingsCache(
        'settings load failed tenant=$tenantId site=$siteId consecutiveFailures=$consecutiveFailures retryAfter=${failure.nextRetryAt.toIso8601String()} errorType=${failure.errorType}',
      );
      rethrow;
    }
  }
}

Duration alertSettingsRetryDelay(int consecutiveFailures) {
  final int exponent = consecutiveFailures <= 1 ? 0 : consecutiveFailures - 1;
  final int multiplier = 1 << exponent.clamp(0, 8);
  final int seconds = 30 * multiplier;
  return Duration(seconds: seconds > 300 ? 300 : seconds);
}

class AlertSettingsLoadFailureState {
  const AlertSettingsLoadFailureState({
    required this.failedAt,
    required this.consecutiveFailures,
    required this.retryAfter,
    required this.errorType,
  });

  final DateTime failedAt;
  final int consecutiveFailures;
  final DateTime retryAfter;
  final String errorType;

  DateTime get nextRetryAt => retryAfter;
}

class AlertSettingsLoadBackoffException implements Exception {
  const AlertSettingsLoadBackoffException({
    required this.tenantId,
    required this.siteId,
    required this.retryAfter,
    required this.consecutiveFailures,
  });

  final String tenantId;
  final String siteId;
  final DateTime retryAfter;
  final int consecutiveFailures;

  @override
  String toString() =>
      'Alert settings load is in backoff tenant=$tenantId site=$siteId retryAfter=${retryAfter.toIso8601String()} consecutiveFailures=$consecutiveFailures';
}

void _logSettingsCache(String message) {
  stdout.writeln('[alert-settings-cache] $message');
}

bool _looksLikeAlertSettingsPayload(Map<String, Object?> payload) {
  return payload['alerts'] is Map || payload['munters'] is Map;
}

abstract class AlertSettingsLoader {
  Future<Map<String, Object?>?> load(String tenantId, String siteId);
}

class AlertSettingsCacheKey {
  const AlertSettingsCacheKey({required this.tenantId, required this.siteId});

  final String tenantId;
  final String siteId;

  @override
  bool operator ==(Object other) {
    return other is AlertSettingsCacheKey &&
        other.tenantId == tenantId &&
        other.siteId == siteId;
  }

  @override
  int get hashCode => Object.hash(tenantId, siteId);
}

class CachedAlertSettings {
  const CachedAlertSettings({
    required this.tenantId,
    required this.siteId,
    required this.alerts,
    required this.thresholds,
    required this.loadedAt,
    required this.source,
    this.updatedAt,
  });

  factory CachedAlertSettings.fromRaw({
    required String tenantId,
    required String siteId,
    required Map<String, Object?> raw,
    required DateTime loadedAt,
    required String source,
  }) {
    return CachedAlertSettings(
      tenantId: tenantId,
      siteId: siteId,
      alerts: CachedAlertToggles.fromRaw(raw['alerts']),
      thresholds: CachedAlertThresholds.fromRaw(raw),
      loadedAt: loadedAt,
      updatedAt: _readDateTime(raw['updatedAt']),
      source: source,
    );
  }

  final String tenantId;
  final String siteId;
  final CachedAlertToggles alerts;
  final CachedAlertThresholds thresholds;
  final DateTime loadedAt;
  final DateTime? updatedAt;
  final String source;
}

class CachedAlertToggles {
  const CachedAlertToggles({
    required this.muntersDoorOpen,
    required this.roomDoorOpen,
    required this.highTemperatureHeatingActive,
    required this.lowTemperatureHumidifierActive,
    required this.highDifferentialPressure,
    required this.highHumidity,
    required this.dewPointRisk,
  });

  factory CachedAlertToggles.fromRaw(Object? raw) {
    final Map<String, Object?> source = raw is Map
        ? Map<String, Object?>.from(raw as Map<Object?, Object?>)
        : <String, Object?>{};
    final Map<AlertType, CachedAlertToggle> normalized =
        _normalizeOrders(<AlertType, CachedAlertToggle>{
          AlertType.muntersDoorOpen: CachedAlertToggle.fromRaw(
            source['muntersDoorOpen'],
            defaultOrder:
                AlertMetadataRegistry.priorityIndex(AlertType.muntersDoorOpen) +
                1,
          ),
          AlertType.roomDoorOpen: CachedAlertToggle.fromRaw(
            source['roomDoorOpen'],
            defaultOrder:
                AlertMetadataRegistry.priorityIndex(AlertType.roomDoorOpen) + 1,
          ),
          AlertType.highTemperatureHeatingActive: CachedAlertToggle.fromRaw(
            source['highTemperatureHeatingActive'] ??
                source['lowTemperatureHeatingActive'],
            defaultOrder:
                AlertMetadataRegistry.priorityIndex(
                  AlertType.highTemperatureHeatingActive,
                ) +
                1,
          ),
          AlertType.lowTemperatureHumidifierActive: CachedAlertToggle.fromRaw(
            source['lowTemperatureHumidifierActive'] ??
                source['highTemperatureHumidifierActive'],
            defaultOrder:
                AlertMetadataRegistry.priorityIndex(
                  AlertType.lowTemperatureHumidifierActive,
                ) +
                1,
          ),
          AlertType.highDifferentialPressure: CachedAlertToggle.fromRaw(
            source['highDifferentialPressure'],
            defaultOrder:
                AlertMetadataRegistry.priorityIndex(
                  AlertType.highDifferentialPressure,
                ) +
                1,
          ),
          AlertType.highHumidity: CachedAlertToggle.fromRaw(
            source['highHumidity'],
            defaultOrder:
                AlertMetadataRegistry.priorityIndex(AlertType.highHumidity) + 1,
          ),
          AlertType.dewPointRisk: CachedAlertToggle.fromRaw(
            source['dewPointRisk'],
            defaultOrder:
                AlertMetadataRegistry.priorityIndex(AlertType.dewPointRisk) + 1,
          ),
        });
    return CachedAlertToggles(
      muntersDoorOpen: normalized[AlertType.muntersDoorOpen]!,
      roomDoorOpen: normalized[AlertType.roomDoorOpen]!,
      highTemperatureHeatingActive:
          normalized[AlertType.highTemperatureHeatingActive]!,
      lowTemperatureHumidifierActive:
          normalized[AlertType.lowTemperatureHumidifierActive]!,
      highDifferentialPressure: normalized[AlertType.highDifferentialPressure]!,
      highHumidity: normalized[AlertType.highHumidity]!,
      dewPointRisk: normalized[AlertType.dewPointRisk]!,
    );
  }

  final CachedAlertToggle muntersDoorOpen;
  final CachedAlertToggle roomDoorOpen;
  final CachedAlertToggle highTemperatureHeatingActive;
  final CachedAlertToggle lowTemperatureHumidifierActive;
  final CachedAlertToggle highDifferentialPressure;
  final CachedAlertToggle highHumidity;
  final CachedAlertToggle dewPointRisk;

  CachedAlertToggle toggleFor(AlertType type) {
    return switch (type) {
      AlertType.muntersDoorOpen => muntersDoorOpen,
      AlertType.roomDoorOpen => roomDoorOpen,
      AlertType.highTemperatureHeatingActive => highTemperatureHeatingActive,
      AlertType.lowTemperatureHumidifierActive =>
        lowTemperatureHumidifierActive,
      AlertType.highDifferentialPressure => highDifferentialPressure,
      AlertType.highHumidity => highHumidity,
      AlertType.dewPointRisk => dewPointRisk,
    };
  }

  int effectiveOrder(AlertType type) => toggleFor(type).order;

  int compareAlertTypes(AlertType a, AlertType b) {
    final int orderComparison = effectiveOrder(a).compareTo(effectiveOrder(b));
    if (orderComparison != 0) {
      return orderComparison;
    }
    return AlertMetadataRegistry.priorityIndex(
      a,
    ).compareTo(AlertMetadataRegistry.priorityIndex(b));
  }

  static Map<AlertType, CachedAlertToggle> _normalizeOrders(
    Map<AlertType, CachedAlertToggle> source,
  ) {
    final List<AlertType> types = AlertMetadataRegistry.ordered
        .map((AlertMetadata metadata) => metadata.type)
        .toList(growable: false);
    types.sort((AlertType a, AlertType b) {
      final int orderComparison = source[a]!.order.compareTo(source[b]!.order);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return AlertMetadataRegistry.priorityIndex(
        a,
      ).compareTo(AlertMetadataRegistry.priorityIndex(b));
    });
    return <AlertType, CachedAlertToggle>{
      for (int i = 0; i < types.length; i += 1)
        types[i]: source[types[i]]!.copyWith(order: i + 1),
    };
  }
}

class CachedAlertToggle {
  const CachedAlertToggle({
    required this.enabled,
    required this.sendWhatsapp,
    required this.order,
  });

  factory CachedAlertToggle.fromRaw(Object? raw, {required int defaultOrder}) {
    if (raw is! Map) {
      return CachedAlertToggle(
        enabled: true,
        sendWhatsapp: false,
        order: defaultOrder,
      );
    }
    final Map<Object?, Object?> data = raw;
    final bool enabled = data['enabled'] is bool
        ? data['enabled'] as bool
        : true;
    final bool sendWhatsapp = enabled && data['sendWhatsapp'] == true;
    return CachedAlertToggle(
      enabled: enabled,
      sendWhatsapp: sendWhatsapp,
      order: _readPositiveInt(data['order']) ?? defaultOrder,
    );
  }

  final bool enabled;
  final bool sendWhatsapp;
  final int order;

  CachedAlertToggle copyWith({bool? enabled, bool? sendWhatsapp, int? order}) {
    final bool nextEnabled = enabled ?? this.enabled;
    return CachedAlertToggle(
      enabled: nextEnabled,
      sendWhatsapp: nextEnabled ? sendWhatsapp ?? this.sendWhatsapp : false,
      order: order ?? this.order,
    );
  }
}

class CachedAlertThresholds {
  const CachedAlertThresholds({
    required this.temperatureMin,
    required this.temperatureMax,
    required this.humidityRedMinExclusive,
    required this.dewPointMarginRedMaxInclusive,
    required this.filterPressureMax,
  });

  factory CachedAlertThresholds.fromRaw(Map<String, Object?> raw) {
    return CachedAlertThresholds(
      temperatureMin: _readDouble(raw, const <List<String>>[
        <String>['munters', 'munters1', 'tempInterior', 'min'],
      ]),
      temperatureMax: _readDouble(raw, const <List<String>>[
        <String>['munters', 'munters1', 'tempInterior', 'max'],
      ]),
      humidityRedMinExclusive: _readDouble(raw, const <List<String>>[
        <String>[
          'munters',
          'munters1',
          'humidityInterior',
          'alarm',
          'redMinExclusive',
        ],
      ]),
      dewPointMarginRedMaxInclusive: _readDouble(raw, const <List<String>>[
        <String>[
          'munters',
          'munters1',
          'dewPointMargin',
          'alarm',
          'redMaxInclusive',
        ],
      ]),
      filterPressureMax: _readDouble(raw, const <List<String>>[
        <String>['munters', 'munters1', 'presionDiferencial', 'max'],
      ]),
    );
  }

  final double? temperatureMin;
  final double? temperatureMax;
  final double? humidityRedMinExclusive;
  final double? dewPointMarginRedMaxInclusive;
  final double? filterPressureMax;
}

double? _readDouble(Map<String, Object?> raw, List<List<String>> paths) {
  for (final List<String> path in paths) {
    Object? current = raw;
    for (final String segment in path) {
      if (current is Map) {
        current = current[segment];
      } else {
        current = null;
        break;
      }
    }
    if (current is num) {
      return current.toDouble();
    }
    if (current != null) {
      final double? parsed = double.tryParse(current.toString());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

int? _readPositiveInt(Object? raw) {
  if (raw is int && raw > 0) {
    return raw;
  }
  if (raw is num && raw.isFinite && raw > 0) {
    return raw.toInt();
  }
  if (raw is String) {
    final int? parsed = int.tryParse(raw.trim());
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }
  return null;
}

DateTime? _readDateTime(Object? raw) {
  if (raw is DateTime) {
    return raw;
  }
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  return null;
}
