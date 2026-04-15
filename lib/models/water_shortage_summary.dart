class WaterShortageSummary {
  const WaterShortageSummary({
    required this.totalEvents,
    required this.monthEvents,
    required this.monthKey,
  });

  const WaterShortageSummary.empty()
    : totalEvents = 0,
      monthEvents = 0,
      monthKey = '';

  final int totalEvents;
  final int monthEvents;
  final String monthKey;
}
