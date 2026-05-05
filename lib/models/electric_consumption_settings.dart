class ElectricConsumptionSettings {
  const ElectricConsumptionSettings({
    this.fanLevels = const <FanConsumptionLevel>[],
    this.humidifierPumpKw,
    this.heaterStage1Kw,
    this.heaterStage2Kw,
  });

  const ElectricConsumptionSettings.defaults()
    : fanLevels = const <FanConsumptionLevel>[],
      humidifierPumpKw = null,
      heaterStage1Kw = null,
      heaterStage2Kw = null;

  factory ElectricConsumptionSettings.fromFirestore(Map<String, dynamic> data) {
    final List<FanConsumptionLevel> levels =
        (data['fanLevels'] as List<dynamic>? ?? <dynamic>[])
            .map(FanConsumptionLevel.tryParse)
            .whereType<FanConsumptionLevel>()
            .toList()
          ..sort((a, b) => a.percent.compareTo(b.percent));

    return ElectricConsumptionSettings(
      fanLevels: levels,
      humidifierPumpKw: _readDouble(data['humidifierPumpKw']),
      heaterStage1Kw: _readDouble(data['heaterStage1Kw']),
      heaterStage2Kw: _readDouble(data['heaterStage2Kw']),
    );
  }

  final List<FanConsumptionLevel> fanLevels;
  final double? humidifierPumpKw;
  final double? heaterStage1Kw;
  final double? heaterStage2Kw;

  Map<String, Object?> toFirestore() {
    return <String, Object?>{
      'fanLevels': fanLevels
          .map((FanConsumptionLevel level) => level.toFirestore())
          .toList(growable: false),
      if (humidifierPumpKw != null) 'humidifierPumpKw': humidifierPumpKw,
      if (heaterStage1Kw != null) 'heaterStage1Kw': heaterStage1Kw,
      if (heaterStage2Kw != null) 'heaterStage2Kw': heaterStage2Kw,
    };
  }
}

class FanConsumptionLevel {
  const FanConsumptionLevel({required this.percent, required this.kw});

  static FanConsumptionLevel? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    final double? percent = _readDouble(raw['percent']);
    final double? kw = _readDouble(raw['kw']);
    if (percent == null || kw == null) {
      return null;
    }
    return FanConsumptionLevel(percent: percent, kw: kw);
  }

  final double percent;
  final double kw;

  Map<String, Object?> toFirestore() => <String, Object?>{
    'percent': percent,
    'kw': kw,
  };
}

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
