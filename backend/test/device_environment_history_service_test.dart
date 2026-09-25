// Prompt_Historicos_Temperatura_Humedad_por_Device §19, hardened by
// Prompt_Cierre_Historicos_Ambientales_Robustez_H1_H7 §16 — tests for the
// aggregator (avg/min/max/sampleCount, independent temp/humidity validity,
// H11 null-not-zero), hour/day close (deterministic ID, H1 durable pending,
// no duplicate on retry), H2 restart dedup + recovery, H3 checkpoint
// identity isolation, H4 Site validation, H5 freshness gating, H6 durable
// daily pending, H7 exact range contract, and O(1) daily cost (no reread of
// 24 hourly documents per hour close).
//
// Run with: dart test/device_environment_history_service_test.dart

import 'dart:io';

import 'package:agro_data_control_backend/src/device_environment_history_service.dart';
import 'package:agro_data_control_backend/src/firestore_device_environment_history_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';

late Directory _testDisk;

Future<void> _run(Future<void> Function() test) async {
  _testDisk = await Directory.systemTemp.createTemp("env-history-test-");
  try {
    await test();
  } finally {
    await _testDisk.delete(recursive: true);
  }
}

Future<void> main() async {
  await _run(_testAggregatorAvgMinMaxSampleCount);
  await _run(_testInvalidSampleIgnored);
  await _run(_testTemperatureValidHumidityInvalid);
  await _run(_testHumidityValidTemperatureInvalid);
  await _run(_testZeroValidSamplesSkipsHour);
  await _run(_testSampleCountZeroIsNullNotZero);
  await _run(_testHourCloseDeterministicIdAndRetryNoDuplicate);
  await _run(_testDailyWeightedAverageAndMinMax);
  await _run(_testDailyDayChangeAccordingToArgentinaTimezone);
  await _run(_testScopeSeparation);
  await _run(_testPersistenceRoundtripAndRangeQuery);
  await _run(_testRestartRecoversFromLocalCheckpoint);

  // H1
  await _run(_testH1SaveHourlyFailureStaysPendingThenRecovers);
  await _run(_testH1PendingHourNeverOverwrittenByNextHour);
  // H2
  await _run(_testH2RestartMidSlotDoesNotDoubleCount);
  await _run(_testH2RestartAfterHourCloseRecoversPendingFirst);
  // H3
  await _run(_testH3CheckpointIdentityMismatchIgnored);
  // H4
  await _run(_testH4SiteMismatchBlocksWrites);
  await _run(_testH4SiteMatchProceeds);
  await _run(_testH4UnknownSiteDefersWrites);
  // H5
  await _run(_testH5PlcStopRejected);
  await _run(_testH5PlcOfflineRejected);
  await _run(_testH5DataNotFreshRejected);
  await _run(_testH5StaleNumericValueWithFreshFlagAccepted);
  // H6
  await _run(_testH6DailyFailureStaysPendingAcrossDayChange);
  // H7
  await _run(_testH7ExactHourRangeExcludesOutOfRange);
  await _run(_testH7RangeOver31DaysThrows);
  // Cost: O(1) daily, no reread.
  await _run(_testDailyDoesNotRereadHourlyDocuments);

  // ignore: avoid_print
  print('device_environment_history_service_test: all expectations passed');
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

DeviceEnvironmentHistoryConfig _config({
  String tenantId = 'test-tenant',
  String siteId = 'test-site',
  String deviceId = 'device-1',
  String checkpointDirectoryPath = '',
  String? firestoreProjectId = 'test-project',
}) {
  return DeviceEnvironmentHistoryConfig(
    enabled: true,
    temperatureSourcePath: 'unit1.tempInterior',
    humiditySourcePath: 'unit1.humInterior',
    tenantId: tenantId,
    siteId: siteId,
    deviceId: deviceId,
    firestoreProjectId: firestoreProjectId,
    firestoreDatabaseId: '(default)',
    firestoreServiceAccountPath: 'fake-path.json',
    checkpointDirectoryPath: checkpointDirectoryPath.isEmpty
        ? _testDisk.path
        : checkpointDirectoryPath,
  );
}

/// Fresh-by-default (H5): `dataFresh`/`plcOnline`/`plcRunning` all `true`
/// unless a test explicitly overrides them to exercise H5 rejection.
Map<String, Object?> _unitsJson({
  double? temp,
  double? hum,
  bool dataFresh = true,
  bool plcOnline = true,
  bool plcRunning = true,
}) {
  final Map<String, Object?> signals = <String, Object?>{
    'dataFresh': dataFresh,
    'plcOnline': plcOnline,
    'plcRunning': plcRunning,
  };
  if (temp != null) signals['tempInterior'] = temp;
  if (hum != null) signals['humInterior'] = hum;
  return <String, Object?>{'unit1': signals};
}

/// In-memory fake — stores every saved document keyed by its deterministic
/// periodId, so tests can assert on exact content and on write counts
/// without touching a real network or emulator.
class _FakeRepository extends FirestoreDeviceEnvironmentHistoryRepository {
  _FakeRepository({
    required super.config,
    this.deviceSiteId,
    this.siteUnavailable = false,
  });
  bool siteUnavailable;

  final Map<String, DeviceEnvironmentHourlyRecord> hourlyByPeriodId =
      <String, DeviceEnvironmentHourlyRecord>{};
  final Map<String, DeviceEnvironmentDailyRecord> dailyByPeriodId =
      <String, DeviceEnvironmentDailyRecord>{};
  int hourlyWriteCount = 0;
  int dailyWriteCount = 0;
  int hourlyReadCount = 0;

  /// The Device's real Site, as `fetchDeviceSiteId` would report it from
  /// Firestore. `null` simulates "Device document not found/no siteId".
  String? deviceSiteId;

  /// H1/H6 — when set, every `saveHourly`/`saveDaily` call throws instead
  /// of succeeding, simulating a Firestore outage.
  bool failWrites = false;

  @override
  bool get isConfigured => true;

  @override
  Future<String?> fetchDeviceSiteId() async =>
      siteUnavailable ? null : deviceSiteId ?? config.siteId;

  @override
  Future<void> saveHourly(DeviceEnvironmentHourlyRecord record) async {
    if (failWrites) {
      throw FirestoreDeviceEnvironmentHistoryException('simulated outage');
    }
    hourlyByPeriodId[record.periodId] = record;
    hourlyWriteCount += 1;
  }

  @override
  Future<void> saveDaily(DeviceEnvironmentDailyRecord record) async {
    if (failWrites) {
      throw FirestoreDeviceEnvironmentHistoryException('simulated outage');
    }
    dailyByPeriodId[record.periodId] = record;
    dailyWriteCount += 1;
  }

  @override
  Future<DeviceEnvironmentHourlyRecord?> loadHourly(
    String periodId, {
    String? expectedSiteId,
    void Function(String periodId, String actualSiteId)? onSiteMismatch,
  }) async {
    hourlyReadCount += 1;
    final DeviceEnvironmentHourlyRecord? record = hourlyByPeriodId[periodId];
    if (record == null) return null;
    if (record.siteId != (expectedSiteId ?? config.siteId)) {
      onSiteMismatch?.call(periodId, record.siteId);
      return null;
    }
    return record;
  }

  @override
  Future<List<DeviceEnvironmentHourlyRecord>> loadHourlyForDate(
    String dateKey, {
    String? expectedSiteId,
    void Function(String periodId, String actualSiteId)? onSiteMismatch,
  }) async {
    final List<DeviceEnvironmentHourlyRecord> results =
        <DeviceEnvironmentHourlyRecord>[];
    for (int hour = 0; hour < 24; hour += 1) {
      final String periodId = '${dateKey}T${hour.toString().padLeft(2, '0')}';
      final DeviceEnvironmentHourlyRecord? record = await loadHourly(
        periodId,
        expectedSiteId: expectedSiteId,
        onSiteMismatch: onSiteMismatch,
      );
      if (record != null) results.add(record);
    }
    return results;
  }
}

/// UTC helper: `art(hour, minute)` on [day] means that local-ART wall-clock
/// time, expressed as the equivalent UTC instant (ART = UTC-3).
DateTime _art(int year, int month, int day, int hour, [int minute = 0]) {
  return DateTime.utc(year, month, day, hour + 3, minute);
}

// ---------------------------------------------------------------------------
// Aggregator
// ---------------------------------------------------------------------------

Future<void> _testAggregatorAvgMinMaxSampleCount() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 22.0, hum: 65.0),
    observedAtUtc: _art(2026, 9, 24, 10, 20),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 21.0, hum: 55.0),
    observedAtUtc: _art(2026, 9, 24, 10, 40),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 70.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0), // forces hour 10 to close.
  );
  await service.dispose();

  final DeviceEnvironmentHourlyRecord? record =
      repository.hourlyByPeriodId['2026-09-24T10'];
  _expect(record != null, 'hourly record for hour 10 should exist');
  _expect(record!.temperature.sampleCount == 3, 'temperature sampleCount=3');
  _expect(record.humidity.sampleCount == 3, 'humidity sampleCount=3');
  _expectClose(record.temperature.avg!, 21.0, 'temperature avg = (20+22+21)/3');
  _expect(record.temperature.min == 20.0, 'temperature min=20.0');
  _expect(record.temperature.max == 22.0, 'temperature max=22.0');
  _expectClose(record.humidity.avg!, 60.0, 'humidity avg = (60+65+55)/3');
  _expect(record.humidity.min == 55.0, 'humidity min=55.0');
  _expect(record.humidity.max == 65.0, 'humidity max=65.0');
}

Future<void> _testInvalidSampleIgnored() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: double.nan, hum: double.nan),
    observedAtUtc: _art(2026, 9, 24, 10, 20),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 22.0, hum: 62.0),
    observedAtUtc: _art(2026, 9, 24, 10, 40),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 70.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  final DeviceEnvironmentHourlyRecord record =
      repository.hourlyByPeriodId['2026-09-24T10']!;
  _expect(
    record.temperature.sampleCount == 2,
    'NaN sample must not count: expected 2, got ${record.temperature.sampleCount}',
  );
  _expect(
    record.humidity.sampleCount == 2,
    'NaN sample must not count: expected 2, got ${record.humidity.sampleCount}',
  );
}

Future<void> _testTemperatureValidHumidityInvalid() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: null),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  final DeviceEnvironmentHourlyRecord record =
      repository.hourlyByPeriodId['2026-09-24T10']!;
  _expect(record.temperature.sampleCount == 1, 'temperature increments alone');
  _expect(record.humidity.sampleCount == 0, 'humidity stays at 0 when null');
}

Future<void> _testHumidityValidTemperatureInvalid() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: null, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  final DeviceEnvironmentHourlyRecord record =
      repository.hourlyByPeriodId['2026-09-24T10']!;
  _expect(record.temperature.sampleCount == 0, 'temperature stays at 0');
  _expect(record.humidity.sampleCount == 1, 'humidity increments alone');
}

Future<void> _testZeroValidSamplesSkipsHour() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: null, hum: null),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: null, hum: null),
    observedAtUtc: _art(2026, 9, 24, 10, 20),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  _expect(
    !repository.hourlyByPeriodId.containsKey('2026-09-24T10'),
    'an hour with zero valid samples for both metrics must not be written',
  );
}

Future<void> _testSampleCountZeroIsNullNotZero() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: null),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  final DeviceEnvironmentHourlyRecord record =
      repository.hourlyByPeriodId['2026-09-24T10']!;
  _expect(
    record.humidity.sampleCount == 0,
    'H11 fixture: humidity really has 0 samples',
  );
  _expect(
    record.humidity.avg == null,
    'H11: avg must be null, not 0.0, when sampleCount is 0 — got ${record.humidity.avg}',
  );
  _expect(record.humidity.min == null, 'H11: min must be null');
  _expect(record.humidity.max == null, 'H11: max must be null');
}

// ---------------------------------------------------------------------------
// Hora
// ---------------------------------------------------------------------------

Future<void> _testHourCloseDeterministicIdAndRetryNoDuplicate() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 25.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 14, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 15, 0),
  );
  await service.dispose();
  _expect(
    repository.hourlyByPeriodId.containsKey('2026-09-24T14'),
    'deterministic hourly ID must be dateKey + T + 2-digit hour',
  );
  _expect(repository.hourlyWriteCount == 1, 'exactly one write for hour 14');

  final DeviceEnvironmentHourlyRecord original =
      repository.hourlyByPeriodId['2026-09-24T14']!;
  await repository.saveHourly(original);
  _expect(
    repository.hourlyByPeriodId.length == 1,
    'retrying the same period must not create a second document',
  );
}

// ---------------------------------------------------------------------------
// Día
// ---------------------------------------------------------------------------

Future<void> _testDailyWeightedAverageAndMinMax() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 40.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 40.0),
    observedAtUtc: _art(2026, 9, 24, 10, 20),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 40.0),
    observedAtUtc: _art(2026, 9, 24, 10, 40),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0), // closes hour 10.
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 11, 20),
  );
  // Next day forces hour 11 AND the day itself to close (Option B —
  // write-once-at-close).
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 15.0, hum: 30.0),
    observedAtUtc: _art(2026, 9, 25, 0, 0),
  );
  await service.dispose();

  final DeviceEnvironmentDailyRecord daily =
      repository.dailyByPeriodId['2026-09-24']!;
  // (20*3 + 30*2) / 5 = 24, not 25 (plain average of hour averages).
  _expectClose(daily.temperature.avg!, 24.0, 'weighted daily avg');
  _expect(daily.temperature.sampleCount == 5, 'daily sampleCount = 3 + 2');
  _expect(daily.temperature.min == 20.0, 'daily min across both hours');
  _expect(daily.temperature.max == 30.0, 'daily max across both hours');
  _expectClose(daily.humidity.avg!, 44.0, '(40*3 + 50*2) / 5 = 44');
  _expect(
    repository.dailyWriteCount == 1,
    'daily written exactly once (Option B)',
  );
}

Future<void> _testDailyDayChangeAccordingToArgentinaTimezone() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 18.0, hum: 55.0),
    observedAtUtc: DateTime.utc(2026, 9, 25, 2, 0), // = 2026-09-24 23:00 ART.
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 19.0, hum: 56.0),
    observedAtUtc: DateTime.utc(2026, 9, 25, 2, 20),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 10.0, hum: 40.0),
    observedAtUtc: DateTime.utc(2026, 9, 25, 3, 0), // 00:00 ART next day.
  );
  await service.dispose();

  _expect(
    repository.hourlyByPeriodId.containsKey('2026-09-24T23'),
    'a sample at 02:00-02:20 UTC on the 25th belongs to 2026-09-24T23 ART',
  );
}

// ---------------------------------------------------------------------------
// Scope
// ---------------------------------------------------------------------------

Future<void> _testScopeSeparation() async {
  final _FakeRepository repoTenantA = _FakeRepository(
    config: _config(tenantId: 'tenant-a', deviceId: 'sala1'),
  );
  final _FakeRepository repoTenantB = _FakeRepository(
    config: _config(tenantId: 'tenant-b', deviceId: 'sala1'),
  );
  final _FakeRepository repoSiteB = _FakeRepository(
    config: _config(tenantId: 'tenant-a', siteId: 'site-b', deviceId: 'sala1'),
  );
  final _FakeRepository repoSala2 = _FakeRepository(
    config: _config(tenantId: 'tenant-a', deviceId: 'sala2'),
  );

  final DeviceEnvironmentHistoryService serviceA =
      DeviceEnvironmentHistoryService(
        config: _config(tenantId: 'tenant-a', deviceId: 'sala1'),
        repository: repoTenantA,
      );
  final DeviceEnvironmentHistoryService serviceB =
      DeviceEnvironmentHistoryService(
        config: _config(tenantId: 'tenant-b', deviceId: 'sala1'),
        repository: repoTenantB,
      );
  final DeviceEnvironmentHistoryService serviceSiteB =
      DeviceEnvironmentHistoryService(
        config: _config(
          tenantId: 'tenant-a',
          siteId: 'site-b',
          deviceId: 'sala1',
        ),
        repository: repoSiteB,
      );
  final DeviceEnvironmentHistoryService serviceSala2 =
      DeviceEnvironmentHistoryService(
        config: _config(tenantId: 'tenant-a', deviceId: 'sala2'),
        repository: repoSala2,
      );

  for (final (DeviceEnvironmentHistoryService, _FakeRepository) pair
      in <(DeviceEnvironmentHistoryService, _FakeRepository)>[
        (serviceA, repoTenantA),
        (serviceB, repoTenantB),
        (serviceSiteB, repoSiteB),
        (serviceSala2, repoSala2),
      ]) {
    pair.$1.handleSnapshot(
      unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
      observedAtUtc: _art(2026, 9, 24, 10, 0),
    );
    pair.$1.handleSnapshot(
      unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
      observedAtUtc: _art(2026, 9, 24, 11, 0),
    );
    await pair.$1.dispose();
  }

  for (final _FakeRepository repo in <_FakeRepository>[
    repoTenantA,
    repoTenantB,
    repoSiteB,
    repoSala2,
  ]) {
    _expect(
      repo.hourlyByPeriodId.length == 1,
      'each independent repository received exactly its own write, no '
      'cross-contamination between tenants/sites/devices',
    );
  }
  _expect(
    repoTenantA.hourlyByPeriodId['2026-09-24T10']!.tenantId == 'tenant-a',
    'tenant-a record carries its own tenantId',
  );
  _expect(
    repoTenantB.hourlyByPeriodId['2026-09-24T10']!.tenantId == 'tenant-b',
    'tenant-b record carries its own tenantId',
  );
  _expect(
    repoSiteB.hourlyByPeriodId['2026-09-24T10']!.siteId == 'site-b',
    'site-b record carries its own siteId',
  );
  _expect(
    repoSala2.hourlyByPeriodId['2026-09-24T10']!.deviceId == 'sala2',
    'Sala2 record carries deviceId=sala2, independent from Sala1',
  );
}

// ---------------------------------------------------------------------------
// Persistencia — roundtrip + query por rango (fake repository)
// ---------------------------------------------------------------------------

Future<void> _testPersistenceRoundtripAndRangeQuery() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 20, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 20, 11, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 22.0, hum: 52.0),
    observedAtUtc: _art(2026, 9, 21, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 21, 11, 0),
  );
  await service.dispose();

  final DeviceEnvironmentHourlyRecord? roundtripped = await repository
      .loadHourly('2026-09-20T10');
  _expect(roundtripped != null, 'loadHourly must return the saved record');
  _expect(roundtripped!.temperature.avg == 20.0, 'roundtrip preserves avg');

  final List<DeviceEnvironmentHourlyRecord> range = await repository
      .getHourlyHistory(
        fromUtc: DateTime.utc(2026, 9, 20),
        toUtc: DateTime.utc(2026, 9, 22),
      );
  // 2026-09-20T10, 2026-09-20T11, 2026-09-21T10 (2026-09-21T11 never closes).
  _expect(
    range.length == 3,
    'range query across 2026-09-20..22(exclusive) returns 3 records, got ${range.length}',
  );
}

// ---------------------------------------------------------------------------
// Reinicios — checkpoint local en disco
// ---------------------------------------------------------------------------

Future<void> _testRestartRecoversFromLocalCheckpoint() async {
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'device-env-history-checkpoint-',
  );
  try {
    final DeviceEnvironmentHistoryConfig config = _config(
      deviceId: 'restart-device',
      checkpointDirectoryPath: tempDir.path,
    );
    final _FakeRepository repository = _FakeRepository(config: config);

    final DeviceEnvironmentHistoryService instance1 =
        DeviceEnvironmentHistoryService(config: config, repository: repository);
    instance1.handleSnapshot(
      unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
      observedAtUtc: _art(2026, 9, 24, 10, 0),
    );
    instance1.handleSnapshot(
      unitsJson: _unitsJson(temp: 22.0, hum: 52.0),
      observedAtUtc: _art(2026, 9, 24, 10, 20),
    );
    await instance1.dispose();
    _expect(
      repository.hourlyByPeriodId.isEmpty,
      'nothing should be in Firestore yet — the hour has not closed',
    );

    final DeviceEnvironmentHistoryService instance2 =
        DeviceEnvironmentHistoryService(config: config, repository: repository);
    instance2.handleSnapshot(
      unitsJson: _unitsJson(temp: 24.0, hum: 54.0),
      observedAtUtc: _art(2026, 9, 24, 10, 40),
    );
    instance2.handleSnapshot(
      unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
      observedAtUtc: _art(2026, 9, 24, 11, 0),
    );
    await instance2.dispose();

    final DeviceEnvironmentHourlyRecord? record =
        repository.hourlyByPeriodId['2026-09-24T10'];
    _expect(record != null, 'hour 10 should have closed');
    _expect(
      record!.temperature.sampleCount == 3,
      'recovered 2 samples + 1 new one before close = 3, '
      'got ${record.temperature.sampleCount}',
    );
    _expectClose(
      record.temperature.avg!,
      22.0,
      '(20 + 22 + 24) / 3 = 22, proving checkpointed samples were folded '
      'back into the average, not just the count',
    );
  } finally {
    await tempDir.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// H1 — Horas pendientes durables
// ---------------------------------------------------------------------------

Future<void> _testH1SaveHourlyFailureStaysPendingThenRecovers() async {
  final _FakeRepository repository = _FakeRepository(config: _config())
    ..failWrites = true;
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0), // closes hour 10 — save fails.
  );
  await service.dispose();

  _expect(
    !repository.hourlyByPeriodId.containsKey('2026-09-24T10'),
    'Firestore write failed — nothing confirmed yet',
  );
  _expect(
    service.pendingHourlyPeriods.length == 1 &&
        service.pendingHourlyPeriods.single.periodId == '2026-09-24T10',
    'the closed hour must be held durably pending, not discarded (H1)',
  );

  // Firestore recovers; the next sample (or a retry pass) must persist it.
  repository.failWrites = false;
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 32.0, hum: 62.0),
    observedAtUtc: _art(2026, 9, 24, 11, 20),
  );
  await service.dispose();

  _expect(
    repository.hourlyByPeriodId.containsKey('2026-09-24T10'),
    'once Firestore recovers, the pending hour must be persisted',
  );
  _expect(
    service.pendingHourlyPeriods.isEmpty,
    'confirmed period must be removed from pending',
  );
}

Future<void> _testH1PendingHourNeverOverwrittenByNextHour() async {
  final _FakeRepository repository = _FakeRepository(config: _config())
    ..failWrites = true;
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 25.0, hum: 55.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0), // closes hour 10 (fails).
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 12, 0), // closes hour 11 (fails too).
  );
  await service.dispose();

  _expect(
    service.pendingHourlyPeriods.length == 2,
    'two consecutive failed hours must both remain pending independently, '
    'never overwriting one another — got ${service.pendingHourlyPeriods.length}',
  );
  final Set<String> ids = service.pendingHourlyPeriods
      .map((DeviceEnvironmentHourlyRecord r) => r.periodId)
      .toSet();
  _expect(
    ids.containsAll(<String>['2026-09-24T10', '2026-09-24T11']),
    'both hour 10 and hour 11 must be present in pending',
  );
}

// ---------------------------------------------------------------------------
// H2 — Reinicio y deduplicación
// ---------------------------------------------------------------------------

Future<void> _testH2RestartMidSlotDoesNotDoubleCount() async {
  final Directory tempDir = await Directory.systemTemp.createTemp('h2-dedup-');
  try {
    final DeviceEnvironmentHistoryConfig config = _config(
      deviceId: 'h2-device',
      checkpointDirectoryPath: tempDir.path,
    );
    final _FakeRepository repository = _FakeRepository(config: config);

    final DeviceEnvironmentHistoryService instance1 =
        DeviceEnvironmentHistoryService(config: config, repository: repository);
    instance1.handleSnapshot(
      unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
      observedAtUtc: _art(2026, 9, 24, 10, 20),
    );
    await instance1.dispose();

    // "Restart" 30 seconds later, same 20-minute slot re-delivered by a
    // fresh poll cycle.
    final DeviceEnvironmentHistoryService instance2 =
        DeviceEnvironmentHistoryService(config: config, repository: repository);
    instance2.handleSnapshot(
      unitsJson: _unitsJson(temp: 20.5, hum: 50.5),
      observedAtUtc: _art(2026, 9, 24, 10, 20).add(const Duration(seconds: 30)),
    );
    instance2.handleSnapshot(
      unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
      observedAtUtc: _art(2026, 9, 24, 11, 0), // closes hour 10.
    );
    await instance2.dispose();

    final DeviceEnvironmentHourlyRecord record =
        repository.hourlyByPeriodId['2026-09-24T10']!;
    _expect(
      record.temperature.sampleCount == 1,
      'the 10:20 slot must be counted exactly once across the restart, got '
      '${record.temperature.sampleCount}',
    );
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<void> _testH2RestartAfterHourCloseRecoversPendingFirst() async {
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'h2-recover-pending-',
  );
  try {
    final DeviceEnvironmentHistoryConfig config = _config(
      deviceId: 'h2-recover-device',
      checkpointDirectoryPath: tempDir.path,
    );
    final _FakeRepository repository = _FakeRepository(config: config)
      ..failWrites = true;

    final DeviceEnvironmentHistoryService instance1 =
        DeviceEnvironmentHistoryService(config: config, repository: repository);
    instance1.handleSnapshot(
      unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
      observedAtUtc: _art(2026, 9, 24, 10, 40),
    );
    instance1.handleSnapshot(
      unitsJson: _unitsJson(temp: 25.0, hum: 55.0),
      // 11:00 ART closes hour 10 — but Firestore is down, so it stays
      // pending and durable in the checkpoint.
      observedAtUtc: _art(2026, 9, 24, 11, 0),
    );
    await instance1.dispose();

    // Backend restarts at 11:00 with hour 10 pending, Firestore now healthy.
    repository.failWrites = false;
    final DeviceEnvironmentHistoryService instance2 =
        DeviceEnvironmentHistoryService(config: config, repository: repository);
    instance2.handleSnapshot(
      unitsJson: _unitsJson(temp: 26.0, hum: 56.0),
      observedAtUtc: _art(2026, 9, 24, 11, 20),
    );
    await instance2.dispose();

    _expect(
      repository.hourlyByPeriodId.containsKey('2026-09-24T10'),
      'hour 10, pending before the restart, must be persisted first (H2/§14)',
    );
  } finally {
    await tempDir.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// H3 — Aislamiento de checkpoint
// ---------------------------------------------------------------------------

Future<void> _testH3CheckpointIdentityMismatchIgnored() async {
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'h3-isolation-',
  );
  try {
    final DeviceEnvironmentHistoryConfig configA = _config(
      tenantId: 'tenant-a',
      deviceId: 'shared-device-id',
      checkpointDirectoryPath: tempDir.path,
    );
    final _FakeRepository repoA = _FakeRepository(config: configA);
    final DeviceEnvironmentHistoryService serviceA =
        DeviceEnvironmentHistoryService(config: configA, repository: repoA);
    serviceA.handleSnapshot(
      unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
      observedAtUtc: _art(2026, 9, 24, 10, 0),
    );
    await serviceA.dispose();

    // Same deviceId, different tenant, pointed at the SAME checkpoint
    // directory (simulating a misconfiguration that would otherwise let
    // two tenants collide on one checkpoint file).
    final DeviceEnvironmentHistoryConfig configB = _config(
      tenantId: 'tenant-b',
      deviceId: 'shared-device-id',
      checkpointDirectoryPath: tempDir.path,
    );
    final _FakeRepository repoB = _FakeRepository(config: configB);
    final DeviceEnvironmentHistoryService serviceB =
        DeviceEnvironmentHistoryService(config: configB, repository: repoB);
    serviceB.handleSnapshot(
      unitsJson: _unitsJson(temp: 99.0, hum: 99.0),
      observedAtUtc: _art(2026, 9, 24, 10, 20),
    );
    serviceB.handleSnapshot(
      unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
      observedAtUtc: _art(2026, 9, 24, 11, 0),
    );
    await serviceB.dispose();

    final DeviceEnvironmentHourlyRecord recordB =
        repoB.hourlyByPeriodId['2026-09-24T10']!;
    _expect(
      recordB.temperature.sampleCount == 1,
      'tenant-b must never have restored tenant-a\'s in-progress accumulator '
      '(different filename per identity already prevents this — H3 is the '
      'belt-and-suspenders content check), got '
      '${recordB.temperature.sampleCount} samples',
    );
    _expect(
      recordB.tenantId == 'tenant-b',
      'the persisted record must carry tenant-b, never tenant-a data mixed in',
    );
  } finally {
    await tempDir.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// H4 — Validación real del Site
// ---------------------------------------------------------------------------

Future<void> _testH4SiteMismatchBlocksWrites() async {
  final _FakeRepository repository = _FakeRepository(
    config: _config(siteId: 'configured-site'),
    deviceSiteId: 'actual-different-site',
  );
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(siteId: 'configured-site'),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  _expect(
    service.writesBlocked,
    'a confirmed Site mismatch must permanently block this writer (H4)',
  );
  _expect(
    repository.hourlyByPeriodId.isEmpty,
    'no data may be written once the Site mismatch is confirmed',
  );
}

Future<void> _testH4SiteMatchProceeds() async {
  final _FakeRepository repository = _FakeRepository(
    config: _config(siteId: 'the-real-site'),
    deviceSiteId: 'the-real-site',
  );
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(siteId: 'the-real-site'),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  _expect(!service.writesBlocked, 'a matching Site must never block writes');
  _expect(
    repository.hourlyByPeriodId.containsKey('2026-09-24T10'),
    'writes proceed normally once the Site is confirmed to match',
  );
}

Future<void> _testH4UnknownSiteDefersWrites() async {
  // deviceSiteId left null — simulates the Device document not existing
  // yet / not having a siteId, which cannot be treated as a *confirmed*
  // mismatch.
  final _FakeRepository repository = _FakeRepository(
    config: _config(),
    siteUnavailable: true,
  );
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  _expect(
    !service.writesBlocked,
    'an inconclusive Site check (no Device doc found) is unavailable, not a permanent mismatch',
  );
  _expect(
    repository.hourlyByPeriodId.isEmpty &&
        service.pendingHourlyPeriods.length == 1,
    'writes remain pending until the Site can be verified',
  );
}

// ---------------------------------------------------------------------------
// H5 — Frescura del PLC
// ---------------------------------------------------------------------------

Future<void> _testH5PlcStopRejected() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0, plcRunning: false),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  _expect(
    !repository.hourlyByPeriodId.containsKey('2026-09-24T10'),
    'a sample taken while plcRunning=false (STOP) must never accumulate (H5)',
  );
}

Future<void> _testH5PlcOfflineRejected() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0, plcOnline: false),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  _expect(
    !repository.hourlyByPeriodId.containsKey('2026-09-24T10'),
    'a sample taken while plcOnline=false must never accumulate (H5)',
  );
}

Future<void> _testH5DataNotFreshRejected() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0, dataFresh: false),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  _expect(
    !repository.hourlyByPeriodId.containsKey('2026-09-24T10'),
    'a sample taken while dataFresh=false must never accumulate (H5)',
  );
}

/// The exact real-world scenario the audit flagged: a PLC that goes to
/// STOP can keep returning its last, perfectly-finite numeric reading
/// forever — only the freshness flags distinguish that from a live value.
Future<void> _testH5StaleNumericValueWithFreshFlagAccepted() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  // Same finite temperature value repeated while genuinely fresh — sanity
  // check that a fresh, merely-unchanging value IS accepted (the gate is on
  // freshness flags, not on the value "looking different").
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 30.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0),
  );
  await service.dispose();

  _expect(
    repository.hourlyByPeriodId['2026-09-24T10']!.temperature.sampleCount == 1,
    'a genuinely fresh sample must still be accepted even if its value is '
    'unremarkable/unchanged from a plausible previous reading',
  );
}

// ---------------------------------------------------------------------------
// H6 — Daily pendiente durable
// ---------------------------------------------------------------------------

Future<void> _testH6DailyFailureStaysPendingAcrossDayChange() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 20.0, hum: 50.0),
    observedAtUtc: _art(2026, 9, 24, 10, 0),
  );
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 25.0, hum: 55.0),
    observedAtUtc: _art(2026, 9, 24, 11, 0), // closes hour 10.
  );
  await service.dispose();
  _expect(repository.dailyByPeriodId.isEmpty, 'day has not rolled over yet');

  // Firestore goes down right as the day rolls over.
  repository.failWrites = true;
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 15.0, hum: 30.0),
    observedAtUtc: _art(2026, 9, 25, 0, 0), // closes 2026-09-24 (fails).
  );
  await service.dispose();

  _expect(
    !repository.dailyByPeriodId.containsKey('2026-09-24'),
    'daily write failed — nothing confirmed yet',
  );
  _expect(
    service.pendingDailyPeriods.any(
      (DeviceEnvironmentDailyRecord r) => r.periodId == '2026-09-24',
    ),
    'the failed daily must be held durably pending even though the day has '
    'already changed (H6)',
  );

  // Firestore recovers on the NEXT day's cycle.
  repository.failWrites = false;
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 16.0, hum: 31.0),
    observedAtUtc: _art(2026, 9, 25, 0, 20),
  );
  await service.dispose();

  _expect(
    repository.dailyByPeriodId.containsKey('2026-09-24'),
    'the pending daily for 2026-09-24 must eventually be persisted, even '
    'though "today" is now the 25th',
  );
  _expect(service.pendingDailyPeriods.isEmpty, 'retired once confirmed');
}

// ---------------------------------------------------------------------------
// H7 — Contrato de rango
// ---------------------------------------------------------------------------

Future<void> _testH7ExactHourRangeExcludesOutOfRange() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  for (final int hour in <int>[9, 10, 18]) {
    service.handleSnapshot(
      unitsJson: _unitsJson(temp: hour.toDouble(), hum: 50.0),
      observedAtUtc: _art(2026, 9, 24, hour, 0),
    );
    service.handleSnapshot(
      unitsJson: _unitsJson(temp: 99.0, hum: 60.0),
      observedAtUtc: _art(2026, 9, 24, hour + 1, 0), // forces close.
    );
  }
  await service.dispose();

  // Local 10:00-11:00 ART = UTC 13:00-14:00.
  final List<DeviceEnvironmentHourlyRecord> range = await repository
      .getHourlyHistory(
        fromUtc: DateTime.utc(2026, 9, 24, 13, 0),
        toUtc: DateTime.utc(2026, 9, 24, 14, 0),
      );
  _expect(
    range.length == 1 && range.single.periodId == '2026-09-24T10',
    'a 10:00-11:00 range must return exactly the 10:00 hour, never the 18:00 '
    'one — got ${range.map((DeviceEnvironmentHourlyRecord r) => r.periodId).toList()}',
  );
}

Future<void> _testH7RangeOver31DaysThrows() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  bool threw = false;
  try {
    await repository.getHourlyHistory(
      fromUtc: DateTime.utc(2026, 1, 1),
      toUtc: DateTime.utc(2026, 3, 1), // ~59 days.
    );
  } on DeviceEnvironmentHistoryRangeTooLargeException {
    threw = true;
  }
  _expect(
    threw,
    'a range over 31 days must throw explicitly (H7), never silently truncate',
  );
}

// ---------------------------------------------------------------------------
// Costo — el diario no debe releer 24 documentos horarios por cierre de hora.
// ---------------------------------------------------------------------------

Future<void> _testDailyDoesNotRereadHourlyDocuments() async {
  final _FakeRepository repository = _FakeRepository(config: _config());
  final DeviceEnvironmentHistoryService service =
      DeviceEnvironmentHistoryService(
        config: _config(),
        repository: repository,
      );

  for (int hour = 0; hour < 5; hour += 1) {
    service.handleSnapshot(
      unitsJson: _unitsJson(temp: 20.0 + hour, hum: 50.0),
      observedAtUtc: _art(2026, 9, 24, hour, 0),
    );
  }
  service.handleSnapshot(
    unitsJson: _unitsJson(temp: 99.0, hum: 60.0),
    observedAtUtc: _art(2026, 9, 24, 5, 0), // closes hour 4.
  );
  await service.dispose();

  _expect(
    repository.hourlyReadCount == 0,
    'the daily accumulator is folded in-memory (O(1)) — closing hours must '
    'never call loadHourly/loadHourlyForDate, got ${repository.hourlyReadCount} reads',
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('Assertion failed: $message');
  }
}

void _expectClose(double actual, double expected, String message) {
  if ((actual - expected).abs() > 0.0001) {
    throw StateError(
      'Assertion failed: $message (expected $expected, got $actual)',
    );
  }
}
