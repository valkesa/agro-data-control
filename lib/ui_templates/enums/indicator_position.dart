enum IndicatorPosition {
  aboveValue('aboveValue'),
  belowValue('belowValue'),
  leftOfValue('leftOfValue'),
  rightOfValue('rightOfValue');

  const IndicatorPosition(this.wireName);

  final String wireName;

  static IndicatorPosition fromWireName(String value) {
    for (final IndicatorPosition position in IndicatorPosition.values) {
      if (position.wireName == value) {
        return position;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unknown IndicatorPosition');
  }
}
