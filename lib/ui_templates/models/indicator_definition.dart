import '../enums/indicator_position.dart';
import '_parsing.dart';

class IndicatorDefinition {
  IndicatorDefinition({
    required this.key,
    required this.sourceField,
    required this.icon,
    required this.condition,
    required this.position,
  }) {
    requireNonEmpty(key, 'key');
    requireNonEmpty(sourceField, 'sourceField');
    requireNonEmpty(icon, 'icon');
    requireSerializableScalar(condition, 'condition');
  }

  factory IndicatorDefinition.fromMap(Map<String, Object?> map) {
    return IndicatorDefinition(
      key: readRequiredString(map, 'key'),
      sourceField: readRequiredString(map, 'sourceField'),
      icon: readRequiredString(map, 'icon'),
      condition: map['condition'],
      position: IndicatorPosition.fromWireName(
        readRequiredString(map, 'position'),
      ),
    );
  }

  final String key;
  final String sourceField;
  final String icon;
  final Object? condition;
  final IndicatorPosition position;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'key': key,
      'sourceField': sourceField,
      'icon': icon,
      'condition': condition,
      'position': position.wireName,
    };
  }
}
