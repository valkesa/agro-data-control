import '../enums/metric_display_type.dart';
import '../enums/metric_transform.dart';
import '../models/metric_definition.dart';

const String templateNoDataLabel = 'Sin datos';

String formatTemplateMetricValue(MetricDefinition metric, Object? value) {
  if (value == null) {
    return templateNoDataLabel;
  }

  return switch (metric.displayType) {
    MetricDisplayType.number => _formatNumber(value, metric.decimals),
    MetricDisplayType.percentage => _formatPercentage(metric, value),
    MetricDisplayType.counter => _formatNumber(value, metric.decimals),
    MetricDisplayType.boolean => _formatBoolean(value),
    MetricDisplayType.status => value.toString(),
    MetricDisplayType.text => value.toString(),
  };
}

String formatTemplateMetricUnit(MetricDefinition metric, Object? value) {
  if (value == null || metric.displayType == MetricDisplayType.boolean) {
    return '';
  }
  return metric.unit;
}

String _formatNumber(Object value, int decimals) {
  if (value is num) {
    return value.toStringAsFixed(decimals);
  }
  return value.toString();
}

String _formatPercentage(MetricDefinition metric, Object value) {
  if (value is! num) {
    return value.toString();
  }
  final double displayValue =
      metric.transform == MetricTransform.voltageToPercent
      ? value.toDouble() * 100
      : value.toDouble();
  return displayValue.toStringAsFixed(metric.decimals);
}

String _formatBoolean(Object value) {
  if (value is! bool) {
    return value.toString();
  }
  return value ? 'Activo' : 'Inactivo';
}
