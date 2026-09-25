import '../ui_templates/models/metric_definition.dart';
import 'catalog_validation.dart';
import 'metric_indicator_definition.dart';

/// Sentinel catalog selectable from the BoardPreset Editor (N6.5 §26,
/// N6.5.2 §18 "Sin perfil") to mean "no capability profile yet" — never
/// mutated, never produced by `DeviceCapabilityProfile.resolve(...)`, never
/// eligible for any admin CRUD action.
final DeviceMetricCatalog emptyDeviceMetricCatalog = DeviceMetricCatalog(
  id: '__empty__',
  name: 'Sin catálogo / catálogo vacío',
  metrics: const [],
);

/// Available capabilities, independent of any device identity or geometry.
/// List iteration order carries no visual ordering semantics.
class DeviceMetricCatalog {
  DeviceMetricCatalog({
    required this.id,
    required this.name,
    this.description = '',
    this.enabled = true,
    required Iterable<MetricDefinition> metrics,
    this.schemaVersion = CatalogValidation.schemaVersion,
    this.catalogVersion = 1,
    Iterable<MetricIndicatorDefinition> indicators = const [],
    Map<String, List<String>> availableIndicators = const {},
  }) : metrics = List.unmodifiable(metrics),
       indicators = List.unmodifiable(indicators),
       availableIndicators = Map.unmodifiable({
         for (final entry in availableIndicators.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }) {
    CatalogValidation.key(id, 'id');
    CatalogValidation.string(name, 'name');
    if (schemaVersion != CatalogValidation.schemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Unsupported schema',
      );
    }
    CatalogValidation.integer(catalogVersion, 'catalogVersion');
    final metricKeys = <String>{};
    for (final metric in this.metrics) {
      CatalogValidation.metric(metric);
      if (!metricKeys.add(metric.key)) {
        throw ArgumentError('Duplicate metric ${metric.key}');
      }
    }
    final indicatorKeys = <String>{};
    for (final indicator in this.indicators) {
      if (!indicatorKeys.add(indicator.key)) {
        throw ArgumentError('Duplicate indicator ${indicator.key}');
      }
    }
    for (final entry in this.availableIndicators.entries) {
      if (!metricKeys.contains(entry.key)) {
        throw ArgumentError('Unknown metric ${entry.key}');
      }
      final seen = <String>{};
      for (final key in entry.value) {
        if (!indicatorKeys.contains(key) || !seen.add(key)) {
          throw ArgumentError(
            'Unknown or repeated indicator $key for ${entry.key}',
          );
        }
      }
    }
  }

  factory DeviceMetricCatalog.fromMap(Map<String, Object?> map) {
    CatalogValidation.fields(map, {
      'id',
      'name',
      'description',
      'enabled',
      'schemaVersion',
      'catalogVersion',
      'metrics',
      'indicators',
      'availableIndicators',
    });
    final associations = CatalogValidation.map(
      map['availableIndicators'],
      'availableIndicators',
    );
    return DeviceMetricCatalog(
      id: CatalogValidation.string(map['id'], 'id'),
      name: CatalogValidation.string(map['name'], 'name'),
      description: map.containsKey('description')
          ? CatalogValidation.string(
              map['description'],
              'description',
              allowEmpty: true,
            )
          : '',
      enabled: map.containsKey('enabled') ? map['enabled'] == true : true,
      schemaVersion: CatalogValidation.integer(
        map['schemaVersion'],
        'schemaVersion',
      ),
      catalogVersion: CatalogValidation.integer(
        map['catalogVersion'],
        'catalogVersion',
      ),
      metrics: CatalogValidation.list(
        map['metrics'],
        'metrics',
      ).map(CatalogValidation.readMetric),
      indicators: CatalogValidation.list(map['indicators'], 'indicators').map(
        (item) => MetricIndicatorDefinition.fromMap(
          CatalogValidation.map(item, 'indicator'),
        ),
      ),
      availableIndicators: {
        for (final entry in associations.entries)
          entry.key: CatalogValidation.list(entry.value, entry.key)
              .map((item) => CatalogValidation.string(item, 'indicator key'))
              .toList(),
      },
    );
  }

  final String id;
  final String name;
  final String description;
  final bool enabled;
  final int schemaVersion;
  final int catalogVersion;
  final List<MetricDefinition> metrics;
  final List<MetricIndicatorDefinition> indicators;
  final Map<String, List<String>> availableIndicators;

  MetricDefinition? metricByKey(String key) {
    for (final metric in metrics) {
      if (metric.key == key) return metric;
    }
    return null;
  }

  MetricIndicatorDefinition? indicatorByKey(String key) {
    for (final indicator in indicators) {
      if (indicator.key == key) return indicator;
    }
    return null;
  }

  /// Local per-device capability customization. Full definitions replace by key;
  /// new keys add capabilities; removals change availability, never visibility.
  /// The result is an effective catalog, not a revision of the shared base.
  /// Persistence of the binding and override delta is deferred to a later stage.
  DeviceMetricCatalog withOverrides({
    Iterable<MetricDefinition> upserts = const [],
    Iterable<String> removedKeys = const [],
    Iterable<MetricIndicatorDefinition> indicatorUpserts = const [],
    Iterable<String> removedIndicatorKeys = const [],
    Map<String, List<String>> indicatorAssociations = const {},
  }) {
    final next = {for (final metric in metrics) metric.key: metric};
    final removed = <String>{};
    for (final key in removedKeys) {
      if (!removed.add(key) || next.remove(key) == null) {
        throw ArgumentError('Unknown or repeated removal $key');
      }
    }
    final seen = <String>{};
    for (final metric in upserts) {
      if (removed.contains(metric.key) || !seen.add(metric.key)) {
        throw ArgumentError('Conflicting override ${metric.key}');
      }
      next[metric.key] = metric;
    }
    final nextIndicators = {for (final item in indicators) item.key: item};
    final removedIndicators = <String>{};
    for (final key in removedIndicatorKeys) {
      if (!removedIndicators.add(key) || nextIndicators.remove(key) == null) {
        throw ArgumentError('Unknown or repeated indicator removal $key');
      }
    }
    final seenIndicators = <String>{};
    for (final item in indicatorUpserts) {
      if (removedIndicators.contains(item.key) ||
          !seenIndicators.add(item.key)) {
        throw ArgumentError('Conflicting indicator override ${item.key}');
      }
      nextIndicators[item.key] = item;
    }
    return DeviceMetricCatalog(
      id: id,
      name: name,
      description: description,
      enabled: enabled,
      schemaVersion: schemaVersion,
      catalogVersion: catalogVersion,
      metrics: next.values,
      indicators: nextIndicators.values,
      availableIndicators: {
        for (final entry in availableIndicators.entries)
          if (!removed.contains(entry.key))
            entry.key: entry.value
                .where((key) => !removedIndicators.contains(key))
                .toList(),
        ...indicatorAssociations,
      },
    );
  }

  /// Catalog-level administration fields only (N6.5 §7/§10): never touches
  /// `metrics`/`indicators`/`availableIndicators` — use [withOverrides] for
  /// those. `id` is intentionally not settable here: it is the stable,
  /// immutable key other objects (a [BoardPreset]'s `metricCatalogId`)
  /// reference, never a rename side effect.
  DeviceMetricCatalog copyWith({
    String? name,
    String? description,
    bool? enabled,
    int? catalogVersion,
  }) => DeviceMetricCatalog(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    enabled: enabled ?? this.enabled,
    schemaVersion: schemaVersion,
    catalogVersion: catalogVersion ?? this.catalogVersion,
    metrics: metrics,
    indicators: indicators,
    availableIndicators: availableIndicators,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'enabled': enabled,
    'schemaVersion': schemaVersion,
    'catalogVersion': catalogVersion,
    'metrics': metrics.map((metric) => metric.toMap()).toList(),
    'indicators': indicators.map((indicator) => indicator.toMap()).toList(),
    'availableIndicators': {
      for (final entry in availableIndicators.entries)
        entry.key: entry.value.toList(),
    },
  };
}
