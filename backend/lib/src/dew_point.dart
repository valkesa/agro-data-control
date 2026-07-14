import 'dart:math' as math;

/// Replica la semántica actual del frontend en comparison_page.dart:
/// HR clamp 1..100, constantes Magnus a=17.62 y b=243.12.
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

  final double rh = relativeHumidityPercent.clamp(1.0, 100.0).toDouble();
  const double a = 17.62;
  const double b = 243.12;
  final double gamma =
      math.log(rh / 100.0) + (a * temperatureC) / (b + temperatureC);
  final double dewPointC = (b * gamma) / (a - gamma);
  return dewPointC.isFinite ? dewPointC : null;
}

double? calculateDewPointMarginC({
  required double? temperatureC,
  required double? relativeHumidityPercent,
}) {
  final double? dewPointC = calculateDewPointC(
    temperatureC: temperatureC,
    relativeHumidityPercent: relativeHumidityPercent,
  );
  if (temperatureC == null || dewPointC == null || !temperatureC.isFinite) {
    return null;
  }
  final double margin = temperatureC - dewPointC;
  return margin.isFinite ? margin : null;
}
