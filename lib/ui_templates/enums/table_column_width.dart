enum TemplateTableColumnWidth {
  small('small'),
  medium('medium'),
  large('large');

  const TemplateTableColumnWidth(this.wireName);

  final String wireName;

  static TemplateTableColumnWidth fromWireName(String value) {
    for (final TemplateTableColumnWidth width
        in TemplateTableColumnWidth.values) {
      if (width.wireName == value) {
        return width;
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Unknown TemplateTableColumnWidth',
    );
  }
}
