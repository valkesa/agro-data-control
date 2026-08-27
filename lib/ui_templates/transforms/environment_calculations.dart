import 'dart:math' as math;

double? calculateDewPointC({
  required double? temperatureC,
  required double? relativeHumidityPercent,
}) {
  if (temperatureC == null || relativeHumidityPercent == null) {
    return null;
  }
  if (!temperatureC.isFinite || !relativeHumidityPercent.isFinite) {
    return null;
  }

  final double rh = relativeHumidityPercent.clamp(1.0, 100.0);
  const double a = 17.62;
  const double b = 243.12;
  final double gamma =
      (a * temperatureC) / (b + temperatureC) + math.log(rh / 100.0);
  return (b * gamma) / (a - gamma);
}

double? calculateDewPointDeltaC({
  required double? temperatureC,
  required double? dewPointC,
}) {
  if (temperatureC == null || dewPointC == null) {
    return null;
  }
  if (!temperatureC.isFinite || !dewPointC.isFinite) {
    return null;
  }
  return dewPointC - temperatureC;
}
