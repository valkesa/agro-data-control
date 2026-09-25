// Prompt_Cierre_Historicos_Ambientales_Robustez_H1_H7 §17 — "No cerrar solo
// con fake repositories": repeats the critical H1-H7 scenarios against a
// REAL local Firestore Emulator, using the exact
// [DeviceEnvironmentHistoryService]/[FirestoreDeviceEnvironmentHistoryRepository]
// pair production uses (real HTTP + wire-encoding, not a fake). Covers:
// fallo + recovery, two tenants sharing the same deviceId, a contradictory
// Site, a real restart with checkpoint recovery, a pending daily surviving
// a day change, and idempotency (no duplicate documents on replay).
//
// Run with:
//   dart test/device_environment_history_manual_verification_test.dart
// (requires the `firebase` CLI on PATH; starts and tears down its own
// throwaway Firestore emulator instance, never touches real Firestore).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/device_environment_history_service.dart';
import 'package:agro_data_control_backend/src/firestore_device_environment_history_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';

const String _projectId = 'demo-historicos-manual-verification';
const int _port = 8104;
const String _baseUrl = 'http://127.0.0.1:$_port';

Future<void> main() async {
  final Directory emulatorProjectDir = await _writeEmulatorProject();
  final StringBuffer emulatorLog = StringBuffer();
  Process? emulatorProcess;
  final Directory checkpointDir = await Directory.systemTemp.createTemp(
    'historicos-manual-checkpoint-',
  );

  try {
    emulatorProcess = await _startEmulator(emulatorProjectDir, emulatorLog);
    await _waitForReady(emulatorLog);
    await _waitForRestApi();
    // Real Devices are required before history writes (C2/C3).
    await _adminPatch('tenants/baseline-tenant/devices/baseline-device', {
      'siteId': _stringField('baseline-site'),
    });
    await _adminPatch('tenants/failure-tenant/devices/failure-device', {
      'siteId': _stringField('failure-site'),
    });
    await _adminPatch('tenants/tenant-x/devices/shared-id', {
      'siteId': _stringField('site-x'),
    });
    await _adminPatch('tenants/tenant-y/devices/shared-id', {
      'siteId': _stringField('site-y'),
    });
    await _adminPatch('tenants/restart-tenant/devices/restart-device', {
      'siteId': _stringField('restart-site'),
    });
    await _adminPatch(
      'tenants/daily-pending-tenant/devices/daily-pending-device',
      {'siteId': _stringField('daily-pending-site')},
    );
    await _adminPatch('tenants/idempotent-tenant/devices/idempotent-device', {
      'siteId': _stringField('idempotent-site'),
    });

    await _scenarioBaselineAndPersistence(checkpointDir);
    await _scenarioFailureThenRecovery(checkpointDir);
    await _scenarioTwoTenantsSameDeviceId(checkpointDir);
    await _scenarioContradictorySite(checkpointDir);
    await _scenarioRealRestart(checkpointDir);
    await _scenarioPendingDailyAcrossDayChange(checkpointDir);
    await _scenarioIdempotencyNoDuplicateOnReplay(checkpointDir);
    await _scenarioFinalClosure(checkpointDir);

    print('');
    print('device_environment_history_manual_verification: TODOS LOS PASOS OK');
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
    if (await checkpointDir.exists()) {
      await checkpointDir.delete(recursive: true);
    }
  }
}

DeviceEnvironmentHistoryConfig _config({
  required String tenantId,
  required String siteId,
  required String deviceId,
  required Directory checkpointDir,
}) {
  return DeviceEnvironmentHistoryConfig(
    enabled: true,
    temperatureSourcePath: 'sala1.tempInterior',
    humiditySourcePath: 'sala1.humInterior',
    tenantId: tenantId,
    siteId: siteId,
    deviceId: deviceId,
    firestoreProjectId: _projectId,
    firestoreDatabaseId: '(default)',
    firestoreServiceAccountPath: '',
    checkpointDirectoryPath: checkpointDir.path,
  );
}

FirestoreDeviceEnvironmentHistoryRepository _repository(
  DeviceEnvironmentHistoryConfig config,
) {
  return FirestoreDeviceEnvironmentHistoryRepository(
    config: config,
    baseUrl: _baseUrl,
    accessTokenProvider: () async => 'owner',
  );
}

Map<String, Object?> _unitsJson({
  required double temp,
  required double hum,
  bool dataFresh = true,
  bool plcOnline = true,
  bool plcRunning = true,
}) {
  return <String, Object?>{
    'sala1': <String, Object?>{
      'tempInterior': temp,
      'humInterior': hum,
      'dataFresh': dataFresh,
      'plcOnline': plcOnline,
      'plcRunning': plcRunning,
    },
  };
}

DateTime _art(int year, int month, int day, int hour, [int minute = 0]) =>
    DateTime.utc(year, month, day, hour + 3, minute);

// ---------------------------------------------------------------------------
// Escenario 1 — línea base: varias muestras, agregado horario, persistencia,
// consulta, temp+hum juntas, promedio ponderado.
// ---------------------------------------------------------------------------

Future<void> _scenarioBaselineAndPersistence(Directory checkpointDir) async {
  print(
    '=== Escenario 1: línea base (muestras, horario, diario, consulta) ===',
  );
  final DeviceEnvironmentHistoryConfig config = _config(
    tenantId: 'baseline-tenant',
    siteId: 'baseline-site',
    deviceId: 'baseline-device',
    checkpointDir: checkpointDir,
  );
  final FirestoreDeviceEnvironmentHistoryRepository repository = _repository(
    config,
  );
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(config: config, repository: repository);

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 22.0, hum: 62.0),
    observedAtUtc: _art(2026, 9, 24, 10, 20),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 21.0, hum: 61.0),
    observedAtUtc: _art(2026, 9, 24, 10, 40),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 70.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0), // closes hour 10.
  );
  await service.dispose();

  final DeviceEnvironmentHourlyRecord? hourly = await repository.loadHourly(
    '2026-09-24T10',
  );
  _check(hourly != null, 'el resumen horario debe existir en Firestore');
  _check(
    hourly!.temperature.sampleCount == 3 && hourly.humidity.sampleCount == 3,
    'sampleCount correcto para ambas variables',
  );
  _checkClose(hourly.temperature.avg!, 21.0, 'avg de temperatura correcto');
  print(
    'Leído de Firestore: temp avg=${hourly.temperature.avg} n=${hourly.temperature.sampleCount} '
    '| hum avg=${hourly.humidity.avg} n=${hourly.humidity.sampleCount}',
  );

  // Cierra el día para ejercitar el diario ponderado (Option B: 1 sola
  // escritura al cerrar el día, no una reescritura por cada hora).
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 40.0, hum: 80.0),
    observedAtUtc: _art(2026, 9, 25, 0, 0), // cierra el día 24.
  );
  await service.dispose();

  final List<DeviceEnvironmentDailyRecord> daily = await repository
      .getDailyHistory(
        fromUtc: DateTime.utc(2026, 9, 24),
        toUtc: DateTime.utc(2026, 9, 25),
      );
  _check(daily.length == 1, 'el resumen diario debe existir');
  print(
    'Diario: avg=${daily.single.temperature.avg} n=${daily.single.temperature.sampleCount}',
  );
}

// ---------------------------------------------------------------------------
// Escenario 2 — H1: fallo de saveHourly + recuperación posterior.
// ---------------------------------------------------------------------------

Future<void> _scenarioFailureThenRecovery(Directory checkpointDir) async {
  print('=== Escenario 2 (H1): fallo de persistencia + recuperación ===');
  final DeviceEnvironmentHistoryConfig config = _config(
    tenantId: 'failure-tenant',
    siteId: 'failure-site',
    deviceId: 'failure-device',
    checkpointDir: checkpointDir,
  );
  // Un baseUrl inválido simula un Firestore inalcanzable para el primer
  // intento — el mismo repository real, apuntado a un puerto que no
  // responde en absoluto.
  final FirestoreDeviceEnvironmentHistoryRepository brokenRepository =
      FirestoreDeviceEnvironmentHistoryRepository(
        config: config,
        baseUrl: 'http://127.0.0.1:1', // nadie escucha ahí.
        accessTokenProvider: () async => 'owner',
      );
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: config,
        repository: brokenRepository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0), // cierra hora 10 — falla el save.
  );
  await service.dispose();
  _check(
    service.pendingHourlyPeriods.length == 1,
    'la hora fallida debe quedar pendiente de forma durable (H1)',
  );

  // El repositorio real (emulador) reemplaza al roto — misma config,
  // mismo checkpoint en disco, "Firestore" ahora funciona.
  final FirestoreDeviceEnvironmentHistoryRepository realRepository =
      _repository(config);
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 32.0, hum: 62.0),
    observedAtUtc: _art(2026, 9, 24, 11, 20),
  );
  await service.dispose();
  // El propio servicio sigue apuntando al repository roto — para probar la
  // recuperación real emulamos el "reinicio" con una instancia nueva que sí
  // usa el repository sano, leyendo el mismo checkpoint en disco.
  final DeviceEnvironmentHistoryService recovered =
      DeviceEnvironmentHistoryService(
        config: config,
        repository: realRepository,
      );
  recovered.handleSnapshot(
    unitsJson: _unitsJson(temp: 33.0, hum: 63.0),
    observedAtUtc: _art(2026, 9, 24, 11, 40),
  );
  await recovered.dispose();

  final DeviceEnvironmentHourlyRecord? persisted = await realRepository
      .loadHourly('2026-09-24T10');
  _check(
    persisted != null,
    'tras recuperar Firestore, la hora pendiente debe persistirse (H1)',
  );
  print('Hora 10 recuperada y persistida tras el fallo simulado.');
}

// ---------------------------------------------------------------------------
// Escenario 3 — H3/scope: mismo deviceId en dos tenants distintos, sin
// mezcla de checkpoint ni de datos.
// ---------------------------------------------------------------------------

Future<void> _scenarioTwoTenantsSameDeviceId(Directory checkpointDir) async {
  print('=== Escenario 3 (H3): mismo deviceId, dos tenants ===');
  final DeviceEnvironmentHistoryConfig configA = _config(
    tenantId: 'tenant-x',
    siteId: 'site-x',
    deviceId: 'shared-id',
    checkpointDir: checkpointDir,
  );
  final DeviceEnvironmentHistoryConfig configB = _config(
    tenantId: 'tenant-y',
    siteId: 'site-y',
    deviceId: 'shared-id',
    checkpointDir: checkpointDir,
  );
  final FirestoreDeviceEnvironmentHistoryRepository repoA = _repository(
    configA,
  );
  final FirestoreDeviceEnvironmentHistoryRepository repoB = _repository(
    configB,
  );
  final DeviceEnvironmentHistoryService serviceA =
      DeviceEnvironmentHistoryService(config: configA, repository: repoA);
  final DeviceEnvironmentHistoryService serviceB =
      DeviceEnvironmentHistoryService(config: configB, repository: repoB);

  serviceA.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 12, 0),
  );
  serviceB.handleSnapshot(
    unitsJson: _unitsJson(temp: 99.0, hum: 99.0),
    observedAtUtc: _art(2026, 9, 24, 12, 0),
  );
  serviceA.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 13, 0),
  );
  serviceB.handleSnapshot(
    unitsJson: _unitsJson(temp: 40.0, hum: 40.0),
    observedAtUtc: _art(2026, 9, 24, 13, 0),
  );
  await serviceA.dispose();
  await serviceB.dispose();

  final DeviceEnvironmentHourlyRecord recordA = (await repoA.loadHourly(
    '2026-09-24T12',
  ))!;
  final DeviceEnvironmentHourlyRecord recordB = (await repoB.loadHourly(
    '2026-09-24T12',
  ))!;
  _check(
    recordA.tenantId == 'tenant-x' && recordA.temperature.avg == 20.0,
    'tenant-x conserva su propio valor',
  );
  _check(
    recordB.tenantId == 'tenant-y' && recordB.temperature.avg == 99.0,
    'tenant-y conserva su propio valor, sin mezcla con tenant-x',
  );
  print(
    'tenant-x y tenant-y, mismo deviceId, documentos y checkpoints independientes.',
  );
}

// ---------------------------------------------------------------------------
// Escenario 4 — H4: Site contradictorio bloquea al writer.
// ---------------------------------------------------------------------------

Future<void> _scenarioContradictorySite(Directory checkpointDir) async {
  print('=== Escenario 4 (H4): Site contradictorio ===');
  const String tenantId = 'site-check-tenant';
  const String deviceId = 'site-check-device';

  // Documento real del Device en Firestore, con el Site verdadero.
  await _adminPatch('tenants/$tenantId/devices/$deviceId', <String, Object?>{
    'siteId': _stringField('real-site'),
    'name': _stringField('Sala Real'),
  });

  final DeviceEnvironmentHistoryConfig config = _config(
    tenantId: tenantId,
    siteId: 'wrong-site', // contradice al Device real.
    deviceId: deviceId,
    checkpointDir: checkpointDir,
  );
  final FirestoreDeviceEnvironmentHistoryRepository repository = _repository(
    config,
  );
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(config: config, repository: repository);

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 14, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 15, 0),
  );
  await service.dispose();

  _check(
    service.writesBlocked,
    'un Site contradictorio contra el Device real debe bloquear el writer (H4)',
  );
  final DeviceEnvironmentHourlyRecord? shouldBeNull = await repository
      .loadHourly('2026-09-24T14');
  _check(
    shouldBeNull == null,
    'no debe haberse escrito nada con el Site incorrecto',
  );
  print(
    'Writer bloqueado correctamente: siteId configurado no coincide con el Device real.',
  );
}

// ---------------------------------------------------------------------------
// Escenario 5 — H2: reinicio real (nuevo proceso/instancia) recupera la
// hora en curso desde el checkpoint en disco.
// ---------------------------------------------------------------------------

Future<void> _scenarioRealRestart(Directory checkpointDir) async {
  print('=== Escenario 5 (H2): reinicio real ===');
  final DeviceEnvironmentHistoryConfig config = _config(
    tenantId: 'restart-tenant',
    siteId: 'restart-site',
    deviceId: 'restart-device',
    checkpointDir: checkpointDir,
  );
  final FirestoreDeviceEnvironmentHistoryRepository repository = _repository(
    config,
  );

  final DeviceEnvironmentHistoryService instance1 =
      DeviceEnvironmentHistoryService(config: config, repository: repository);
  instance1.handleSnapshot(
    unitsJson: _unitsJson(temp: 18.0, hum: 55.0),
    observedAtUtc: _art(2026, 9, 24, 16, 0),
  );
  instance1.handleSnapshot(
    unitsJson: _unitsJson(temp: 19.0, hum: 56.0),
    observedAtUtc: _art(2026, 9, 24, 16, 20),
  );
  await instance1.dispose(); // "cae" el backend — instance1 se descarta.

  final DeviceEnvironmentHistoryService instance2 =
      DeviceEnvironmentHistoryService(config: config, repository: repository);
  instance2.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 57.0),
    observedAtUtc: _art(2026, 9, 24, 16, 40),
  );
  instance2.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 17, 0), // cierra la hora 16.
  );
  await instance2.dispose();

  final DeviceEnvironmentHourlyRecord? record = await repository.loadHourly(
    '2026-09-24T16',
  );
  _check(
    record != null && record.temperature.sampleCount == 3,
    'las 2 muestras previas al reinicio + 1 posterior deben combinarse '
    '(sampleCount=${record?.temperature.sampleCount})',
  );
  print('Reinicio real: 3 muestras combinadas correctamente vía checkpoint.');
}

// ---------------------------------------------------------------------------
// Escenario 6 — H6: diario pendiente sobrevive el cambio de día.
// ---------------------------------------------------------------------------

Future<void> _scenarioPendingDailyAcrossDayChange(
  Directory checkpointDir,
) async {
  print('=== Escenario 6 (H6): diario pendiente tras cambio de día ===');
  final DeviceEnvironmentHistoryConfig config = _config(
    tenantId: 'daily-pending-tenant',
    siteId: 'daily-pending-site',
    deviceId: 'daily-pending-device',
    checkpointDir: checkpointDir,
  );

  final DeviceEnvironmentHistoryConfig brokenConfig = config;
  final FirestoreDeviceEnvironmentHistoryRepository brokenRepository =
      FirestoreDeviceEnvironmentHistoryRepository(
        config: brokenConfig,
        baseUrl: 'http://127.0.0.1:1',
        accessTokenProvider: () async => 'owner',
      );
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: config,
        repository: brokenRepository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 20, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 21.0, hum: 51.0),
    observedAtUtc: _art(2026, 9, 24, 21, 0), // cierra hora 20 (falla).
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 22.0, hum: 52.0),
    observedAtUtc: _art(2026, 9, 25, 0, 0), // cierra día 24 (falla también).
  );
  await service.dispose();
  _check(
    service.pendingDailyPeriods.any(
      (DeviceEnvironmentDailyRecord r) => r.periodId == '2026-09-24',
    ),
    'el diario del 24 debe seguir pendiente aunque ya sea el día 25 (H6)',
  );

  final FirestoreDeviceEnvironmentHistoryRepository realRepository =
      _repository(config);
  final DeviceEnvironmentHistoryService recovered =
      DeviceEnvironmentHistoryService(
        config: config,
        repository: realRepository,
      );
  recovered.handleSnapshot(
    unitsJson: _unitsJson(temp: 23.0, hum: 53.0),
    observedAtUtc: _art(2026, 9, 25, 0, 20),
  );
  await recovered.dispose();

  final List<DeviceEnvironmentDailyRecord> daily = await realRepository
      .getDailyHistory(
        fromUtc: DateTime.utc(2026, 9, 24),
        toUtc: DateTime.utc(2026, 9, 25),
      );
  _check(
    daily.length == 1,
    'el diario pendiente del 24 debe terminar persistido tras recuperar (H6)',
  );
  print('Diario del 24 recuperado y persistido pese al cambio de día.');
}

// ---------------------------------------------------------------------------
// Escenario 7 — idempotencia: reintentar un saveHourly ya confirmado no crea
// un documento duplicado.
// ---------------------------------------------------------------------------

Future<void> _scenarioIdempotencyNoDuplicateOnReplay(
  Directory checkpointDir,
) async {
  print('=== Escenario 7: idempotencia (replay no duplica) ===');
  final DeviceEnvironmentHistoryConfig config = _config(
    tenantId: 'idempotent-tenant',
    siteId: 'idempotent-site',
    deviceId: 'idempotent-device',
    checkpointDir: checkpointDir,
  );
  final FirestoreDeviceEnvironmentHistoryRepository repository = _repository(
    config,
  );
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(config: config, repository: repository);

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 22, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 23, 0),
  );
  await service.dispose();

  final DeviceEnvironmentHourlyRecord original = (await repository.loadHourly(
    '2026-09-24T22',
  ))!;
  await repository.saveHourly(original); // replay explícito.

  final int docCount = await _countDocuments(
    'tenants/idempotent-tenant/devices/idempotent-device/historyHourly',
  );
  _check(
    docCount == 1,
    'el replay no debe crear un segundo documento, hay $docCount',
  );
  print('Replay de saveHourly: sigue habiendo 1 solo documento.');
}

// ---------------------------------------------------------------------------
// Infra del emulador (mismo patrón que los otros *_firestore_emulator_test.dart)
// ---------------------------------------------------------------------------

Future<Directory> _writeEmulatorProject() async {
  final Directory dir = await Directory.systemTemp.createTemp(
    'historicos-manual-emulator-',
  );
  await File('${dir.path}/firestore.rules').writeAsString(
    'rules_version = "2";\nservice cloud.firestore {\n'
    '  match /databases/{database}/documents {\n'
    '    match /{document=**} { allow read, write: if true; }\n'
    '  }\n}\n',
  );
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
  final jar = Platform.environment['FIRESTORE_EMULATOR_JAR'];
  final Process process = jar == null
      ? await Process.start('firebase', [
          'emulators:start',
          '--only',
          'firestore',
          '--project',
          _projectId,
        ], workingDirectory: projectDir.path)
      : await Process.start('java', [
          '-jar',
          jar,
          '--host',
          '127.0.0.1',
          '--port',
          '$_port',
          '--rules',
          '${projectDir.path}/firestore.rules',
        ]);
  // The direct, cached JAR avoids a CLI download; REST readiness still gates tests.
  if (jar != null) log.write('All emulators ready');
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

Future<void> _adminPatch(String path, Map<String, Object?> fields) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/$path',
    );
    final HttpClientRequest request = await client.patchUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    request.write(jsonEncode(<String, Object?>{'fields': fields}));
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError(
        'Admin PATCH $path failed status=${response.statusCode} body=$body',
      );
    }
  } finally {
    client.close(force: true);
  }
}

Future<int> _countDocuments(String collectionPath) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/$collectionPath',
    );
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError(
        'LIST $collectionPath failed status=${response.statusCode} body=$body',
      );
    }
    final Map<String, dynamic> payload =
        jsonDecode(body) as Map<String, dynamic>;
    final Object? documents = payload['documents'];
    return documents is List ? documents.length : 0;
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> _stringField(String value) => <String, Object?>{
  'stringValue': value,
};

void _check(bool condition, String message) {
  if (!condition) {
    throw StateError('FALLO: $message');
  }
  print('OK: $message');
}

void _checkClose(double actual, double expected, String message) {
  if ((actual - expected).abs() > 0.001) {
    throw StateError('FALLO: $message (esperado $expected, obtenido $actual)');
  }
  print('OK: $message');
}

/// Final C1-C7 integration: real missing Device lookup, pending recovery,
/// contradictory Site before retry, consistent restart, ART lookup and scoped reads.
Future<void> _scenarioFinalClosure(Directory dir) async {
  print(
    '=== Escenario 8 C1-C7: Site gating, restart, ART/UTC, scoped reads ===',
  );
  final c = _config(
    tenantId: 'final-tenant',
    siteId: 'final-site',
    deviceId: 'final-device',
    checkpointDir: dir,
  );
  final repo = _repository(c);
  Future<void> feed(
    DeviceEnvironmentHistoryService s,
    DateTime time,
    double temp,
  ) async {
    s.handleSnapshot(
      unitsJson: _unitsJson(temp: temp, hum: 50),
      observedAtUtc: time,
    );
    await s.dispose();
  }

  final first = DeviceEnvironmentHistoryService(config: c, repository: repo);
  await feed(first, _art(2026, 9, 24, 22, 40), 10);
  await feed(first, _art(2026, 9, 24, 23, 1), 30);
  _check(
    first.siteState == DeviceHistorySiteState.temporarilyUnavailable,
    'missing Device defers writes',
  );
  _check(
    await repo.loadHourly('2026-09-24T22') == null,
    'no remote hourly before Site validation',
  );
  _check(
    first.pendingHourlyPeriods.length == 1,
    'local pending survives missing Site',
  );
  await _adminPatch('tenants/final-tenant/devices/final-device', {
    'siteId': _stringField('wrong-site'),
  });
  final blocked = DeviceEnvironmentHistoryService(config: c, repository: repo);
  await feed(blocked, _art(2026, 9, 24, 23, 2), 30);
  _check(
    blocked.writesBlocked && await repo.loadHourly('2026-09-24T22') == null,
    'pending + mismatch causes zero writes',
  );
  await _adminPatch('tenants/final-tenant/devices/final-device', {
    'siteId': _stringField('final-site'),
  });
  // The original unavailable instance retries and verifies without restart.
  await feed(first, _art(2026, 9, 24, 23, 3), 30);
  _check(
    first.siteState == DeviceHistorySiteState.verified &&
        first.pendingHourlyPeriods.isEmpty,
    'unavailable to verified drains pending',
  );
  final recovered = DeviceEnvironmentHistoryService(
    config: c,
    repository: repo,
  );
  await feed(recovered, _art(2026, 9, 24, 23, 20), 30);
  await feed(recovered, _art(2026, 9, 25, 0, 1), 99);
  final daily = await repo.getDailyHistory(
    fromUtc: _art(2026, 9, 24, 0),
    toUtc: _art(2026, 9, 25, 0),
  );
  _check(
    daily.length == 1 &&
        daily.single.temperature.sampleCount == 2 &&
        daily.single.temperature.avg == 20,
    'restart daily: exactly two samples, weighted avg 20',
  );
  final hours = await repo.getHourlyHistory(
    fromUtc: DateTime.utc(2026, 9, 25, 2),
    toUtc: DateTime.utc(2026, 9, 25, 3),
  );
  _check(
    hours.length == 1 && hours.single.periodId == '2026-09-24T23',
    '02Z finds previous ART day',
  );
  final other = _repository(
    _config(
      tenantId: 'final-tenant',
      siteId: 'another-site',
      deviceId: 'final-device',
      checkpointDir: dir,
    ),
  );
  _check(
    await other.loadHourly('2026-09-24T23') == null,
    'loadHourly uses configured Site by default',
  );
  _check(
    (await other.loadHourlyForDate('2026-09-24')).isEmpty,
    'loadHourlyForDate default Site',
  );
  _check(
    (await other.getHourlyHistory(
      fromUtc: DateTime.utc(2026, 9, 24),
      toUtc: DateTime.utc(2026, 9, 26),
    )).isEmpty,
    'hourly range default Site',
  );
  _check(
    (await other.getDailyHistory(
      fromUtc: DateTime.utc(2026, 9, 24),
      toUtc: DateTime.utc(2026, 9, 26),
    )).isEmpty,
    'daily range default Site',
  );
  await repo.saveHourly(hours.single);
  _check(
    await _countDocuments(
          'tenants/final-tenant/devices/final-device/historyHourly',
        ) ==
        2,
    'replay retains two hourly documents',
  );
}
