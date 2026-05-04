class ManualFanStatusSettings {
  const ManualFanStatusSettings({
    required this.munters1,
    required this.munters2,
  });

  const ManualFanStatusSettings.defaults()
    : munters1 = const FanUnitStatusSettings.defaults(),
      munters2 = const FanUnitStatusSettings.defaults();

  final FanUnitStatusSettings munters1;
  final FanUnitStatusSettings munters2;

  ManualFanStatusSettings copyWith({
    FanUnitStatusSettings? munters1,
    FanUnitStatusSettings? munters2,
  }) {
    return ManualFanStatusSettings(
      munters1: munters1 ?? this.munters1,
      munters2: munters2 ?? this.munters2,
    );
  }
}

class FanUnitStatusSettings {
  const FanUnitStatusSettings({
    required this.q5,
    required this.q6,
    required this.q7,
    required this.q8,
    required this.q9,
    required this.q10,
  });

  const FanUnitStatusSettings.defaults()
    : q5 = true,
      q6 = true,
      q7 = true,
      q8 = true,
      q9 = true,
      q10 = true;

  final bool q5;
  final bool q6;
  final bool q7;
  final bool q8;
  final bool q9;
  final bool q10;

  FanUnitStatusSettings copyWith({
    bool? q5,
    bool? q6,
    bool? q7,
    bool? q8,
    bool? q9,
    bool? q10,
  }) {
    return FanUnitStatusSettings(
      q5: q5 ?? this.q5,
      q6: q6 ?? this.q6,
      q7: q7 ?? this.q7,
      q8: q8 ?? this.q8,
      q9: q9 ?? this.q9,
      q10: q10 ?? this.q10,
    );
  }
}
