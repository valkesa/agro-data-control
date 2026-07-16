class AlertRuntimeConfig {
  const AlertRuntimeConfig({
    this.cooldown = const Duration(minutes: 10),
    this.hysteresis = const AlertHysteresisConfig(),
  });

  final Duration cooldown;
  final AlertHysteresisConfig hysteresis;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'cooldownMinutes': cooldown.inMinutes,
      'hysteresis': hysteresis.toJson(),
    };
  }
}

class AlertHysteresisConfig {
  const AlertHysteresisConfig({
    this.dewPointRiskC = 0.2,
    this.temperatureC = 1.0,
    this.humidityPercent = 2.0,
  });

  final double dewPointRiskC;
  final double temperatureC;
  final double humidityPercent;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'dewPointRiskC': dewPointRiskC,
      'temperatureC': temperatureC,
      'humidityPercent': humidityPercent,
    };
  }
}
