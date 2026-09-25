// Etapa B5 §40 — Verificación end-to-end de `alertRecipients` contra un
// Firestore Emulator real, cargado con el `firestore.rules` real (Etapa
// B4.5). Mismo patrón que `verify_hierarchical_alert_config_emulator.dart`:
// script Dart puro (dart:io + HttpClient), sin cloud_firestore/Flutter.
//
// A diferencia de `alertConfig`, `alertRecipients` no tiene campos
// anidados que fusionar campo a campo — todo (`displayName`, `phoneE164`,
// `enabled`) es top-level, así que un `.set(merge:true)`/`.update()` con
// esas claves ya es seguro sin necesidad de field-paths punteados. Este
// script se enfoca en lo que SÍ es específico de recipients: agregar,
// editar, deshabilitar, eliminar, aislamiento entre Device/Tenant, y el
// fixture obligatorio Enzo/Mauro a nivel Device (Etapa B5 §28).
//
// Uso:
//   dart run tool/verify_hierarchical_alert_recipients_emulator.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _projectId = 'demo-b5-alert-recipients-verify';
const int _port = 8131;
const String _baseUrl = 'http://127.0.0.1:$_port';

int _passed = 0;
int _failed = 0;

Future<void> main() async {
  final Directory dir = await Directory.systemTemp.createTemp(
    'b5-alert-recipients-verify-',
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

  final StringBuffer log = StringBuffer();
  final Process process = await Process.start('firebase', <String>[
    'emulators:start',
    '--only',
    'firestore',
    '--project',
    _projectId,
  ], workingDirectory: dir.path);
  process.stdout.transform(utf8.decoder).listen(log.write);
  process.stderr.transform(utf8.decoder).listen(log.write);

  try {
    await _waitForReady(log);
    await _seedAuthContext();

    await _testAgregarEditarDeshabilitarEliminar();
    await _testEnzoMauroEnDeviceLaboratorio();
    await _testOtroDeviceNoRecibeEnzoMauro();
    await _testCreatedByPreservadoEnEdicion();

    stdout.writeln('\n=== RESULTADO: $_passed OK, $_failed FALLOS ===');
    if (_failed > 0) exit(1);
  } finally {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 15));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

Future<void> _testAgregarEditarDeshabilitarEliminar() async {
  const String path = 'tenants/the-gene-pig/alertRecipients/5491111111111';
  final int createStatus = await _writeAsAdmin(
    'admin-a',
    path,
    {
      'displayName': 'Responsable Tenant',
      'phoneE164': '+5491111111111',
      'enabled': true,
      'createdBy': 'admin-a',
    },
    updateMask: [
      'schemaVersion',
      'displayName',
      'phoneE164',
      'enabled',
      'updatedAt',
      'updatedBy',
      'createdAt',
      'createdBy',
    ],
  );
  _check('agregar recipient -> 200', createStatus == 200);

  final int editStatus = await _writeAsAdmin(
    'admin-a',
    path,
    {'displayName': 'Responsable Tenant (editado)'},
    updateMask: ['schemaVersion', 'displayName', 'updatedAt', 'updatedBy'],
  );
  _check('editar displayName -> 200', editStatus == 200);
  Map<String, Object?>? doc = await _read(path);
  _check(
    'displayName editado',
    doc?['displayName'] == 'Responsable Tenant (editado)',
  );
  _check(
    'phoneE164 no se tocó al editar solo el nombre',
    doc?['phoneE164'] == '+5491111111111',
  );

  final int disableStatus = await _writeAsAdmin(
    'admin-a',
    path,
    {'enabled': false},
    updateMask: ['schemaVersion', 'enabled', 'updatedAt', 'updatedBy'],
  );
  _check(
    'deshabilitar -> 200 (acción normal, reversible)',
    disableStatus == 200,
  );
  doc = await _read(path);
  _check('enabled=false persiste', doc?['enabled'] == false);

  final int deleteStatus = await _deleteAsAdmin('admin-a', path);
  _check('eliminar -> 200 (acción administrativa)', deleteStatus == 200);
  doc = await _read(path);
  _check('el documento ya no existe tras eliminar', doc == null);
}

Future<void> _testEnzoMauroEnDeviceLaboratorio() async {
  const String enzoPath =
      'tenants/the-gene-pig/devices/laboratorio/alertRecipients/enzo';
  const String mauroPath =
      'tenants/the-gene-pig/devices/laboratorio/alertRecipients/mauro';
  final int enzoStatus = await _writeAsAdmin(
    'admin-a',
    enzoPath,
    {
      'displayName': 'Enzo',
      'phoneE164': '+5491123040959',
      'enabled': true,
      'createdBy': 'admin-a',
    },
    updateMask: [
      'schemaVersion',
      'displayName',
      'phoneE164',
      'enabled',
      'updatedAt',
      'updatedBy',
      'createdAt',
      'createdBy',
    ],
  );
  final int mauroStatus = await _writeAsAdmin(
    'admin-a',
    mauroPath,
    {
      'displayName': 'Mauro',
      'phoneE164': '+5492227516703',
      'enabled': true,
      'createdBy': 'admin-a',
    },
    updateMask: [
      'schemaVersion',
      'displayName',
      'phoneE164',
      'enabled',
      'updatedAt',
      'updatedBy',
      'createdAt',
      'createdBy',
    ],
  );
  _check(
    'Enzo creado en Device Laboratorio -> 200 (Etapa B5 §28)',
    enzoStatus == 200,
  );
  _check(
    'Mauro creado en Device Laboratorio -> 200 (Etapa B5 §28)',
    mauroStatus == 200,
  );
  final Map<String, Object?>? enzoDoc = await _read(enzoPath);
  final Map<String, Object?>? mauroDoc = await _read(mauroPath);
  _check('Enzo con teléfono real', enzoDoc?['phoneE164'] == '+5491123040959');
  _check('Mauro con teléfono real', mauroDoc?['phoneE164'] == '+5492227516703');
}

Future<void> _testOtroDeviceNoRecibeEnzoMauro() async {
  const String path =
      'tenants/the-gene-pig/devices/otro-device/alertRecipients/enzo';
  final Map<String, Object?>? doc = await _read(path);
  _check(
    'otro Device no tiene el documento de Enzo (aislamiento por colección)',
    doc == null,
  );
}

Future<void> _testCreatedByPreservadoEnEdicion() async {
  const String path = 'tenants/the-gene-pig/alertRecipients/audit-check';
  await _writeAsAdmin(
    'admin-a',
    path,
    {
      'displayName': 'Audit Check',
      'phoneE164': '+5491199999999',
      'enabled': true,
      'createdBy': 'admin-a',
    },
    updateMask: [
      'schemaVersion',
      'displayName',
      'phoneE164',
      'enabled',
      'updatedAt',
      'updatedBy',
      'createdAt',
      'createdBy',
    ],
  );
  final int status = await _writeAsAdmin(
    'admin-b',
    path,
    {'enabled': false},
    updateMask: ['schemaVersion', 'enabled', 'updatedAt', 'updatedBy'],
  );
  _check('otro admin del mismo tenant puede editar -> 200', status == 200);
  final Map<String, Object?>? doc = await _read(path);
  _check(
    'createdBy preservado (admin-a), aunque editó admin-b',
    doc?['createdBy'] == 'admin-a',
  );
  _check('updatedBy pasa a admin-b', doc?['updatedBy'] == 'admin-b');
}

// ── Infra HTTP mínima contra el emulador ──────────────────────────────────

Future<void> _waitForReady(StringBuffer log) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (log.toString().contains('All emulators ready')) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('Firestore emulator no arrancó a tiempo.\n$log');
}

Future<void> _seedAuthContext() async {
  await _adminPatch('users/admin-a', {
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'the-gene-pig',
  });
  await _adminPatch('users/admin-b', {
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'the-gene-pig',
  });
  await _adminPatch('tenants/the-gene-pig/members/admin-a', {
    'active': true,
    'role': 'tenant_admin',
  });
  await _adminPatch('tenants/the-gene-pig/members/admin-b', {
    'active': true,
    'role': 'tenant_admin',
  });
}

Future<void> _adminPatch(String path, Map<String, Object?> fields) async {
  final int status = await _writeAs(
    '__owner__',
    path,
    fields,
    updateMask: null,
    bearerOverride: 'owner',
  );
  if (status != 200) {
    throw StateError('Seed falló para $path status=$status');
  }
}

Future<int> _writeAsAdmin(
  String uid,
  String path,
  Map<String, Object?> fields, {
  required List<String>? updateMask,
}) {
  return _writeAs(uid, path, fields, updateMask: updateMask);
}

Future<int> _writeAs(
  String uid,
  String path,
  Map<String, Object?> fields, {
  required List<String>? updateMask,
  String? bearerOverride,
}) async {
  final HttpClient client = HttpClient();
  try {
    final Map<String, Object?> full = <String, Object?>{
      'schemaVersion': 1,
      'updatedAt': DateTime.now().toUtc(),
      'updatedBy': uid,
      ...fields,
    };
    final Uri uri = _documentUri(path, updateMask);
    final HttpClientRequest request = await client.patchUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${bearerOverride ?? _jwt(uid)}',
    );
    request.write(
      jsonEncode({'fields': full.map((k, v) => MapEntry(k, _encode(v)))}),
    );
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Uri _documentUri(String path, List<String>? updateMask) {
  final String base =
      '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/$path';
  if (updateMask == null || updateMask.isEmpty) {
    return Uri.parse(base);
  }
  final String query = updateMask
      .map(
        (field) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(field)}',
      )
      .join('&');
  return Uri.parse('$base?$query');
}

Future<int> _deleteAsAdmin(String uid, String path) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/$path',
    );
    final HttpClientRequest request = await client.deleteUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_jwt(uid)}');
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>?> _read(String path) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/$path',
    );
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('GET $path status=${response.statusCode} body=$body');
    }
    final Map<String, dynamic> payload =
        jsonDecode(body) as Map<String, dynamic>;
    final Map<String, dynamic> fields =
        payload['fields'] as Map<String, dynamic>? ?? {};
    return fields.map((k, v) => MapEntry(k, _decode(v)));
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> _encode(Object? value) {
  if (value == null) return {'nullValue': null};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': value.toString()};
  if (value is double) return {'doubleValue': value};
  if (value is String) return {'stringValue': value};
  if (value is DateTime) {
    return {'timestampValue': value.toUtc().toIso8601String()};
  }
  throw ArgumentError('unsupported: $value (${value.runtimeType})');
}

Object? _decode(Object? value) {
  if (value is! Map) return null;
  final Map<Object?, Object?> field = value;
  if (field.containsKey('nullValue')) return null;
  if (field.containsKey('stringValue')) return field['stringValue'];
  if (field.containsKey('booleanValue')) return field['booleanValue'];
  if (field.containsKey('integerValue')) {
    return int.tryParse(field['integerValue'].toString());
  }
  if (field.containsKey('doubleValue')) {
    return (field['doubleValue'] as num).toDouble();
  }
  if (field.containsKey('timestampValue')) return field['timestampValue'];
  return null;
}

String _jwt(String uid) {
  final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final String header = _b64({'alg': 'none', 'typ': 'JWT'});
  final String payload = _b64({
    'iss': 'https://securetoken.google.com/$_projectId',
    'aud': _projectId,
    'auth_time': now,
    'iat': now,
    'exp': now + 3600,
    'sub': uid,
    'user_id': uid,
    'firebase': {'sign_in_provider': 'custom'},
  });
  return '$header.$payload.';
}

String _b64(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

void _check(String description, bool condition) {
  if (condition) {
    _passed += 1;
    stdout.writeln('OK   — $description');
  } else {
    _failed += 1;
    stdout.writeln('FAIL — $description');
  }
}
