// Cleans up redundant HB documents in Firestore.
//
// Logic:
//   For each event (plcId + deviceType + startedAt), keep only the HB with
//   the highest activeDurationSec (= the most recent snapshot of that event).
//   All earlier HBs for the same event are deleted — they add no information
//   that the latest one doesn't already contain.
//
//   OFF heartbeats (deviceIsOn=false, durationSec=0) are grouped by
//   (plcId + deviceType) and only the most recent one per device is kept.
//
// Usage: dart run scripts/cleanup_hb_records.dart [--dry-run]
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/service_account_auth.dart';

const String _projectId = 'agro-data-control';
const String _database = '(default)';
const String _tenantId = 'the-gene-pig';
const String _siteId = 'genetica-1';
const List<String> _plcIds = <String>['munters1', 'munters2'];
const String _serviceAccountPath = 'backend/config/service-account.json';

void main(List<String> args) async {
  final bool dryRun = args.contains('--dry-run');
  if (dryRun) print('=== DRY RUN — no documents will be deleted ===\n');

  final ServiceAccountAuth auth = ServiceAccountAuth(
    serviceAccountJsonPath: _serviceAccountPath,
  );

  final List<String> toDelete = <String>[];

  for (final String plcId in _plcIds) {
    final String collectionPath =
        'tenants/$_tenantId/sites/$_siteId/plcs/$plcId/runtimeEvents';

    // Fetch all HB documents for this PLC.
    final List<Map<String, dynamic>> docs =
        await _fetchAllHbDocs(auth, collectionPath);

    print('$plcId: fetched ${docs.length} HB documents');

    // ── Group ON HBs by (deviceType + startedAt) ──────────────────────────
    // Keep the one with the highest activeDurationSec per group.
    final Map<String, Map<String, dynamic>> bestOnHb =
        <String, Map<String, dynamic>>{};

    // ── Group OFF HBs by deviceType ───────────────────────────────────────
    // Keep the most recent (latest observedAt) per device.
    final Map<String, Map<String, dynamic>> bestOffHb =
        <String, Map<String, dynamic>>{};

    for (final Map<String, dynamic> doc in docs) {
      final bool deviceIsOn = doc['deviceIsOn'] as bool? ?? true;
      final String deviceType = doc['deviceType'] as String? ?? '';

      if (!deviceIsOn) {
        // OFF HB: group by deviceType
        final Map<String, dynamic>? existing = bestOffHb[deviceType];
        if (existing == null) {
          bestOffHb[deviceType] = doc;
        } else {
          final DateTime obsNew = _parseTs(doc['observedAt']);
          final DateTime obsOld = _parseTs(existing['observedAt']);
          if (obsNew.isAfter(obsOld)) bestOffHb[deviceType] = doc;
        }
      } else {
        // ON HB: group by deviceType + startedAt
        final String startedAtKey = _tsKey(doc['startedAt']);
        final String groupKey = '$deviceType::$startedAtKey';
        final Map<String, dynamic>? existing = bestOnHb[groupKey];
        if (existing == null) {
          bestOnHb[groupKey] = doc;
        } else {
          final int durNew = doc['activeDurationSec'] as int? ?? 0;
          final int durOld = existing['activeDurationSec'] as int? ?? 0;
          if (durNew > durOld) bestOnHb[groupKey] = doc;
        }
      }
    }

    // Collect names to keep.
    final Set<String> keepNames = <String>{
      ...bestOnHb.values.map((Map<String, dynamic> d) => d['_name'] as String),
      ...bestOffHb.values.map((Map<String, dynamic> d) => d['_name'] as String),
    };

    int kept = 0;
    int deleted = 0;
    for (final Map<String, dynamic> doc in docs) {
      final String name = doc['_name'] as String;
      if (keepNames.contains(name)) {
        kept++;
      } else {
        toDelete.add(name);
        deleted++;
      }
    }

    print(
      '$plcId: keeping $kept, deleting $deleted\n'
      '  ON groups kept:  ${bestOnHb.length}\n'
      '  OFF groups kept: ${bestOffHb.length}',
    );
    print('');
  }

  print('Total documents to delete: ${toDelete.length}');
  if (toDelete.isEmpty) {
    print('Nothing to do.');
    return;
  }

  if (dryRun) {
    print('\nDry run — skipping deletion.');
    return;
  }

  // Batch delete in chunks of 500 (Firestore limit per commit).
  const int chunkSize = 500;
  int deleted = 0;
  for (int i = 0; i < toDelete.length; i += chunkSize) {
    final List<String> chunk = toDelete.sublist(
      i,
      (i + chunkSize).clamp(0, toDelete.length),
    );
    await _batchDelete(auth, chunk);
    deleted += chunk.length;
    print('Deleted $deleted / ${toDelete.length}...');
  }

  print('\nDone. Deleted ${toDelete.length} documents.');
}

// ── Firestore helpers ─────────────────────────────────────────────────────────

Future<List<Map<String, dynamic>>> _fetchAllHbDocs(
  ServiceAccountAuth auth,
  String collectionPath,
) async {
  final List<Map<String, dynamic>> all = <Map<String, dynamic>>[];
  final String parent =
      'projects/$_projectId/databases/$_database/documents/$collectionPath';
  // Use runQuery with a filter on isOpen=true.
  final String queryParent = parent.substring(0, parent.lastIndexOf('/'));
  final String collectionId = collectionPath.split('/').last;

  String? pageToken;
  do {
    final String token = await auth.getAccessToken();
    final Uri uri = Uri.parse(
      'https://firestore.googleapis.com/v1/$queryParent:runQuery',
    );

    final Map<String, Object?> query = <String, Object?>{
      'structuredQuery': <String, Object?>{
        'from': <Object?>[
          <String, Object?>{
            'collectionId': collectionId,
            'allDescendants': false,
          },
        ],
        'where': <String, Object?>{
          'fieldFilter': <String, Object?>{
            'field': <String, Object?>{'fieldPath': 'isOpen'},
            'op': 'EQUAL',
            'value': <String, Object?>{'booleanValue': true},
          },
        },
      },
    };

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.postUrl(uri);
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.contentTypeHeader, 'application/json');
      req.write(jsonEncode(query));
      final HttpClientResponse res = await req.close();
      final String body = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('runQuery failed ${res.statusCode}: $body');
      }

      final List<dynamic> rows = jsonDecode(body) as List<dynamic>;
      pageToken = null; // runQuery doesn't paginate like listDocuments

      for (final dynamic row in rows) {
        final Map<String, dynamic>? doc =
            (row as Map<String, dynamic>)['document'] as Map<String, dynamic>?;
        if (doc == null) continue;
        final Map<String, dynamic> fields =
            doc['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
        all.add(<String, dynamic>{
          '_name': doc['name'] as String,
          'deviceType': _extractString(fields['deviceType']),
          'deviceIsOn': _extractBool(fields['deviceIsOn']),
          'startedAt': fields['startedAt'],
          'observedAt': fields['observedAt'],
          'activeDurationSec': _extractInt(fields['activeDurationSec']),
        });
      }
    } finally {
      client.close(force: true);
    }
  } while (pageToken != null);

  return all;
}

Future<void> _batchDelete(ServiceAccountAuth auth, List<String> names) async {
  final String token = await auth.getAccessToken();
  final Uri uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$_projectId'
    '/databases/$_database/documents:commit',
  );

  final List<Object?> writes = names
      .map(
        (String name) => <String, Object?>{
          'delete': name,
        },
      )
      .toList();

  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest req = await client.postUrl(uri);
    req.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.contentTypeHeader, 'application/json');
    req.write(jsonEncode(<String, Object?>{'writes': writes}));
    final HttpClientResponse res = await req.close();
    final String body = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('batch delete failed ${res.statusCode}: $body');
    }
  } finally {
    client.close(force: true);
  }
}

// ── Field extractors ──────────────────────────────────────────────────────────

String? _extractString(Object? field) {
  if (field is Map) return field['stringValue'] as String?;
  return null;
}

bool? _extractBool(Object? field) {
  if (field is Map) return field['booleanValue'] as bool?;
  return null;
}

int? _extractInt(Object? field) {
  if (field is Map) {
    final Object? v = field['integerValue'];
    if (v is String) return int.tryParse(v);
    if (v is int) return v;
  }
  return null;
}

DateTime _parseTs(Object? field) {
  if (field is Map) {
    final Object? v = field['timestampValue'];
    if (v is String) return DateTime.parse(v);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

String _tsKey(Object? field) {
  return _parseTs(field).toUtc().toIso8601String();
}
