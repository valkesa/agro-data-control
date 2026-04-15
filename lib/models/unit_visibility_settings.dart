class UnitVisibilitySettings {
  const UnitVisibilitySettings({
    required this.showMunters1,
    required this.showMunters2,
  });

  const UnitVisibilitySettings.defaults()
    : showMunters1 = true,
      showMunters2 = true;

  final bool showMunters1;
  final bool showMunters2;
}
