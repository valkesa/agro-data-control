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

  AgroDevice copyWith({
    String? name,
    String? type,
    String? model,
    String? description,
    bool? enabled,
    DateTime? updatedAt,
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
        other.updatedAt == updatedAt;
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
