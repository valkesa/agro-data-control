import '../ui_templates/catalog/agro_ui_templates.dart';
import 'device_metric_catalog.dart';
import 'metric_indicator_definition.dart';

/// Temporary extraction boundary, not a visual template or production resolver.
/// Reuses actual MetricDefinition instances. Never reads slots or table config.
final List<DeviceMetricCatalog> referenceMetricCatalogs = List.unmodifiable([
  _extract(
    'room_climate',
    'environment_room_v1',
    'Capacidades ambientales',
    excludedKeys: {'deviceName', 'plcId'},
    availableIndicators: {
      'tempInterior': [
        'calefaccionEtapa1',
        'calefaccionEtapa2',
        'humidificacion',
      ],
    },
  ),
  _extract(
    'laboratory_basic',
    'laboratory_v1',
    'Temperatura y humedad',
    excludedKeys: {'equipment', 'labPending'},
  ),
  _extract(
    'disinfection_arch',
    'disinfection_arch_v1',
    'Capacidades de desinfección',
    excludedKeys: {'equipment'},
  ),
]);

DeviceMetricCatalog? referenceMetricCatalogById(String id) {
  for (final catalog in referenceMetricCatalogs) {
    if (catalog.id == id) return catalog;
  }
  return null;
}

DeviceMetricCatalog _extract(
  String legacyId,
  String id,
  String name, {
  required Set<String> excludedKeys,
  Map<String, List<String>> availableIndicators = const {},
}) {
  final legacy = getTemplateById(legacyId);
  if (legacy == null) throw StateError('Missing local reference $legacyId');
  return DeviceMetricCatalog(
    id: id,
    name: name,
    metrics: legacy.metrics.where(
      (metric) => !excludedKeys.contains(metric.key),
    ),
    indicators: legacy.indicators.map(
      (item) => MetricIndicatorDefinition(
        key: item.key,
        sourceField: item.sourceField,
        icon: item.icon,
        condition: item.condition,
      ),
    ),
    availableIndicators: availableIndicators,
  );
}
