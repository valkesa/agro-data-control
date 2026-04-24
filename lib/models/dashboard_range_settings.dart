class DashboardRangeSettings {
  const DashboardRangeSettings({
    required this.temperatureMin,
    required this.temperatureMax,
    required this.humidityMin,
    required this.humidityMax,
    required this.filterPressureMax,
  });

  const DashboardRangeSettings.defaults()
    : temperatureMin = 15,
      temperatureMax = 32,
      humidityMin = 30,
      humidityMax = 80,
      filterPressureMax = 30;

  final double temperatureMin;
  final double temperatureMax;
  final double humidityMin;
  final double humidityMax;
  final double filterPressureMax;
}
