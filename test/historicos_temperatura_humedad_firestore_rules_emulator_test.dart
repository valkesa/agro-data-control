// Prompt_Historicos_Temperatura_Humedad_por_Device §17/§19/§25 — Firestore
// Security Rules emulator test for the new per-Device
// `historyHourly`/`historyDaily` subcollections. Same from-scratch,
// dependency-free technique as `test/n7_1_firestore_rules_emulator_test.dart`
// (hand-built unsigned JWTs the Firestore emulator accepts, raw REST
// PATCH/GET calls, plain-Dart-script assertions) — there is no
// `package:test`/`rules-unit-testing` dependency in this repo to reuse
// instead. Run with:
//   dart test/historicos_temperatura_humedad_firestore_rules_emulator_test.dart
// (requires the `firebase` CLI on PATH; starts and tears down its own
// throwaway Firestore emulator instance, never touches real Firestore).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _projectId = 'demo-historicos-rules-test';
const int _port = 8102;
const String _baseUrl = 'http://127.0.0.1:$_port';

Future<void> main() async {
  final Directory emulatorProjectDir = await _writeEmulatorProject();
  final StringBuffer emulatorLog = StringBuffer();
  Process? emulatorProcess;

  try {
    emulatorProcess = await _startEmulator(emulatorProjectDir, emulatorLog);
    await _waitForReady(emulatorLog);
    await _waitForRestApi();
    await _seedAuthContext();
    await _seedHistoryDocuments();

    await _testTenantMemberCanReadOwnTenantHourly();
    await _testTenantMemberCanReadOwnTenantDaily();
    await _testOtherTenantCannotReadHourly();
    await _testUnauthenticatedCannotReadHourly();
    await _testOwnerCanRead();
    await _testClientCannotCreateHourlyEvenAsOwner();
    await _testClientCannotUpdateDailyEvenAsOwner();
    await _testClientCannotDeleteHourlyEvenAsOwner();
    await _testTenantAdminCannotWriteHourly();

    // ignore: avoid_print
    print(
      'historicos_temperatura_humedad_firestore_rules_emulator_test: all expectations passed',
    );
  } finally {
    if (emulatorProcess != null) {
      emulatorProcess.kill(ProcessSignal.sigterm);
      try {
        await emulatorProcess.exitCode.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        emulatorProcess.kill(ProcessSignal.sigkill);
      }
    }
    if (await emulatorProjectDir.exists()) {
      await emulatorProjectDir.delete(recursive: true);
    }
  }
}

Future<Directory> _writeEmulatorProject() async {
  final Directory dir = await Directory.systemTemp.createTemp(
    'historicos-rules-test-',
  );
  final String rules = await File('firestore.rules').readAsString();
  await File('${dir.path}/firestore.rules').writeAsString(rules);
  await File('${dir.path}/firebase.json').writeAsString(
    jsonEncode(<String, Object?>{
      'firestore': <String, Object?>{'rules': 'firestore.rules'},
      'emulators': <String, Object?>{
        'firestore': <String, Object?>{'port': _port},
      },
    }),
  );
  return dir;
}

Future<Process> _startEmulator(Directory projectDir, StringBuffer log) async {
  final Process process = await Process.start('firebase', <String>[
    'emulators:start',
    '--only',
    'firestore',
    '--project',
    _projectId,
  ], workingDirectory: projectDir.path);
  process.stdout.transform(utf8.decoder).listen(log.write);
  process.stderr.transform(utf8.decoder).listen(log.write);
  return process;
}

Future<void> _waitForReady(StringBuffer log) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (log.toString().contains('All emulators ready')) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError(
    'Firestore emulator did not report ready within 90s.\n--- emulator log ---\n$log',
  );
}

Future<void> _waitForRestApi() async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
  final HttpClient client = HttpClient();
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final HttpClientRequest request = await client.getUrl(
          Uri.parse(
            '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/tenants',
          ),
        );
        final HttpClientResponse response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200 || response.statusCode == 403) return;
      } catch (_) {
        // Keep polling.
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  } finally {
    client.close(force: true);
  }
  throw StateError('Firestore emulator REST API never became reachable.');
}

Future<void> _seedAuthContext() async {
  await _adminPatch('users/owner-uid', <String, Object?>{
    'active': true,
    'role': 'owner',
    'activeTenantId': 'tenant-a',
  });
  await _adminPatch('users/admin-a', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'tenant-a',
  });
  await _adminPatch('users/admin-b', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'tenant-b',
  });
  await _adminPatch('tenants/tenant-a/members/admin-a', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
  });
  await _adminPatch('tenants/tenant-b/members/admin-b', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
  });
}

/// Seeded directly with the admin bypass (`Bearer owner`) — simulates the
/// backend's own Google service-account writes, which never go through
/// these rules at all (§17: "backend/admin escribe").
Future<void> _seedHistoryDocuments() async {
  await _adminPatch(
    'tenants/tenant-a/devices/sala1/historyHourly/2026-09-24T10',
    _hourlyFields(),
  );
  await _adminPatch(
    'tenants/tenant-a/devices/sala1/historyDaily/2026-09-24',
    _dailyFields(),
  );
}

Future<void> _testTenantMemberCanReadOwnTenantHourly() async {
  final int status = await _getAs(
    uid: 'admin-a',
    path: 'tenants/tenant-a/devices/sala1/historyHourly/2026-09-24T10',
  );
  _expect(status == 200, 'tenant-a member can read tenant-a Device history');
}

Future<void> _testTenantMemberCanReadOwnTenantDaily() async {
  final int status = await _getAs(
    uid: 'admin-a',
    path: 'tenants/tenant-a/devices/sala1/historyDaily/2026-09-24',
  );
  _expect(status == 200, 'tenant-a member can read tenant-a daily history');
}

Future<void> _testOtherTenantCannotReadHourly() async {
  final int status = await _getAs(
    uid: 'admin-b',
    path: 'tenants/tenant-a/devices/sala1/historyHourly/2026-09-24T10',
  );
  _expect(status == 403, 'tenant-b member cannot read tenant-a Device history');
}

Future<void> _testUnauthenticatedCannotReadHourly() async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(
      _docUri('tenants/tenant-a/devices/sala1/historyHourly/2026-09-24T10'),
    );
    // No Authorization header at all.
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    _expect(
      response.statusCode == 403,
      'a request with no auth token at all cannot read Device history',
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _testOwnerCanRead() async {
  final int status = await _getAs(
    uid: 'owner-uid',
    path: 'tenants/tenant-a/devices/sala1/historyHourly/2026-09-24T10',
  );
  _expect(status == 200, 'owner can read any tenant\'s Device history');
}

Future<void> _testClientCannotCreateHourlyEvenAsOwner() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/tenant-a/devices/sala1/historyHourly/2026-09-24T11',
    fields: _hourlyFields(),
  );
  _expect(
    status == 403,
    '§17 — Flutter client never writes históricos, not even as owner; '
    'only the backend service account (IAM, bypasses these rules) does',
  );
}

Future<void> _testClientCannotUpdateDailyEvenAsOwner() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/tenant-a/devices/sala1/historyDaily/2026-09-24',
    fields: _dailyFields(),
  );
  _expect(status == 403, 'client update of an existing daily doc is denied');
}

Future<void> _testClientCannotDeleteHourlyEvenAsOwner() async {
  final int status = await _deleteAs(
    uid: 'owner-uid',
    path: 'tenants/tenant-a/devices/sala1/historyHourly/2026-09-24T10',
  );
  _expect(status == 403, 'client delete of a hourly doc is denied');
}

Future<void> _testTenantAdminCannotWriteHourly() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/tenant-a/devices/sala1/historyHourly/2026-09-24T12',
    fields: _hourlyFields(),
  );
  _expect(status == 403, 'tenant_admin cannot write history either');
}

Map<String, Object?> _hourlyFields() => <String, Object?>{
  'tenantId': 'tenant-a',
  'siteId': 'site-a',
  'deviceId': 'sala1',
  'periodStart': DateTime.utc(2026, 9, 24, 13, 0),
  'periodEnd': DateTime.utc(2026, 9, 24, 14, 0),
  'schemaVersion': 1,
  'createdAt': DateTime.utc(2026, 9, 24, 14, 0),
  'temperature': <String, Object?>{
    'avg': 21.0,
    'min': 20.0,
    'max': 22.0,
    'sampleCount': 3,
  },
  'humidity': <String, Object?>{
    'avg': 60.0,
    'min': 55.0,
    'max': 65.0,
    'sampleCount': 3,
  },
};

Map<String, Object?> _dailyFields() => <String, Object?>{
  'tenantId': 'tenant-a',
  'siteId': 'site-a',
  'deviceId': 'sala1',
  'periodStart': DateTime.utc(2026, 9, 24, 3, 0),
  'periodEnd': DateTime.utc(2026, 9, 25, 3, 0),
  'schemaVersion': 1,
  'createdAt': DateTime.utc(2026, 9, 24, 14, 0),
  'temperature': <String, Object?>{
    'avg': 21.0,
    'min': 20.0,
    'max': 22.0,
    'sampleCount': 3,
  },
  'humidity': <String, Object?>{
    'avg': 60.0,
    'min': 55.0,
    'max': 65.0,
    'sampleCount': 3,
  },
};

Future<void> _adminPatch(String path, Map<String, Object?> fields) async {
  final int status = await _write(
    method: 'PATCH',
    path: path,
    fields: fields,
    bearer: 'owner',
  );
  if (status != 200) {
    throw StateError('Admin seed failed for $path status=$status');
  }
}

Future<int> _patchAs({
  required String uid,
  required String path,
  required Map<String, Object?> fields,
}) {
  return _write(method: 'PATCH', path: path, fields: fields, bearer: _jwt(uid));
}

Future<int> _getAs({required String uid, required String path}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(_docUri(path));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_jwt(uid)}');
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<int> _deleteAs({required String uid, required String path}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.deleteUrl(_docUri(path));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_jwt(uid)}');
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<int> _write({
  required String method,
  required String path,
  required Map<String, Object?> fields,
  required String bearer,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = method == 'PATCH'
        ? await client.patchUrl(_docUri(path))
        : await client.postUrl(_docUri(path));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    request.write(
      jsonEncode(<String, Object?>{
        'fields': <String, Object?>{
          for (final MapEntry<String, Object?> entry in fields.entries)
            entry.key: _encodeFirestoreValue(entry.value),
        },
      }),
    );
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Uri _docUri(String path) {
  return Uri.parse(
    '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/$path',
  );
}

Map<String, Object?> _encodeFirestoreValue(Object? value) {
  if (value == null) return <String, Object?>{'nullValue': null};
  if (value is bool) return <String, Object?>{'booleanValue': value};
  if (value is int) return <String, Object?>{'integerValue': value.toString()};
  if (value is double) return <String, Object?>{'doubleValue': value};
  if (value is String) return <String, Object?>{'stringValue': value};
  if (value is DateTime) {
    return <String, Object?>{'timestampValue': value.toUtc().toIso8601String()};
  }
  if (value is List) {
    return <String, Object?>{
      'arrayValue': <String, Object?>{
        'values': value.map(_encodeFirestoreValue).toList(),
      },
    };
  }
  if (value is Map) {
    return <String, Object?>{
      'mapValue': <String, Object?>{
        'fields': <String, Object?>{
          for (final MapEntry<Object?, Object?> entry in value.entries)
            entry.key.toString(): _encodeFirestoreValue(entry.value),
        },
      },
    };
  }
  throw ArgumentError.value(value, 'value', 'Unsupported Firestore value type');
}

String _jwt(String uid) {
  final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final String header = _base64UrlJson(<String, Object?>{
    'alg': 'none',
    'typ': 'JWT',
  });
  final String payload = _base64UrlJson(<String, Object?>{
    'iss': 'https://securetoken.google.com/$_projectId',
    'aud': _projectId,
    'auth_time': now,
    'iat': now,
    'exp': now + 3600,
    'sub': uid,
    'user_id': uid,
    'firebase': <String, Object?>{'sign_in_provider': 'custom'},
  });
  return '$header.$payload.';
}

String _base64UrlJson(Map<String, Object?> value) {
  return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
