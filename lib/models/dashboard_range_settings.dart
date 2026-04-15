class DashboardRangeSettings {
  const DashboardRangeSettings({
    required this.temperatureMin,
    required this.temperatureMax,
    required this.humidityMin,
    required this.humidityMax,
  });

  const DashboardRangeSettings.defaults()
    : temperatureMin = 15,
      temperatureMax = 32,
      humidityMin = 30,
      humidityMax = 80;

  final double temperatureMin;
  final double temperatureMax;
  final double humidityMin;
  final double humidityMax;
}
