class RuntimeEvent {
  const RuntimeEvent({
    required this.deviceType,
    required this.startedAt,
    required this.endedAt,
    required this.durationSec,
    required this.plcId,
    this.powerPercent,
    this.powerWatts,
    this.energyKwh,
  });

  factory RuntimeEvent.closed({
    required String deviceType,
    required DateTime startedAt,
    required DateTime endedAt,
    required String plcId,
    int? powerPercent,
    double? powerWatts,
  }) {
    final int durationSec = endedAt.difference(startedAt).inSeconds.abs();
    final double? energyKwh = powerWatts == null
        ? null
        : (powerWatts / 1000) * (durationSec / 3600);
    return RuntimeEvent(
      deviceType: deviceType,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSec: durationSec,
      plcId: plcId,
      powerPercent: powerPercent,
      powerWatts: powerWatts,
      energyKwh: energyKwh,
    );
  }

  factory RuntimeEvent.heartbeat({
    required String deviceType,
    required DateTime startedAt,
    required DateTime observedAt,
    required String plcId,
    int? powerPercent,
    double? powerWatts,
  }) {
    final int durationSec = observedAt.difference(startedAt).inSeconds.abs();
    final double? energyKwh = powerWatts == null
        ? null
        : (powerWatts / 1000) * (durationSec / 3600);
    return RuntimeEvent(
      deviceType: deviceType,
      startedAt: startedAt,
      endedAt: observedAt,
      durationSec: durationSec,
      plcId: plcId,
      powerPercent: powerPercent,
      powerWatts: powerWatts,
      energyKwh: energyKwh,
    );
  }

  final String deviceType;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSec;
  final String plcId;
  final int? powerPercent;
  final double? powerWatts;
  final double? energyKwh;
}
