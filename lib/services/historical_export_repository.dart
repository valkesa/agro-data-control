import 'package:cloud_firestore/cloud_firestore.dart';

import 'historical_export_point.dart';

export 'historical_export_point.dart' show HistoricalExportPoint;

/// Lee `historyHourly` directamente — nunca el esquema legacy
/// (`tenants/{t}/sites/{s}/plcs/{p}`), nunca `historyDaily`, nunca streams.
/// A propósito una clase aparte de `DeviceEnvironmentHistoryRepository`
/// (que sí mezcla legacy+moderno para el gráfico en vivo): la exportación
/// solo necesita una query puntual y acotada por rango sobre la colección
/// moderna, y mantenerla separada hace trivial auditar que ningún camino
/// legacy participa acá.
class HistoricalExportRepository {
  const HistoricalExportRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  /// Una sola `.get()` acotada por `[fromUtc, toUtcExclusive)` — nunca "todo
  /// el historial". Cualquier cantidad de variables seleccionadas se leen de
  /// la MISMA query/documento (todas viven en el mismo doc de
  /// `historyHourly`), así que el costo en lecturas de Firestore depende
  /// solo de cuántos Devices se exportan, nunca de cuántas variables.
  Future<List<HistoricalExportPoint>> fetchHourlyRange({
    required String tenantId,
    required String siteId,
    required String deviceId,
    required DateTime fromUtc,
    required DateTime toUtcExclusive,
  }) async {
    final result = await (_firestore ?? FirebaseFirestore.instance)
        .collection('tenants/$tenantId/devices/$deviceId/historyHourly')
        .where('periodStart', isGreaterThanOrEqualTo: Timestamp.fromDate(fromUtc))
        .where('periodStart', isLessThan: Timestamp.fromDate(toUtcExclusive))
        .orderBy('periodStart')
        .get();
    final points = <HistoricalExportPoint>[];
    for (final doc in result.docs) {
      final d = doc.data();
      if (d['tenantId'] != tenantId ||
          d['siteId'] != siteId ||
          d['deviceId'] != deviceId ||
          d['periodStart'] is! Timestamp) {
        continue;
      }
      points.add(
        HistoricalExportPoint((d['periodStart'] as Timestamp).toDate(), d),
      );
    }
    return points;
  }
}

/// ART midnight de [year]/[month]/[day] (ART = UTC-3), expresado como el
/// instante UTC equivalente — misma convención que el resto del código de
/// históricos (`device_environment_history_repository.dart`).
DateTime artDayStartUtc(int year, int month, int day) =>
    DateTime.utc(year, month, day, 3);
