import 'package:cloud_firestore/cloud_firestore.dart';

/// Sector: a functional subdivision within a Site (e.g. Genetica,
/// Laboratorio, Maternidad, Recria). Always belongs to exactly one Site.
///
/// Lives at `tenants/{tenantId}/sectors/{sectorId}` — a brand new
/// collection, sibling of `sites`, independent of the legacy
/// `sites/{siteId}/plcs/{plcId}` schema used by PLC LOGO! installations.
///
/// Intentionally does NOT model Zona/Area/Subarea/Sala/Galpon/Jaula — those
/// finer subdivisions are left for future functional modules.
class AgroSector {
  const AgroSector({
    required this.id,
    required this.tenantId,
    required this.siteId,
    required this.name,
    required this.description,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AgroSector.fromFirestore(
    String id, {
    required String tenantId,
    required Map<String, Object?> data,
  }) {
    return AgroSector(
      id: id,
      tenantId: tenantId,
      siteId: data['siteId'] is String ? data['siteId'] as String : '',
      name: data['name'] is String ? data['name'] as String : '',
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
  final String description;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AgroSector copyWith({
    String? name,
    String? description,
    bool? enabled,
    DateTime? updatedAt,
  }) {
    return AgroSector(
      id: id,
      tenantId: tenantId,
      siteId: siteId,
      name: name ?? this.name,
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
      'description': description,
      'enabled': enabled,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, Object?> toUpdatePayload() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AgroSector &&
        other.id == id &&
        other.tenantId == tenantId &&
        other.siteId == siteId &&
        other.name == name &&
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
