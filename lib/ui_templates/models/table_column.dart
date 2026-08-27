import '../enums/table_column_width.dart';
import '_parsing.dart';

class TableColumn {
  TableColumn({
    required this.metricKey,
    required this.order,
    required this.width,
    required this.visible,
    this.indicators = const <String>[],
  }) {
    requireNonEmpty(metricKey, 'metricKey');
    requireNonNegative(order, 'order');
  }

  factory TableColumn.fromMap(Map<String, Object?> map) {
    return TableColumn(
      metricKey: readRequiredString(map, 'metricKey'),
      order: readNonNegativeInt(map, 'order'),
      width: TemplateTableColumnWidth.fromWireName(
        readRequiredString(map, 'width'),
      ),
      visible: readBool(map['visible'], defaultValue: true),
      indicators: readStringList(map['indicators']),
    );
  }

  final String metricKey;
  final int order;
  final TemplateTableColumnWidth width;
  final bool visible;
  final List<String> indicators;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'metricKey': metricKey,
      'order': order,
      'width': width.wireName,
      'visible': visible,
      'indicators': indicators,
    };
  }
}
