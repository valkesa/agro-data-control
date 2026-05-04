class PlcDisplayConfig {
  const PlcDisplayConfig({
    required this.plcId,
    required this.displayName,
    required this.columnLabel,
    required this.technicalId,
    required this.active,
    required this.sortOrder,
  });

  final String plcId;
  final String displayName;
  final String columnLabel;
  final String technicalId;
  final bool active;
  final int sortOrder;

  PlcDisplayConfig copyWith({String? displayName, String? columnLabel}) {
    return PlcDisplayConfig(
      plcId: plcId,
      displayName: displayName ?? this.displayName,
      columnLabel: columnLabel ?? this.columnLabel,
      technicalId: technicalId,
      active: active,
      sortOrder: sortOrder,
    );
  }
}
