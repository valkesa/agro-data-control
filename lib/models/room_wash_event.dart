import 'package:cloud_firestore/cloud_firestore.dart';

class RoomWashEvent {
  const RoomWashEvent({
    this.id,
    required this.tenantId,
    required this.roomId,
    required this.roomNumber,
    required this.muntersId,
    required this.washedAt,
    this.createdAt,
    required this.createdByUid,
    required this.createdByName,
    required this.source,
  });

  final String? id;
  final String tenantId;
  final String roomId;
  final int roomNumber;
  final String muntersId;
  final DateTime washedAt;
  final DateTime? createdAt;
  final String createdByUid;
  final String createdByName;
  final String source;

  static const String operatorSource = 'operator';
  static const Duration defaultHumidityShadingWindow = Duration(hours: 2);

  bool overlapsHumidityShadingRange(
    DateTime rangeStart,
    DateTime rangeEnd, {
    Duration window = defaultHumidityShadingWindow,
  }) {
    final DateTime washWindowEnd = washedAt.add(window);
    return washedAt.isBefore(rangeEnd) && washWindowEnd.isAfter(rangeStart);
  }

  Map<String, Object?> toCreatePayload() {
    return <String, Object?>{
      'roomId': roomId,
      'tenantId': tenantId,
      'roomNumber': roomNumber,
      'muntersId': muntersId,
      'washedAt': Timestamp.fromDate(washedAt),
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'source': source,
    };
  }

  static RoomWashEvent? fromFirestore(
    Map<String, dynamic> data, {
    required String documentId,
  }) {
    final String? roomId = data['roomId'] as String?;
    final String? tenantId = data['tenantId'] as String?;
    final int? roomNumber = (data['roomNumber'] as num?)?.toInt();
    final String? muntersId = data['muntersId'] as String?;
    final Timestamp? washedAt = data['washedAt'] as Timestamp?;
    final String? createdByUid = data['createdByUid'] as String?;
    final String? createdByName = data['createdByName'] as String?;
    final String? source = data['source'] as String?;
    if (roomId == null ||
        tenantId == null ||
        roomNumber == null ||
        muntersId == null ||
        washedAt == null ||
        createdByUid == null ||
        createdByName == null ||
        source == null) {
      return null;
    }

    return RoomWashEvent(
      id: documentId,
      tenantId: tenantId,
      roomId: roomId,
      roomNumber: roomNumber,
      muntersId: muntersId,
      washedAt: washedAt.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      createdByUid: createdByUid,
      createdByName: createdByName,
      source: source,
    );
  }
}
