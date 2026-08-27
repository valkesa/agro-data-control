enum MetricTransform {
  none('none'),
  voltageToPercent('voltageToPercent');

  const MetricTransform(this.wireName);

  final String wireName;

  static MetricTransform fromWireName(String value) {
    for (final MetricTransform transform in MetricTransform.values) {
      if (transform.wireName == value) {
        return transform;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unknown MetricTransform');
  }
}
