// Etapa 2/2 — repository-level coverage for month pagination (fetchMonth/
// loadMonth/loadModernRange). Mirrors device_environment_history_merge_test
// .dart's approach: only the two real Firestore-adjacent seams are faked
// (loadModernRange here, legacy via FakeLegacyRepository); the merge itself
// runs for real.
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
  final dailyCalls = <Map<String, Object?>>[];
  List<TemperatureDailyPoint> dailyPoints = const [];

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

TemperatureDailyPoint daily(DateTime artMidnightUtc, String dateKey, double avg) =>
    TemperatureDailyPoint(
      timestampDayStart: artMidnightUtc,
      dateKey: dateKey,
      avgTemp: avg,
      minTemp: avg - 1,
      maxTemp: avg + 1,
      hoursCount: 20,
    );

EnvironmentHistoryPoint modernDay(int year, int month, int day, double avg) =>
    EnvironmentHistoryPoint(
      DateTime.utc(year, month, day, 3), // ART midnight expressed in UTC
      _stats(avg),
      _stats(avg + 50),
    );

/// Fakes only loadModernRange; fetchMonth/loadMonth run for real.
class _MonthTestRepository extends DeviceEnvironmentHistoryRepository {
  _MonthTestRepository({required TemperatureHistoryRepository legacy})
    : super(legacyTemperature: legacy);
  List<EnvironmentHistoryPoint> modernPoints = const [];
  int modernRangeCalls = 0;
  DateTime? lastFrom, lastTo;

  @override
  Future<List<EnvironmentHistoryPoint>> loadModernRange(
    EnvironmentHistoryScope scope,
    DateTime fromUtc,
    DateTime toUtcExclusive,
  ) async {
    modernRangeCalls++;
    lastFrom = fromUtc;
    lastTo = toUtcExclusive;
    final inRange = modernPoints
        .where((p) => !p.start.isBefore(fromUtc) && p.start.isBefore(toUtcExclusive))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return inRange;
  }
}

void main() {
  const scope = EnvironmentHistoryScope(_tenant, _site, _sala1);

  test('EnvironmentHistoryMonth.previous cruza el año correctamente', () {
    expect(
      const EnvironmentHistoryMonth(2026, 1).previous,
      const EnvironmentHistoryMonth(2025, 12),
    );
    expect(
      const EnvironmentHistoryMonth(2026, 9).previous,
      const EnvironmentHistoryMonth(2026, 8),
    );
  });

  test('mes completo en modern: no se consulta legacy', () async {
    final legacy = FakeLegacyRepository();
    final repo = _MonthTestRepository(legacy: legacy)
      ..modernPoints = [
        for (var d = 1; d <= 30; d++) modernDay(2026, 9, d, 20),
      ];
    final result = await repo.fetchMonth(
      scope,
      const EnvironmentHistoryMonth(2026, 9),
    );
    expect(result.length, 30);
    expect(legacy.dailyCalls, isEmpty);
    // Rango consultado: exactamente el mes, dos límites (nunca "toda la
    // historia").
    expect(repo.lastFrom, DateTime.utc(2026, 9, 1, 3));
    expect(repo.lastTo, DateTime.utc(2026, 10, 1, 3));
  });

  test('mes cruzando el punto de corte legacy/modern: se combinan sin duplicar', () async {
    // Agosto 2026: días 1-15 solo legacy, 16-31 modern (simula el punto de
    // corte real, que en producción cae en septiembre, pero el mecanismo es
    // el mismo cualquiera sea el mes).
    final legacy = FakeLegacyRepository()
      ..dailyPoints = [
        for (var d = 1; d <= 20; d++)
          daily(DateTime.utc(2026, 8, d, 3), '2026-08-${d.toString().padLeft(2, '0')}', 15),
      ];
    final repo = _MonthTestRepository(legacy: legacy)
      ..modernPoints = [
        for (var d = 16; d <= 31; d++) modernDay(2026, 8, d, 22),
      ];
    final result = await repo.fetchMonth(
      scope,
      const EnvironmentHistoryMonth(2026, 8),
    );
    expect(result.length, 31); // 1-31, sin huecos ni duplicados
    // Día 16-20 existe en ambas fuentes: modern gana.
    final day16 = result.firstWhere((p) => p.start.day == 16);
    expect(day16.temperature.avg, 22); // modern, no 15 (legacy)
    expect(day16.temperatureSource, EnvironmentHistorySource.modern);
    final day1 = result.firstWhere((p) => p.start.day == 1);
    expect(day1.temperatureSource, EnvironmentHistorySource.legacy);
    // Legacy se acotó al mes, no pidió de más.
    expect(legacy.dailyCalls.single['fromDateKeyInclusive'], '2026-08-01');
    expect(legacy.dailyCalls.single['beforeDateKey'], '2026-09-01');
  });

  test('mes íntegramente legacy (antes de la activación moderna)', () async {
    final legacy = FakeLegacyRepository()
      ..dailyPoints = [
        for (var d = 1; d <= 30; d++)
          daily(DateTime.utc(2026, 4, d, 3), '2026-04-${d.toString().padLeft(2, '0')}', 12),
      ];
    final repo = _MonthTestRepository(legacy: legacy);
    final result = await repo.fetchMonth(
      scope,
      const EnvironmentHistoryMonth(2026, 4),
    );
    expect(result.length, 30);
    expect(result.every((p) => p.temperatureSource == EnvironmentHistorySource.legacy), isTrue);
    expect(result.every((p) => p.humidity.value == null), isTrue); // sin humedad vieja
  });

  test('mes sin datos en ninguna fuente: lista vacía (floor de historia)', () async {
    final legacy = FakeLegacyRepository();
    final repo = _MonthTestRepository(legacy: legacy);
    final result = await repo.fetchMonth(
      scope,
      const EnvironmentHistoryMonth(2025, 1),
    );
    expect(result, isEmpty);
  });

  test('cache por mes: pedir el mismo mes dos veces no repite queries', () async {
    final legacy = FakeLegacyRepository()
      ..dailyPoints = [daily(DateTime.utc(2026, 8, 1, 3), '2026-08-01', 15)];
    final repo = _MonthTestRepository(legacy: legacy);
    await repo.fetchMonth(scope, const EnvironmentHistoryMonth(2026, 8));
    await repo.fetchMonth(scope, const EnvironmentHistoryMonth(2026, 8));
    await repo.fetchMonth(scope, const EnvironmentHistoryMonth(2026, 8));
    expect(repo.modernRangeCalls, 1);
    expect(legacy.dailyCalls.length, 1);
  });

  test('doble solicitud concurrente del mismo mes: 1 sola query (dedup)', () async {
    final legacy = FakeLegacyRepository();
    final repo = _MonthTestRepository(legacy: legacy)
      ..modernPoints = [modernDay(2026, 9, 1, 20)];
    await Future.wait([
      repo.fetchMonth(scope, const EnvironmentHistoryMonth(2026, 9)),
      repo.fetchMonth(scope, const EnvironmentHistoryMonth(2026, 9)),
    ]);
    expect(repo.modernRangeCalls, 1);
  });

  test('meses distintos son cache keys distintas', () async {
    final legacy = FakeLegacyRepository();
    final repo = _MonthTestRepository(legacy: legacy)
      ..modernPoints = [
        modernDay(2026, 8, 1, 19),
        modernDay(2026, 9, 1, 20),
      ];
    await repo.fetchMonth(scope, const EnvironmentHistoryMonth(2026, 8));
    await repo.fetchMonth(scope, const EnvironmentHistoryMonth(2026, 9));
    expect(repo.modernRangeCalls, 2);
  });

  test('tenant isolation: el bridge Gene Pig no aplica a otro tenant', () async {
    final legacy = FakeLegacyRepository()
      ..dailyPoints = [daily(DateTime.utc(2026, 8, 1, 3), '2026-08-01', 15)];
    final repo = _MonthTestRepository(legacy: legacy);
    const otherScope = EnvironmentHistoryScope(
      'other-tenant',
      'other-site',
      'plc-genetica-sala1',
    );
    final result = await repo.fetchMonth(
      otherScope,
      const EnvironmentHistoryMonth(2026, 8),
    );
    expect(result, isEmpty);
    expect(legacy.dailyCalls, isEmpty);
  });
}
