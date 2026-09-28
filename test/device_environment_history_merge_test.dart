import 'package:agro_data_control/models/temperature_history_point.dart';
import 'package:agro_data_control/services/device_environment_history_repository.dart';
import 'package:agro_data_control/services/temperature_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _tenant = 'the-gene-pig';
const _site = 'las-heras';
const _sala1 = 'plc-genetica-sala1';

EnvironmentHistoryStats _stats(double v, {int count = 3}) =>
    EnvironmentHistoryStats(v, v - 1, v + 1, count);

class FakeLegacyRepository extends TemperatureHistoryRepository {
  final hourlyCalls = <Map<String, Object?>>[];
  final dailyCalls = <Map<String, Object?>>[];
  List<TemperatureHourlyPoint> hourlyPoints = const [];
  List<TemperatureDailyPoint> dailyPoints = const [];

  @override
  Future<List<TemperatureHourlyPoint>> fetchTemperatureHourlyHistory({
    required String tenantId,
    required String siteId,
    required String plcId,
    int limit = 24,
    DateTime? before,
  }) async {
    hourlyCalls.add({
      'tenantId': tenantId,
      'siteId': siteId,
      'plcId': plcId,
      'limit': limit,
      'before': before,
    });
    final filtered = before == null
        ? hourlyPoints
        : hourlyPoints
              .where((p) => p.timestampHourStart.isBefore(before))
              .toList();
    return filtered.take(limit).toList();
  }

  @override
  Future<List<TemperatureDailyPoint>> fetchTemperatureDailyHistory({
    required String tenantId,
    required String siteId,
    required String plcId,
    int limit = 30,
    String? beforeDateKey,
    String? fromDateKeyInclusive,
  }) async {
    dailyCalls.add({
      'tenantId': tenantId,
      'siteId': siteId,
      'plcId': plcId,
      'limit': limit,
      'beforeDateKey': beforeDateKey,
      'fromDateKeyInclusive': fromDateKeyInclusive,
    });
    var filtered = dailyPoints;
    if (beforeDateKey != null) {
      filtered = filtered
          .where((p) => p.dateKey.compareTo(beforeDateKey) < 0)
          .toList();
    }
    if (fromDateKeyInclusive != null) {
      filtered = filtered
          .where((p) => p.dateKey.compareTo(fromDateKeyInclusive) >= 0)
          .toList();
    }
    return filtered.take(limit).toList();
  }
}

TemperatureHourlyPoint hourly(DateTime start, double avg, {int count = 3}) =>
    TemperatureHourlyPoint(
      timestampHourStart: start,
      dateKey: '',
      hourKey: '',
      hour: start.hour,
      avgTemp: avg,
      minTemp: avg - 1,
      maxTemp: avg + 1,
      samplesCount: count,
    );

TemperatureDailyPoint daily(DateTime start, String dateKey, double avg) =>
    TemperatureDailyPoint(
      timestampDayStart: start,
      dateKey: dateKey,
      avgTemp: avg,
      minTemp: avg - 1,
      maxTemp: avg + 1,
      hoursCount: 20,
    );

/// Fakes only the modern Firestore read (loadModern); the legacy bridge and
/// the merge itself run for real, which is what these tests exercise.
class _MergeTestRepository extends DeviceEnvironmentHistoryRepository {
  _MergeTestRepository({required TemperatureHistoryRepository legacy})
    : super(legacyTemperature: legacy);
  List<EnvironmentHistoryPoint> modernPoints = const [];
  int modernCalls = 0;

  @override
  Future<List<EnvironmentHistoryPoint>> loadModern(
    EnvironmentHistoryScope scope,
    EnvironmentHistoryMode mode,
    int limit, {
    DateTime? beforeUtc,
  }) async {
    modernCalls++;
    final sorted = [...modernPoints]..sort((a, b) => a.start.compareTo(b.start));
    return sorted.length > limit
        ? sorted.sublist(sorted.length - limit)
        : sorted;
  }
}

void main() {
  const scope = EnvironmentHistoryScope(_tenant, _site, _sala1);

  test('merge horario: legacy + modern se combinan en una serie ordenada', () async {
    final legacy = FakeLegacyRepository()
      ..hourlyPoints = [
        hourly(DateTime.utc(2026, 9, 24, 12), 18),
        hourly(DateTime.utc(2026, 9, 24, 13), 19),
        hourly(DateTime.utc(2026, 9, 24, 14), 20),
      ];
    final repo = _MergeTestRepository(legacy: legacy)
      ..modernPoints = [
        EnvironmentHistoryPoint(
          DateTime.utc(2026, 9, 25, 12),
          _stats(21),
          _stats(75),
        ),
        EnvironmentHistoryPoint(
          DateTime.utc(2026, 9, 25, 13),
          _stats(22),
          _stats(76),
        ),
      ];
    final result = await repo.load(scope, EnvironmentHistoryMode.hourly, 24);
    expect(result.length, 5);
    expect(result.map((p) => p.start.hour), [12, 13, 14, 12, 13]);
    expect(
      result.first.temperatureSource,
      EnvironmentHistorySource.legacy,
    );
    expect(result.last.temperatureSource, EnvironmentHistorySource.modern);
    // Sanity: series is chronologically ascending end to end.
    for (var i = 1; i < result.length; i++) {
      expect(result[i].start.isAfter(result[i - 1].start), isTrue);
    }
  });

  test('solapamiento: mismo período en legacy y modern, modern gana', () async {
    final collision = DateTime.utc(2026, 9, 25, 12);
    final legacy = FakeLegacyRepository()
      ..hourlyPoints = [hourly(collision, 99)]; // legacy value, should be discarded
    final repo = _MergeTestRepository(legacy: legacy)
      ..modernPoints = [
        EnvironmentHistoryPoint(collision, _stats(21), _stats(75)),
      ];
    final result = await repo.load(scope, EnvironmentHistoryMode.hourly, 24);
    expect(result.length, 1);
    expect(result.single.temperature.avg, 21); // modern value, not legacy 99
    expect(result.single.temperatureSource, EnvironmentHistorySource.modern);
    expect(result.single.humidity.value, 75); // humidity only ever modern
  });

  test('ventana: modern aporta 10, legacy completa hasta 24 sin leer de más', () async {
    final legacy = FakeLegacyRepository()
      ..hourlyPoints = [
        for (var i = 0; i < 30; i++)
          hourly(DateTime.utc(2026, 9, 20).add(Duration(hours: i)), 15),
      ];
    final repo = _MergeTestRepository(legacy: legacy)
      ..modernPoints = [
        for (var i = 0; i < 10; i++)
          EnvironmentHistoryPoint(
            DateTime.utc(2026, 9, 25, 12).add(Duration(hours: i)),
            _stats(20),
            _stats(70),
          ),
      ];
    final result = await repo.load(scope, EnvironmentHistoryMode.hourly, 24);
    expect(result.length, 24);
    expect(legacy.hourlyCalls.single['limit'], 14); // 24 - 10, not 24
    expect(
      legacy.hourlyCalls.single['before'],
      DateTime.utc(2026, 9, 25, 12), // oldest modern point retained
    );
  });

  test('modern ya llena la ventana: no se lee legacy', () async {
    final legacy = FakeLegacyRepository()
      ..hourlyPoints = [hourly(DateTime.utc(2026, 9, 1), 15)];
    final repo = _MergeTestRepository(legacy: legacy)
      ..modernPoints = [
        for (var i = 0; i < 24; i++)
          EnvironmentHistoryPoint(
            DateTime.utc(2026, 9, 25).add(Duration(hours: i)),
            _stats(20),
            _stats(70),
          ),
      ];
    final result = await repo.load(scope, EnvironmentHistoryMode.hourly, 24);
    expect(result.length, 24);
    expect(legacy.hourlyCalls, isEmpty);
  });

  test('daily: mismo criterio de merge y ventana que hourly', () async {
    final legacy = FakeLegacyRepository()
      ..dailyPoints = [
        daily(DateTime.utc(2026, 8, 1), '2026-08-01', 17),
        daily(DateTime.utc(2026, 8, 2), '2026-08-02', 18),
      ];
    final repo = _MergeTestRepository(legacy: legacy)
      ..modernPoints = [
        EnvironmentHistoryPoint(
          DateTime.utc(2026, 9, 25, 3), // ART midnight 2026-09-25
          _stats(21),
          _stats(78),
        ),
      ];
    final result = await repo.load(scope, EnvironmentHistoryMode.daily, 30);
    expect(result.length, 3);
    expect(legacy.dailyCalls.single['limit'], 29);
    expect(legacy.dailyCalls.single['beforeDateKey'], '2026-09-25');
  });

  test('humedad: abrir Humedad nunca consulta legacy', () async {
    // The widget never asks the repository for a single metric — one fetch
    // covers both — so this asserts the structural guarantee instead: the
    // legacy bridge is only reachable through the temperature merge path,
    // and a point built from legacy always carries empty humidity.
    final legacy = FakeLegacyRepository()
      ..hourlyPoints = [hourly(DateTime.utc(2026, 9, 24, 12), 18)];
    final repo = _MergeTestRepository(legacy: legacy);
    final result = await repo.load(scope, EnvironmentHistoryMode.hourly, 24);
    expect(result.single.humidity.value, isNull);
    expect(result.single.humidity.sampleCount, 0);
  });

  test('cache: Temp -> Hum -> Temp no repite reads ya cargados', () async {
    final legacy = FakeLegacyRepository()
      ..hourlyPoints = [hourly(DateTime.utc(2026, 9, 24, 12), 18)];
    final repo = _MergeTestRepository(legacy: legacy)
      ..modernPoints = [
        EnvironmentHistoryPoint(
          DateTime.utc(2026, 9, 25, 12),
          _stats(21),
          _stats(75),
        ),
      ];
    await repo.fetch(scope, EnvironmentHistoryMode.hourly);
    await repo.fetch(scope, EnvironmentHistoryMode.hourly);
    await repo.fetch(scope, EnvironmentHistoryMode.hourly);
    expect(repo.modernCalls, 1);
    expect(legacy.hourlyCalls.length, 1);
  });

  test('Las Heras: site estructural resuelve M1/M2 y el bridge sigue usando genetica-1', () async {
    final legacy = FakeLegacyRepository()
      ..hourlyPoints = [hourly(DateTime.utc(2026, 9, 24, 12), 18)];
    final repo = _MergeTestRepository(legacy: legacy);
    // scope.siteId is las-heras (the real structural Site); the bridge must
    // still query the legacy tree under genetica-1 internally.
    await repo.load(scope, EnvironmentHistoryMode.hourly, 24);
    expect(scope.siteId, 'las-heras');
    expect(legacy.hourlyCalls.single['siteId'], 'genetica-1');
    expect(legacy.hourlyCalls.single['tenantId'], 'the-gene-pig');
    expect(legacy.hourlyCalls.single['plcId'], 'munters1');
  });

  test('tenant isolation: el bridge Gene Pig no se aplica a otro tenant', () async {
    final legacy = FakeLegacyRepository()
      ..hourlyPoints = [hourly(DateTime.utc(2026, 9, 24, 12), 18)];
    final repo = _MergeTestRepository(legacy: legacy);
    const otherScope = EnvironmentHistoryScope(
      'other-tenant',
      'other-site',
      'plc-genetica-sala1', // same physical id, different tenant
    );
    final result = await repo.load(
      otherScope,
      EnvironmentHistoryMode.hourly,
      24,
    );
    expect(result, isEmpty); // no modern points, and legacy never consulted
    expect(legacy.hourlyCalls, isEmpty);
  });
}
