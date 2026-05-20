import 'package:cloud_firestore/cloud_firestore.dart';

class PigStatsRecord {
  const PigStatsRecord({
    required this.currentCount,
    required this.updatedAt,
    required this.updatedBy,
  });

  factory PigStatsRecord.fromFirestore(Map<String, dynamic> data) {
    return PigStatsRecord(
      currentCount: _parseInt(data['currentCount']) ?? 0,
      updatedAt: _parseDateTime(data['updatedAt']),
      updatedBy: data['updatedBy']?.toString(),
    );
  }

  final int currentCount;
  final DateTime? updatedAt;
  final String? updatedBy;
}

class PigMovementRecord {
  const PigMovementRecord({
    required this.movementId,
    required this.type,
    required this.date,
    required this.quantity,
    this.reasonId,
    this.reasonName,
    required this.userId,
    required this.userName,
    required this.createdAt,
  });

  factory PigMovementRecord.fromFirestore(
    Map<String, dynamic> data, {
    required String documentId,
  }) {
    return PigMovementRecord(
      movementId: documentId,
      type: data['type']?.toString() ?? 'in',
      date: _parseDateTime(data['date']),
      quantity: _parseInt(data['quantity']) ?? 0,
      reasonId: data['reasonId']?.toString(),
      reasonName: data['reasonName']?.toString(),
      userId: data['userId']?.toString() ?? '',
      userName: data['userName']?.toString() ?? '',
      createdAt: _parseDateTime(data['createdAt']),
    );
  }

  final String movementId;
  final String type;
  final DateTime? date;
  final int quantity;
  final String? reasonId;
  final String? reasonName;
  final String userId;
  final String userName;
  final DateTime? createdAt;

  bool get isIn => type == 'in';
  bool get isOut => type == 'out';
}

class PigExitReasonRecord {
  const PigExitReasonRecord({
    required this.reasonId,
    required this.name,
    required this.normalizedName,
  });

  factory PigExitReasonRecord.fromFirestore(
    Map<String, dynamic> data, {
    required String documentId,
  }) {
    return PigExitReasonRecord(
      reasonId: documentId,
      name: data['name']?.toString() ?? '',
      normalizedName: data['normalizedName']?.toString() ?? '',
    );
  }

  final String reasonId;
  final String name;
  final String normalizedName;
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
