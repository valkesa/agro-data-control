enum MetricDisplayType {
  number('number'),
  percentage('percentage'),
  counter('counter'),
  boolean('boolean'),
  status('status'),
  text('text');

  const MetricDisplayType(this.wireName);

  final String wireName;

  static MetricDisplayType fromWireName(String value) {
    for (final MetricDisplayType type in MetricDisplayType.values) {
      if (type.wireName == value) {
        return type;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unknown MetricDisplayType');
  }
}
