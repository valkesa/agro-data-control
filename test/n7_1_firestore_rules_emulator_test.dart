// N7.1 §16/§25 — Firestore Security Rules emulator test for the new N7.1
// collections (global config + per-device `settings/boardConfig`). Same
// from-scratch, dependency-free technique as
// `backend/test/alert_config_firestore_rules_emulator_test.dart` (hand-built
// unsigned JWTs the Firestore emulator accepts, raw REST PATCH/DELETE calls,
// plain-Dart-script assertions) — there is no `package:test`/
// `rules-unit-testing` dependency in this repo to reuse instead. Run with:
//   dart test/n7_1_firestore_rules_emulator_test.dart
// (requires the `firebase` CLI on PATH; starts and tears down its own
// throwaway Firestore emulator instance, never touches real Firestore).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _projectId = 'demo-n7-1-rules-test';
const int _port = 8101;
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

    await _testOwnerCanCreateGlobalConfig();
    await _testTenantAdminCannotCreateGlobalConfig();
    await _testAnyAuthenticatedUserCanReadGlobalConfig();
    await _testUnknownFieldOnBoardPresetDenied();
    await _testOwnerCanDeleteBoardPreset();
    await _testCapabilityProfileCannotBeDeleted();
    await _testTenantAdminCanWriteOwnTenantDeviceBoardConfig();
    await _testTenantAdminCannotWriteOtherTenantDeviceBoardConfig();
    await _testAnyTenantMemberCanReadDeviceBoardConfig();
    await _testDeviceIdMismatchDenied();
    await _testMissingRequiredFieldDenied();

    // ignore: avoid_print
    print('n7_1_firestore_rules_emulator_test: all expectations passed');
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
    'n7-1-rules-test-',
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

Future<void> _testOwnerCanCreateGlobalConfig() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'capabilityProfiles/sala_a',
    fields: _capabilityProfileFields(),
  );
  _expect(status == 200, 'owner can create a global capabilityProfile');
}

Future<void> _testTenantAdminCannotCreateGlobalConfig() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'capabilityProfiles/sala_b',
    fields: _capabilityProfileFields(),
  );
  _expect(status == 403, 'tenant_admin cannot write global config');
}

Future<void> _testAnyAuthenticatedUserCanReadGlobalConfig() async {
  final int status = await _getAs(
    uid: 'admin-a',
    path: 'capabilityProfiles/sala_a',
  );
  _expect(status == 200, 'any authenticated user can read global config');
}

Future<void> _testUnknownFieldOnBoardPresetDenied() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'boardPresets/preset_x',
    fields: <String, Object?>{..._boardPresetFields(), 'debug': true},
  );
  _expect(status == 403, 'unknown top-level field on boardPreset is denied');
}

Future<void> _testOwnerCanDeleteBoardPreset() async {
  final int createStatus = await _patchAs(
    uid: 'owner-uid',
    path: 'boardPresets/preset_to_delete',
    fields: _boardPresetFields(id: 'preset_to_delete'),
  );
  _expect(createStatus == 200, 'owner creates preset before delete test');
  final int deleteStatus = await _deleteAs(
    uid: 'owner-uid',
    path: 'boardPresets/preset_to_delete',
  );
  _expect(deleteStatus == 200, 'owner can delete a BoardPreset (N7.1 §10)');
}

Future<void> _testCapabilityProfileCannotBeDeleted() async {
  final int deleteStatus = await _deleteAs(
    uid: 'owner-uid',
    path: 'capabilityProfiles/sala_a',
  );
  _expect(
    deleteStatus == 403,
    'capabilityProfiles are never physically deleted',
  );
}

Future<void> _testTenantAdminCanWriteOwnTenantDeviceBoardConfig() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/tenant-a/devices/device-1/settings/boardConfig',
    fields: _boardConfigFields(deviceId: 'device-1'),
  );
  _expect(
    status == 200,
    'tenant_admin can write their own tenant device board config',
  );
}

Future<void> _testTenantAdminCannotWriteOtherTenantDeviceBoardConfig() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/tenant-b/devices/device-2/settings/boardConfig',
    fields: _boardConfigFields(deviceId: 'device-2'),
  );
  _expect(status == 403, 'tenant_admin cannot write another tenant\'s device');
}

Future<void> _testAnyTenantMemberCanReadDeviceBoardConfig() async {
  final int status = await _getAs(
    uid: 'admin-a',
    path: 'tenants/tenant-a/devices/device-1/settings/boardConfig',
  );
  _expect(
    status == 200,
    'tenant member can read their own device board config',
  );
}

Future<void> _testDeviceIdMismatchDenied() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/tenant-a/devices/device-1/settings/boardConfig',
    fields: _boardConfigFields(deviceId: 'a-different-device-id'),
  );
  _expect(status == 403, 'deviceId must match the path segment');
}

Future<void> _testMissingRequiredFieldDenied() async {
  final Map<String, Object?> fields = _boardConfigFields(deviceId: 'device-1')
    ..remove('layoutVersion');
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/tenant-a/devices/device-1/settings/boardConfig',
    fields: fields,
  );
  _expect(status == 403, 'missing required field (layoutVersion) is denied');
}

Map<String, Object?> _capabilityProfileFields() => <String, Object?>{
  'id': 'sala_a',
  'name': 'Sala A',
  'description': '',
  'enabled': true,
  'metricKeys': <Object?>[],
  'indicatorKeys': <Object?>[],
  'metricBindings': <String, Object?>{},
  'indicatorBindings': <String, Object?>{},
  'suggestedIndicatorsByMetric': <String, Object?>{},
  'profileVersion': 1,
  'createdAt': DateTime.utc(2026, 9, 19),
  'updatedAt': DateTime.utc(2026, 9, 19),
};

Map<String, Object?> _boardPresetFields({String id = 'preset_x'}) =>
    <String, Object?>{
      'id': id,
      'name': 'Preset X',
      'description': '',
      'layoutTemplateId': 'grid_6x4',
      'showTitleDefault': true,
      'titleOverride': null,
      'items': <Object?>[],
      'requiredMetricKeys': <Object?>[],
      'optionalMetricKeys': <Object?>[],
      'capabilityProfileId': null,
      'schemaVersion': 1,
      'presetVersion': 1,
      'enabled': true,
      'createdAt': DateTime.utc(2026, 9, 19),
      'updatedAt': DateTime.utc(2026, 9, 19),
    };

Map<String, Object?> _boardConfigFields({required String deviceId}) =>
    <String, Object?>{
      'deviceId': deviceId,
      'layoutTemplateId': 'grid_6x4',
      'showTitle': true,
      'titleOverride': null,
      'schemaVersion': 2,
      'layoutVersion': 1,
      'items': <Object?>[],
      'createdAt': DateTime.utc(2026, 9, 19),
      'updatedAt': DateTime.utc(2026, 9, 19),
      'capabilityProfileId': null,
      'sourceBoardPresetId': null,
      'sourceBoardPresetVersion': null,
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
