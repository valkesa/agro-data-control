import 'package:cloud_firestore/cloud_firestore.dart';

class DifferentialPressureDailyPoint {
  const DifferentialPressureDailyPoint({
    required this.timestampDayStart,
    required this.dateKey,
    required this.avgPressureDifferential,
    required this.minPressureDifferential,
    required this.maxPressureDifferential,
    required this.samplesCount,
  });

  factory DifferentialPressureDailyPoint.fromFirestore(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    final DateTime date =
        _readDateTime(data['timestampDayStart']) ??
        _readDateTimeFromDateKey(data['dateKey']?.toString()) ??
        _readDateTimeFromDateKey(documentId) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final double avg = _readDouble(data['avgPressureDifferential']) ?? 0;
    return DifferentialPressureDailyPoint(
      timestampDayStart: date,
      dateKey: data['dateKey']?.toString() ?? _formatDateKey(date),
      avgPressureDifferential: avg,
      minPressureDifferential:
          _readDouble(data['minPressureDifferential']) ?? avg,
      maxPressureDifferential:
          _readDouble(data['maxPressureDifferential']) ?? avg,
      samplesCount: _readInt(data['samplesCount']) ?? 0,
    );
  }

  final DateTime timestampDayStart;
  final String dateKey;
  final double avgPressureDifferential;
  final double minPressureDifferential;
  final double maxPressureDifferential;
  final int samplesCount;
}

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

DateTime? _readDateTime(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

DateTime? _readDateTimeFromDateKey(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

String _formatDateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
