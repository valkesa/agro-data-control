enum BoardPreset {
  large('large'),
  medium('medium'),
  compact('compact');

  const BoardPreset(this.wireName);

  final String wireName;

  static BoardPreset fromWireName(String value) {
    for (final BoardPreset preset in BoardPreset.values) {
      if (preset.wireName == value) {
        return preset;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unknown BoardPreset');
  }
}
