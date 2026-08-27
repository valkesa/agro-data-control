enum BoardSlotSize {
  large('large'),
  medium('medium'),
  small('small');

  const BoardSlotSize(this.wireName);

  final String wireName;

  static BoardSlotSize fromWireName(String value) {
    for (final BoardSlotSize size in BoardSlotSize.values) {
      if (size.wireName == value) {
        return size;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unknown BoardSlotSize');
  }
}
