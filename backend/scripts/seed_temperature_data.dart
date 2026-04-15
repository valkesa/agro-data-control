// Script de prueba: graba 3 registros horarios de temperatura inventados en
// Firestore para validar la conexión backend → base de datos.
//
// Uso:
//   cd backend
//   dart scripts/seed_temperature_data.dart
//
// Los datos se graban en:
//   tenants/the-gene-pig/sites/genetica-1/plcs/munters2/metrics/temperature/

import 'dart:io';

import 'package:agro_data_control_backend/src/firestore_temperature_history_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';

void main() async {
  stdout.writeln('=== seed_temperature_data ===');
  stdout.writeln('Grabando 3 registros horarios de temperatura inventados...\n');

  final String scriptDir = File(Platform.script.toFilePath()).parent.parent.path;
  final String serviceAccountPath =
      '$scriptDir/config/service-account.json';

  stdout.writeln('Usando service account: $serviceAccountPath');

  final TemperatureHistoryConfig config = TemperatureHistoryConfig(
    enabled: true,
    sourcePath: 'munters2.tempInterior',
    tenantId: 'the-gene-pig',
    siteId: 'genetica-1',
    plcId: 'munters2',
    firestoreProjectId: 'agro-data-control',
    firestoreDatabaseId: '(default)',
    firestoreServiceAccountPath: serviceAccountPath,
  );

  final FirestoreTemperatureHistoryRepository repo =
      FirestoreTemperatureHistoryRepository(config: config);

  if (!repo.isConfigured) {
    stderr.writeln('ERROR: repositorio no configurado: ${repo.missingConfigurationReason}');
    exit(1);
  }

  // ── Registros horarios inventados para hoy 2026-04-13 ──────────────────────
  // Hora 08:00 – mañana fresca
  // Hora 12:00 – mediodía más cálido
  // Hora 17:00 – tarde

  final List<TemperatureHourlyRecord> hourlyRecords = <TemperatureHourlyRecord>[
    TemperatureHourlyRecord(
      timestampHourStartUtc: DateTime.utc(2026, 4, 13, 11, 0), // 08:00 UTC-3
      dateKey: '2026-04-13',
      hourKey: '20260413_08',
      hour: 8,
      avgTemp: 18.4,
      minTemp: 17.1,
      maxTemp: 19.6,
      samplesCount: 3,
    ),
    TemperatureHourlyRecord(
      timestampHourStartUtc: DateTime.utc(2026, 4, 13, 15, 0), // 12:00 UTC-3
      dateKey: '2026-04-13',
      hourKey: '20260413_12',
      hour: 12,
      avgTemp: 23.7,
      minTemp: 22.5,
      maxTemp: 25.1,
      samplesCount: 3,
    ),
    TemperatureHourlyRecord(
      timestampHourStartUtc: DateTime.utc(2026, 4, 13, 20, 0), // 17:00 UTC-3
      dateKey: '2026-04-13',
      hourKey: '20260413_17',
      hour: 17,
      avgTemp: 21.2,
      minTemp: 20.0,
      maxTemp: 22.8,
      samplesCount: 3,
    ),
  ];

  // ── Grabar registros horarios ───────────────────────────────────────────────
  for (final TemperatureHourlyRecord record in hourlyRecords) {
    stdout.write(
      'Guardando horario ${record.hourKey} '
      'avg=${record.avgTemp}°C min=${record.minTemp}°C max=${record.maxTemp}°C ... ',
    );
    try {
      await repo.saveHourly(record);
      stdout.writeln('OK');
    } on Object catch (e) {
      stdout.writeln('ERROR: $e');
      exit(1);
    }
  }

  // ── Grabar registro diario ──────────────────────────────────────────────────
  final TemperatureDailyRecord dailyRecord = TemperatureDailyRecord(
    timestampDayStartUtc: DateTime.utc(2026, 4, 13, 0, 0),
    dateKey: '2026-04-13',
    avgTemp: 21.1,
    minTemp: 17.1,
    maxTemp: 25.1,
    hoursCount: 3,
  );

  stdout.write(
    'Guardando diario ${dailyRecord.dateKey} '
    'avg=${dailyRecord.avgTemp}°C min=${dailyRecord.minTemp}°C max=${dailyRecord.maxTemp}°C ... ',
  );
  try {
    await repo.saveDaily(dailyRecord);
    stdout.writeln('OK');
  } on Object catch (e) {
    stdout.writeln('ERROR: $e');
    exit(1);
  }

  stdout.writeln('\n✓ Datos grabados correctamente en Firestore.');
  stdout.writeln('  Path: tenants/the-gene-pig/sites/genetica-1/plcs/munters2/metrics/temperature/');
  stdout.writeln('  Horarios: 20260413_08, 20260413_12, 20260413_17');
  stdout.writeln('  Diario:   2026-04-13');
}
