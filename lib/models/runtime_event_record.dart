import 'package:cloud_firestore/cloud_firestore.dart';

class RuntimeEventRecord {
  const RuntimeEventRecord({
    required this.id,
    required this.deviceType,
    required this.plcId,
    required this.startedAt,
    required this.durationSec,
    required this.isHeartbeat,
    this.endedAt,
    this.observedAt,
    this.deviceIsOn,
    this.powerPercent,
    this.powerWatts,
    this.energyKwh,
  });

  final String id;
  final String deviceType;
  final String plcId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? observedAt;
  final int durationSec;
  final bool isHeartbeat;
  // Explicit ON/OFF state stored by the backend. Null for closed events or old HBs.
  final bool? deviceIsOn;
  final int? powerPercent;
  final double? powerWatts;
  final double? energyKwh;

  DateTime get eventTime => endedAt ?? observedAt ?? startedAt;

  static RuntimeEventRecord? fromFirestore(Map<String, dynamic> data, String id) {
    try {
      final bool isOpen = data['isOpen'] as bool? ?? false;
      final String? deviceType = data['deviceType'] as String?;
      final String? plcId = data['plcId'] as String?;
      if (deviceType == null || plcId == null) return null;

      final bool? deviceIsOn = data['deviceIsOn'] as bool?;

      DateTime? startedAt;
      DateTime? endedAt;
      DateTime? observedAt;
      int durationSec;

      if (isOpen) {
        final Timestamp? observedAtTs = data['observedAt'] as Timestamp?;
        observedAt = observedAtTs?.toDate();
        durationSec = (data['activeDurationSec'] as num?)?.toInt() ?? 0;
        final Timestamp? startedAtTs = data['startedAt'] as Timestamp?;
        // OFF heartbeats don't write startedAt — fall back to observedAt.
        startedAt = startedAtTs?.toDate() ?? observedAt;
      } else {
        final Timestamp? startedAtTs = data['startedAt'] as Timestamp?;
        if (startedAtTs == null) return null;
        startedAt = startedAtTs.toDate();
        final Timestamp? ts = data['endedAt'] as Timestamp?;
        endedAt = ts?.toDate();
        durationSec = (data['durationSec'] as num?)?.toInt() ?? 0;
      }

      if (startedAt == null) return null;

      return RuntimeEventRecord(
        id: id,
        deviceType: deviceType,
        plcId: plcId,
        startedAt: startedAt,
        endedAt: endedAt,
        observedAt: observedAt,
        durationSec: durationSec,
        isHeartbeat: isOpen,
        deviceIsOn: deviceIsOn,
        powerPercent: (data['powerPercent'] as num?)?.toInt(),
        powerWatts: (data['powerWatts'] as num?)?.toDouble(),
        energyKwh: (data['energyKwh'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
