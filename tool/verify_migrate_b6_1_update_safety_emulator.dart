// Etapa B6.1 §10/§11 — Verificacion end-to-end del camino de UPDATE
// hardenizado de `tool/migrate_alerts_b6_the_gene_pig.dart` contra un
// Firestore Emulator real (no un mock ni una reimplementacion paralela):
// este script importa y ejercita directamente `FirestoreRest.patchDoc`,
// `diffFunctionalFields`, `buildCreatePayload`, `buildUpdatePayload` y
// `buildUpdateMask` — las mismas funciones que usa el migrador real — para
// que un hallazgo aca sea un hallazgo real del codigo de produccion, no de
// una copia.
//
// Test obligatorio §10 (auditoria): crear con createdBy=admin-a/createdAt=T1
// y thresholds.min=10/max=30, actualizar thresholds.min=15 con
// updatedBy=admin-b, y confirmar que createdBy/createdAt no cambian,
// thresholds.max sigue en 30, thresholds.min pasa a 15 y updatedBy pasa a
// admin-b.
//
// Test obligatorio §11 (replace peligroso): confirmar que el update NO
// borra campos hermanos que no forman parte del diff (p. ej.
// cooldownMinutes, whatsappEnabled) — releyendo el documento real, no
// solo mirando el status HTTP.
//
// Uso:
//   dart run tool/verify_migrate_b6_1_update_safety_emulator.dart
//
// Requiere `firebase-tools` instalado. No toca Firestore productivo: usa
// `Bearer owner`, que el Firestore Emulator trata como admin y evita
// depender de `firestore.rules` para este test (que ya se verifica aparte
// en `tool/verify_hierarchical_alert_config_emulator.dart`).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'migrate_alerts_b6_the_gene_pig.dart'
    show
        FieldDiff,
        FirestoreRest,
        buildCreatePayload,
        buildUpdateMask,
        buildUpdatePayload,
        diffFunctionalFields;

const String _projectId = 'demo-b6-1-update-safety-verify';
const int _port = 8131;
const String _baseUrl = 'http://127.0.0.1:$_port';

int _passed = 0;
int _failed = 0;

Future<void> main() async {
  final Directory dir = await Directory.systemTemp.createTemp(
    'b6-1-update-safety-verify-',
  );
  await File('${dir.path}/firestore.rules').writeAsString(
    'rules_version = "2";\n'
    'service cloud.firestore {\n'
    '  match /databases/{database}/documents {\n'
    '    match /{document=**} { allow read, write: if true; }\n'
    '  }\n'
    '}\n',
  );
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

    final FirestoreRest firestore = FirestoreRest(
      projectId: _projectId,
      serviceAccountPath: '',
      accessToken: 'owner',
      baseUrl: _baseUrl,
    );

    await _testAuditPreservedOnPartialUpdate(firestore);
    await _testUpdateDoesNotDeleteSiblingFields(firestore);
    await _testCreatePathIsUnaffectedByUpdateMask(firestore);

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

/// Test obligatorio B6.1 §10.
Future<void> _testAuditPreservedOnPartialUpdate(FirestoreRest firestore) async {
  const String path =
      'tenants/the-gene-pig/sites/las-heras/alertConfig/audit-test';
  final DateTime t1 = DateTime.utc(2026, 9, 9, 10);

  final Map<String, Object?> createPayload = buildCreatePayload(
    functionalFields: <String, Object?>{
      'enabled': true,
      'thresholds': <String, Object?>{'min': 10, 'max': 30},
    },
    now: t1,
    adminUid: 'admin-a',
  );
  await firestore.patchDoc(path, createPayload);

  final Map<String, Object?>? created = await firestore.getDoc(path);
  _check('doc creado existe', created != null);

  final FieldDiff diff = diffFunctionalFields(<String, Object?>{
    'enabled': true,
    'thresholds': <String, Object?>{'min': 15, 'max': 30},
  }, created!);
  _check(
    'diff detecta unicamente thresholds.min como cambiado',
    diff.maskPaths.length == 1 && diff.maskPaths.single == 'thresholds.min',
  );

  final DateTime t2 = DateTime.utc(2026, 9, 9, 11);
  final Map<String, Object?> updatePayload = buildUpdatePayload(
    diff: diff,
    now: t2,
    adminUid: 'admin-b',
  );
  _check(
    'updatePayload no incluye createdAt/createdBy',
    !updatePayload.containsKey('createdAt') &&
        !updatePayload.containsKey('createdBy'),
  );

  await firestore.patchDoc(
    path,
    updatePayload,
    updateMask: buildUpdateMask(diff),
  );

  final Map<String, Object?>? updated = await firestore.getDoc(path);
  _check('createdBy sigue admin-a', updated?['createdBy'] == 'admin-a');
  _check(
    'createdAt sigue T1',
    updated?['createdAt'] is DateTime &&
        (updated!['createdAt'] as DateTime).isAtSameMomentAs(t1),
  );
  _check('updatedBy paso a admin-b', updated?['updatedBy'] == 'admin-b');
  final Map<Object?, Object?>? thresholds =
      updated?['thresholds'] as Map<Object?, Object?>?;
  _check('thresholds.max sigue 30', thresholds?['max'] == 30);
  _check('thresholds.min paso a 15', thresholds?['min'] == 15);
}

/// Test obligatorio B6.1 §11 — releer y comprobar valores, no solo status.
Future<void> _testUpdateDoesNotDeleteSiblingFields(
  FirestoreRest firestore,
) async {
  const String path =
      'tenants/the-gene-pig/sites/las-heras/alertConfig/sibling-test';
  final DateTime t1 = DateTime.utc(2026, 9, 9, 10);

  final Map<String, Object?> createPayload = buildCreatePayload(
    functionalFields: <String, Object?>{
      'enabled': true,
      'visualEnabled': true,
      'whatsappEnabled': true,
      'cooldownMinutes': 10,
      'order': 4,
      'thresholds': <String, Object?>{'min': 15, 'max': 33},
    },
    now: t1,
    adminUid: 'admin-a',
  );
  await firestore.patchDoc(path, createPayload);
  final Map<String, Object?>? created = await firestore.getDoc(path);

  // Solo cambia enabled -> false. Todo lo demas (hermanos) debe sobrevivir.
  final FieldDiff diff = diffFunctionalFields(<String, Object?>{
    'enabled': false,
    'visualEnabled': true,
    'whatsappEnabled': true,
    'cooldownMinutes': 10,
    'order': 4,
    'thresholds': <String, Object?>{'min': 15, 'max': 33},
  }, created!);
  _check(
    'diff detecta unicamente enabled como cambiado',
    diff.maskPaths.length == 1 && diff.maskPaths.single == 'enabled',
  );

  await firestore.patchDoc(
    path,
    buildUpdatePayload(
      diff: diff,
      now: DateTime.utc(2026, 9, 9, 11),
      adminUid: 'admin-b',
    ),
    updateMask: buildUpdateMask(diff),
  );

  final Map<String, Object?>? updated = await firestore.getDoc(path);
  _check('enabled paso a false', updated?['enabled'] == false);
  _check(
    'visualEnabled hermano sobrevive intacto',
    updated?['visualEnabled'] == true,
  );
  _check(
    'whatsappEnabled hermano sobrevive intacto',
    updated?['whatsappEnabled'] == true,
  );
  _check(
    'cooldownMinutes hermano sobrevive intacto',
    updated?['cooldownMinutes'] == 10,
  );
  _check('order hermano sobrevive intacto', updated?['order'] == 4);
  final Map<Object?, Object?>? thresholds =
      updated?['thresholds'] as Map<Object?, Object?>?;
  _check(
    'thresholds.min/max hermanos (no tocados por este diff) sobreviven',
    thresholds?['min'] == 15 && thresholds?['max'] == 33,
  );
  _check('createdBy preservado', updated?['createdBy'] == 'admin-a');
  _check('createdAt preservado', updated?['createdAt'] is DateTime);
}

/// Confirma que el camino CREATE (sin updateMask, doc inexistente) sigue
/// funcionando igual que antes del hardening de B6.1.
Future<void> _testCreatePathIsUnaffectedByUpdateMask(
  FirestoreRest firestore,
) async {
  const String path =
      'tenants/the-gene-pig/sites/las-heras/alertConfig/create-test';
  final Map<String, Object?> payload = buildCreatePayload(
    functionalFields: <String, Object?>{'enabled': true, 'order': 1},
    now: DateTime.utc(2026, 9, 9, 10),
    adminUid: 'admin-a',
  );
  await firestore.patchDoc(path, payload);
  final Map<String, Object?>? doc = await firestore.getDoc(path);
  _check('create sin updateMask sigue funcionando', doc?['enabled'] == true);
  _check('schemaVersion presente en create', doc?['schemaVersion'] == 1);
  _check('createdBy presente en create', doc?['createdBy'] == 'admin-a');
}

Future<void> _waitForReady(StringBuffer log) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (log.toString().contains('All emulators ready')) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('Firestore emulator no arranco a tiempo.\n$log');
}

void _check(String description, bool condition) {
  if (condition) {
    _passed += 1;
    stdout.writeln('OK   $description');
  } else {
    _failed += 1;
    stdout.writeln('FAIL $description');
  }
}
