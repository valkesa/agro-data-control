import '../enums/board_slot_size.dart';
import '_parsing.dart';

class BoardSlot {
  BoardSlot({
    required this.metricKey,
    required this.position,
    required this.size,
    required this.visible,
    this.showLabel = true,
    this.showIcon = true,
    this.indicators = const <String>[],
  }) {
    requireNonEmpty(metricKey, 'metricKey');
    requirePositive(position, 'position');
  }

  factory BoardSlot.fromMap(Map<String, Object?> map) {
    return BoardSlot(
      metricKey: readRequiredString(map, 'metricKey'),
      position: readPositiveInt(map, 'position'),
      size: BoardSlotSize.fromWireName(readRequiredString(map, 'size')),
      visible: readBool(map['visible'], defaultValue: true),
      showLabel: readBool(map['showLabel'], defaultValue: true),
      showIcon: readBool(map['showIcon'], defaultValue: true),
      indicators: readStringList(map['indicators']),
    );
  }

  final String metricKey;
  final int position;
  final BoardSlotSize size;
  final bool visible;
  final bool showLabel;
  final bool showIcon;
  final List<String> indicators;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'metricKey': metricKey,
      'position': position,
      'size': size.wireName,
      'visible': visible,
      'showLabel': showLabel,
      'showIcon': showIcon,
      'indicators': indicators,
    };
  }
}
