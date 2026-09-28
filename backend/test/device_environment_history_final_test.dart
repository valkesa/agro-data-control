import 'dart:convert';
import 'dart:io';
import 'package:agro_data_control_backend/src/device_environment_history_service.dart';
import 'package:agro_data_control_backend/src/firestore_device_environment_history_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';

void check(bool ok, String reason) {
  if (!ok) throw StateError(reason);
}

DateTime art(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 9, day, hour + 3, minute);
DeviceEnvironmentHistoryConfig config(
  Directory dir, {
  String project = 'test-project',
  String database = '(default)',
  String tenant = 'tenant',
  String site = 'site',
  String device = 'device',
}) => DeviceEnvironmentHistoryConfig(
  enabled: true,
  temperatureSourcePath: 'u.tempInterior',
  humiditySourcePath: 'u.humInterior',
  tenantId: tenant,
  siteId: site,
  deviceId: device,
  firestoreProjectId: project,
  firestoreDatabaseId: database,
  firestoreServiceAccountPath: 'unused',
  checkpointDirectoryPath: dir.path,
);

class Repo extends FirestoreDeviceEnvironmentHistoryRepository {
  Repo(superConfig) : super(config: superConfig);
  final hourly = <String, DeviceEnvironmentHourlyRecord>{};
  final daily = <String, DeviceEnvironmentDailyRecord>{};
  final events = <String>[];
  bool failWrites = false, siteMissing = false, siteError = false;
  String? actualSite;
  void Function()? afterHourly, afterDaily;
  @override
  bool get isConfigured => true;
  @override
  Future<String?> fetchDeviceSiteId() async {
    events.add('site');
    if (siteError) throw StateError('site unavailable');
    return siteMissing ? null : actualSite ?? this.config.siteId;
  }

  @override
  Future<void> saveHourly(DeviceEnvironmentHourlyRecord r) async {
    events.add('hour');
    if (failWrites) throw StateError('network');
    hourly[r.periodId] = r;
    afterHourly?.call();
  }

  @override
  Future<void> saveDaily(DeviceEnvironmentDailyRecord r) async {
    events.add('day');
    if (failWrites) throw StateError('network');
    daily[r.periodId] = r;
    afterDaily?.call();
  }

  @override
  Future<DeviceEnvironmentHourlyRecord?> loadHourly(
    String id, {
    String? expectedSiteId,
    void Function(String, String)? onSiteMismatch,
  }) async {
    final r = hourly[id];
    return r?.siteId == (expectedSiteId ?? this.config.siteId) ? r : null;
  }
}

Future<void> feed(
  DeviceEnvironmentHistoryService s,
  DateTime when, {
  double temp = 20,
}) async {
  s.handleSnapshot(
    unitsJson: {
      'u': {
        'tempInterior': temp,
        'humInterior': 50.0,
        'dataFresh': true,
        'plcOnline': true,
        'plcRunning': true,
      },
    },
    observedAtUtc: when,
  );
  await s.dispose();
}

DeviceEnvironmentHistoryService service(
  DeviceEnvironmentHistoryConfig c,
  Repo r,
) => DeviceEnvironmentHistoryService(config: c, repository: r);
Map<String, dynamic> state(DeviceEnvironmentHistoryService s) =>
    jsonDecode(File(s.checkpointPath).readAsStringSync())
        as Map<String, dynamic>;
Future<void> run(String name, Future<void> Function(Directory) test) async {
  final d = await Directory.systemTemp.createTemp('env-final-');
  try {
    await test(d);
    print('PASS $name');
  } finally {
    await d.delete(recursive: true);
  }
}

Future<void> main() async {
  await run('C1 restart fuera del minuto de muestra no duplica daily', (
    d,
  ) async {
    final c = config(d), r = Repo(config(d));
    final s = service(c, r);
    await feed(s, art(24, 10, 40), temp: 10);
    await feed(s, art(24, 11, 1));
    check(state(s)['currentHour'] == null, 'closed hour retired durably');
    final next = service(c, r);
    await feed(next, art(24, 11, 2));
    await feed(next, art(24, 11, 20), temp: 30);
    await feed(next, art(25, 0));
    check(r.daily['2026-09-24']!.temperature.sampleCount == 2, 'daily count');
    check(r.daily['2026-09-24']!.temperature.avg == 20, 'daily avg');
  });
  await run(
    'A/B/C rollback antes del checkpoint; recuperación después de filesystem sano',
    (d) async {
      final c = config(d), r = Repo(config(d));
      final s = service(c, r);
      await feed(s, art(24, 10, 40));
      final before = File(s.checkpointPath).readAsStringSync();
      final obstacle = Directory('${s.checkpointPath}.tmp')..createSync();
      await feed(s, art(24, 11, 1));
      check(
        s.durabilityDegraded &&
            r.hourly.isEmpty &&
            s.pendingHourlyPeriods.isEmpty,
        'failed transition rolled back',
      );
      check(
        File(s.checkpointPath).readAsStringSync() == before,
        'durable A remains intact; B/C never published',
      );
      obstacle.deleteSync();
      await feed(s, art(24, 11, 2));
      check(
        !s.durabilityDegraded && r.hourly.length == 1,
        'filesystem recovery',
      );
      await feed(s, art(25, 0));
      check(
        r.daily['2026-09-24']!.temperature.sampleCount == 1,
        'fold once after retry',
      );
    },
  );
  await run(
    'D/E horario durable antes de write y replay de confirmación sin retiro',
    (d) async {
      final c = config(d), r = Repo(config(d));
      final s = service(c, r);
      await feed(s, art(24, 10, 40));
      String? captured;
      r.afterHourly = () {
        captured = File(s.checkpointPath).readAsStringSync();
        Directory('${s.checkpointPath}.tmp').createSync();
      };
      await feed(s, art(24, 11, 1));
      check(
        s.durabilityDegraded && s.pendingHourlyPeriods.length == 1,
        'E pending not removed when checkpoint fails',
      );
      final j = jsonDecode(captured!);
      check(
        j['currentHour'] == null && j['pendingHourlyPeriods'].length == 1,
        'D coherent',
      );
      final created = r.hourly.values.single.createdAtUtc;
      Directory('${s.checkpointPath}.tmp').deleteSync();
      r.afterHourly = null;
      final next = service(c, r);
      await feed(next, art(24, 11, 2));
      await feed(next, art(25, 0));
      check(
        r.hourly.length == 1 && r.hourly.values.single.createdAtUtc == created,
        'stable id/content/createdAt after E',
      );
      check(
        r.daily['2026-09-24']!.temperature.sampleCount == 1,
        'E replay no extra fold',
      );
    },
  );
  await run('F/G daily durable; confirmación sin retiro sobrevive restart', (
    d,
  ) async {
    final c = config(d), r = Repo(config(d));
    final s = service(c, r);
    await feed(s, art(24, 22));
    await feed(s, art(24, 23, 1)); // F: hourly confirmed, active daily.
    final f = File(s.checkpointPath).readAsStringSync();
    r.afterDaily = () {
      final j = state(s);
      check(
        j['dailyAccumulator'] == null &&
            (j['pendingDailyPeriods'] as List).length == 1,
        'G coherent',
      );
      Directory('${s.checkpointPath}.tmp').createSync();
    };
    await feed(s, art(25, 0, 1));
    check(
      s.pendingDailyPeriods.length == 1,
      'daily retained after failed ack checkpoint',
    );
    Directory('${s.checkpointPath}.tmp').deleteSync();
    r.afterDaily = null;
    final next = service(c, r);
    await feed(next, art(25, 0, 2));
    check(
      next.pendingDailyPeriods.isEmpty && r.daily.length == 1,
      'G recovered',
    );
    File(
      s.checkpointPath,
    ).writeAsStringSync(f); // Restart at F: no day close persisted yet.
    await feed(service(c, r), art(25, 0, 3));
    check(
      r.daily.values.single.temperature.sampleCount == 1,
      'F replay count stable',
    );
  });
  await run('C1 marcador de fold ignora una hora ya incorporada', (d) async {
    final c = config(d), r = Repo(config(d));
    final s = service(c, r);
    await feed(s, art(24, 10, 40));
    final hour = state(s)['currentHour'];
    await feed(s, art(24, 11, 1));
    final j = state(s);
    j['currentHour'] = hour;
    File(s.checkpointPath).writeAsStringSync(jsonEncode(j));
    final next = service(c, r);
    await feed(next, art(24, 11, 2));
    await feed(next, art(25, 0));
    check(
      r.daily['2026-09-24']!.temperature.sampleCount == 1,
      'same period ignored by fold identity',
    );
  });
  await run('C2 pending y Site contradictorio: cero writes', (d) async {
    final c = config(d), r = Repo(config(d))..failWrites = true;
    final s = service(c, r);
    await feed(s, art(24, 23));
    await feed(s, art(25, 0));
    final blocked = Repo(c)..actualSite = 'other';
    final next = service(c, blocked);
    await feed(next, art(25, 0, 20));
    check(
      next.writesBlocked && blocked.events.join(',') == 'site',
      'Site checked before hourly AND daily recovery',
    );
    check(
      next.pendingHourlyPeriods.isNotEmpty &&
          next.pendingDailyPeriods.isNotEmpty,
      'pending preserved',
    );
  });
  for (final mismatch in [false, true]) {
    await run(
      'C3 temporalmente unavailable luego ${mismatch ? 'mismatch' : 'verified'}',
      (d) async {
        final c = config(d), r = Repo(config(d))..siteError = true;
        final s = service(c, r);
        await feed(s, art(24, 10));
        await feed(s, art(24, 11));
        check(
          s.siteState == DeviceHistorySiteState.temporarilyUnavailable &&
              r.hourly.isEmpty &&
              s.pendingHourlyPeriods.length == 1,
          'no writes while unverified',
        );
        r.siteError = false;
        r.actualSite = mismatch ? 'other' : c.siteId;
        await feed(s, art(24, 11, 20));
        check(
          mismatch ? r.hourly.isEmpty : r.hourly.length == 1,
          'gate after retry',
        );
      },
    );
  }
  await run('C4 ART/UTC, medianoches y contrato 31 días', (d) async {
    final c = config(d), r = Repo(config(d));
    final s = service(c, r);
    await feed(s, art(24, 21));
    await feed(s, art(24, 23));
    await feed(s, art(25, 0));
    await feed(s, art(25, 1));
    final result = await r.getHourlyHistory(
      fromUtc: DateTime.utc(2026, 9, 25, 2),
      toUtc: DateTime.utc(2026, 9, 25, 3),
    );
    check(
      result.length == 1 && result.single.periodId == '2026-09-24T23',
      '02Z finds previous ART date',
    );
    final midnight = await r.getHourlyHistory(
      fromUtc: DateTime.utc(2026, 9, 25),
      toUtc: DateTime.utc(2026, 9, 25, 4),
    );
    check(midnight.length == 3, 'UTC midnight + ART midnight');
    final from = DateTime.utc(2026, 9, 1);
    await r.getHourlyHistory(
      fromUtc: from,
      toUtc: from.add(const Duration(days: 31)),
    );
    await r.getHourlyHistory(
      fromUtc: from,
      toUtc: from.add(const Duration(days: 30, hours: 23, minutes: 59)),
    );
    check(
      (await r.getHourlyHistory(fromUtc: from, toUtc: from)).isEmpty,
      'empty',
    );
    for (final end in [
      from.add(const Duration(days: 31, seconds: 1)),
      from.subtract(const Duration(seconds: 1)),
    ]) {
      var threw = false;
      try {
        await r.getHourlyHistory(fromUtc: from, toUtc: end);
      } on DeviceEnvironmentHistoryRangeException {
        threw = true;
      }
      check(threw, 'invalid duration rejected');
    }
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'schema999': (j) => j['schemaVersion'] = 999,
    'missing': (j) => j.remove('pendingDailyPeriods'),
    'type': (j) => j['pendingHourlyPeriods'] = 'bad',
    'identity': (j) => j['tenantId'] = 'other',
    'internal pending identity': (j) =>
        j['pendingHourlyPeriods'][0]['siteId'] = 'other',
    'internal pending database': (j) =>
        j['pendingHourlyPeriods'][0]['firestoreDatabaseId'] = 'other',
    'timestamp': (j) =>
        j['pendingHourlyPeriods'][0]['periodStart'] = 'not-a-date',
    'stats': (j) =>
        j['pendingHourlyPeriods'][0]['temperature']['sampleCount'] = -1,
    // Epsilon must not become a loophole: an egregiously wrong avg (not a
    // float64 rounding artifact) still has to be rejected.
    'stats bounds egregious': (j) =>
        j['pendingHourlyPeriods'][0]['temperature']['avg'] =
            (j['pendingHourlyPeriods'][0]['temperature']['max'] as num) + 1.0,
  };
  for (final e in mutations.entries) {
    await run('C5 rejected ${e.key}', (d) async {
      final c = config(d), r = Repo(config(d))..failWrites = true;
      final s = service(c, r);
      await feed(s, art(24, 10));
      await feed(s, art(24, 11));
      final j = state(s);
      e.value(j);
      File(s.checkpointPath).writeAsStringSync(jsonEncode(j));
      r.failWrites = false;
      await feed(service(c, r), art(24, 11, 20));
      check(
        r.hourly.isEmpty &&
            d.listSync().any((f) => f.path.contains('.rejected.')),
        'quarantined, never sent',
      );
    });
  }
  // Real incident, 2026-09-25: three identical samples (e.g. 23.6 three
  // times) average to 23.600000000000005 in float64 — a hair above their
  // own max. The OLD zero-tolerance `stats bounds` check threw on THIS
  // exact value on every single _commitLocal (the "before" snapshot round
  // trip runs the same validator), which is outside its own try/catch and
  // silently wedged the whole per-Device pipeline for ~19h on both Salas —
  // /health stayed green throughout because nothing there watched this.
  // failWrites mirrors production's actual failure mode: the record stays
  // pending (confirmation never drains it) across the restart, exactly
  // like the real checkpoints found stuck on the VPS.
  await run(
    'regresión: redondeo float64 en avg no debe congelar el pipeline (incidente 2026-09-25)',
    (d) async {
      final c = config(d), r = Repo(config(d))..failWrites = true;
      final s = service(c, r);
      await feed(s, art(24, 10, 0), temp: 23.6);
      await feed(s, art(24, 10, 20), temp: 23.6);
      await feed(s, art(24, 10, 40), temp: 23.6);
      // Closes the 10:00 hour; the pending record's avg lands a float64
      // hair above max — this used to throw on every commit from here on.
      await feed(s, art(24, 11, 0), temp: 23.6);
      final pending = state(s)['pendingHourlyPeriods'] as List;
      check(pending.isNotEmpty, 'hour actually closed into a pending record');
      final temp = pending.single['temperature'] as Map;
      check(
        (temp['avg'] as num) > (temp['max'] as num),
        'reproduces the real float64 artifact (avg marginally above max)',
      );
      // The real symptom: a fresh instance recovering this exact on-disk
      // checkpoint (still holding the "poisoned" pending record) must keep
      // accepting new samples and eventually confirm the write, instead of
      // silently wedging like production did for ~19h.
      r.failWrites = false;
      final s2 = service(c, r);
      await feed(s2, art(24, 11, 20), temp: 23.6);
      await feed(s2, art(24, 11, 40), temp: 23.6);
      final j = state(s2);
      check(
        j['currentHour'] != null && (j['currentHour']['tempCount'] as int) >= 1,
        'kept accepting new samples instead of freezing at the old slot',
      );
      // lastSampleSlot is stored as the ART wall-clock value tagged UTC
      // (same host-TZ-independent convention as the rest of this checkpoint
      // — see argentinaUtcOffset docs), not the true UTC instant art()
      // produces for feeding samples.
      check(
        j['lastSampleSlot'] == DateTime.utc(2026, 9, 24, 11, 40).toIso8601String(),
        'lastSampleSlot advanced past the incident hour, not stuck at the old slot',
      );
      check(
        r.hourly.containsKey('2026-09-24T10'),
        'the previously-stuck pending record eventually reached Firestore',
      );
      check(
        (state(s2)['pendingHourlyPeriods'] as List).isEmpty,
        'drained from the checkpoint once confirmed',
      );
    },
  );
  // Diagnostic signal added after the incident: isStalled()/healthJson()
  // must catch "PLC keeps delivering fresh data but history stopped
  // advancing" regardless of WHICH internal failure mode is behind it —
  // here durability (checkpoint writes failing), not the validator bug
  // above. This is why freshness tracking sits at the very top of
  // _process(), ahead of the durability early-return.
  await run(
    'diagnóstico: isStalled detecta datos frescos sin avance del historial',
    (d) async {
      final c = config(d), r = Repo(config(d));
      final s = service(c, r);
      await feed(s, art(24, 10, 40));
      check(!s.isStalled(), 'not stalled right after a healthy sample');
      final obstacle = Directory('${s.checkpointPath}.tmp')..createSync();
      // Minutes below stay on the 20-minute sample grid (sampleIntervalMinutes)
      // so acceptance is only ever blocked by the obstacle, never by
      // _resolveSampleSlot rejecting an off-grid minute. Each feed still
      // observes fresh PLC data (freshness is recorded before the durability
      // check) but every commit fails, so lastSampleSlot never advances past
      // 10:40.
      await feed(s, art(24, 11, 40));
      check(
        s.durabilityDegraded,
        'sanity: this reproduces a durability stall, not the float64 one',
      );
      check(
        !s.isStalled(),
        'not stalled yet: fresh data trails the last sample by only ~1h, under the 2h threshold',
      );
      await feed(s, art(24, 13, 40));
      check(
        s.isStalled(),
        'stalled: fresh data now trails the last accepted sample by 3h',
      );
      check(
        s.healthJson()['stalled'] == true,
        'the same signal is exposed through healthJson for /health',
      );
      obstacle.deleteSync();
      await feed(s, art(24, 13, 40));
      check(
        !s.isStalled() && !s.durabilityDegraded,
        'recovers once the filesystem obstacle is gone and a sample is accepted again',
      );
      check(
        s.lastSampleSlot == DateTime.utc(2026, 9, 24, 13, 40),
        'the retried sample actually advanced lastSampleSlot past the stall',
      );
    },
  );
  await run('C5 invalid JSON', (d) async {
    final c = config(d), r = Repo(config(d));
    final s = service(c, r);
    File(s.checkpointPath).writeAsStringSync('{');
    await feed(s, art(24, 10));
    check(
      d.listSync().any((f) => f.path.contains('.rejected.')),
      'invalid JSON preserved',
    );
  });
  await run('C6 project y database físicamente separados', (d) async {
    final paths = <String>{};
    for (final project in ['a', 'b']) {
      for (final db in ['(default)', 'other']) {
        final c = config(d, project: project, database: db),
            r = Repo(config(d, project: project, database: db));
        final s = service(c, r);
        paths.add(s.checkpointPath);
        await feed(s, art(24, 10, 20));
        await feed(service(c, r), art(24, 11));
        check(
          r.hourly.values.single.temperature.sampleCount == 1,
          'independent recovery',
        );
      }
    }
    check(paths.length == 4, 'four physical files');
  });
  print('FINAL C1-C7: all expectations passed');
}
