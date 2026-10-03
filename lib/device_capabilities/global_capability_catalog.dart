import '../device_metric_catalogs/device_metric_catalog.dart';
import '../device_metric_catalogs/metric_indicator_definition.dart';
import '../ui_templates/models/metric_definition.dart';
import 'capability_library_store.dart';

/// Read-only adapter used by the BoardPreset editor and its existing
/// renderer/validator boundary. The global semantic libraries remain the
/// source of truth; these neutral source fields are never persisted or used
/// to bind a real Device.
DeviceMetricCatalog buildGlobalCapabilityCatalog({
  required MetricLibraryStore metrics,
  required IndicatorLibraryStore indicators,
}) {
  final resolvedIndicators = [
    for (final indicator in indicators.indicators)
      MetricIndicatorDefinition(
        key: indicator.key,
        sourceField: indicator.key,
        icon: indicator.defaultIcon,
        condition: true,
      ),
  ];
  final indicatorKeys = resolvedIndicators.map((item) => item.key).toList();
  final resolvedMetrics = [
    for (final metric in metrics.metrics)
      MetricDefinition(
        key: metric.key,
        label: metric.label,
        shortLabel: metric.shortLabel,
        unit: metric.defaultUnit,
        icon: metric.icon,
        sourceField: metric.key,
        displayType: metric.displayType,
        decimals: metric.decimals,
        statusBehavior: metric.statusBehavior,
      ),
  ];
  return DeviceMetricCatalog(
    id: '__global_capability_libraries__',
    name: 'Bibliotecas globales',
    metrics: resolvedMetrics,
    indicators: resolvedIndicators,
    availableIndicators: {
      for (final metric in resolvedMetrics) metric.key: indicatorKeys,
    },
  );
}

/// Produces only the choices shown by the add-metric UI. Validation keeps
/// using [globalCatalog], so this projection can never invalidate content.
DeviceMetricCatalog filterGlobalCapabilityCatalog(
  DeviceMetricCatalog globalCatalog, {
  required Iterable<String> metricKeys,
  required Iterable<String> indicatorKeys,
  required String id,
  required String name,
}) {
  final allowedMetrics = metricKeys.toSet();
  final allowedIndicators = indicatorKeys.toSet();
  final metrics = globalCatalog.metrics
      .where((item) => allowedMetrics.contains(item.key))
      .toList();
  final indicators = globalCatalog.indicators
      .where((item) => allowedIndicators.contains(item.key))
      .toList();
  final resolvedIndicatorKeys = indicators.map((item) => item.key).toList();
  return DeviceMetricCatalog(
    id: id,
    name: name,
    metrics: metrics,
    indicators: indicators,
    availableIndicators: {
      for (final metric in metrics) metric.key: resolvedIndicatorKeys,
    },
  );
}
