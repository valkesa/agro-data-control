import '../enums/board_preset.dart';
import '../enums/board_slot_size.dart';
import '../enums/indicator_position.dart';
import '../enums/metric_display_type.dart';
import '../enums/metric_status_behavior.dart';
import '../enums/metric_transform.dart';
import '../enums/table_column_width.dart';
import '../models/board_slot.dart';
import '../models/device_template.dart';
import '../models/indicator_definition.dart';
import '../models/metric_definition.dart';
import '../models/table_column.dart';

final List<DeviceTemplate> agroUiTemplates = List<DeviceTemplate>.unmodifiable(
  <DeviceTemplate>[
    _roomClimateTemplate(),
    _laboratoryBasicTemplate(),
    _disinfectionArchTemplate(),
  ],
);

DeviceTemplate? getTemplateById(String id) {
  final String normalizedId = id.trim();
  for (final DeviceTemplate template in agroUiTemplates) {
    if (template.id == normalizedId) {
      return template;
    }
  }
  return null;
}

DeviceTemplate _roomClimateTemplate() {
  return DeviceTemplate(
    id: 'room_climate',
    name: 'Sala / Ambiente controlado',
    boardPreset: BoardPreset.large,
    metrics: <MetricDefinition>[
      _metric(
        key: 'tempInterior',
        label: 'Temperatura interior',
        shortLabel: 'Temp. int.',
        unit: '°C',
        icon: 'thermometer',
        sourceField: 'tempInterior',
        displayType: MetricDisplayType.number,
        decimals: 1,
        statusBehavior: MetricStatusBehavior.alarmState,
      ),
      _metric(
        key: 'humedadInterior',
        label: 'Humedad interior',
        shortLabel: 'HR int.',
        unit: '%',
        icon: 'humidity',
        sourceField: 'humInterior',
        displayType: MetricDisplayType.percentage,
        decimals: 0,
        statusBehavior: MetricStatusBehavior.alarmState,
      ),
      _metric(
        key: 'dewPointDelta',
        label: 'Delta punto de rocio',
        shortLabel: 'Delta PR',
        unit: '°C',
        icon: 'dewPoint',
        sourceField: 'computed.dewPointDelta',
        displayType: MetricDisplayType.number,
        decimals: 1,
        statusBehavior: MetricStatusBehavior.alarmState,
      ),
      _metric(
        key: 'tempExterior',
        label: 'Temperatura exterior',
        shortLabel: 'Temp. ext.',
        unit: '°C',
        icon: 'thermometerOutdoor',
        sourceField: 'tempExterior',
        displayType: MetricDisplayType.number,
        decimals: 1,
      ),
      _metric(
        key: 'humedadExterior',
        label: 'Humedad exterior',
        shortLabel: 'HR ext.',
        unit: '%',
        icon: 'humidityOutdoor',
        sourceField: 'humExterior',
        displayType: MetricDisplayType.percentage,
        decimals: 0,
      ),
      _metric(
        key: 'fan',
        label: 'Fan',
        shortLabel: 'Fan',
        unit: '%',
        icon: 'fan',
        sourceField: 'tensionSalidaVentiladores',
        displayType: MetricDisplayType.percentage,
        decimals: 0,
        transform: MetricTransform.voltageToPercent,
      ),
      _metric(
        key: 'puertaSala',
        label: 'Puerta sala',
        shortLabel: 'Sala',
        unit: '',
        icon: 'door',
        sourceField: 'salaAbierta',
        displayType: MetricDisplayType.boolean,
        decimals: 0,
        statusBehavior: MetricStatusBehavior.alarmState,
      ),
      _metric(
        key: 'puertaMunters',
        label: 'Puerta equipo',
        shortLabel: 'Munters',
        unit: '',
        icon: 'equipmentDoor',
        sourceField: 'munterAbierto',
        valueLabelSourceField: 'equipmentDoorLabel',
        displayType: MetricDisplayType.boolean,
        decimals: 0,
        statusBehavior: MetricStatusBehavior.alarmState,
      ),
      _metric(
        key: 'presion',
        label: 'Presion diferencial',
        shortLabel: 'Presion',
        unit: 'Pa',
        icon: 'pressure',
        sourceField: 'presionDiferencial',
        displayType: MetricDisplayType.number,
        decimals: 0,
        statusBehavior: MetricStatusBehavior.alarmState,
      ),
      _metric(
        key: 'sowCount',
        label: 'Cerdas',
        shortLabel: 'Cerdas',
        unit: '',
        icon: 'pig',
        sourceField: 'currentCount',
        displayType: MetricDisplayType.counter,
        decimals: 0,
      ),
      _metric(
        key: 'nh3',
        label: 'NH3',
        shortLabel: 'NH3',
        unit: 'ppm',
        icon: 'ammonia',
        sourceField: 'nh3',
        displayType: MetricDisplayType.number,
        decimals: 0,
      ),
      _metric(
        key: 'co2',
        label: 'CO2',
        shortLabel: 'CO2',
        unit: 'ppm',
        icon: 'co2',
        sourceField: 'pending.co2',
        displayType: MetricDisplayType.number,
        decimals: 0,
      ),
      _metric(
        key: 'agua',
        label: 'Agua',
        shortLabel: 'Agua',
        unit: 'L/dia',
        icon: 'water',
        sourceField: 'pending.aguaLitrosDia',
        displayType: MetricDisplayType.number,
        decimals: 0,
      ),
      _metric(
        key: 'deviceName',
        label: 'Dispositivo',
        shortLabel: 'Sala',
        unit: '',
        icon: 'room',
        sourceField: 'name',
        displayType: MetricDisplayType.text,
        decimals: 0,
      ),
      _metric(
        key: 'plcId',
        label: 'PLC',
        shortLabel: 'PLC',
        unit: '',
        icon: 'equipment',
        sourceField: 'historyPlcId',
        displayType: MetricDisplayType.text,
        decimals: 0,
      ),
    ],
    indicators: <IndicatorDefinition>[
      _heatingIndicator('calefaccionEtapa1', 'resistencia1'),
      _heatingIndicator('calefaccionEtapa2', 'resistencia2'),
      _coolingIndicator('humidificacion', 'bombaHumidificador'),
    ],
    boardSlots: <BoardSlot>[
      _slot('tempInterior', 1, BoardSlotSize.large, <String>[
        'calefaccionEtapa1',
        'calefaccionEtapa2',
        'humidificacion',
      ]),
      _slot('humedadInterior', 2, BoardSlotSize.medium),
      _slot('dewPointDelta', 3, BoardSlotSize.medium),
      _slot('tempExterior', 4, BoardSlotSize.medium),
      _slot('humedadExterior', 5, BoardSlotSize.medium),
      _slot('puertaSala', 6, BoardSlotSize.small, const <String>[], false),
      _slot('puertaMunters', 7, BoardSlotSize.small, const <String>[], false),
      _slot('fan', 8, BoardSlotSize.medium, const <String>[], false),
      _slot('presion', 9, BoardSlotSize.medium, const <String>[], false),
      _slot('sowCount', 10, BoardSlotSize.small, const <String>[], false),
      _slot('nh3', 11, BoardSlotSize.small, const <String>[], true, false),
      _slot('co2', 12, BoardSlotSize.small, const <String>[], true, false),
      _slot('agua', 13, BoardSlotSize.small, const <String>[], false),
    ],
    tableSection: 'Salas',
    tableColumns: <TableColumn>[
      _column('deviceName', 0, TemplateTableColumnWidth.large),
      _column('puertaSala', 1, TemplateTableColumnWidth.small),
      _column('puertaMunters', 2, TemplateTableColumnWidth.small),
      _column('tempExterior', 3, TemplateTableColumnWidth.medium),
      _column('tempInterior', 4, TemplateTableColumnWidth.medium, <String>[
        'calefaccionEtapa1',
        'calefaccionEtapa2',
        'humidificacion',
      ]),
      _column('dewPointDelta', 5, TemplateTableColumnWidth.medium),
      _column('humedadExterior', 6, TemplateTableColumnWidth.medium),
      _column('humedadInterior', 7, TemplateTableColumnWidth.medium),
      _column('presion', 8, TemplateTableColumnWidth.medium),
      _column('fan', 9, TemplateTableColumnWidth.small),
      _column('sowCount', 10, TemplateTableColumnWidth.medium),
      _column('co2', 11, TemplateTableColumnWidth.medium),
      _column('agua', 12, TemplateTableColumnWidth.medium),
      _column('nh3', 13, TemplateTableColumnWidth.medium),
    ],
  );
}

DeviceTemplate _laboratoryBasicTemplate() {
  return DeviceTemplate(
    id: 'laboratory_basic',
    name: 'Laboratorio básico',
    boardPreset: BoardPreset.compact,
    metrics: <MetricDefinition>[
      _metric(
        key: 'equipment',
        label: 'Equipo',
        unit: '',
        icon: 'equipment',
        sourceField: 'name',
        displayType: MetricDisplayType.text,
        decimals: 0,
      ),
      _metric(
        key: 'tempInterior',
        label: 'Temperatura interior',
        unit: '°C',
        icon: 'thermometer',
        sourceField: 'tempInterior',
        displayType: MetricDisplayType.number,
        decimals: 1,
      ),
      _metric(
        key: 'humedadInterior',
        label: 'Humedad interior',
        unit: '%',
        icon: 'humidity',
        sourceField: 'humInterior',
        displayType: MetricDisplayType.percentage,
        decimals: 0,
      ),
      _metric(
        key: 'labPending',
        label: 'Pendiente',
        unit: '',
        icon: 'unknown',
        sourceField: 'pending.laboratoryPlaceholder',
        displayType: MetricDisplayType.text,
        decimals: 0,
      ),
    ],
    boardSlots: <BoardSlot>[
      _slot('tempInterior', 1, BoardSlotSize.medium),
      _slot('humedadInterior', 2, BoardSlotSize.medium),
      _slot(
        'labPending',
        3,
        BoardSlotSize.medium,
        const <String>[],
        false,
        false,
      ),
    ],
    tableSection: 'Laboratorio',
    tableColumns: <TableColumn>[
      _column('equipment', 0, TemplateTableColumnWidth.large),
      _column('tempInterior', 1, TemplateTableColumnWidth.medium),
      _column('humedadInterior', 2, TemplateTableColumnWidth.medium),
    ],
  );
}

DeviceTemplate _disinfectionArchTemplate() {
  return DeviceTemplate(
    id: 'disinfection_arch',
    name: 'Arco de desinfección',
    boardPreset: BoardPreset.compact,
    metrics: <MetricDefinition>[
      _metric(
        key: 'equipment',
        label: 'Equipo',
        unit: '',
        icon: 'equipment',
        sourceField: 'name',
        displayType: MetricDisplayType.text,
        decimals: 0,
      ),
      _metric(
        key: 'vehiclesDisinfectedDaily',
        label: 'Vehiculos desinfectados dia',
        shortLabel: 'Desinfectados/dia',
        unit: '',
        icon: 'vehicle',
        sourceField: 'pending.vehiclesDisinfectedDaily',
        displayType: MetricDisplayType.counter,
        decimals: 0,
      ),
      _metric(
        key: 'vehiclesTotalDaily',
        label: 'Vehiculos totales dia',
        shortLabel: 'Vehiculos/dia',
        unit: '',
        icon: 'vehicleTotal',
        sourceField: 'pending.vehiclesTotalDaily',
        displayType: MetricDisplayType.counter,
        decimals: 0,
      ),
      _metric(
        key: 'disinfectantLevel',
        label: 'Nivel desinfectante',
        shortLabel: 'Nivel',
        unit: '%',
        icon: 'tank',
        sourceField: 'pending.disinfectantLevel',
        displayType: MetricDisplayType.percentage,
        decimals: 0,
      ),
    ],
    boardSlots: <BoardSlot>[
      _slot('vehiclesDisinfectedDaily', 1, BoardSlotSize.medium),
      _slot('vehiclesTotalDaily', 2, BoardSlotSize.medium),
      _slot('disinfectantLevel', 3, BoardSlotSize.medium),
    ],
    tableSection: 'Arco Desinfección',
    tableColumns: <TableColumn>[
      _column('equipment', 0, TemplateTableColumnWidth.large),
      _column('vehiclesDisinfectedDaily', 1, TemplateTableColumnWidth.medium),
      _column('vehiclesTotalDaily', 2, TemplateTableColumnWidth.medium),
      _column('disinfectantLevel', 3, TemplateTableColumnWidth.medium),
    ],
  );
}

MetricDefinition _metric({
  required String key,
  required String label,
  String? shortLabel,
  required String unit,
  required String icon,
  required String sourceField,
  String? valueLabelSourceField,
  required MetricDisplayType displayType,
  required int decimals,
  MetricTransform transform = MetricTransform.none,
  MetricStatusBehavior statusBehavior = MetricStatusBehavior.none,
}) {
  return MetricDefinition(
    key: key,
    label: label,
    shortLabel: shortLabel,
    unit: unit,
    icon: icon,
    sourceField: sourceField,
    valueLabelSourceField: valueLabelSourceField,
    displayType: displayType,
    decimals: decimals,
    transform: transform,
    statusBehavior: statusBehavior,
  );
}

IndicatorDefinition _heatingIndicator(String key, String sourceField) {
  return IndicatorDefinition(
    key: key,
    sourceField: sourceField,
    icon: 'flame',
    condition: true,
    // Deliberately matches the current tablero/table visual placement.
    position: IndicatorPosition.leftOfValue,
  );
}

IndicatorDefinition _coolingIndicator(String key, String sourceField) {
  return IndicatorDefinition(
    key: key,
    sourceField: sourceField,
    icon: 'snowflake',
    condition: true,
    position: IndicatorPosition.leftOfValue,
  );
}

BoardSlot _slot(
  String metricKey,
  int position,
  BoardSlotSize size, [
  List<String> indicators = const <String>[],
  bool showLabel = true,
  bool showIcon = true,
]) {
  return BoardSlot(
    metricKey: metricKey,
    position: position,
    size: size,
    visible: true,
    showLabel: showLabel,
    showIcon: showIcon,
    indicators: indicators,
  );
}

TableColumn _column(
  String metricKey,
  int order,
  TemplateTableColumnWidth width, [
  List<String> indicators = const <String>[],
]) {
  return TableColumn(
    metricKey: metricKey,
    order: order,
    width: width,
    visible: true,
    indicators: indicators,
  );
}
