// Etapa B5 §39 — Verificación end-to-end de `alertConfig` contra un
// Firestore Emulator real, cargado con el `firestore.rules` real del repo
// (no un ruleset permisivo de juguete). Sigue el mismo patrón ya
// establecido en `backend/test/alert_config_firestore_rules_emulator_test.dart`
// (Etapa B4/B4.1) y en `tool/seed_device_templates.dart`: script Dart puro
// (dart:io + HttpClient), sin `cloud_firestore`/Flutter, porque un paquete
// cliente no puede embeber el SDK de Firestore en un script de línea de
// comandos — habla la REST API del emulador directamente.
//
// Fidelidad con lo que realmente hace `hierarchical_alert_config_service.dart`:
// este script no solo imita los NOMBRES de campo, sino el mecanismo real de
// Firestore que el servicio explota a propósito:
//   - CREATE  -> equivalente a `.set(data, SetOptions(merge:true))`: se
//     manda `updateMask.fieldPaths` con cada campo top-level y `thresholds`
//     como mapa anidado completo (sin puntos).
//   - UPDATE  -> equivalente a `.update(data)`: se manda
//     `updateMask.fieldPaths` incluyendo paths punteados como
//     `thresholds.max`; un path presente en el mask pero AUSENTE de
//     `fields` es cómo Firestore borra ESE campo puntual sin tocar a sus
//     hermanos — es la semántica real detrás de `FieldValue.delete()` en
//     `.update()`.
// Confirmar esto con un emulador real (no solo leyendo el código del SDK)
// es precisamente el punto de este script.
//
// Uso:
//   dart run tool/verify_hierarchical_alert_config_emulator.dart
//
// Requiere `firebase-tools` instalado. No toca Firestore productivo.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _projectId = 'demo-b5-alert-config-verify';
const int _port = 8130;
const String _baseUrl = 'http://127.0.0.1:$_port';

int _passed = 0;
int _failed = 0;

Future<void> main() async {
  final Directory dir = await Directory.systemTemp.createTemp(
    'b5-alert-config-verify-',
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

    await _testCreateAtEachLevel();
    await _testHeredarBorraSoloElCampoConUpdateMask();
    await _testBorrarDocumentoCuandoNoQuedaOverride();
    await _testExplicitFalsePersiste();
    await _testThresholdParcialConUpdateMaskNoBorraHermanos();
    await _testCreatedByPreservadoUpdatedByActualizado();
    await _testOtroAdminPuedeActualizarPreservandoCreatedBy();
    await _testUpdateSinMaskEnPathPunteadoEsRechazadoPorRulesOIgnorado();

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

Future<void> _testCreateAtEachLevel() async {
  const List<String> paths = [
    'tenants/the-gene-pig/alertConfig/temperature_interior',
    'tenants/the-gene-pig/sites/las-heras/alertConfig/temperature_interior',
    'tenants/the-gene-pig/devices/laboratorio/alertConfig/temperature_interior',
    'tenants/the-gene-pig/devices/laboratorio/rooms/room_1/alertConfig/temperature_interior',
  ];
  for (final String path in paths) {
    // Equivalente a buildAlertConfigCreatePayload + .set(merge:true).
    final int status = await _writeAsAdmin(
      path,
      fields: {
        'enabled': true,
        'thresholds': {'min': 20.0},
        'createdBy': 'admin-a',
      },
      updateMask: [
        'schemaVersion',
        'updatedAt',
        'updatedBy',
        'enabled',
        'thresholds',
        'createdAt',
        'createdBy',
      ],
    );
    _check('create en $path', status == 200);
    final Map<String, Object?>? doc = await _read(path);
    _check(
      'leído en $path tiene enabled=true',
      doc != null && doc['enabled'] == true,
    );
  }
}

Future<void> _testHeredarBorraSoloElCampoConUpdateMask() async {
  const String path = 'tenants/the-gene-pig/alertConfig/high_humidity';
  await _writeAsAdmin(
    path,
    fields: {
      'enabled': true,
      'whatsappEnabled': true,
      'thresholds': {'max': 88.0},
      'createdBy': 'admin-a',
    },
    updateMask: [
      'schemaVersion',
      'updatedAt',
      'updatedBy',
      'enabled',
      'whatsappEnabled',
      'thresholds',
      'createdAt',
      'createdBy',
    ],
  );
  // "Heredar" whatsappEnabled == buildAlertConfigUpdatePayload con
  // FieldValue.delete() en ese campo -> updateMask lo incluye, `fields` no.
  final int status = await _writeAsAdmin(
    path,
    fields: const {},
    updateMask: ['schemaVersion', 'updatedAt', 'updatedBy', 'whatsappEnabled'],
  );
  _check('heredar campo suelto vía updateMask -> 200', status == 200);
  final Map<String, Object?>? doc = await _read(path);
  _check(
    'enabled sigue true tras heredar whatsappEnabled',
    doc?['enabled'] == true,
  );
  _check(
    'whatsappEnabled ya no está presente',
    doc != null && !doc.containsKey('whatsappEnabled'),
  );
  _check(
    'thresholds.max sigue intacto (88) — heredar un campo no borra otros',
    doc != null && (doc['thresholds'] as Map?)?['max'] == 88.0,
  );
}

Future<void> _testBorrarDocumentoCuandoNoQuedaOverride() async {
  const String path = 'tenants/the-gene-pig/alertConfig/dew_point_risk';
  await _writeAsAdmin(
    path,
    fields: {'enabled': true, 'createdBy': 'admin-a'},
    updateMask: [
      'schemaVersion',
      'updatedAt',
      'updatedBy',
      'enabled',
      'createdAt',
      'createdBy',
    ],
  );
  // El servicio real borra el documento completo (DELETE), no un update
  // vacío, cuando ya no queda ningún campo funcional.
  final int status = await _deleteAsAdmin(path);
  _check('borrado de documento sin overrides -> 200', status == 200);
  final Map<String, Object?>? doc = await _read(path);
  _check(
    'el documento ya no existe (fallback legacy puede actuar)',
    doc == null,
  );
}

Future<void> _testExplicitFalsePersiste() async {
  const String path = 'tenants/the-gene-pig/alertConfig/room_door_open';
  final int status = await _writeAsAdmin(
    path,
    fields: {'whatsappEnabled': false, 'createdBy': 'admin-a'},
    updateMask: [
      'schemaVersion',
      'updatedAt',
      'updatedBy',
      'whatsappEnabled',
      'createdAt',
      'createdBy',
    ],
  );
  _check('explicit false -> 200', status == 200);
  final Map<String, Object?>? doc = await _read(path);
  _check(
    'whatsappEnabled=false persiste como false, no ausente',
    doc != null &&
        doc.containsKey('whatsappEnabled') &&
        doc['whatsappEnabled'] == false,
  );
}

Future<void> _testThresholdParcialConUpdateMaskNoBorraHermanos() async {
  const String path =
      'tenants/the-gene-pig/devices/laboratorio/alertConfig/temperature_interior';
  await _writeAsAdmin(
    path,
    fields: {
      'thresholds': {'min': 20.0, 'max': 30.0},
      'createdBy': 'admin-a',
    },
    updateMask: [
      'schemaVersion',
      'updatedAt',
      'updatedBy',
      'thresholds',
      'createdAt',
      'createdBy',
    ],
  );
  // Update real vía field-path punteado: solo thresholds.max, con
  // updateMask=thresholds.max — exactamente lo que .update() manda para
  // buildAlertConfigUpdatePayload({'thresholds.max': 28}).
  final int status = await _writeAsAdmin(
    path,
    fields: {
      'thresholds': {'max': 28.0},
    },
    updateMask: ['schemaVersion', 'updatedAt', 'updatedBy', 'thresholds.max'],
  );
  _check(
    'update threshold parcial vía updateMask punteado -> 200',
    status == 200,
  );
  final Map<String, Object?>? doc = await _read(path);
  final Map<Object?, Object?>? thresholds = doc?['thresholds'] as Map?;
  _check(
    'thresholds.min sigue en 20 (no clobbereado)',
    thresholds?['min'] == 20.0,
  );
  _check('thresholds.max actualizado a 28', thresholds?['max'] == 28.0);
}

Future<void> _testCreatedByPreservadoUpdatedByActualizado() async {
  const String path =
      'tenants/the-gene-pig/alertConfig/high_temperature_heating_active';
  await _writeAs(
    'admin-a',
    path,
    fields: {'enabled': true, 'createdBy': 'admin-a'},
    updateMask: [
      'schemaVersion',
      'updatedAt',
      'updatedBy',
      'enabled',
      'createdAt',
      'createdBy',
    ],
  );
  final int status = await _writeAs(
    'admin-a',
    path,
    fields: {'enabled': false},
    // createdBy NUNCA se reenvía en un update real (Etapa B4.1) — se omite
    // tanto de `fields` como de `updateMask`, así que Firestore ni siquiera
    // lo considera.
    updateMask: ['schemaVersion', 'updatedAt', 'updatedBy', 'enabled'],
  );
  _check('update omitiendo createdBy -> 200', status == 200);
  final Map<String, Object?>? doc = await _read(path);
  _check('createdBy preservado tras update', doc?['createdBy'] == 'admin-a');
  _check('updatedBy actualizado', doc?['updatedBy'] == 'admin-a');
}

Future<void> _testOtroAdminPuedeActualizarPreservandoCreatedBy() async {
  const String path = 'tenants/the-gene-pig/alertConfig/sensor_failure';
  await _writeAs(
    'admin-a',
    path,
    fields: {'enabled': true, 'createdBy': 'admin-a'},
    updateMask: [
      'schemaVersion',
      'updatedAt',
      'updatedBy',
      'enabled',
      'createdAt',
      'createdBy',
    ],
  );
  // admin-b es OTRO tenant_admin autorizado del mismo tenant — el bug de B4
  // (corregido en B4.1) bloqueaba esto si se reenviaba createdBy sin
  // cambios; acá directamente lo omitimos, que es el patrón correcto.
  final int status = await _writeAs(
    'admin-b',
    path,
    fields: {'enabled': false},
    updateMask: ['schemaVersion', 'updatedAt', 'updatedBy', 'enabled'],
  );
  _check(
    'admin-b (otro admin del mismo tenant) puede actualizar -> 200',
    status == 200,
  );
  final Map<String, Object?>? doc = await _read(path);
  _check('createdBy sigue siendo admin-a', doc?['createdBy'] == 'admin-a');
  _check('updatedBy pasa a admin-b', doc?['updatedBy'] == 'admin-b');
}

/// Confirma que, si por error alguien mandara un `.set()` (o un REST PATCH)
/// SIN `updateMask` en absoluto para un cambio parcial, el resultado es el
/// que B4.1 advirtió: reemplazo total del documento. Este test existe para
/// que quede evidencia viva de POR QUÉ el servicio nunca hace esto — no
/// para aprobarlo.
Future<void>
_testUpdateSinMaskEnPathPunteadoEsRechazadoPorRulesOIgnorado() async {
  const String path = 'tenants/the-gene-pig/alertConfig/munters_door_open';
  await _writeAsAdmin(
    path,
    fields: {'enabled': true, 'cooldownMinutes': 15, 'createdBy': 'admin-a'},
    updateMask: [
      'schemaVersion',
      'updatedAt',
      'updatedBy',
      'enabled',
      'cooldownMinutes',
      'createdAt',
      'createdBy',
    ],
  );
  // PATCH sin updateMask (el patrón inseguro): reemplaza el documento
  // COMPLETO con solo lo que viene en `fields`.
  await _writeAsAdmin(path, fields: {'enabled': false}, updateMask: null);
  final Map<String, Object?>? doc = await _read(path);
  _check(
    'PATCH sin updateMask confirma el peligro de B4.1: cooldownMinutes/createdBy desaparecen',
    doc != null &&
        !doc.containsKey('cooldownMinutes') &&
        !doc.containsKey('createdBy'),
  );
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
    fields: fields,
    updateMask: null,
    bearerOverride: 'owner',
  );
  if (status != 200) {
    throw StateError('Seed falló para $path status=$status');
  }
}

Future<int> _writeAsAdmin(
  String path, {
  required Map<String, Object?> fields,
  required List<String>? updateMask,
}) {
  return _writeAs('admin-a', path, fields: fields, updateMask: updateMask);
}

Future<int> _writeAs(
  String uid,
  String path, {
  required Map<String, Object?> fields,
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

Future<int> _deleteAsAdmin(String path) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/$path',
    );
    final HttpClientRequest request = await client.deleteUrl(uri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${_jwt('admin-a')}',
    );
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
  if (value is Map) {
    return {
      'mapValue': {
        'fields': value.map((k, v) => MapEntry(k.toString(), _encode(v))),
      },
    };
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
  if (field.containsKey('mapValue')) {
    final Map<String, dynamic> inner =
        (field['mapValue'] as Map)['fields'] as Map<String, dynamic>? ?? {};
    return inner.map((k, v) => MapEntry(k, _decode(v)));
  }
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
