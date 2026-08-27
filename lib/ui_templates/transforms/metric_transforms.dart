import '../enums/metric_transform.dart';

Object? applyMetricTransform(Object? value, MetricTransform transform) {
  return switch (transform) {
    MetricTransform.none => value,
    MetricTransform.voltageToPercent =>
      value is num ? normalizeVoltageToPercent(value) : null,
  };
}

double? normalizeVoltageToPercent(num? voltage) {
  if (voltage == null) {
    return null;
  }
  // Backend exposes the raw analog output scaled by 100.
  // Example: 450 => 4.50 V, so 100% = 10.00 V.
  return (voltage / 1000).clamp(0.0, 1.0);
}
