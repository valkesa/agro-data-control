import 'munters_model.dart';
import 'dashboard_door_event.dart';

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.units,
    required this.doorEvents,
    required this.backendOnline,
    required this.lastUpdatedAt,
    required this.startedAt,
    this.clientName,
  });

  final List<MuntersModel> units;
  final Map<String, DashboardDoorEvent> doorEvents;
  final bool backendOnline;
  final DateTime? lastUpdatedAt;
  final DateTime? startedAt;
  final String? clientName;

  /// [units] keyed by [MuntersModel.historyPlcId] (the backend snapshot's
  /// unit key, e.g. `munters1`, or an `AgroDevice.snapshotUnitKey` for
  /// dynamic-schema devices) — for O(1) lookup when joining against a
  /// Device list (see `AgroDevice.effectiveSnapshotUnitKey`). Computed, not
  /// stored, so it can never drift out of sync with [units]. Entries whose
  /// `historyPlcId` is null (e.g. placeholder units) are skipped.
  Map<String, MuntersModel> get unitsByKey => <String, MuntersModel>{
    for (final MuntersModel unit in units)
      if (unit.historyPlcId != null) unit.historyPlcId!: unit,
  };

  String? get lastUpdateLabel {
    final DateTime? timestamp = lastUpdatedAt;
    if (timestamp == null) {
      return null;
    }

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}:${twoDigits(timestamp.second)}';
  }

  factory DashboardSnapshot.placeholder({bool backendOnline = false}) {
    return DashboardSnapshot(
      units: const [
        MuntersModel.placeholder(name: 'Munters 1'),
        MuntersModel.placeholder(name: 'Munters 2'),
      ],
      doorEvents: const <String, DashboardDoorEvent>{},
      backendOnline: backendOnline,
      lastUpdatedAt: null,
      startedAt: null,
      clientName: null,
    );
  }
}
