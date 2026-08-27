import '../enums/board_preset.dart';
import '_parsing.dart';
import 'board_slot.dart';
import 'indicator_definition.dart';
import 'metric_definition.dart';
import 'table_column.dart';

class DeviceTemplate {
  DeviceTemplate({
    required this.id,
    required this.name,
    required this.boardPreset,
    this.metrics = const <MetricDefinition>[],
    this.indicators = const <IndicatorDefinition>[],
    this.boardSlots = const <BoardSlot>[],
    required this.tableSection,
    this.tableColumns = const <TableColumn>[],
  }) {
    requireNonEmpty(id, 'id');
    requireNonEmpty(name, 'name');
    requireNonEmpty(tableSection, 'tableSection');
    _validateReferences();
  }

  factory DeviceTemplate.fromMap(Map<String, Object?> map) {
    return DeviceTemplate(
      id: readRequiredString(map, 'id'),
      name: readRequiredString(map, 'name'),
      boardPreset: BoardPreset.fromWireName(
        readRequiredString(map, 'boardPreset'),
      ),
      metrics: readMapList(
        map['metrics'],
      ).map(MetricDefinition.fromMap).toList(growable: false),
      indicators: readMapList(
        map['indicators'],
      ).map(IndicatorDefinition.fromMap).toList(growable: false),
      boardSlots: readMapList(
        map['boardSlots'],
      ).map(BoardSlot.fromMap).toList(growable: false),
      tableSection: readRequiredString(map, 'tableSection'),
      tableColumns: readMapList(
        map['tableColumns'],
      ).map(TableColumn.fromMap).toList(growable: false),
    );
  }

  final String id;
  final String name;
  final BoardPreset boardPreset;
  final List<MetricDefinition> metrics;
  final List<IndicatorDefinition> indicators;
  final List<BoardSlot> boardSlots;
  final String tableSection;
  final List<TableColumn> tableColumns;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'boardPreset': boardPreset.wireName,
      'metrics': metrics
          .map((MetricDefinition metric) => metric.toMap())
          .toList(growable: false),
      'indicators': indicators
          .map((IndicatorDefinition indicator) => indicator.toMap())
          .toList(growable: false),
      'boardSlots': boardSlots
          .map((BoardSlot slot) => slot.toMap())
          .toList(growable: false),
      'tableSection': tableSection,
      'tableColumns': tableColumns
          .map((TableColumn column) => column.toMap())
          .toList(growable: false),
    };
  }

  void _validateReferences() {
    final Set<String> metricKeys = _uniqueKeys(
      metrics.map((MetricDefinition metric) => metric.key),
      'metrics',
    );
    final Set<String> indicatorKeys = _uniqueKeys(
      indicators.map((IndicatorDefinition indicator) => indicator.key),
      'indicators',
    );

    for (final BoardSlot slot in boardSlots) {
      _requireKnownKey(metricKeys, slot.metricKey, 'boardSlots.metricKey');
      for (final String indicatorKey in slot.indicators) {
        _requireKnownKey(indicatorKeys, indicatorKey, 'boardSlots.indicators');
      }
    }

    for (final TableColumn column in tableColumns) {
      _requireKnownKey(metricKeys, column.metricKey, 'tableColumns.metricKey');
      for (final String indicatorKey in column.indicators) {
        _requireKnownKey(
          indicatorKeys,
          indicatorKey,
          'tableColumns.indicators',
        );
      }
    }
  }
}

Set<String> _uniqueKeys(Iterable<String> keys, String fieldName) {
  final Set<String> seen = <String>{};
  for (final String key in keys) {
    if (!seen.add(key)) {
      throw ArgumentError.value(key, fieldName, 'Duplicate key');
    }
  }
  return seen;
}

void _requireKnownKey(Set<String> knownKeys, String key, String fieldName) {
  if (!knownKeys.contains(key)) {
    throw ArgumentError.value(key, fieldName, 'Unknown reference');
  }
}
