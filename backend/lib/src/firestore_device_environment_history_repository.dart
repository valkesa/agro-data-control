import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/service_account_auth.dart';

/// Prompt_Historicos_Temperatura_Humedad_por_Device §6/§13, hardened by
/// Prompt_Cierre_Historicos_Ambientales_Robustez_H1_H7 (H4/H7/H11) — persists
/// to `tenants/{tenantId}/devices/{deviceId}/historyHourly/{periodId}` and
/// `.../historyDaily/{periodId}`, the modern per-Device schema (never the
/// legacy `sites/{siteId}/plcs/{plcId}` path). Same raw-REST +
/// service-account pattern as [FirestoreTemperatureHistoryRepository] —
/// no `cloud_firestore` package dependency in this pure-Dart backend.
///
/// `history/hourly/{periodId}` (the prompt's own conceptual example) is
/// explicitly "NO obligatorio" and does not parse as a valid Firestore
/// document path (an odd number of `/`-segments after `devices/{deviceId}`
/// ends on a collection, not a document) — `historyHourly`/`historyDaily`
/// are flat subcollections directly under `devices/{deviceId}`, the same
/// shape every sibling subcollection there already uses
/// (`alertConfig`, `pigStats`, `rooms`, ...).
class FirestoreDeviceEnvironmentHistoryRepository {
  FirestoreDeviceEnvironmentHistoryRepository({
    required this.config,
    String? baseUrl,
    Future<String> Function()? accessTokenProvider,
  }) : _auth = ServiceAccountAuth(
         serviceAccountJsonPath: config.firestoreServiceAccountPath,
       ),
       _baseUrl = baseUrl ?? 'https://firestore.googleapis.com',
       _accessTokenProvider = accessTokenProvider;

  final DeviceEnvironmentHistoryConfig config;
  final ServiceAccountAuth _auth;

  /// Overridable REST root — production always uses the real Firestore
  /// endpoint (the default). Tests point this at a local Firestore Emulator
  /// instead, exercising the exact same HTTP + wire-decode path
  /// (`_getDocument`/`_commitDocument`) that talks to production. Same
  /// pattern already used by `FirestoreOperationalTopologyLoader`.
  final String _baseUrl;

  /// Overridable token source — production always calls the real
  /// [ServiceAccountAuth] (the default, when null). The Firestore Emulator
  /// does not validate bearer tokens, so tests inject a trivial provider
  /// instead of performing a real Google OAuth exchange.
  final Future<String> Function()? _accessTokenProvider;

  bool get isConfigured =>
      effectiveProjectId.trim().isNotEmpty &&
      (_accessTokenProvider != null ||
          config.firestoreServiceAccountPath.trim().isNotEmpty);

  String get missingConfigurationReason {
    if (effectiveProjectId.trim().isEmpty) {
      return 'missing firestoreProjectId or env FIRESTORE_PROJECT_ID';
    }
    if (config.firestoreServiceAccountPath.trim().isEmpty) {
      return 'missing firestoreServiceAccountPath in config';
    }
    return 'unknown';
  }

  /// H1 — the caller (`DeviceEnvironmentHistoryService`) is responsible for
  /// keeping the record durable (pending, checkpointed) until this call
  /// actually succeeds; this method itself does exactly one write attempt
  /// and throws on failure, it never retries internally.
  ///
  /// `createdAt` is set once, by the caller, at the moment the period first
  /// became pending — never re-derived here via an extra GET (unlike the
  /// pre-H1-hardening version): under the new pending/confirm model a given
  /// `periodId` is written to Firestore exactly once in its final form, so
  /// there is nothing to "preserve" across re-writes, and skipping that GET
  /// removes 1 read per write from the cost profile (§8/§9 of the hardening
  /// prompt).
  Future<void> saveHourly(DeviceEnvironmentHourlyRecord record) async {
    _validateWriteScope(record.tenantId, record.siteId, record.deviceId);
    await _commitDocument(
      _hourlyDocumentPath(record.periodId),
      <String, Object?>{
        'tenantId': _stringField(record.tenantId),
        'siteId': _stringField(record.siteId),
        'deviceId': _stringField(record.deviceId),
        'periodStart': _timestampField(record.periodStartUtc),
        'periodEnd': _timestampField(record.periodEndUtc),
        'schemaVersion': _intField(record.schemaVersion),
        'createdAt': _timestampField(record.createdAtUtc),
        'temperature': _statsField(record.temperature),
        'humidity': _statsField(record.humidity),
      },
    );
  }

  /// H6 — same one-shot-write contract as [saveHourly]; the caller owns the
  /// pending/retry lifecycle.
  Future<void> saveDaily(DeviceEnvironmentDailyRecord record) async {
    _validateWriteScope(record.tenantId, record.siteId, record.deviceId);
    await _commitDocument(
      _dailyDocumentPath(record.periodId),
      <String, Object?>{
        'tenantId': _stringField(record.tenantId),
        'siteId': _stringField(record.siteId),
        'deviceId': _stringField(record.deviceId),
        'periodStart': _timestampField(record.periodStartUtc),
        'periodEnd': _timestampField(record.periodEndUtc),
        'schemaVersion': _intField(record.schemaVersion),
        'createdAt': _timestampField(record.createdAtUtc),
        'temperature': _statsField(record.temperature),
        'humidity': _statsField(record.humidity),
      },
    );
  }

  void _validateWriteScope(String tenant, String site, String device) {
    if (tenant != config.tenantId ||
        site != config.siteId ||
        device != config.deviceId) {
      throw StateError('History record identity does not match repository');
    }
  }

  /// H4 — the real Site a Device belongs to, read directly from its own
  /// `tenants/{tenantId}/devices/{deviceId}` document (the modern schema's
  /// source of truth — never inferred from this history subsystem's own
  /// config). `null` if the Device document does not exist or has no
  /// `siteId` field.
  Future<String?> fetchDeviceSiteId() async {
    final Map<String, dynamic>? document = await _getDocument(
      'tenants/${config.tenantId}/devices/${config.deviceId}',
    );
    if (document == null) {
      return null;
    }
    final Map<String, dynamic> fields =
        document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String siteId = _readString(fields, 'siteId');
    return siteId.isEmpty ? null : siteId;
  }

  /// Reads always enforce config tenant/device/site. [expectedSiteId] may
  /// narrow the request but cannot override the configured Site. A mismatch
  /// is reported through [onSiteMismatch] when supplied.
  Future<DeviceEnvironmentHourlyRecord?> loadHourly(
    String periodId, {
    String? expectedSiteId,
    void Function(String periodId, String actualSiteId)? onSiteMismatch,
  }) async {
    final Map<String, dynamic>? document = await _getDocument(
      _hourlyDocumentPath(periodId),
    );
    if (document == null) {
      return null;
    }
    final DeviceEnvironmentHourlyRecord record = _parseHourlyRecord(
      periodId,
      document,
    );
    if (record.siteId != (expectedSiteId ?? config.siteId) ||
        record.siteId != config.siteId ||
        record.tenantId != config.tenantId ||
        record.deviceId != config.deviceId) {
      onSiteMismatch?.call(periodId, record.siteId);
      return null;
    }
    return record;
  }

  /// Loads every hourly record for [dateKey] (`YYYY-MM-DD`), 24 individual
  /// GETs by deterministic ID — same shape as
  /// `FirestoreTemperatureHistoryRepository.loadHourlyForDate` and, like it,
  /// needs no Firestore composite index (§18): each doc is fetched directly
  /// by its known ID, never via a range `query()`.
  Future<List<DeviceEnvironmentHourlyRecord>> loadHourlyForDate(
    String dateKey, {
    String? expectedSiteId,
    void Function(String periodId, String actualSiteId)? onSiteMismatch,
  }) async {
    final List<DeviceEnvironmentHourlyRecord> records =
        <DeviceEnvironmentHourlyRecord>[];
    for (int hour = 0; hour < 24; hour += 1) {
      final String periodId = '${dateKey}T${hour.toString().padLeft(2, '0')}';
      final DeviceEnvironmentHourlyRecord? record = await loadHourly(
        periodId,
        expectedSiteId: expectedSiteId,
        onSiteMismatch: onSiteMismatch,
      );
      if (record != null) {
        records.add(record);
      }
    }
    return records;
  }

  /// H7 — exact half-open range contract: a record is included if and only
  /// if `fromUtc <= record.periodStartUtc < toUtc`. `10:00`–`11:00` returns
  /// the `10:00` hour and nothing from `11:00` onward. §13: one-shot reads,
  /// no listeners. Throws [DeviceEnvironmentHistoryRangeTooLargeException]
  /// for a span over 31 days — never silently truncates (H7); callers with
  /// a longer span must chunk it themselves into several calls.
  Future<List<DeviceEnvironmentHourlyRecord>> getHourlyHistory({
    required DateTime fromUtc,
    required DateTime toUtc,
    String? expectedSiteId,
    void Function(String periodId, String actualSiteId)? onSiteMismatch,
  }) async {
    _checkRangeSize(fromUtc, toUtc);
    final List<String> dateKeys = _dateKeysInRange(fromUtc, toUtc);
    final List<DeviceEnvironmentHourlyRecord> records =
        <DeviceEnvironmentHourlyRecord>[];
    for (final String dateKey in dateKeys) {
      records.addAll(
        await loadHourlyForDate(
          dateKey,
          expectedSiteId: expectedSiteId,
          onSiteMismatch: onSiteMismatch,
        ),
      );
    }
    records.retainWhere(
      (DeviceEnvironmentHourlyRecord r) =>
          !r.periodStartUtc.isBefore(fromUtc) &&
          r.periodStartUtc.isBefore(toUtc),
    );
    records.sort(
      (DeviceEnvironmentHourlyRecord a, DeviceEnvironmentHourlyRecord b) =>
          a.periodStartUtc.compareTo(b.periodStartUtc),
    );
    return records;
  }

  /// H7 — same half-open contract as [getHourlyHistory], applied to whole
  /// days: a daily record is included if `fromUtc <= periodStartUtc < toUtc`.
  Future<List<DeviceEnvironmentDailyRecord>> getDailyHistory({
    required DateTime fromUtc,
    required DateTime toUtc,
    String? expectedSiteId,
    void Function(String periodId, String actualSiteId)? onSiteMismatch,
  }) async {
    _checkRangeSize(fromUtc, toUtc);
    final List<String> dateKeys = _dateKeysInRange(fromUtc, toUtc);
    final List<DeviceEnvironmentDailyRecord> records =
        <DeviceEnvironmentDailyRecord>[];
    for (final String dateKey in dateKeys) {
      final Map<String, dynamic>? document = await _getDocument(
        _dailyDocumentPath(dateKey),
      );
      if (document == null) {
        continue;
      }
      final DeviceEnvironmentDailyRecord record = _parseDailyRecord(
        dateKey,
        document,
      );
      if (record.siteId != (expectedSiteId ?? config.siteId) ||
          record.siteId != config.siteId ||
          record.tenantId != config.tenantId ||
          record.deviceId != config.deviceId) {
        onSiteMismatch?.call(dateKey, record.siteId);
        continue;
      }
      records.add(record);
    }
    records.retainWhere(
      (DeviceEnvironmentDailyRecord r) =>
          !r.periodStartUtc.isBefore(fromUtc) &&
          r.periodStartUtc.isBefore(toUtc),
    );
    return records;
  }

  static const int maxRangeDays = 31;

  void _checkRangeSize(DateTime fromUtc, DateTime toUtc) {
    if (toUtc.isBefore(fromUtc)) {
      throw DeviceEnvironmentHistoryRangeException(
        'toUtc ($toUtc) is before fromUtc ($fromUtc)',
      );
    }
    final Duration span = toUtc.difference(fromUtc);
    if (span > const Duration(days: maxRangeDays)) {
      throw DeviceEnvironmentHistoryRangeTooLargeException(
        'Requested range spans $span, over the $maxRangeDays-day '
        'limit per call ($fromUtc .. $toUtc) — chunk into several calls, '
        'this never truncates silently (H7).',
      );
    }
  }

  List<String> _dateKeysInRange(DateTime fromUtc, DateTime toUtc) {
    if (!fromUtc.isBefore(toUtc)) return <String>[];
    final startArt = fromUtc.toUtc().subtract(const Duration(hours: 3));
    final endArt = toUtc
        .toUtc()
        .subtract(const Duration(microseconds: 1))
        .subtract(const Duration(hours: 3));
    final from = DateTime.utc(startArt.year, startArt.month, startArt.day);
    final to = DateTime.utc(endArt.year, endArt.month, endArt.day);
    final List<String> keys = <String>[];
    DateTime cursor = from;
    while (!cursor.isAfter(to)) {
      keys.add(_formatDateKey(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return keys;
  }

  Future<void> _commitDocument(
    String documentPath,
    Map<String, Object?> fields,
  ) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.openUrl(
        'POST',
        _commitUri(),
      );
      final String token =
          await (_accessTokenProvider ?? _auth.getAccessToken)();
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(
        jsonEncode(<String, Object?>{
          'writes': <Object?>[
            <String, Object?>{
              'update': <String, Object?>{
                'name': _documentName(documentPath),
                'fields': fields,
              },
              'updateMask': <String, Object?>{
                'fieldPaths': <String>[...fields.keys, 'updatedAt'],
              },
              'updateTransforms': <Object?>[
                <String, Object?>{
                  'fieldPath': 'updatedAt',
                  'setToServerValue': 'REQUEST_TIME',
                },
              ],
            },
          ],
        }),
      );

      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FirestoreDeviceEnvironmentHistoryException(
          'Firestore commit failed status=${response.statusCode} path=$documentPath body=$body',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _getDocument(String documentPath) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(
        _documentUri(documentPath),
      );
      final String token =
          await (_accessTokenProvider ?? _auth.getAccessToken)();
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.notFound) {
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FirestoreDeviceEnvironmentHistoryException(
          'Firestore GET failed status=${response.statusCode} path=$documentPath body=$body',
        );
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Uri _documentUri(String documentPath) {
    return Uri.parse(
      '$_baseUrl/v1/projects/$effectiveProjectId'
      '/databases/${config.firestoreDatabaseId}/documents/$documentPath',
    );
  }

  Uri _commitUri() {
    return Uri.parse(
      '$_baseUrl/v1/projects/$effectiveProjectId'
      '/databases/${config.firestoreDatabaseId}/documents:commit',
    );
  }

  String _documentName(String documentPath) {
    return 'projects/$effectiveProjectId/databases/${config.firestoreDatabaseId}'
        '/documents/$documentPath';
  }

  String _hourlyDocumentPath(String periodId) {
    return 'tenants/${config.tenantId}/devices/${config.deviceId}/historyHourly/$periodId';
  }

  String _dailyDocumentPath(String periodId) {
    return 'tenants/${config.tenantId}/devices/${config.deviceId}/historyDaily/$periodId';
  }

  DeviceEnvironmentHourlyRecord _parseHourlyRecord(
    String periodId,
    Map<String, dynamic> document,
  ) {
    final Map<String, dynamic> fields =
        document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return DeviceEnvironmentHourlyRecord(
      periodId: periodId,
      tenantId: _readString(fields, 'tenantId'),
      siteId: _readString(fields, 'siteId'),
      deviceId: _readString(fields, 'deviceId'),
      periodStartUtc: DateTime.parse(
        _readTimestamp(fields, 'periodStart'),
      ).toUtc(),
      periodEndUtc: DateTime.parse(_readTimestamp(fields, 'periodEnd')).toUtc(),
      schemaVersion: _readInt(fields, 'schemaVersion'),
      createdAtUtc: DateTime.parse(_readTimestamp(fields, 'createdAt')).toUtc(),
      temperature: _readStats(fields, 'temperature'),
      humidity: _readStats(fields, 'humidity'),
    );
  }

  DeviceEnvironmentDailyRecord _parseDailyRecord(
    String periodId,
    Map<String, dynamic> document,
  ) {
    final Map<String, dynamic> fields =
        document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return DeviceEnvironmentDailyRecord(
      periodId: periodId,
      tenantId: _readString(fields, 'tenantId'),
      siteId: _readString(fields, 'siteId'),
      deviceId: _readString(fields, 'deviceId'),
      periodStartUtc: DateTime.parse(
        _readTimestamp(fields, 'periodStart'),
      ).toUtc(),
      periodEndUtc: DateTime.parse(_readTimestamp(fields, 'periodEnd')).toUtc(),
      schemaVersion: _readInt(fields, 'schemaVersion'),
      createdAtUtc: DateTime.parse(_readTimestamp(fields, 'createdAt')).toUtc(),
      temperature: _readStats(fields, 'temperature'),
      humidity: _readStats(fields, 'humidity'),
    );
  }

  String get effectiveProjectId =>
      config.firestoreProjectId ??
      Platform.environment['FIRESTORE_PROJECT_ID'] ??
      '';
}

/// H11 — `avg`/`min`/`max` are `null` when [sampleCount] is 0: a period with
/// no valid samples for this metric must never be readable as "0 °C"/"0 %".
class DeviceEnvironmentStats {
  const DeviceEnvironmentStats({
    required this.avg,
    required this.min,
    required this.max,
    required this.sampleCount,
  });

  /// A metric with zero valid samples in the period (§8 — an invalid
  /// variable must not invalidate the other one sharing the same period).
  static const DeviceEnvironmentStats empty = DeviceEnvironmentStats(
    avg: null,
    min: null,
    max: null,
    sampleCount: 0,
  );

  final double? avg;
  final double? min;
  final double? max;
  final int sampleCount;

  bool get hasData => sampleCount > 0;
}

class DeviceEnvironmentHourlyRecord {
  const DeviceEnvironmentHourlyRecord({
    required this.periodId,
    required this.tenantId,
    required this.siteId,
    required this.deviceId,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.temperature,
    required this.humidity,
  });

  final String periodId;
  final String tenantId;
  final String siteId;
  final String deviceId;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final int schemaVersion;
  final DateTime createdAtUtc;
  final DeviceEnvironmentStats temperature;
  final DeviceEnvironmentStats humidity;
}

class DeviceEnvironmentDailyRecord {
  const DeviceEnvironmentDailyRecord({
    required this.periodId,
    required this.tenantId,
    required this.siteId,
    required this.deviceId,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.temperature,
    required this.humidity,
  });

  final String periodId;
  final String tenantId;
  final String siteId;
  final String deviceId;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final int schemaVersion;
  final DateTime createdAtUtc;
  final DeviceEnvironmentStats temperature;
  final DeviceEnvironmentStats humidity;
}

class FirestoreDeviceEnvironmentHistoryException implements Exception {
  FirestoreDeviceEnvironmentHistoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// H7 — base type for range-contract violations.
class DeviceEnvironmentHistoryRangeException implements Exception {
  DeviceEnvironmentHistoryRangeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// H7 — thrown instead of silently truncating a range over
/// [FirestoreDeviceEnvironmentHistoryRepository.maxRangeDays].
class DeviceEnvironmentHistoryRangeTooLargeException
    extends DeviceEnvironmentHistoryRangeException {
  DeviceEnvironmentHistoryRangeTooLargeException(super.message);
}

Map<String, Object?> _stringField(String value) => <String, Object?>{
  'stringValue': value,
};

Map<String, Object?> _intField(int value) => <String, Object?>{
  'integerValue': value.toString(),
};

Map<String, Object?> _doubleFieldOrNull(double? value) => value == null
    ? <String, Object?>{'nullValue': null}
    : <String, Object?>{'doubleValue': value};

Map<String, Object?> _timestampField(DateTime value) => <String, Object?>{
  'timestampValue': value.toUtc().toIso8601String(),
};

Map<String, Object?> _statsField(DeviceEnvironmentStats stats) =>
    <String, Object?>{
      'mapValue': <String, Object?>{
        'fields': <String, Object?>{
          'avg': _doubleFieldOrNull(stats.avg),
          'min': _doubleFieldOrNull(stats.min),
          'max': _doubleFieldOrNull(stats.max),
          'sampleCount': _intField(stats.sampleCount),
        },
      },
    };

DeviceEnvironmentStats _readStats(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic> wrapper =
      fields[key] as Map<String, dynamic>? ?? <String, dynamic>{};
  final Map<String, dynamic> mapValue =
      wrapper['mapValue'] as Map<String, dynamic>? ?? <String, dynamic>{};
  final Map<String, dynamic> inner =
      mapValue['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
  final int sampleCount = _readInt(inner, 'sampleCount');
  if (sampleCount == 0) {
    return DeviceEnvironmentStats.empty;
  }
  return DeviceEnvironmentStats(
    avg: _readDoubleOrNull(inner, 'avg'),
    min: _readDoubleOrNull(inner, 'min'),
    max: _readDoubleOrNull(inner, 'max'),
    sampleCount: sampleCount,
  );
}

String _readString(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic> value =
      fields[key] as Map<String, dynamic>? ?? <String, dynamic>{};
  return (value['stringValue'] ?? '').toString();
}

String _readTimestamp(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic> value =
      fields[key] as Map<String, dynamic>? ?? <String, dynamic>{};
  return (value['timestampValue'] ?? '').toString();
}

int _readInt(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic> value =
      fields[key] as Map<String, dynamic>? ?? <String, dynamic>{};
  final Object? raw = value['integerValue'] ?? value['doubleValue'];
  if (raw is num) {
    return raw.toInt();
  }
  if (raw == null) {
    return 0;
  }
  return int.parse(raw.toString());
}

double? _readDoubleOrNull(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic>? value = fields[key] as Map<String, dynamic>?;
  if (value == null || value.containsKey('nullValue')) {
    return null;
  }
  final Object? raw = value['doubleValue'] ?? value['integerValue'];
  if (raw is num) {
    return raw.toDouble();
  }
  if (raw is String) {
    return double.tryParse(raw);
  }
  return null;
}

String _formatDateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
