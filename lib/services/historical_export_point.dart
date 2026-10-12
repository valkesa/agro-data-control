/// One `historyHourly`-shaped data point, kept as the raw decoded map (not
/// split into named fields) so [HistoricalExportVariable.extractAvg] — and
/// any variable added to the registry later — can read it without this
/// class knowing variable names.
///
/// Deliberately has NO `cloud_firestore` import (unlike
/// `HistoricalExportRepository`, which produces these from a live query):
/// a plain `dart run` script (no Flutter engine) can't load
/// `cloud_firestore` at all (it pulls in `dart:ui` transitively) — moving
/// this plain data class out of `historical_export_repository.dart` is what
/// lets a one-off extraction script build the same `.xlsx` via
/// `buildHistoricalExportWorkbook` without needing the Flutter SDK, see
/// `tool/export_legacy_genetica_temperature.dart`.
class HistoricalExportPoint {
  const HistoricalExportPoint(this.periodStartUtc, this.raw);
  final DateTime periodStartUtc;
  final Map<String, Object?> raw;
}
