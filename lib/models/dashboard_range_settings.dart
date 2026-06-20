class DashboardRangeSettings {
  const DashboardRangeSettings({
    required this.temperatureMin,
    required this.temperatureMax,
    required this.humidityMin,
    required this.humidityMax,
    required this.filterPressureMax,
    required this.thermalFlowThresholdC,
    required this.thermalFlowMarkedDeltaC,
  });

  const DashboardRangeSettings.defaults()
    : temperatureMin = 15,
      temperatureMax = 32,
      humidityMin = 30,
      humidityMax = 80,
      filterPressureMax = 30,
      thermalFlowThresholdC = 0.5,
      thermalFlowMarkedDeltaC = 2;

  final double temperatureMin;
  final double temperatureMax;
  final double humidityMin;
  final double humidityMax;
  final double filterPressureMax;
  final double thermalFlowThresholdC;
  final double thermalFlowMarkedDeltaC;

  DashboardRangeSettings copyWith({
    double? temperatureMin,
    double? temperatureMax,
    double? humidityMin,
    double? humidityMax,
    double? filterPressureMax,
    double? thermalFlowThresholdC,
    double? thermalFlowMarkedDeltaC,
  }) {
    return DashboardRangeSettings(
      temperatureMin: temperatureMin ?? this.temperatureMin,
      temperatureMax: temperatureMax ?? this.temperatureMax,
      humidityMin: humidityMin ?? this.humidityMin,
      humidityMax: humidityMax ?? this.humidityMax,
      filterPressureMax: filterPressureMax ?? this.filterPressureMax,
      thermalFlowThresholdC:
          thermalFlowThresholdC ?? this.thermalFlowThresholdC,
      thermalFlowMarkedDeltaC:
          thermalFlowMarkedDeltaC ?? this.thermalFlowMarkedDeltaC,
    );
  }
}
