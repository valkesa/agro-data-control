import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/service_account_auth.dart';

class FirestoreTemperatureHistoryRepository {
  FirestoreTemperatureHistoryRepository({required this.config})
    : _auth = ServiceAccountAuth(
        serviceAccountJsonPath: config.firestoreServiceAccountPath,
      );

  final TemperatureHistoryConfig config;
  final ServiceAccountAuth _auth;

  bool get isConfigured =>
      _effectiveProjectId.trim().isNotEmpty &&
      config.firestoreServiceAccountPath.trim().isNotEmpty;

  String get missingConfigurationReason {
    if (_effectiveProjectId.trim().isEmpty) {
      return 'missing firestoreProjectId or env FIRESTORE_PROJECT_ID';
    }
    if (config.firestoreServiceAccountPath.trim().isEmpty) {
      return 'missing firestoreServiceAccountPath in config';
    }
    return 'unknown';
  }

  Future<void> saveHourly(TemperatureHourlyRecord record) async {
    await _commitDocument(
      _hourlyDocumentPath(record.hourKey),
      <String, Object?>{
        'timestampHourStart': _timestampField(record.timestampHourStartUtc),
        'dateKey': _stringField(record.dateKey),
        'hourKey': _stringField(record.hourKey),
        'hour': _intField(record.hour),
        'avgTemp': _doubleField(record.avgTemp),
        'minTemp': _doubleField(record.minTemp),
        'maxTemp': _doubleField(record.maxTemp),
        'samplesCount': _intField(record.samplesCount),
      },
    );
  }

  Future<void> saveDaily(TemperatureDailyRecord record) async {
    await _commitDocument(_dailyDocumentPath(record.dateKey), <String, Object?>{
      'dateKey': _stringField(record.dateKey),
      'timestampDayStart': _timestampField(record.timestampDayStartUtc),
      'avgTemp': _doubleField(record.avgTemp),
      'minTemp': _doubleField(record.minTemp),
      'maxTemp': _doubleField(record.maxTemp),
      'hoursCount': _intField(record.hoursCount),
    });
  }

  Future<List<TemperatureHourlyRecord>> loadHourlyForDate(
    String dateKey,
  ) async {
    final List<TemperatureHourlyRecord> records = <TemperatureHourlyRecord>[];
    for (int hour = 0; hour < 24; hour += 1) {
      final String hourKey =
          '${dateKey.replaceAll('-', '')}_${hour.toString().padLeft(2, '0')}';
      final Map<String, dynamic>? document = await _getDocument(
        _hourlyDocumentPath(hourKey),
      );
      if (document == null) {
        continue;
      }
      records.add(_parseHourlyRecord(document));
    }
    return records;
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
      final String token = await _auth.getAccessToken();
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
        throw FirestoreTemperatureHistoryException(
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
      final String token = await _auth.getAccessToken();
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $token',
      );

      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.notFound) {
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FirestoreTemperatureHistoryException(
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
      'https://firestore.googleapis.com/v1/projects/$_effectiveProjectId'
      '/databases/${config.firestoreDatabaseId}/documents/$documentPath',
    );
  }

  Uri _commitUri() {
    return Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_effectiveProjectId'
      '/databases/${config.firestoreDatabaseId}/documents:commit',
    );
  }

  String _documentName(String documentPath) {
    return 'projects/$_effectiveProjectId/databases/${config.firestoreDatabaseId}'
        '/documents/$documentPath';
  }

  String _hourlyDocumentPath(String hourKey) {
    return 'tenants/${config.tenantId}/sites/${config.siteId}/plcs/${config.plcId}/metrics/temperature/hourly/$hourKey';
  }

  String _dailyDocumentPath(String dateKey) {
    return 'tenants/${config.tenantId}/sites/${config.siteId}/plcs/${config.plcId}/metrics/temperature/daily/$dateKey';
  }

  TemperatureHourlyRecord _parseHourlyRecord(Map<String, dynamic> document) {
    final Map<String, dynamic> fields =
        document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return TemperatureHourlyRecord(
      timestampHourStartUtc: DateTime.parse(
        _readString(fields, 'timestampHourStart'),
      ).toUtc(),
      dateKey: _readString(fields, 'dateKey'),
      hourKey: _readString(fields, 'hourKey'),
      hour: _readInt(fields, 'hour'),
      avgTemp: _readDouble(fields, 'avgTemp'),
      minTemp: _readDouble(fields, 'minTemp'),
      maxTemp: _readDouble(fields, 'maxTemp'),
      samplesCount: _readInt(fields, 'samplesCount'),
    );
  }

  String get _effectiveProjectId =>
      config.firestoreProjectId ??
      Platform.environment['FIRESTORE_PROJECT_ID'] ??
      '';
}

class TemperatureHourlyRecord {
  const TemperatureHourlyRecord({
    required this.timestampHourStartUtc,
    required this.dateKey,
    required this.hourKey,
    required this.hour,
    required this.avgTemp,
    required this.minTemp,
    required this.maxTemp,
    required this.samplesCount,
  });

  final DateTime timestampHourStartUtc;
  final String dateKey;
  final String hourKey;
  final int hour;
  final double avgTemp;
  final double minTemp;
  final double maxTemp;
  final int samplesCount;
}

class TemperatureDailyRecord {
  const TemperatureDailyRecord({
    required this.timestampDayStartUtc,
    required this.dateKey,
    required this.avgTemp,
    required this.minTemp,
    required this.maxTemp,
    required this.hoursCount,
  });

  final DateTime timestampDayStartUtc;
  final String dateKey;
  final double avgTemp;
  final double minTemp;
  final double maxTemp;
  final int hoursCount;
}

class FirestoreTemperatureHistoryException implements Exception {
  FirestoreTemperatureHistoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

Map<String, Object?> _stringField(String value) => <String, Object?>{
  'stringValue': value,
};

Map<String, Object?> _intField(int value) => <String, Object?>{
  'integerValue': value.toString(),
};

Map<String, Object?> _doubleField(double value) => <String, Object?>{
  'doubleValue': value,
};

Map<String, Object?> _timestampField(DateTime value) => <String, Object?>{
  'timestampValue': value.toUtc().toIso8601String(),
};

String _readString(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic> value =
      fields[key] as Map<String, dynamic>? ?? <String, dynamic>{};
  return (value['stringValue'] ?? value['timestampValue'] ?? '').toString();
}

int _readInt(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic> value =
      fields[key] as Map<String, dynamic>? ?? <String, dynamic>{};
  final Object? raw = value['integerValue'] ?? value['doubleValue'];
  if (raw is num) {
    return raw.toInt();
  }
  return int.parse(raw.toString());
}

double _readDouble(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic> value =
      fields[key] as Map<String, dynamic>? ?? <String, dynamic>{};
  final Object? raw = value['doubleValue'] ?? value['integerValue'];
  if (raw is num) {
    return raw.toDouble();
  }
  return double.parse(raw.toString());
}
