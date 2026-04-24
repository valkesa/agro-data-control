import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/service_account_auth.dart';

class FirestoreDoorOpeningsRepository {
  FirestoreDoorOpeningsRepository({required this.config})
    : _auth = ServiceAccountAuth(
        serviceAccountJsonPath: config.firestoreServiceAccountPath,
      );

  final DoorOpeningsConfig config;
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

  /// Writes door state (isOpen=true) and a new opening record atomically.
  /// If [recoveredOpen] is true, marks the opening as recovered (backend restart).
  Future<void> recordOpened({
    required DoorConfig door,
    required String openingId,
    required DateTime openedAt,
    bool recoveredOpen = false,
  }) async {
    final Map<String, Object?> openingFields = <String, Object?>{
      'openingId': _stringField(openingId),
      'doorId': _stringField(door.doorId),
      'doorName': _stringField(door.label),
      'openedAt': _timestampField(openedAt),
      'closedAt': _nullField(),
      'durationS': _nullField(),
      'status': _stringField('open'),
      'source': _stringField('plc'),
      'createdAt': _timestampField(openedAt),
    };
    if (recoveredOpen) {
      openingFields['recoveredOpen'] = _boolField(value: true);
    }

    await _batchCommit(<Map<String, Object?>>[
      _updateWrite(
        _doorDocumentPath(door.doorId),
        <String, Object?>{
          'doorId': _stringField(door.doorId),
          'doorName': _stringField(door.label),
          'isOpen': _boolField(value: true),
          'currentOpenedAt': _timestampField(openedAt),
          'lastChangedAt': _timestampField(openedAt),
          'lastOpeningId': _stringField(openingId),
        },
        additionalTransforms: <Map<String, Object?>>[
          _incrementTransform('openCountTotal', 1),
        ],
      ),
      _updateWrite(_openingDocumentPath(door.doorId, openingId), openingFields),
    ]);
  }

  /// Writes door state (isOpen=false) and closes the opening record atomically.
  /// If [recoveredClosure] is true, marks the closure as recovered (backend restart).
  Future<void> recordClosed({
    required DoorConfig door,
    required String? openingId,
    required DateTime openedAt,
    required DateTime closedAt,
    bool recoveredClosure = false,
  }) async {
    final int durationS = closedAt.difference(openedAt).inSeconds.abs();

    final Map<String, Object?> doorFields = <String, Object?>{
      'doorId': _stringField(door.doorId),
      'doorName': _stringField(door.label),
      'isOpen': _boolField(value: false),
      'currentOpenedAt': _nullField(),
      'lastChangedAt': _timestampField(closedAt),
      'lastDurationS': _intField(durationS),
    };

    final List<Map<String, Object?>> writes = <Map<String, Object?>>[
      _updateWrite(
        _doorDocumentPath(door.doorId),
        doorFields,
        additionalTransforms: <Map<String, Object?>>[
          _incrementTransform('totalOpenDurationS', durationS),
        ],
      ),
    ];

    if (openingId != null && openingId.isNotEmpty) {
      final Map<String, Object?> openingFields = <String, Object?>{
        'closedAt': _timestampField(closedAt),
        'durationS': _intField(durationS),
        'status': _stringField('closed'),
      };
      if (recoveredClosure) {
        openingFields['recoveredClosure'] = _boolField(value: true);
      }
      writes.add(
        _updateWrite(
          _openingDocumentPath(door.doorId, openingId),
          openingFields,
        ),
      );
    }

    await _batchCommit(writes);
  }

  /// Reads the persisted door state. Returns null if the document does not exist.
  Future<PersistedDoorState?> loadLastState(DoorConfig door) async {
    final Map<String, dynamic>? document = await _getDocument(
      _doorDocumentPath(door.doorId),
    );
    if (document == null) {
      return null;
    }
    final Map<String, dynamic> fields =
        document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final bool isOpen = _readBool(fields, 'isOpen');
    final String? lastOpeningId = _readStringOrNull(fields, 'lastOpeningId');
    final DateTime? lastOpenedAt = _readTimestampOrNull(
      fields,
      'currentOpenedAt',
    );
    final DateTime? lastChangedAt = _readTimestampOrNull(
      fields,
      'lastChangedAt',
    );
    return PersistedDoorState(
      isOpen: isOpen,
      lastOpeningId: lastOpeningId,
      lastOpenedAt: lastOpenedAt,
      lastChangedAt: lastChangedAt,
    );
  }

  Future<void> _batchCommit(List<Map<String, Object?>> writes) async {
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
      request.write(jsonEncode(<String, Object?>{'writes': writes}));

      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FirestoreDoorOpeningsException(
          'Firestore commit failed status=${response.statusCode} body=$body',
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
        throw FirestoreDoorOpeningsException(
          'Firestore GET failed status=${response.statusCode} path=$documentPath body=$body',
        );
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> _updateWrite(
    String documentPath,
    Map<String, Object?> fields, {
    List<Map<String, Object?>> additionalTransforms =
        const <Map<String, Object?>>[],
  }) {
    return <String, Object?>{
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
        ...additionalTransforms,
      ],
    };
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

  String _doorDocumentPath(String doorId) =>
      'tenants/${config.tenantId}/sites/${config.siteId}/doors/$doorId';

  String _openingDocumentPath(String doorId, String openingId) =>
      'tenants/${config.tenantId}/sites/${config.siteId}/doors/$doorId/openings/$openingId';

  String get _effectiveProjectId =>
      config.firestoreProjectId ??
      Platform.environment['FIRESTORE_PROJECT_ID'] ??
      '';
}

class PersistedDoorState {
  const PersistedDoorState({
    required this.isOpen,
    required this.lastOpeningId,
    required this.lastOpenedAt,
    required this.lastChangedAt,
  });

  final bool isOpen;
  final String? lastOpeningId;
  final DateTime? lastOpenedAt;
  final DateTime? lastChangedAt;
}

class FirestoreDoorOpeningsException implements Exception {
  FirestoreDoorOpeningsException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Firestore field helpers
// ---------------------------------------------------------------------------

Map<String, Object?> _stringField(String value) => <String, Object?>{
  'stringValue': value,
};

Map<String, Object?> _intField(int value) => <String, Object?>{
  'integerValue': value.toString(),
};

Map<String, Object?> _boolField({required bool value}) => <String, Object?>{
  'booleanValue': value,
};

Map<String, Object?> _timestampField(DateTime value) => <String, Object?>{
  'timestampValue': value.toUtc().toIso8601String(),
};

Map<String, Object?> _nullField() => <String, Object?>{'nullValue': null};

/// Firestore fieldTransform that increments [fieldPath] by [delta].
Map<String, Object?> _incrementTransform(String fieldPath, int delta) =>
    <String, Object?>{'fieldPath': fieldPath, 'increment': _intField(delta)};

// ---------------------------------------------------------------------------
// Firestore field readers
// ---------------------------------------------------------------------------

/// Returns the string value at [key], or null if missing/empty.
String? _readStringOrNull(Map<String, dynamic> fields, String key) {
  final Object? entry = fields[key];
  if (entry is! Map) {
    return null;
  }
  final String value = (entry['stringValue'] ?? '').toString();
  return value.isEmpty ? null : value;
}

bool _readBool(Map<String, dynamic> fields, String key) {
  final Object? entry = fields[key];
  if (entry is! Map) {
    return false;
  }
  final Object? raw = entry['booleanValue'];
  if (raw is bool) {
    return raw;
  }
  return raw.toString().toLowerCase() == 'true';
}

DateTime? _readTimestampOrNull(Map<String, dynamic> fields, String key) {
  final Object? entry = fields[key];
  if (entry is! Map) {
    return null;
  }
  final Object? raw = entry['timestampValue'];
  if (raw == null) {
    return null;
  }
  return DateTime.tryParse(raw.toString())?.toUtc();
}
