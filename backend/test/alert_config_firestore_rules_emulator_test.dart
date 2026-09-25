import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/alert_configuration_contracts.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/alert_settings_cache.dart';
import 'package:agro_data_control_backend/src/hierarchical_alert_settings.dart';

const String _projectId = 'demo-alert-config-rules-test';
const int _port = 8100;
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

    await _testOwnerValidWrite();
    await _testTenantAdminOwnTenantWrite();
    await _testTenantAdminOtherTenantDenied();
    await _testUnknownFieldDenied();
    await _testWrongTypeDenied();
    await _testInvalidAlertIdDenied();
    await _testPartialThresholdsAccepted();
    await _testExplicitFalseAccepted();
    await _testInvalidSchemaVersionDenied();
    await _testFunctionallyEmptyDocumentDenied();
    await _testSecondAdminCanUpdatePreservingCreatedBy();
    await _testSecondAdminCannotMutateCreatedBy();
    await _testSecondAdminCanUpdateOmittingCreatedBy();
    await _testOwnerCanUpdateDocumentCreatedByTenantAdmin();
    await _testDeleteAllowedOnlyForAuthorizedWriter();
    await _testB3LoaderResolverReadsDocumentsAllowedByRules();

    // ignore: avoid_print
    print(
      'alert_config_firestore_rules_emulator_test: all expectations passed',
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
    'alert-config-rules-test-',
  );
  final String rules = await File('../firestore.rules').exists()
      ? await File('../firestore.rules').readAsString()
      : await File('firestore.rules').readAsString();
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
    'activeTenantId': 'the-gene-pig',
  });
  await _adminPatch('users/admin-a', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'the-gene-pig',
  });
  await _adminPatch('users/admin-b', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'the-gene-pig',
  });
  await _adminPatch('users/admin-other', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'la-payana',
  });
  await _adminPatch('tenants/the-gene-pig/members/admin-a', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
  });
  await _adminPatch('tenants/the-gene-pig/members/admin-b', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
  });
  await _adminPatch('tenants/la-payana/members/admin-other', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
  });
}

Future<void> _testOwnerValidWrite() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertConfig/temperature_interior',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{
        'enabled': true,
        'thresholds': <String, Object?>{'max': 30.0},
      },
    ),
  );
  _expect(status == 200, 'owner can write tenant alert config');
}

Future<void> _testTenantAdminOwnTenantWrite() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/the-gene-pig/sites/las-heras/alertConfig/high_humidity',
    fields: _alertConfigFields(
      updatedBy: 'admin-a',
      overrides: <String, Object?>{
        'thresholds': <String, Object?>{'max': 88.0},
      },
    ),
  );
  _expect(status == 200, 'tenant_admin can write own tenant alert config');
}

Future<void> _testTenantAdminOtherTenantDenied() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/la-payana/alertConfig/temperature_interior',
    fields: _alertConfigFields(
      updatedBy: 'admin-a',
      overrides: <String, Object?>{'enabled': true},
    ),
  );
  _expect(status == 403, 'tenant_admin cannot write another tenant');
}

Future<void> _testUnknownFieldDenied() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertConfig/high_humidity',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{'enabled': true, 'debug': true},
    ),
  );
  _expect(status == 403, 'unknown top-level field is denied');
}

Future<void> _testWrongTypeDenied() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertConfig/high_humidity',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{
        'thresholds': <String, Object?>{'max': '28'},
      },
    ),
  );
  _expect(status == 403, 'wrong threshold type is denied');
}

Future<void> _testInvalidAlertIdDenied() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertConfig/not_a_real_alert',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{'enabled': true},
    ),
  );
  _expect(status == 403, 'invalid alertId is denied');
}

Future<void> _testPartialThresholdsAccepted() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path:
        'tenants/the-gene-pig/devices/munters1/alertConfig/temperature_interior',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{
        'thresholds': <String, Object?>{'max': 28.0},
      },
    ),
  );
  _expect(status == 200, 'partial thresholds are accepted');
}

Future<void> _testExplicitFalseAccepted() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path:
        'tenants/the-gene-pig/devices/munters1/rooms/room_1/alertConfig/temperature_interior',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{'whatsappEnabled': false},
    ),
  );
  _expect(status == 200, 'explicit false is accepted');
}

Future<void> _testInvalidSchemaVersionDenied() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertConfig/room_door_open',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      schemaVersion: 2,
      overrides: <String, Object?>{'enabled': true},
    ),
  );
  _expect(status == 403, 'unsupported schemaVersion is denied');
}

Future<void> _testFunctionallyEmptyDocumentDenied() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertConfig/room_door_open',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: const <String, Object?>{},
    ),
  );
  _expect(status == 403, 'functionally empty alert config doc is denied');
}

Future<void> _testSecondAdminCanUpdatePreservingCreatedBy() async {
  const String path = 'tenants/the-gene-pig/alertConfig/munters_door_open';
  final int createStatus = await _patchAs(
    uid: 'admin-a',
    path: path,
    fields: _alertConfigFields(
      updatedBy: 'admin-a',
      createdBy: 'admin-a',
      overrides: <String, Object?>{'enabled': true},
    ),
  );
  _expect(createStatus == 200, 'admin-a can create alert config');

  final int updateStatus = await _patchAs(
    uid: 'admin-b',
    path: path,
    fields: _alertConfigFields(
      updatedBy: 'admin-b',
      createdBy: 'admin-a',
      overrides: <String, Object?>{'enabled': true, 'whatsappDelayMinutes': 7},
    ),
  );
  _expect(
    updateStatus == 200,
    'admin-b can update preserving admin-a createdBy',
  );
}

Future<void> _testSecondAdminCannotMutateCreatedBy() async {
  const String path = 'tenants/the-gene-pig/alertConfig/room_door_open';
  final int createStatus = await _patchAs(
    uid: 'admin-a',
    path: path,
    fields: _alertConfigFields(
      updatedBy: 'admin-a',
      createdBy: 'admin-a',
      overrides: <String, Object?>{'enabled': true},
    ),
  );
  _expect(createStatus == 200, 'admin-a creates immutable createdBy fixture');

  final int updateStatus = await _patchAs(
    uid: 'admin-b',
    path: path,
    fields: _alertConfigFields(
      updatedBy: 'admin-b',
      createdBy: 'admin-b',
      overrides: <String, Object?>{'enabled': false},
    ),
  );
  _expect(updateStatus == 403, 'admin-b cannot mutate createdBy');
}

Future<void> _testSecondAdminCanUpdateOmittingCreatedBy() async {
  const String path = 'tenants/the-gene-pig/alertConfig/sensor_failure';
  final int createStatus = await _patchAs(
    uid: 'admin-a',
    path: path,
    fields: _alertConfigFields(
      updatedBy: 'admin-a',
      createdBy: 'admin-a',
      overrides: <String, Object?>{'visualEnabled': true},
    ),
  );
  _expect(createStatus == 200, 'admin-a creates omit-createdBy fixture');

  final int updateStatus = await _patchAs(
    uid: 'admin-b',
    path: path,
    fields: _alertConfigFields(
      updatedBy: 'admin-b',
      includeCreatedBy: false,
      overrides: <String, Object?>{'visualEnabled': false},
    ),
  );
  _expect(updateStatus == 200, 'admin-b can update omitting createdBy');
}

Future<void> _testOwnerCanUpdateDocumentCreatedByTenantAdmin() async {
  const String path =
      'tenants/the-gene-pig/alertConfig/high_temperature_heating_active';
  final int createStatus = await _patchAs(
    uid: 'admin-a',
    path: path,
    fields: _alertConfigFields(
      updatedBy: 'admin-a',
      createdBy: 'admin-a',
      overrides: <String, Object?>{'order': 4},
    ),
  );
  _expect(createStatus == 200, 'tenant admin creates owner update fixture');

  final int updateStatus = await _patchAs(
    uid: 'owner-uid',
    path: path,
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      createdBy: 'admin-a',
      overrides: <String, Object?>{'order': 5},
    ),
  );
  _expect(
    updateStatus == 200,
    'owner can update preserving tenant admin createdBy',
  );
}

Future<void> _testDeleteAllowedOnlyForAuthorizedWriter() async {
  const String path =
      'tenants/the-gene-pig/devices/munters1/alertConfig/high_differential_pressure';
  final int createStatus = await _patchAs(
    uid: 'owner-uid',
    path: path,
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{'cooldownMinutes': 10},
    ),
  );
  _expect(createStatus == 200, 'owner creates document before delete test');
  final int denied = await _deleteAs(uid: 'admin-other', path: path);
  _expect(denied == 403, 'tenant_admin from another tenant cannot delete');
  final int allowed = await _deleteAs(uid: 'admin-a', path: path);
  _expect(allowed == 200, 'tenant_admin from own tenant can delete');
}

Future<void> _testB3LoaderResolverReadsDocumentsAllowedByRules() async {
  await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertConfig/temperature_interior',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{
        'enabled': true,
        'whatsappEnabled': true,
        'thresholds': <String, Object?>{'min': 20.0, 'max': 30.0},
      },
    ),
  );
  await _patchAs(
    uid: 'owner-uid',
    path:
        'tenants/the-gene-pig/sites/las-heras/alertConfig/temperature_interior',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{
        'thresholds': <String, Object?>{'max': 28.0},
      },
    ),
  );
  await _patchAs(
    uid: 'owner-uid',
    path:
        'tenants/the-gene-pig/devices/munters1/rooms/room_1/alertConfig/temperature_interior',
    fields: _alertConfigFields(
      updatedBy: 'owner-uid',
      overrides: <String, Object?>{'whatsappEnabled': false},
    ),
  );

  const AlertConfigurationTarget target = AlertConfigurationTarget(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    scope: AlertConfigurationScope.room,
    deviceId: 'munters1',
    roomId: 'room_1',
    snapshotUnitKey: 'munters1',
    muntersId: 'munters1',
  );
  final HierarchicalAlertConfigSnapshot snapshot = await _loaderFor(
    'owner-uid',
  ).load(target);
  final EffectiveAlertConfiguration effective =
      const HierarchicalAlertConfigResolver().resolve(
        target: target,
        modern: snapshot,
        legacy: _legacySettings(),
      );
  final EffectiveAlertConfig temperature = effective.configFor(
    AlertType.temperatureInterior,
  );
  final EffectiveAlertConfig dewPoint = effective.configFor(
    AlertType.dewPointRisk,
  );
  _expect(temperature.thresholds.min == 20.0, 'tenant min resolved');
  _expect(temperature.thresholds.max == 28.0, 'site max override resolved');
  _expect(!temperature.whatsappEnabled, 'room explicit false resolved');
  _expect(
    temperature.fieldOrigins['whatsappEnabled'] == AlertConfigOrigin.room,
    'room field origin preserved',
  );
  _expect(
    dewPoint.origin == AlertConfigOrigin.legacy,
    'unmigrated alert still falls back to legacy',
  );
}

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

Map<String, Object?> _alertConfigFields({
  required String updatedBy,
  required Map<String, Object?> overrides,
  String? createdBy,
  bool includeCreatedBy = true,
  int schemaVersion = 1,
}) {
  return <String, Object?>{
    'schemaVersion': schemaVersion,
    ...overrides,
    'updatedAt': DateTime.utc(2026, 9, 7, 12),
    'updatedBy': updatedBy,
    if (includeCreatedBy) 'createdBy': createdBy ?? updatedBy,
  };
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

FirestoreHierarchicalAlertConfigLoader _loaderFor(String uid) {
  return FirestoreHierarchicalAlertConfigLoader(
    projectId: _projectId,
    databaseId: '(default)',
    serviceAccountJsonPath: 'unused-in-emulator-mode',
    baseUrl: _baseUrl,
    accessTokenProvider: () async => _jwt(uid),
  );
}

CachedAlertSettings _legacySettings() {
  return CachedAlertSettings.fromRaw(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    raw: <String, Object?>{
      'alerts': <String, Object?>{
        'dewPointRisk': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': true,
          'order': 9,
        },
      },
      'munters': <String, Object?>{
        'munters1': <String, Object?>{
          'dewPointMargin': <String, Object?>{
            'alarm': <String, Object?>{'redMaxInclusive': 2.5},
          },
        },
      },
    },
    loadedAt: DateTime.utc(2026, 9, 7),
    source: 'legacy-test',
  );
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
