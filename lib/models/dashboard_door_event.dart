class DashboardDoorEvent {
  const DashboardDoorEvent({
    required this.doorId,
    required this.isOpen,
    required this.currentOpenedAt,
    required this.lastChangedAt,
    required this.lastOpeningId,
  });

  factory DashboardDoorEvent.fromJson(
    String doorId,
    Map<String, dynamic> json,
  ) {
    return DashboardDoorEvent(
      doorId: doorId,
      isOpen: json['isOpen'] == true,
      currentOpenedAt: _parseDateTime(json['currentOpenedAt']),
      lastChangedAt: _parseDateTime(json['lastChangedAt']),
      lastOpeningId: json['lastOpeningId']?.toString(),
    );
  }

  final String doorId;
  final bool isOpen;
  final DateTime? currentOpenedAt;
  final DateTime? lastChangedAt;
  final String? lastOpeningId;

  static DateTime? _parseDateTime(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}
