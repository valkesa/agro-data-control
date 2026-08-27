Duration fanSpinDurationForPercent(double? speedPercent) {
  if (speedPercent == null) {
    return const Duration(milliseconds: 650);
  }
  final double clamped = speedPercent.clamp(0.0, 1.0);
  if (clamped <= 0.25) {
    return const Duration(milliseconds: 1500);
  }
  if (clamped <= 0.5) {
    return const Duration(milliseconds: 650);
  }
  if (clamped < 0.75) {
    return const Duration(milliseconds: 400);
  }
  return const Duration(milliseconds: 250);
}
