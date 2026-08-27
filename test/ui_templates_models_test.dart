import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/ui_templates/ui_templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceTemplate', () {
    test('accepts a valid self-contained template', () {
      final DeviceTemplate template = _roomClimateTemplate();

      expect(template.id, 'room_climate');
      expect(
        template.metrics.map((MetricDefinition metric) => metric.key),
        <String>['tempInterior', 'humedadInterior'],
      );
      expect(
        template.indicators.map(
          (IndicatorDefinition indicator) => indicator.key,
        ),
        <String>['calefaccionEtapa1', 'calefaccionEtapa2', 'humidificacion'],
      );
    });

    test('accepts valid metric and indicator references', () {
      final DeviceTemplate template = _roomClimateTemplate();

      expect(template.boardSlots.single.metricKey, 'tempInterior');
      expect(template.tableColumns.single.metricKey, 'tempInterior');
      expect(template.boardSlots.single.indicators, <String>[
        'calefaccionEtapa1',
        'calefaccionEtapa2',
        'humidificacion',
      ]);
      expect(template.tableColumns.single.indicators, <String>[
        'calefaccionEtapa1',
        'calefaccionEtapa2',
        'humidificacion',
      ]);
    });

    test('rejects unknown BoardSlot metricKey', () {
      expect(
        () => _roomClimateTemplate(
          boardSlots: <BoardSlot>[
            BoardSlot(
              metricKey: 'missingMetric',
              position: 1,
              size: BoardSlotSize.large,
              visible: true,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown TableColumn metricKey', () {
      expect(
        () => _roomClimateTemplate(
          tableColumns: <TableColumn>[
            TableColumn(
              metricKey: 'missingMetric',
              order: 1,
              width: TemplateTableColumnWidth.medium,
              visible: true,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown BoardSlot indicator key', () {
      expect(
        () => _roomClimateTemplate(
          boardSlots: <BoardSlot>[
            BoardSlot(
              metricKey: 'tempInterior',
              position: 1,
              size: BoardSlotSize.large,
              visible: true,
              indicators: <String>['missingIndicator'],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown TableColumn indicator key', () {
      expect(
        () => _roomClimateTemplate(
          tableColumns: <TableColumn>[
            TableColumn(
              metricKey: 'tempInterior',
              order: 1,
              width: TemplateTableColumnWidth.medium,
              visible: true,
              indicators: <String>['missingIndicator'],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicated metric keys', () {
      expect(
        () => _roomClimateTemplate(
          metrics: <MetricDefinition>[
            _temperatureMetric(),
            _temperatureMetric(),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicated indicator keys', () {
      expect(
        () => _roomClimateTemplate(
          indicators: <IndicatorDefinition>[
            _heatStage1Indicator(),
            _heatStage1Indicator(),
          ],
        ),
        throwsArgumentError,
      );
    });

    test(
      'round trips complete maps intended for future persisted settings',
      () {
        final DeviceTemplate template = DeviceTemplate.fromMap(
          _roomClimateTemplate().toMap(),
        );

        expect(
          DeviceTemplate.fromMap(template.toMap()).toMap(),
          template.toMap(),
        );
      },
    );

    test('validates minimum constructor constraints in production', () {
      expect(
        () => DeviceTemplate(
          id: '',
          name: 'Clima sala',
          boardPreset: BoardPreset.large,
          tableSection: 'Salas',
        ),
        throwsArgumentError,
      );
      expect(
        () => BoardSlot(
          metricKey: 'tempInterior',
          position: 0,
          size: BoardSlotSize.large,
          visible: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => TableColumn(
          metricKey: 'tempInterior',
          order: -1,
          width: TemplateTableColumnWidth.medium,
          visible: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('IndicatorDefinition', () {
    test('round trips with scalar conditions', () {
      for (final Object? condition in <Object?>[true, 1, 1.5, 'on', null]) {
        final IndicatorDefinition indicator = IndicatorDefinition(
          key: 'condition_${condition ?? 'null'}',
          sourceField: 'heatStage1',
          icon: 'flame',
          condition: condition,
          position: IndicatorPosition.belowValue,
        );

        expect(
          IndicatorDefinition.fromMap(indicator.toMap()).toMap(),
          indicator.toMap(),
        );
      }
    });

    test('rejects non-serializable conditions', () {
      for (final Object condition in <Object>[
        DateTime.utc(2026),
        <String>['on'],
        <String, Object?>{'value': true},
        Object(),
      ]) {
        expect(
          () => IndicatorDefinition(
            key: 'badCondition',
            sourceField: 'heatStage1',
            icon: 'flame',
            condition: condition,
            position: IndicatorPosition.belowValue,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects non-finite numeric conditions', () {
      for (final double condition in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => IndicatorDefinition(
            key: 'badCondition',
            sourceField: 'heatStage1',
            icon: 'flame',
            condition: condition,
            position: IndicatorPosition.belowValue,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('Enums', () {
    test('reject unknown wire names', () {
      expect(
        () => MetricDisplayType.fromWireName('unknownDisplayType'),
        throwsArgumentError,
      );
      expect(
        () => MetricTransform.fromWireName('unknownTransform'),
        throwsArgumentError,
      );
      expect(
        () => BoardPreset.fromWireName('unknownPreset'),
        throwsArgumentError,
      );
    });

    test('MetricTransform supports wire names', () {
      expect(MetricTransform.none.wireName, 'none');
      expect(MetricTransform.voltageToPercent.wireName, 'voltageToPercent');
      expect(MetricTransform.fromWireName('none'), MetricTransform.none);
      expect(
        MetricTransform.fromWireName('voltageToPercent'),
        MetricTransform.voltageToPercent,
      );
      expect(
        MetricStatusBehavior.fromWireName('alarmState'),
        MetricStatusBehavior.alarmState,
      );
    });
  });

  group('MetricDefinition', () {
    test('round trips with transform and shortLabel', () {
      final MetricDefinition metric = MetricDefinition(
        key: 'fan',
        label: 'Fan',
        shortLabel: 'Fan',
        unit: '%',
        icon: 'fan',
        sourceField: 'tensionSalidaVentiladores',
        valueLabelSourceField: 'fanLabel',
        displayType: MetricDisplayType.percentage,
        decimals: 0,
        transform: MetricTransform.voltageToPercent,
      );

      expect(MetricDefinition.fromMap(metric.toMap()).toMap(), metric.toMap());
    });

    test('defaults missing transform to none', () {
      final Map<String, Object?> map = _temperatureMetric().toMap()
        ..remove('transform');

      expect(MetricDefinition.fromMap(map).transform, MetricTransform.none);
    });
  });

  group('Metric transforms', () {
    test('voltageToPercent reproduces current fan normalization', () {
      expect(normalizeVoltageToPercent(null), isNull);
      expect(normalizeVoltageToPercent(-100), 0);
      expect(normalizeVoltageToPercent(0), 0);
      expect(normalizeVoltageToPercent(450), 0.45);
      expect(normalizeVoltageToPercent(1000), 1);
      expect(normalizeVoltageToPercent(1200), 1);
      expect(applyMetricTransform(450, MetricTransform.voltageToPercent), 0.45);
    });
  });

  group('Agro UI template catalog', () {
    test('contains the three initial templates with unique IDs', () {
      final List<String> ids = agroUiTemplates
          .map((DeviceTemplate template) => template.id)
          .toList(growable: false);

      expect(
        ids,
        containsAll(<String>[
          'room_climate',
          'laboratory_basic',
          'disinfection_arch',
        ]),
      );
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('getTemplateById returns the matching template or null', () {
      expect(
        getTemplateById('room_climate')?.name,
        'Sala / Ambiente controlado',
      );
      expect(getTemplateById(' laboratory_basic ')?.id, 'laboratory_basic');
      expect(getTemplateById('missing_template'), isNull);
    });

    test('all catalog templates pass internal validation and round trip', () {
      for (final DeviceTemplate template in agroUiTemplates) {
        expect(
          DeviceTemplate.fromMap(template.toMap()).toMap(),
          template.toMap(),
        );
      }
    });

    test('room_climate contains heating and cooling indicators', () {
      final DeviceTemplate template = getTemplateById('room_climate')!;
      final Set<String> indicatorKeys = template.indicators
          .map((IndicatorDefinition indicator) => indicator.key)
          .toSet();

      expect(
        indicatorKeys,
        containsAll(<String>[
          'calefaccionEtapa1',
          'calefaccionEtapa2',
          'humidificacion',
        ]),
      );
      expect(
        template.boardSlots
            .singleWhere((BoardSlot slot) => slot.metricKey == 'tempInterior')
            .indicators,
        containsAll(<String>[
          'calefaccionEtapa1',
          'calefaccionEtapa2',
          'humidificacion',
        ]),
      );
    });

    test('room_climate uses short labels and hides technical labels', () {
      final DeviceTemplate template = getTemplateById('room_climate')!;
      final Map<String, MetricDefinition> metricsByKey =
          <String, MetricDefinition>{
            for (final MetricDefinition metric in template.metrics)
              metric.key: metric,
          };
      final Map<String, BoardSlot> slotsByMetric = <String, BoardSlot>{
        for (final BoardSlot slot in template.boardSlots) slot.metricKey: slot,
      };

      expect(metricsByKey['tempInterior']?.shortLabel, 'Temp. int.');
      expect(metricsByKey['puertaSala']?.shortLabel, 'Sala');
      expect(metricsByKey['puertaMunters']?.shortLabel, 'Munters');
      expect(
        metricsByKey['puertaMunters']?.valueLabelSourceField,
        'equipmentDoorLabel',
      );
      expect(slotsByMetric['puertaSala']?.showLabel, isFalse);
      expect(slotsByMetric['puertaMunters']?.showLabel, isFalse);
      expect(slotsByMetric['fan']?.showLabel, isFalse);
      expect(slotsByMetric['presion']?.showLabel, isFalse);
      expect(slotsByMetric['sowCount']?.showLabel, isFalse);
      expect(slotsByMetric['agua']?.showLabel, isFalse);
      expect(slotsByMetric['agua']?.showIcon, isTrue);
      expect(slotsByMetric['tempExterior']?.size, BoardSlotSize.medium);
      expect(slotsByMetric['humedadExterior']?.size, BoardSlotSize.medium);
      expect(slotsByMetric['nh3']?.showIcon, isFalse);
      expect(slotsByMetric['co2']?.showIcon, isFalse);
    });

    test(
      'room_climate uses cerdas currentCount instead of peso placeholder',
      () {
        final DeviceTemplate template = getTemplateById('room_climate')!;
        final Set<String> metricKeys = template.metrics
            .map((MetricDefinition metric) => metric.key)
            .toSet();
        final MetricDefinition sowCount = template.metrics.singleWhere(
          (MetricDefinition metric) => metric.key == 'sowCount',
        );

        expect(metricKeys.contains('peso'), isFalse);
        expect(sowCount.label, 'Cerdas');
        expect(sowCount.sourceField, 'currentCount');
        expect(
          template.boardSlots
              .singleWhere((BoardSlot slot) => slot.position == 10)
              .metricKey,
          'sowCount',
        );
      },
    );

    test('room_climate fan uses voltageToPercent transform', () {
      final DeviceTemplate template = getTemplateById('room_climate')!;
      final MetricDefinition fan = template.metrics.singleWhere(
        (MetricDefinition metric) => metric.key == 'fan',
      );

      expect(fan.sourceField, 'tensionSalidaVentiladores');
      expect(fan.transform, MetricTransform.voltageToPercent);
    });

    test('room_climate separates PLC ID and door states', () {
      final DeviceTemplate template = getTemplateById('room_climate')!;
      final Map<String, MetricDefinition> metricsByKey =
          <String, MetricDefinition>{
            for (final MetricDefinition metric in template.metrics)
              metric.key: metric,
          };
      final List<TableColumn> columns = template.tableColumns;

      expect(metricsByKey.containsKey('equipment'), isFalse);
      expect(metricsByKey['plcId']?.sourceField, 'historyPlcId');
      expect(metricsByKey['puertaSala']?.sourceField, 'salaAbierta');
      expect(
        metricsByKey['puertaSala']?.displayType,
        MetricDisplayType.boolean,
      );
      expect(metricsByKey['puertaMunters']?.sourceField, 'munterAbierto');
      expect(
        metricsByKey['puertaMunters']?.displayType,
        MetricDisplayType.boolean,
      );
      expect(columns[0].metricKey, 'deviceName');
      expect(columns[1].metricKey, 'puertaSala');
      expect(columns[2].metricKey, 'puertaMunters');
      expect(
        columns.any((TableColumn column) => column.metricKey == 'plcId'),
        isFalse,
      );
    });

    test('room_climate marks only range-backed metrics as alarmState', () {
      final DeviceTemplate template = getTemplateById('room_climate')!;
      final Map<String, MetricStatusBehavior> statusByMetric =
          <String, MetricStatusBehavior>{
            for (final MetricDefinition metric in template.metrics)
              metric.key: metric.statusBehavior,
          };

      expect(statusByMetric['tempInterior'], MetricStatusBehavior.alarmState);
      expect(
        statusByMetric['humedadInterior'],
        MetricStatusBehavior.alarmState,
      );
      expect(statusByMetric['dewPointDelta'], MetricStatusBehavior.alarmState);
      expect(statusByMetric['presion'], MetricStatusBehavior.alarmState);
      expect(statusByMetric['puertaSala'], MetricStatusBehavior.alarmState);
      expect(statusByMetric['puertaMunters'], MetricStatusBehavior.alarmState);
      expect(statusByMetric['fan'], MetricStatusBehavior.none);
      expect(statusByMetric['deviceName'], MetricStatusBehavior.none);
      expect(statusByMetric['plcId'], MetricStatusBehavior.none);
      expect(statusByMetric['agua'], MetricStatusBehavior.none);
    });

    test(
      'laboratory_basic contains temperature humidity and placeholder metrics',
      () {
        final DeviceTemplate template = getTemplateById('laboratory_basic')!;
        final Set<String> metricKeys = template.metrics
            .map((MetricDefinition metric) => metric.key)
            .toSet();
        final Map<String, BoardSlot> slotsByMetric = <String, BoardSlot>{
          for (final BoardSlot slot in template.boardSlots)
            slot.metricKey: slot,
        };

        expect(
          metricKeys,
          containsAll(<String>[
            'tempInterior',
            'humedadInterior',
            'labPending',
          ]),
        );
        expect(slotsByMetric['labPending']?.size, BoardSlotSize.medium);
        expect(slotsByMetric['labPending']?.showLabel, isFalse);
        expect(slotsByMetric['labPending']?.showIcon, isFalse);
      },
    );

    test('disinfection_arch contains compact daily arch metrics', () {
      final DeviceTemplate template = getTemplateById('disinfection_arch')!;
      final Set<String> metricKeys = template.metrics
          .map((MetricDefinition metric) => metric.key)
          .toSet();
      final Map<String, MetricDefinition> metricsByKey =
          <String, MetricDefinition>{
            for (final MetricDefinition metric in template.metrics)
              metric.key: metric,
          };

      expect(template.boardPreset, BoardPreset.compact);
      expect(
        metricKeys,
        containsAll(<String>[
          'vehiclesDisinfectedDaily',
          'vehiclesTotalDaily',
          'disinfectantLevel',
        ]),
      );
      expect(
        metricsByKey['vehiclesDisinfectedDaily']?.sourceField,
        'pending.vehiclesDisinfectedDaily',
      );
      expect(
        metricsByKey['vehiclesDisinfectedDaily']?.displayType,
        MetricDisplayType.counter,
      );
      expect(
        metricsByKey['vehiclesTotalDaily']?.sourceField,
        'pending.vehiclesTotalDaily',
      );
      expect(
        metricsByKey['vehiclesTotalDaily']?.displayType,
        MetricDisplayType.counter,
      );
      expect(
        metricsByKey['disinfectantLevel']?.sourceField,
        'pending.disinfectantLevel',
      );
      expect(
        metricsByKey['disinfectantLevel']?.displayType,
        MetricDisplayType.percentage,
      );
      expect(
        metricsByKey.values.map(
          (MetricDefinition metric) => metric.statusBehavior,
        ),
        everyElement(MetricStatusBehavior.none),
      );
    });
  });

  group('DeviceTemplateResolver scoping', () {
    const DeviceTemplateResolver resolver = DeviceTemplateResolver();

    test('Gene Pig legacy Sala1/Sala2 use the real tenant/site IDs', () {
      expect(
        resolver.templateIdForLegacyRoom(
          tenantId: 'the-gene-pig',
          siteId: 'genetica-1',
        ),
        'room_climate',
      );
      expect(
        resolver.templateIdForLegacyRoom(
          tenantId: 'otro',
          siteId: 'genetica-1',
        ),
        isNull,
      );
      expect(
        resolver.templateIdForLegacyRoom(
          tenantId: 'the-gene-pig',
          siteId: 'otro-site',
        ),
        isNull,
      );
    });

    test(
      'La Payana legacy rooms do not receive room_climate automatically',
      () {
        expect(
          resolver.templateIdForLegacyRoom(
            tenantId: 'la-payana',
            siteId: 'roque-perez',
          ),
          isNull,
        );
      },
    );

    test('real laboratory identity wins over generic room type', () {
      expect(
        resolver.templateIdForDevice(
          _device(
            id: 'plc-genetica-laboratorio',
            type: 'environment_single_room',
          ),
        ),
        'laboratory_basic',
      );
    });

    test('generic environmental room device resolves room_climate', () {
      expect(
        resolver.templateIdForDevice(
          _device(id: 'room-device-test', type: 'environment_single_room'),
        ),
        'room_climate',
      );
    });

    test('specific supported device types still resolve their templates', () {
      expect(
        resolver.templateIdForDeviceType('laboratory'),
        'laboratory_basic',
      );
      expect(
        resolver.templateIdForDeviceType('disinfection_arch'),
        'disinfection_arch',
      );
    });

    test('invented arch identity is not treated as a productive real ID', () {
      expect(
        resolver.templateIdForDevice(
          _device(id: 'arco-desinfeccion', type: 'other'),
        ),
        isNull,
      );
    });

    test(
      'real Gene Pig Arco device resolves disinfection_arch by exact id',
      () {
        expect(
          resolver.templateIdForDevice(
            _device(
              id: 'plc-genetica-arcodesinf',
              name: 'Arco Desf',
              type: 'environment_single_room',
            ),
          ),
          'disinfection_arch',
        );
      },
    );

    test('known Arco identity wins over its generic environmental type', () {
      // El device real tiene type=environment_single_room, que por si solo
      // resuelve room_climate (ver 'generic environmental room device
      // resolves room_climate'). La identidad especifica debe ganarle a
      // ese fallback generico.
      expect(
        resolver.templateIdForDeviceType('environment_single_room'),
        'room_climate',
      );
      expect(
        resolver.templateIdForDevice(
          _device(
            id: 'plc-genetica-arcodesinf',
            name: 'Arco Desf',
            type: 'environment_single_room',
          ),
        ),
        'disinfection_arch',
      );
    });

    test(
      'arch-like id/name without the real known id no longer matches by substring',
      () {
        expect(
          resolver.templateIdForDevice(
            _device(
              id: 'plc-genetica-arco-desinfeccion',
              name: 'Arco de desinfeccion',
              type: 'environment_single_room',
            ),
          ),
          'room_climate',
        );
      },
    );

    test('unknown device does not receive room_climate by default', () {
      expect(
        resolver.templateIdForDevice(_device(id: 'unknown', type: 'unknown')),
        isNull,
      );
      expect(
        resolver.templateForDevice(_device(id: 'unknown', type: 'unknown')),
        isNull,
      );
    });
  });
}

DeviceTemplate _roomClimateTemplate({
  List<MetricDefinition>? metrics,
  List<IndicatorDefinition>? indicators,
  List<BoardSlot>? boardSlots,
  List<TableColumn>? tableColumns,
}) {
  return DeviceTemplate(
    id: 'room_climate',
    name: 'Clima sala',
    boardPreset: BoardPreset.large,
    metrics:
        metrics ?? <MetricDefinition>[_temperatureMetric(), _humidityMetric()],
    indicators:
        indicators ??
        <IndicatorDefinition>[
          _heatStage1Indicator(),
          _heatStage2Indicator(),
          _coolingIndicator(),
        ],
    boardSlots:
        boardSlots ??
        <BoardSlot>[
          BoardSlot(
            metricKey: 'tempInterior',
            position: 1,
            size: BoardSlotSize.large,
            visible: true,
            showLabel: false,
            showIcon: false,
            indicators: <String>[
              'calefaccionEtapa1',
              'calefaccionEtapa2',
              'humidificacion',
            ],
          ),
        ],
    tableSection: 'Salas',
    tableColumns:
        tableColumns ??
        <TableColumn>[
          TableColumn(
            metricKey: 'tempInterior',
            order: 4,
            width: TemplateTableColumnWidth.medium,
            visible: true,
            indicators: <String>[
              'calefaccionEtapa1',
              'calefaccionEtapa2',
              'humidificacion',
            ],
          ),
        ],
  );
}

IndicatorDefinition _coolingIndicator() {
  return IndicatorDefinition(
    key: 'humidificacion',
    sourceField: 'bombaHumidificador',
    icon: 'snowflake',
    condition: true,
    position: IndicatorPosition.belowValue,
  );
}

MetricDefinition _temperatureMetric() {
  return MetricDefinition(
    key: 'tempInterior',
    label: 'Temperatura interior',
    unit: '°C',
    icon: 'thermometer',
    sourceField: 'tempInt',
    displayType: MetricDisplayType.number,
    decimals: 1,
  );
}

MetricDefinition _humidityMetric() {
  return MetricDefinition(
    key: 'humedadInterior',
    label: 'Humedad interior',
    unit: '%',
    icon: 'humidity',
    sourceField: 'humidityInt',
    displayType: MetricDisplayType.percentage,
    decimals: 0,
  );
}

IndicatorDefinition _heatStage1Indicator() {
  return IndicatorDefinition(
    key: 'calefaccionEtapa1',
    sourceField: 'heatStage1',
    icon: 'flame',
    condition: true,
    position: IndicatorPosition.belowValue,
  );
}

IndicatorDefinition _heatStage2Indicator() {
  return IndicatorDefinition(
    key: 'calefaccionEtapa2',
    sourceField: 'heatStage2',
    icon: 'flame',
    condition: true,
    position: IndicatorPosition.belowValue,
  );
}

AgroDevice _device({required String id, required String type, String? name}) {
  return AgroDevice(
    id: id,
    tenantId: 'tenant',
    siteId: 'site',
    name: name ?? id,
    type: type,
    model: '',
    description: '',
    enabled: true,
    createdAt: null,
    updatedAt: null,
  );
}
