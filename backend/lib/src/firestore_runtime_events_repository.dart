import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/runtime_event.dart';
import 'package:agro_data_control_backend/src/service_account_auth.dart';

class FirestoreRuntimeEventsRepository {
  FirestoreRuntimeEventsRepository({required this.config})
    : _auth = ServiceAccountAuth(
        serviceAccountJsonPath: config.firestoreServiceAccountPath,
      );

  final RuntimeEventsConfig config;
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

  Future<void> saveHeartbeat(RuntimeEvent event, {String? docId}) async {
    final DateTime observedAt = event.endedAt ?? DateTime.now().toUtc();
    final bool deviceIsOn = event.deviceIsOn ?? true;
    final Map<String, Object?> fields = <String, Object?>{
      'deviceType': _stringField(event.deviceType),
      'observedAt': _timestampField(observedAt),
      'plcId': _stringField(event.plcId),
      'isOpen': _boolField(true),
      'deviceIsOn': _boolField(deviceIsOn),
      'startedAt': _timestampField(event.startedAt),
      if (deviceIsOn)
        'activeDurationSec': _intField(event.durationSec),
      if (event.powerPercent != null)
        'powerPercent': _intField(event.powerPercent!),
      if (event.powerWatts != null)
        'powerWatts': _doubleField(event.powerWatts!),
      if (event.energyKwh != null) 'energyKwh': _doubleField(event.energyKwh!),
    };

    final String documentPath = _runtimeEventDocumentPath(
      event.plcId,
      docId ?? _heartbeatId(event, observedAt),
    );
    await _commitDocument(documentPath, fields);
  }

  Future<void> saveClosed(RuntimeEvent event) async {
    final DateTime? endedAt = event.endedAt;
    if (endedAt == null) {
      throw FirestoreRuntimeEventsException(
        'Cannot persist open runtime event deviceType=${event.deviceType}',
      );
    }

    final Map<String, Object?> fields = <String, Object?>{
      'deviceType': _stringField(event.deviceType),
      'startedAt': _timestampField(event.startedAt),
      'endedAt': _timestampField(endedAt),
      'durationSec': _intField(event.durationSec),
      'plcId': _stringField(event.plcId),
      if (event.powerPercent != null)
        'powerPercent': _intField(event.powerPercent!),
      if (event.powerWatts != null)
        'powerWatts': _doubleField(event.powerWatts!),
      if (event.energyKwh != null) 'energyKwh': _doubleField(event.energyKwh!),
    };

    final String documentPath = _runtimeEventDocumentPath(
      event.plcId,
      _newEventId(event),
    );
    await _commitDocument(documentPath, fields);
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
                'fieldPaths': <String>[...fields.keys, 'createdAt'],
              },
              'updateTransforms': <Object?>[
                <String, Object?>{
                  'fieldPath': 'createdAt',
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
        throw FirestoreRuntimeEventsException(
          'Firestore commit failed status=${response.statusCode} path=$documentPath body=$body',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Uri _commitUri() => Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$_effectiveProjectId'
    '/databases/${config.firestoreDatabaseId}/documents:commit',
  );

  String _documentName(String documentPath) =>
      'projects/$_effectiveProjectId/databases/${config.firestoreDatabaseId}'
      '/documents/$documentPath';

  String _runtimeEventDocumentPath(String plcId, String eventId) =>
      'tenants/${config.tenantId}/sites/${config.siteId}/plcs/$plcId/runtimeEvents/$eventId';

  String _newEventId(RuntimeEvent event) {
    final DateTime t = event.startedAt.toUtc();
    final String y = t.year.toString().padLeft(4, '0');
    final String mo = t.month.toString().padLeft(2, '0');
    final String d = t.day.toString().padLeft(2, '0');
    final String h = t.hour.toString().padLeft(2, '0');
    final String mi = t.minute.toString().padLeft(2, '0');
    final String s = t.second.toString().padLeft(2, '0');
    final String ms = t.millisecond.toString().padLeft(3, '0');
    final String safeDeviceType = event.deviceType.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    return '${y}${mo}${d}_${h}${mi}${s}_${ms}_$safeDeviceType';
  }

  String get _effectiveProjectId =>
      config.firestoreProjectId ??
      Platform.environment['FIRESTORE_PROJECT_ID'] ??
      '';
}

class FirestoreRuntimeEventsException implements Exception {
  FirestoreRuntimeEventsException(this.message);

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

Map<String, Object?> _boolField(bool value) => <String, Object?>{
  'booleanValue': value,
};

String _heartbeatId(RuntimeEvent event, DateTime observedAt) {
  final DateTime t = observedAt.toUtc();
  final String y = t.year.toString().padLeft(4, '0');
  final String mo = t.month.toString().padLeft(2, '0');
  final String d = t.day.toString().padLeft(2, '0');
  final String h = t.hour.toString().padLeft(2, '0');
  final String mi = t.minute.toString().padLeft(2, '0');
  final String s = t.second.toString().padLeft(2, '0');
  final String ms = t.millisecond.toString().padLeft(3, '0');
  final String safeDeviceType = event.deviceType.replaceAll(
    RegExp(r'[^A-Za-z0-9_-]'),
    '_',
  );
  return '${y}${mo}${d}_${h}${mi}${s}_${ms}_${safeDeviceType}_hb';
}
