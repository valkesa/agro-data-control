// Quick script to count runtimeEvents documents in Firestore.
// Usage: dart run scripts/count_runtime_events.dart
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/service_account_auth.dart';

const String _projectId = 'agro-data-control';
const String _database = '(default)';
const String _tenantId = 'the-gene-pig';
const String _siteId = 'genetica-1';
const List<String> _plcIds = <String>['munters1', 'munters2'];
const String _serviceAccountPath = 'backend/config/service-account.json';

void main() async {
  final ServiceAccountAuth auth = ServiceAccountAuth(
    serviceAccountJsonPath: _serviceAccountPath,
  );

  int totalHb = 0;
  int totalClosed = 0;

  for (final String plcId in _plcIds) {
    final String parent =
        'projects/$_projectId/databases/$_database/documents'
        '/tenants/$_tenantId/sites/$_siteId/plcs/$plcId';

    final int hb = await _count(auth, parent, isOpen: true);
    final int closed = await _count(auth, parent, isOpen: false);

    print('$plcId  →  HB: $hb   cerrados: $closed   total: ${hb + closed}');
    totalHb += hb;
    totalClosed += closed;
  }

  print('');
  print('TOTAL  →  HB: $totalHb   cerrados: $totalClosed   total: ${totalHb + totalClosed}');
}

Future<int> _count(
  ServiceAccountAuth auth,
  String parent, {
  required bool isOpen,
}) async {
  final String token = await auth.getAccessToken();
  final Uri uri = Uri.parse(
    'https://firestore.googleapis.com/v1/$parent:runAggregationQuery',
  );

  final Map<String, Object?> body = <String, Object?>{
    'structuredAggregationQuery': <String, Object?>{
      'aggregations': <Object?>[
        <String, Object?>{'count': <String, Object?>{}, 'alias': 'c'},
      ],
      'structuredQuery': <String, Object?>{
        'from': <Object?>[
          <String, Object?>{
            'collectionId': 'runtimeEvents',
            'allDescendants': false,
          },
        ],
        'where': <String, Object?>{
          'fieldFilter': <String, Object?>{
            'field': <String, Object?>{'fieldPath': 'isOpen'},
            'op': 'EQUAL',
            'value': <String, Object?>{'booleanValue': isOpen},
          },
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
    req.write(jsonEncode(body));
    final HttpClientResponse res = await req.close();
    final String responseBody = await res.transform(utf8.decoder).join();

    if (res.statusCode < 200 || res.statusCode >= 300) {
      stderr.writeln('Error ${res.statusCode}: $responseBody');
      return -1;
    }

    final List<dynamic> results = jsonDecode(responseBody) as List<dynamic>;
    if (results.isEmpty) return 0;
    final Map<String, dynamic> first = results.first as Map<String, dynamic>;
    final Map<String, dynamic>? result = first['result'] as Map<String, dynamic>?;
    if (result == null) return 0;
    final Map<String, dynamic>? aggregateFields =
        result['aggregateFields'] as Map<String, dynamic>?;
    final Map<String, dynamic>? countField =
        aggregateFields?['c'] as Map<String, dynamic>?;
    final Object? intVal = countField?['integerValue'];
    if (intVal is String) return int.tryParse(intVal) ?? 0;
    if (intVal is int) return intVal;
    return 0;
  } finally {
    client.close(force: true);
  }
}
