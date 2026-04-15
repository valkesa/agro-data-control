import 'package:cloud_firestore/cloud_firestore.dart';

abstract class TemperatureHistoryPointBase {
  const TemperatureHistoryPointBase();

  DateTime get timestamp;
  double get avgTemp;
  double get minTemp;
  double get maxTemp;
}

class TemperatureHourlyPoint implements TemperatureHistoryPointBase {
  const TemperatureHourlyPoint({
    required this.timestampHourStart,
    required this.dateKey,
    required this.hourKey,
    required this.hour,
    required this.avgTemp,
    required this.minTemp,
    required this.maxTemp,
    required this.samplesCount,
  });

  factory TemperatureHourlyPoint.fromFirestore(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    final DateTime timestamp =
        _readDateTime(data['timestampHourStart']) ??
        _readDateTimeFromHourKey(data['hourKey']?.toString()) ??
        _readDateTimeFromHourKey(documentId) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return TemperatureHourlyPoint(
      timestampHourStart: timestamp,
      dateKey: data['dateKey']?.toString() ?? _formatDateKey(timestamp),
      hourKey:
          data['hourKey']?.toString() ??
          documentId ??
          _formatHourKey(timestamp),
      hour: _readInt(data['hour']) ?? timestamp.hour,
      avgTemp: _readDouble(data['avgTemp']) ?? 0,
      minTemp:
          _readDouble(data['minTemp']) ?? _readDouble(data['avgTemp']) ?? 0,
      maxTemp:
          _readDouble(data['maxTemp']) ?? _readDouble(data['avgTemp']) ?? 0,
      samplesCount: _readInt(data['samplesCount']) ?? 0,
    );
  }

  final DateTime timestampHourStart;
  final String dateKey;
  final String hourKey;
  final int hour;
  @override
  final double avgTemp;
  @override
  final double minTemp;
  @override
  final double maxTemp;
  final int samplesCount;

  @override
  DateTime get timestamp => timestampHourStart;
}

class TemperatureDailyPoint implements TemperatureHistoryPointBase {
  const TemperatureDailyPoint({
    required this.timestampDayStart,
    required this.dateKey,
    required this.avgTemp,
    required this.minTemp,
    required this.maxTemp,
    required this.hoursCount,
  });

  factory TemperatureDailyPoint.fromFirestore(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    final DateTime date =
        _readDateTime(data['timestampDayStart']) ??
        _readDateTimeFromDateKey(data['dateKey']?.toString()) ??
        _readDateTimeFromDateKey(documentId) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return TemperatureDailyPoint(
      timestampDayStart: date,
      dateKey: data['dateKey']?.toString() ?? _formatDateKey(date),
      avgTemp: _readDouble(data['avgTemp']) ?? 0,
      minTemp:
          _readDouble(data['minTemp']) ?? _readDouble(data['avgTemp']) ?? 0,
      maxTemp:
          _readDouble(data['maxTemp']) ?? _readDouble(data['avgTemp']) ?? 0,
      hoursCount: _readInt(data['hoursCount']) ?? 0,
    );
  }

  final DateTime timestampDayStart;
  final String dateKey;
  @override
  final double avgTemp;
  @override
  final double minTemp;
  @override
  final double maxTemp;
  final int hoursCount;

  @override
  DateTime get timestamp => timestampDayStart;
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
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

DateTime? _readDateTimeFromHourKey(String? value) {
  if (value == null || value.length < 11) {
    return null;
  }
  try {
    final String normalized = value.replaceAll('_', '');
    if (normalized.length < 10) {
      return null;
    }
    return DateTime(
      int.parse(normalized.substring(0, 4)),
      int.parse(normalized.substring(4, 6)),
      int.parse(normalized.substring(6, 8)),
      int.parse(normalized.substring(8, 10)),
    );
  } catch (_) {
    return null;
  }
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

String _formatHourKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}_'
      '${value.hour.toString().padLeft(2, '0')}';
}
