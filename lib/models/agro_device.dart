import 'package:cloud_firestore/cloud_firestore.dart';

/// Known device `type` values, kept as plain strings (NOT a closed enum) so
/// new device types can be added later without a code change. These
/// constants exist purely for typo-safety when writing code against this
/// model — [AgroDevice.type] accepts any normalized string.
abstract class AgroDeviceType {
  static const String s7 = 's7';
  static const String logo = 'logo';
  static const String modbusGateway = 'modbus_gateway';
  static const String iotSensor = 'iot_sensor';
  static const String other = 'other';
}

/// Device: a physical automation/acquisition/control device (Siemens S7,
/// PLC LOGO!, Modbus gateway, IoT sensor, etc). Always belongs to exactly
/// one Site. A Device may handle variables from multiple Sectors, as long
/// as every one of those Sectors belongs to the same Site as the Device
/// (see `deviceAndSectorBelongToSameSite` in `agro_site_hierarchy_service.dart`).
///
/// Lives at `tenants/{tenantId}/devices/{deviceId}` — a brand new
/// collection, sibling of `sites`/`sectors`, independent of the legacy
/// `sites/{siteId}/plcs/{plcId}` schema used by PLC LOGO! installations.
class AgroDevice {
  const AgroDevice({
    required this.id,
    required this.tenantId,
    required this.siteId,
    required this.name,
    required this.type,
    required this.model,
    required this.description,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.sortOrder = 0,
    this.snapshotUnitKey,
    this.sectorIds = const <String>[],
  });

  factory AgroDevice.fromFirestore(
    String id, {
    required String tenantId,
    required Map<String, Object?> data,
  }) {
    return AgroDevice(
      id: id,
      tenantId: tenantId,
      siteId: data['siteId'] is String ? data['siteId'] as String : '',
      name: data['name'] is String ? data['name'] as String : '',
      type: data['type'] is String
          ? data['type'] as String
          : AgroDeviceType.other,
      model: data['model'] is String ? data['model'] as String : '',
      description: data['description'] is String
          ? data['description'] as String
          : '',
      enabled: data['enabled'] is bool ? data['enabled'] as bool : true,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
      sortOrder: data['sortOrder'] is int ? data['sortOrder'] as int : 0,
      snapshotUnitKey: data['snapshotUnitKey'] is String
          ? data['snapshotUnitKey'] as String
          : null,
      sectorIds: data['sectorIds'] is List
          ? (data['sectorIds'] as List<Object?>).whereType<String>().toList()
          : const <String>[],
    );
  }

  final String id;
  final String tenantId;
  final String siteId;
  final String name;
  final String type;
  final String model;
  final String description;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Display order among the devices of the same site — ascending. Mirrors
  /// the naming already used by the legacy `PlcDisplayConfig.sortOrder`.
  final int sortOrder;

  /// The key this device's telemetry is expected under in the backend
  /// snapshot JSON (`DashboardSnapshot`'s per-unit map). Null until the
  /// device is wired to a live backend; consumers should fall back to
  /// [id] when null (see [effectiveSnapshotUnitKey]).
  final String? snapshotUnitKey;

  /// Convenience for joining against a live snapshot: use the explicit
  /// [snapshotUnitKey] when set, otherwise assume it matches [id].
  String get effectiveSnapshotUnitKey => snapshotUnitKey ?? id;

  /// Sectors (within the SAME Site) this Device handles variables from —
  /// see `deviceAndSectorBelongToSameSite` in `agro_site_hierarchy_service.dart`.
  /// Optional: a Device may legitimately have zero associated Sectors (it
  /// covers the whole Site rather than one functional subdivision of it).
  final List<String> sectorIds;

  AgroDevice copyWith({
    String? name,
    String? type,
    String? model,
    String? description,
    bool? enabled,
    DateTime? updatedAt,
    int? sortOrder,
    String? snapshotUnitKey,
    List<String>? sectorIds,
  }) {
    return AgroDevice(
      id: id,
      tenantId: tenantId,
      siteId: siteId,
      name: name ?? this.name,
      type: type ?? this.type,
      model: model ?? this.model,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      snapshotUnitKey: snapshotUnitKey ?? this.snapshotUnitKey,
      sectorIds: sectorIds ?? this.sectorIds,
    );
  }

  Map<String, Object?> toCreatePayload() {
    return <String, Object?>{
      'siteId': siteId,
      'name': name,
      'type': type,
      'model': model,
      'description': description,
      'enabled': enabled,
      'sortOrder': sortOrder,
      if (snapshotUnitKey != null) 'snapshotUnitKey': snapshotUnitKey,
      'sectorIds': sectorIds,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, Object?> toUpdatePayload() {
    return <String, Object?>{
      'name': name,
      'type': type,
      'model': model,
      'description': description,
      'enabled': enabled,
      'sortOrder': sortOrder,
      if (snapshotUnitKey != null) 'snapshotUnitKey': snapshotUnitKey,
      'sectorIds': sectorIds,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AgroDevice &&
        other.id == id &&
        other.tenantId == tenantId &&
        other.siteId == siteId &&
        other.name == name &&
        other.type == type &&
        other.model == model &&
        other.description == description &&
        other.enabled == enabled &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.sortOrder == sortOrder &&
        other.snapshotUnitKey == snapshotUnitKey &&
        _listEquals(other.sectorIds, sectorIds);
  }

  @override
  int get hashCode => Object.hash(
    id,
    tenantId,
    siteId,
    name,
    type,
    model,
    description,
    enabled,
    createdAt,
    updatedAt,
    sortOrder,
    snapshotUnitKey,
    Object.hashAll(sectorIds),
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
