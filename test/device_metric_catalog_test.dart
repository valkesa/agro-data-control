import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';
import 'package:agro_data_control/device_metric_catalogs/metric_indicator_definition.dart';
import 'package:agro_data_control/device_metric_catalogs/reference_metric_catalogs.dart';
import 'package:agro_data_control/ui_templates/board/template_data_resolver.dart';
import 'package:agro_data_control/ui_templates/board/template_value_formatter.dart';
import 'package:agro_data_control/ui_templates/catalog/agro_ui_templates.dart';
import 'package:agro_data_control/ui_templates/enums/metric_display_type.dart';
import 'package:agro_data_control/ui_templates/enums/metric_transform.dart';
import 'package:agro_data_control/ui_templates/models/metric_definition.dart';
import 'package:agro_data_control/ui_templates/models/template_data_context.dart';
import 'package:flutter_test/flutter_test.dart';

MetricDefinition metric({
  String key = 'temperature',
  String source = 'tempInterior',
  int decimals = 1,
}) => MetricDefinition(
  key: key,
  label: 'Temperatura',
  shortLabel: 'Temp.',
  unit: '°C',
  icon: 'thermometer',
  sourceField: source,
  displayType: MetricDisplayType.number,
  decimals: decimals,
);

MetricIndicatorDefinition indicator({
  String key = 'heating',
  Object? condition = true,
}) => MetricIndicatorDefinition(
  key: key,
  sourceField: 'resistencia1',
  icon: 'flame',
  condition: condition,
);

DeviceMetricCatalog catalog() => DeviceMetricCatalog(
  id: 'environment_v1',
  name: 'Ambiente',
  metrics: [metric()],
  indicators: [indicator()],
  availableIndicators: {
    'temperature': ['heating'],
  },
);

void main() {
  group('Catalog contract', () {
    test('lookup, identity and optional capabilities', () {
      final value = catalog();
      expect(value.metricByKey('temperature')!.sourceField, 'tempInterior');
      expect(value.metricByKey('unknown'), isNull);
      expect(value.indicatorByKey('heating')!.condition, true);
      expect(value.indicatorByKey('unknown'), isNull);
      expect(
        DeviceMetricCatalog(id: 'empty', name: 'Vacío', metrics: []).metrics,
        isEmpty,
      );
    });
    test(
      'defensive copies and deep immutability, including serialized maps',
      () {
        final metrics = [metric()];
        final indicators = [indicator()];
        final keys = ['heating'];
        final associations = {'temperature': keys};
        final value = DeviceMetricCatalog(
          id: 'a',
          name: 'A',
          metrics: metrics,
          indicators: indicators,
          availableIndicators: associations,
        );
        metrics.clear();
        indicators.clear();
        keys.clear();
        associations.clear();
        expect(value.metrics, hasLength(1));
        expect(value.indicators, hasLength(1));
        expect(value.availableIndicators['temperature'], ['heating']);
        expect(() => value.metrics.clear(), throwsUnsupportedError);
        expect(() => value.indicators.clear(), throwsUnsupportedError);
        expect(() => value.availableIndicators.clear(), throwsUnsupportedError);
        expect(
          () => value.availableIndicators['temperature']!.clear(),
          throwsUnsupportedError,
        );
        final map = value.toMap();
        ((map['availableIndicators'] as Map)['temperature'] as List).clear();
        expect(value.availableIndicators['temperature'], ['heating']);
      },
    );
    test('duplicate metric and indicator keys rejected', () {
      expect(
        () => DeviceMetricCatalog(
          id: 'a',
          name: 'A',
          metrics: [metric(), metric()],
        ),
        throwsArgumentError,
      );
      expect(
        () => DeviceMetricCatalog(
          id: 'a',
          name: 'A',
          metrics: [],
          indicators: [indicator(), indicator()],
        ),
        throwsArgumentError,
      );
    });
    for (final associations in [
      {
        'unknown': ['heating'],
      },
      {
        'temperature': ['missing'],
      },
      {
        'temperature': ['heating', 'heating'],
      },
    ]) {
      test('rejects dangling or repeated associations $associations', () {
        expect(
          () => DeviceMetricCatalog.fromMap(
            catalog().toMap()..['availableIndicators'] = associations,
          ),
          throwsArgumentError,
        );
      });
    }
    test('semantic indicators have no position', () {
      expect(indicator().toMap().keys.toSet(), {
        'key',
        'sourceField',
        'icon',
        'condition',
      });
      expect(catalog().availableIndicators['temperature'], ['heating']);
    });
    test('core import graph excludes layouts, persistence and renderers', () {
      final visited = <String>{};
      void visit(File file) {
        if (!visited.add(file.absolute.path)) return;
        final content = file.readAsStringSync();
        expect(
          content,
          isNot(
            matches(
              r'\b(LayoutTemplate|GridPlacement|BoardSlot|TableColumn)\b',
            ),
          ),
        );
        for (final match in RegExp(
          r"(?:import|export) '([^']+)'",
        ).allMatches(content)) {
          final path = match[1]!;
          expect(path, isNot(contains('package:flutter')));
          expect(path, isNot(contains('firestore')));
          expect(path, isNot(contains('renderer')));
          if (!path.contains(':')) visit(File.fromUri(file.uri.resolve(path)));
        }
      }

      visit(File('lib/device_metric_catalogs/device_metric_catalog.dart'));
    });
  });

  group('Source contract and reuse', () {
    const resolver = TemplateDataResolver();
    for (final source in [
      'snapshot.temperature',
      'manual.sowCount',
      'computed.energyConsumption',
      'pending.co2',
      'tempInterior',
    ]) {
      test('represents and round trips $source', () {
        final value = DeviceMetricCatalog(
          id: 'a',
          name: 'A',
          metrics: [metric(source: source)],
        );
        final decoded = DeviceMetricCatalog.fromMap(value.toMap());
        expect(decoded.metricByKey('temperature')!.sourceField, source);
        final resolved = resolver.resolveMetric(
          decoded.metrics.single,
          TemplateDataContext(source: null, extras: {source: 12.5}),
        );
        expect(resolved, source.startsWith('pending.') ? isNull : 12.5);
      });
    }
    test('dotted sources are flat keys, not nested traversal', () {
      expect(
        resolver.resolveMetric(metric(source: 'snapshot.temperature'), {
          'snapshot': {'temperature': 21},
        }),
        isNull,
      );
      expect(
        resolver.resolveMetric(metric(source: 'snapshot.temperature'), {
          'snapshot.temperature': 21,
        }),
        21,
      );
    });
    test('existing computed dew point resolver is reused', () {
      final value = resolver.resolveMetric(
        metric(source: 'computed.dewPointDelta'),
        {'tempInterior': 20.0, 'humInterior': 50.0},
      );
      expect(value, isA<double>());
      expect(value as double, inExclusiveRange(-11, -10));
    });
    test('fan transform and formatter retain legacy semantics', () {
      final fan = referenceMetricCatalogById(
        'environment_room_v1',
      )!.metricByKey('fan')!;
      expect(fan.transform, MetricTransform.voltageToPercent);
      final resolved = resolver.resolveMetric(fan, {
        'tensionSalidaVentiladores': 450,
      });
      expect(resolved, 0.45);
      expect(formatTemplateMetricValue(fan, resolved), '45');
    });
    test('future energyConsumption needs no special branch', () {
      final energy = MetricDefinition(
        key: 'energyConsumption',
        label: 'Consumo eléctrico',
        unit: 'kWh',
        icon: 'energy',
        sourceField: 'snapshot.energyConsumption',
        displayType: MetricDisplayType.number,
        decimals: 2,
      );
      final value = catalog().withOverrides(upserts: [energy]);
      final decoded = DeviceMetricCatalog.fromMap(value.toMap());
      expect(
        resolver.resolveMetric(decoded.metricByKey('energyConsumption')!, {
          'snapshot.energyConsumption': 42.75,
        }),
        42.75,
      );
    });
  });

  group('Local extraction', () {
    for (final spec in [
      ('room_climate', 'environment_room_v1', {'deviceName', 'plcId'}, 13),
      ('laboratory_basic', 'laboratory_v1', {'equipment', 'labPending'}, 2),
      ('disinfection_arch', 'disinfection_arch_v1', {'equipment'}, 3),
    ]) {
      test('${spec.$2} preserves exact metric objects and values', () {
        final legacy = getTemplateById(spec.$1)!;
        final result = referenceMetricCatalogById(spec.$2)!;
        expect(result.metrics, hasLength(spec.$4));
        for (final metric in legacy.metrics.where(
          (metric) => !spec.$3.contains(metric.key),
        )) {
          expect(result.metricByKey(metric.key), same(metric));
          expect(result.metricByKey(metric.key)!.toMap(), metric.toMap());
        }
        for (final key in spec.$3) {
          expect(result.metricByKey(key), isNull);
        }
        expect(
          DeviceMetricCatalog.fromMap(result.toMap()).toMap(),
          result.toMap(),
        );
      });
    }
    test('reference catalog is immutable with unique IDs', () {
      expect(() => referenceMetricCatalogs.clear(), throwsUnsupportedError);
      expect(
        referenceMetricCatalogs.map((item) => item.id).toSet(),
        hasLength(3),
      );
      expect(referenceMetricCatalogById('unknown'), isNull);
    });
    test('indicator semantic subset is preserved', () {
      final legacy = getTemplateById('room_climate')!;
      final value = referenceMetricCatalogById('environment_room_v1')!;
      for (final item in legacy.indicators) {
        expect(
          value.indicatorByKey(item.key)!.toMap(),
          item.toMap()..remove('position'),
        );
      }
    });
  });

  group('Per-device overrides', () {
    test('add, replace and remove independently without changing base', () {
      final base = catalog();
      final a = base.withOverrides(
        upserts: [
          metric(source: 'snapshot.temperature', decimals: 2),
          metric(key: 'energyConsumption'),
        ],
      );
      final b = base.withOverrides(removedKeys: ['temperature']);
      expect(a.metricByKey('temperature')!.decimals, 2);
      expect(a.metricByKey('energyConsumption'), isNotNull);
      expect(b.metrics, isEmpty);
      expect(b.availableIndicators, isEmpty);
      expect(base.metricByKey('temperature')!.sourceField, 'tempInterior');
      expect(base.metrics, hasLength(1));
      expect(DeviceMetricCatalog.fromMap(a.toMap()).toMap(), a.toMap());
    });
    test('add semantic indicator and customize associations', () {
      final result = catalog().withOverrides(
        indicatorUpserts: [indicator(key: 'alarm')],
        indicatorAssociations: {
          'temperature': ['alarm'],
        },
      );
      expect(result.availableIndicators['temperature'], ['alarm']);
      expect(result.indicatorByKey('alarm'), isNotNull);
      expect(
        catalog()
            .withOverrides(indicatorAssociations: {'temperature': []})
            .availableIndicators['temperature'],
        isEmpty,
      );
    });
    test('rejects ambiguous or invalid override deltas', () {
      expect(
        () => catalog().withOverrides(removedKeys: ['missing']),
        throwsArgumentError,
      );
      expect(
        () => catalog().withOverrides(
          removedKeys: ['temperature', 'temperature'],
        ),
        throwsArgumentError,
      );
      expect(
        () => catalog().withOverrides(upserts: [metric(), metric()]),
        throwsArgumentError,
      );
      expect(
        () => catalog().withOverrides(
          upserts: [metric()],
          removedKeys: ['temperature'],
        ),
        throwsArgumentError,
      );
      expect(
        () => catalog().withOverrides(
          indicatorUpserts: [indicator(), indicator()],
        ),
        throwsArgumentError,
      );
      expect(
        () => catalog().withOverrides(
          indicatorAssociations: {
            'temperature': ['missing'],
          },
        ),
        throwsArgumentError,
      );
    });
  });

  group('Defensive versioned serialization', () {
    test('full JSON round trip', () {
      final original = catalog().toMap()..['catalogVersion'] = 4;
      final result = DeviceMetricCatalog.fromMap(
        Map<String, Object?>.from(jsonDecode(jsonEncode(original)) as Map),
      );
      expect(result.toMap(), original);
    });
    for (final field in [
      'id',
      'name',
      'schemaVersion',
      'catalogVersion',
      'metrics',
      'indicators',
      'availableIndicators',
    ]) {
      test('requires $field', () {
        expect(
          () => DeviceMetricCatalog.fromMap(catalog().toMap()..remove(field)),
          throwsArgumentError,
        );
      });
    }
    for (final entry in <String, List<Object?>>{
      'id': ['', ' ', 1, ' bad '],
      'name': ['', false],
      'schemaVersion': [0, 2, '1', 1.5],
      'catalogVersion': [0, -1, 1.5],
      'metrics': [
        null,
        {},
        [3],
      ],
      'indicators': [
        null,
        {},
        [3],
      ],
      'availableIndicators': [
        null,
        [],
        {'temperature': 'heating'},
        {
          'temperature': [1],
        },
      ],
    }.entries) {
      test('invalid catalog ${entry.key}', () {
        for (final value in entry.value) {
          expect(
            () => DeviceMetricCatalog.fromMap(
              catalog().toMap()..[entry.key] = value,
            ),
            throwsArgumentError,
            reason: '$value',
          );
        }
      });
    }
    for (final entry in <String, List<Object?>>{
      'key': ['', 1, ' spaced '],
      'label': ['', true],
      'shortLabel': ['', null],
      'icon': ['', null],
      'unit': [null, 4],
      'decimals': [-1, 21, 1.5, '2'],
      'sourceField': [
        '',
        'manual.',
        '.snapshot',
        'snapshot..temp',
        'snapshot temp',
        'a/b',
        ' tempInterior ',
      ],
      'valueLabelSourceField': ['', 'manual.', null],
      'displayType': ['unknown', null],
      'transform': ['unknown', null],
      'statusBehavior': ['unknown', null],
    }.entries) {
      test('invalid metric ${entry.key}', () {
        for (final value in entry.value) {
          final bad = metric().toMap()..[entry.key] = value;
          expect(
            () => DeviceMetricCatalog.fromMap(
              catalog().toMap()..['metrics'] = [bad],
            ),
            throwsArgumentError,
            reason: '$value',
          );
        }
      });
    }
    test('constructor enforces source syntax and precision', () {
      expect(
        () => DeviceMetricCatalog(
          id: 'a',
          name: 'A',
          metrics: [metric(decimals: 21)],
        ),
        throwsArgumentError,
      );
      expect(
        () => DeviceMetricCatalog(
          id: 'a',
          name: 'A',
          metrics: [metric(source: 'manual..x')],
        ),
        throwsArgumentError,
      );
      expect(
        () => DeviceMetricCatalog(
          id: 'a',
          name: 'A',
          schemaVersion: 2,
          metrics: [],
        ),
        throwsArgumentError,
      );
      expect(
        () => DeviceMetricCatalog(
          id: 'a',
          name: 'A',
          catalogVersion: 0,
          metrics: [],
        ),
        throwsArgumentError,
      );
    });
    test('indicator condition must be finite JSON scalar', () {
      for (final value in [null, true, false, 'on', 0, 1.5]) {
        expect(
          MetricIndicatorDefinition.fromMap(
            indicator(condition: value).toMap(),
          ).condition,
          value,
        );
      }
      for (final value in [double.nan, double.infinity, [], {}]) {
        expect(() => indicator(condition: value), throwsArgumentError);
      }
      expect(
        () => MetricIndicatorDefinition.fromMap(
          indicator().toMap()..remove('condition'),
        ),
        throwsArgumentError,
      );
    });
    for (final field in [
      'tenantId',
      'siteId',
      'deviceName',
      'cardTitle',
      'layoutId',
      'x',
      'y',
      'width',
      'height',
      'position',
      'visible',
      'order',
      'boardSlots',
      'tableColumns',
      'boardPreset',
      'tableSection',
    ]) {
      test('rejects foreign/visual field $field at every boundary', () {
        expect(
          () => DeviceMetricCatalog.fromMap(catalog().toMap()..[field] = 1),
          throwsArgumentError,
        );
        expect(
          () => DeviceMetricCatalog.fromMap(
            catalog().toMap()..['metrics'] = [metric().toMap()..[field] = 1],
          ),
          throwsArgumentError,
        );
        expect(
          () => MetricIndicatorDefinition.fromMap(
            indicator().toMap()..[field] = 1,
          ),
          throwsArgumentError,
        );
      });
    }
  });
}
