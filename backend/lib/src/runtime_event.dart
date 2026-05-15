class RuntimeEvent {
  const RuntimeEvent({
    required this.deviceType,
    required this.startedAt,
    required this.endedAt,
    required this.durationSec,
    required this.plcId,
    this.deviceIsOn,
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

  // Heartbeat for an active (ON) device — records ongoing segment duration.
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
      deviceIsOn: true,
      powerPercent: powerPercent,
      powerWatts: powerWatts,
      energyKwh: energyKwh,
    );
  }

  // Status heartbeat for an OFF device — records that the device is off at
  // this moment. startedAt == observedAt, durationSec == 0.
  factory RuntimeEvent.offHeartbeat({
    required String deviceType,
    required DateTime observedAt,
    required String plcId,
    int? powerPercent,
  }) {
    return RuntimeEvent(
      deviceType: deviceType,
      startedAt: observedAt,
      endedAt: observedAt,
      durationSec: 0,
      plcId: plcId,
      deviceIsOn: false,
      powerPercent: powerPercent,
    );
  }

  final String deviceType;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSec;
  final String plcId;
  // Explicit ON/OFF state at heartbeat time. Null for closed events.
  final bool? deviceIsOn;
  final int? powerPercent;
  final double? powerWatts;
  final double? energyKwh;
}
