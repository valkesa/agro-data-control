import 'package:cloud_firestore/cloud_firestore.dart';

/// A logical Room exposed by a physical [AgroDevice] — e.g. one PLC wired to
/// several Salas, each with its own Temperature/Humidity telemetry under a
/// distinct snapshot unit key.
///
/// Lives at `tenants/{tenantId}/devices/{deviceId}/rooms/{roomId}` — a
/// subcollection of the owning Device. A Device with zero Room documents is
/// still valid: it is treated as exposing exactly one implicit Room (itself),
/// preserving the original 1 Device = 1 snapshot unit behavior.
class AgroDeviceRoom {
  const AgroDeviceRoom({
    required this.id,
    required this.tenantId,
    required this.deviceId,
    required this.siteId,
    required this.name,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.sortOrder = 0,
    this.snapshotUnitKey,
  });

  factory AgroDeviceRoom.fromFirestore(
    String id, {
    required String tenantId,
    required String deviceId,
    required Map<String, Object?> data,
  }) {
    return AgroDeviceRoom(
      id: id,
      tenantId: tenantId,
      deviceId: deviceId,
      siteId: data['siteId'] is String ? data['siteId'] as String : '',
      name: data['name'] is String ? data['name'] as String : '',
      enabled: data['enabled'] is bool ? data['enabled'] as bool : true,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
      sortOrder: data['sortOrder'] is int ? data['sortOrder'] as int : 0,
      snapshotUnitKey: data['snapshotUnitKey'] is String
          ? data['snapshotUnitKey'] as String
          : null,
    );
  }

  final String id;
  final String tenantId;
  final String deviceId;
  final String siteId;
  final String name;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Display order among the rooms of the same device — ascending. Mirrors
  /// [AgroDevice.sortOrder].
  final int sortOrder;

  /// The key this room's telemetry is expected under in the backend
  /// snapshot JSON. Null until wired to a live backend; consumers should
  /// fall back to `'${deviceId}__$id'` when null (see
  /// [effectiveSnapshotUnitKey]).
  final String? snapshotUnitKey;

  /// Convenience for joining against a live snapshot: use the explicit
  /// [snapshotUnitKey] when set, otherwise assume it matches
  /// `'${deviceId}__$id'`.
  String get effectiveSnapshotUnitKey => snapshotUnitKey ?? '${deviceId}__$id';

  AgroDeviceRoom copyWith({
    String? name,
    bool? enabled,
    DateTime? updatedAt,
    int? sortOrder,
    String? snapshotUnitKey,
  }) {
    return AgroDeviceRoom(
      id: id,
      tenantId: tenantId,
      deviceId: deviceId,
      siteId: siteId,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      snapshotUnitKey: snapshotUnitKey ?? this.snapshotUnitKey,
    );
  }

  Map<String, Object?> toCreatePayload() {
    return <String, Object?>{
      'siteId': siteId,
      'name': name,
      'enabled': enabled,
      'sortOrder': sortOrder,
      if (snapshotUnitKey != null) 'snapshotUnitKey': snapshotUnitKey,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, Object?> toUpdatePayload() {
    return <String, Object?>{
      'name': name,
      'enabled': enabled,
      'sortOrder': sortOrder,
      if (snapshotUnitKey != null) 'snapshotUnitKey': snapshotUnitKey,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AgroDeviceRoom &&
        other.id == id &&
        other.tenantId == tenantId &&
        other.deviceId == deviceId &&
        other.siteId == siteId &&
        other.name == name &&
        other.enabled == enabled &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.sortOrder == sortOrder &&
        other.snapshotUnitKey == snapshotUnitKey;
  }

  @override
  int get hashCode => Object.hash(
    id,
    tenantId,
    deviceId,
    siteId,
    name,
    enabled,
    createdAt,
    updatedAt,
    sortOrder,
    snapshotUnitKey,
  );
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
