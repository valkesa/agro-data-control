class DashboardRangeSettings {
  const DashboardRangeSettings({
    required this.temperatureMin,
    required this.temperatureMax,
    required this.humidityMin,
    required this.humidityMax,
    required this.filterPressureMax,
    required this.thermalFlowThresholdC,
    required this.thermalFlowMarkedDeltaC,
    required this.humidityAlarmYellowMin,
    required this.humidityAlarmRedMinExclusive,
    required this.dewPointMarginAlarmRedMax,
    required this.dewPointMarginAlarmYellowMaxExclusive,
  });

  const DashboardRangeSettings.defaults()
    : temperatureMin = 15,
      temperatureMax = 32,
      humidityMin = 30,
      humidityMax = 80,
      filterPressureMax = 30,
      thermalFlowThresholdC = 0.5,
      thermalFlowMarkedDeltaC = 2,
      humidityAlarmYellowMin = 85,
      humidityAlarmRedMinExclusive = 95,
      dewPointMarginAlarmRedMax = 1,
      dewPointMarginAlarmYellowMaxExclusive = 3;

  final double temperatureMin;
  final double temperatureMax;
  final double humidityMin;
  final double humidityMax;
  final double filterPressureMax;
  final double thermalFlowThresholdC;
  final double thermalFlowMarkedDeltaC;
  final double humidityAlarmYellowMin;
  final double humidityAlarmRedMinExclusive;
  final double dewPointMarginAlarmRedMax;
  final double dewPointMarginAlarmYellowMaxExclusive;

  DashboardRangeSettings copyWith({
    double? temperatureMin,
    double? temperatureMax,
    double? humidityMin,
    double? humidityMax,
    double? filterPressureMax,
    double? thermalFlowThresholdC,
    double? thermalFlowMarkedDeltaC,
    double? humidityAlarmYellowMin,
    double? humidityAlarmRedMinExclusive,
    double? dewPointMarginAlarmRedMax,
    double? dewPointMarginAlarmYellowMaxExclusive,
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
      humidityAlarmYellowMin:
          humidityAlarmYellowMin ?? this.humidityAlarmYellowMin,
      humidityAlarmRedMinExclusive:
          humidityAlarmRedMinExclusive ?? this.humidityAlarmRedMinExclusive,
      dewPointMarginAlarmRedMax:
          dewPointMarginAlarmRedMax ?? this.dewPointMarginAlarmRedMax,
      dewPointMarginAlarmYellowMaxExclusive:
          dewPointMarginAlarmYellowMaxExclusive ??
          this.dewPointMarginAlarmYellowMaxExclusive,
    );
  }
}
