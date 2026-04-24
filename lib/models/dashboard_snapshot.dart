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
