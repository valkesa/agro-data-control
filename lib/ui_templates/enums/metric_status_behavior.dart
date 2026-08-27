enum MetricStatusBehavior {
  none('none'),
  alarmState('alarmState');

  const MetricStatusBehavior(this.wireName);

  final String wireName;

  static MetricStatusBehavior fromWireName(String wireName) {
    final String normalized = wireName.trim();
    for (final MetricStatusBehavior value in MetricStatusBehavior.values) {
      if (value.wireName == normalized) {
        return value;
      }
    }
    throw ArgumentError.value(
      wireName,
      'wireName',
      'Unknown metric status behavior',
    );
  }
}
