import 'package:cloud_firestore/cloud_firestore.dart';

class DoorStateRecord {
  const DoorStateRecord({
    required this.doorId,
    required this.doorName,
    required this.isOpen,
    required this.currentOpenedAt,
    required this.lastChangedAt,
    required this.lastOpeningId,
    required this.openCountTotal,
    required this.totalOpenDurationS,
    required this.lastDurationS,
    required this.updatedAt,
  });

  factory DoorStateRecord.fromFirestore(
    Map<String, dynamic> data, {
    required String documentId,
  }) {
    return DoorStateRecord(
      doorId: data['doorId']?.toString() ?? documentId,
      doorName: data['doorName']?.toString() ?? documentId,
      isOpen: data['isOpen'] == true,
      currentOpenedAt: _parseDateTime(data['currentOpenedAt']),
      lastChangedAt: _parseDateTime(data['lastChangedAt']),
      lastOpeningId: data['lastOpeningId']?.toString(),
      openCountTotal: _parseInt(data['openCountTotal']),
      totalOpenDurationS: _parseInt(data['totalOpenDurationS']),
      lastDurationS: _parseInt(data['lastDurationS']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  final String doorId;
  final String doorName;
  final bool isOpen;
  final DateTime? currentOpenedAt;
  final DateTime? lastChangedAt;
  final String? lastOpeningId;
  final int? openCountTotal;
  final int? totalOpenDurationS;
  final int? lastDurationS;
  final DateTime? updatedAt;
}

class DoorOpeningRecord {
  const DoorOpeningRecord({
    required this.openingId,
    required this.doorId,
    required this.doorName,
    required this.openedAt,
    required this.closedAt,
    required this.durationS,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DoorOpeningRecord.fromFirestore(
    Map<String, dynamic> data, {
    required String documentId,
  }) {
    return DoorOpeningRecord(
      openingId: data['openingId']?.toString() ?? documentId,
      doorId: data['doorId']?.toString() ?? '',
      doorName: data['doorName']?.toString() ?? '',
      openedAt: _parseDateTime(data['openedAt']),
      closedAt: _parseDateTime(data['closedAt']),
      durationS: _parseInt(data['durationS']),
      status: data['status']?.toString(),
      source: data['source']?.toString(),
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  final String openingId;
  final String doorId;
  final String doorName;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final int? durationS;
  final String? status;
  final String? source;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOpen => status == 'open' || closedAt == null;
}

DateTime? _parseDateTime(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

int? _parseInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
