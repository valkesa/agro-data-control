import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/service_account_auth.dart';

class FirestoreDifferentialPressureHistoryRepository {
  FirestoreDifferentialPressureHistoryRepository({required this.config})
    : _auth = ServiceAccountAuth(
        serviceAccountJsonPath: config.firestoreServiceAccountPath,
      );

  final DifferentialPressureHistoryConfig config;
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

  Future<DifferentialPressureDailyRecord?> loadDaily(String dateKey) async {
    final Map<String, dynamic>? document = await _getDocument(
      _dailyDocumentPath(dateKey),
    );
    if (document == null) {
      return null;
    }
    return _parseDailyRecord(document);
  }

  Future<void> saveDaily(DifferentialPressureDailyRecord record) async {
    final Map<String, Object?> fields = <String, Object?>{
      'dateKey': _stringField(record.dateKey),
      'timestampDayStart': _timestampField(record.timestampDayStartUtc),
      'avgPressureDifferential': _doubleField(record.avgPressureDifferential),
      'minPressureDifferential': _doubleField(record.minPressureDifferential),
      'maxPressureDifferential': _doubleField(record.maxPressureDifferential),
      'samplesCount': _intField(record.samplesCount),
      'sampleWindowKeys': _stringArrayField(record.sampleWindowKeys),
    };
    await _commitDocument(_dailyDocumentPath(record.dateKey), fields);
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
        throw FirestoreDifferentialPressureHistoryException(
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
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.notFound) {
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FirestoreDifferentialPressureHistoryException(
          'Firestore GET failed status=${response.statusCode} path=$documentPath body=$body',
        );
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Uri _documentUri(String documentPath) => Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$_effectiveProjectId'
    '/databases/${config.firestoreDatabaseId}/documents/$documentPath',
  );

  Uri _commitUri() => Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$_effectiveProjectId'
    '/databases/${config.firestoreDatabaseId}/documents:commit',
  );

  String _documentName(String documentPath) =>
      'projects/$_effectiveProjectId/databases/${config.firestoreDatabaseId}'
      '/documents/$documentPath';

  String _dailyDocumentPath(String dateKey) =>
      'tenants/${config.tenantId}/sites/${config.siteId}/plcs/${config.plcId}/metrics/differentialPressure/daily/$dateKey';

  DifferentialPressureDailyRecord _parseDailyRecord(
    Map<String, dynamic> document,
  ) {
    final Map<String, dynamic> fields =
        document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String dateKey = _readString(fields, 'dateKey');
    final DateTime timestamp = DateTime.parse(
      _readString(fields, 'timestampDayStart'),
    ).toUtc();
    return DifferentialPressureDailyRecord(
      timestampDayStartUtc: timestamp,
      dateKey: dateKey,
      avgPressureDifferential: _readDouble(fields, 'avgPressureDifferential'),
      minPressureDifferential: _readDouble(fields, 'minPressureDifferential'),
      maxPressureDifferential: _readDouble(fields, 'maxPressureDifferential'),
      samplesCount: _readInt(fields, 'samplesCount'),
      sampleWindowKeys: _readStringArray(fields, 'sampleWindowKeys'),
    );
  }

  String get _effectiveProjectId =>
      config.firestoreProjectId ??
      Platform.environment['FIRESTORE_PROJECT_ID'] ??
      '';
}

class DifferentialPressureDailyRecord {
  const DifferentialPressureDailyRecord({
    required this.timestampDayStartUtc,
    required this.dateKey,
    required this.avgPressureDifferential,
    required this.minPressureDifferential,
    required this.maxPressureDifferential,
    required this.samplesCount,
    required this.sampleWindowKeys,
  });

  factory DifferentialPressureDailyRecord.firstSample({
    required DateTime timestampDayStartUtc,
    required String dateKey,
    required String sampleWindowKey,
    required double pressure,
  }) {
    return DifferentialPressureDailyRecord(
      timestampDayStartUtc: timestampDayStartUtc,
      dateKey: dateKey,
      avgPressureDifferential: pressure,
      minPressureDifferential: pressure,
      maxPressureDifferential: pressure,
      samplesCount: 1,
      sampleWindowKeys: <String>[sampleWindowKey],
    );
  }

  final DateTime timestampDayStartUtc;
  final String dateKey;
  final double avgPressureDifferential;
  final double minPressureDifferential;
  final double maxPressureDifferential;
  final int samplesCount;
  final List<String> sampleWindowKeys;

  DifferentialPressureDailyRecord addSample({
    required String sampleWindowKey,
    required double pressure,
  }) {
    final int nextCount = samplesCount + 1;
    return DifferentialPressureDailyRecord(
      timestampDayStartUtc: timestampDayStartUtc,
      dateKey: dateKey,
      avgPressureDifferential:
          ((avgPressureDifferential * samplesCount) + pressure) / nextCount,
      minPressureDifferential: pressure < minPressureDifferential
          ? pressure
          : minPressureDifferential,
      maxPressureDifferential: pressure > maxPressureDifferential
          ? pressure
          : maxPressureDifferential,
      samplesCount: nextCount,
      sampleWindowKeys: <String>{...sampleWindowKeys, sampleWindowKey}.toList()
        ..sort(),
    );
  }
}

class FirestoreDifferentialPressureHistoryException implements Exception {
  FirestoreDifferentialPressureHistoryException(this.message);

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

Map<String, Object?> _stringArrayField(List<String> values) =>
    <String, Object?>{
      'arrayValue': <String, Object?>{
        'values': values.map(_stringField).toList(growable: false),
      },
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
  final Object? raw =
      value['doubleValue'] ?? value['integerValue'] ?? value['stringValue'];
  if (raw is num) {
    return raw.toDouble();
  }
  return double.parse(raw.toString());
}

List<String> _readStringArray(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic> value =
      fields[key] as Map<String, dynamic>? ?? <String, dynamic>{};
  final Map<String, dynamic> arrayValue =
      value['arrayValue'] as Map<String, dynamic>? ?? <String, dynamic>{};
  final List<dynamic> values =
      arrayValue['values'] as List<dynamic>? ?? const [];
  return values
      .map((dynamic entry) {
        final Map<String, dynamic> field =
            entry as Map<String, dynamic>? ?? <String, dynamic>{};
        return field['stringValue']?.toString();
      })
      .whereType<String>()
      .toList(growable: false);
}
