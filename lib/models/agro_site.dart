import 'package:cloud_firestore/cloud_firestore.dart';

abstract class SiteProvisioningStatus {
  static const String pendingBackend = 'pending_backend';
  static const String ready = 'ready';
  static const String error = 'error';

  static const Set<String> allowed = <String>{pendingBackend, ready, error};

  static String? normalize(Object? value) {
    if (value is! String) {
      return null;
    }
    final String trimmed = value.trim();
    return allowed.contains(trimmed) ? trimmed : null;
  }

  static String label(String? status) {
    return switch (status) {
      ready => 'Listo',
      error => 'Error de configuración',
      pendingBackend => 'Pendiente de backend',
      _ => 'Sin estado',
    };
  }
}

/// Site: a physical plant/establishment/location that belongs to a tenant.
///
/// Lives at `tenants/{tenantId}/sites/{siteId}` — the SAME collection
/// already used by the legacy PLC LOGO! schema (`sites/{siteId}/plcs/...`,
/// see [FirestorePaths.plcsCollection]). This model only reads/writes its
/// own fields (name, description, enabled, createdAt, updatedAt) and never
/// touches the legacy fields (technicalId, backendUrl, active) used by
/// `SiteDocument` in `site_config_service.dart`.
class AgroSite {
  const AgroSite({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.description,
    required this.enabled,
    required this.provisioningStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AgroSite.fromFirestore(
    String id, {
    required String tenantId,
    required Map<String, Object?> data,
  }) {
    return AgroSite(
      id: id,
      tenantId: tenantId,
      name: data['name'] is String ? data['name'] as String : '',
      description: data['description'] is String
          ? data['description'] as String
          : '',
      enabled: data['enabled'] is bool ? data['enabled'] as bool : true,
      provisioningStatus:
          SiteProvisioningStatus.normalize(data['provisioningStatus']) ??
          SiteProvisioningStatus.pendingBackend,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
    );
  }

  final String id;
  final String tenantId;
  final String name;
  final String description;
  final bool enabled;
  final String provisioningStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AgroSite copyWith({
    String? name,
    String? description,
    bool? enabled,
    String? provisioningStatus,
    DateTime? updatedAt,
  }) {
    return AgroSite(
      id: id,
      tenantId: tenantId,
      name: name ?? this.name,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      provisioningStatus: provisioningStatus ?? this.provisioningStatus,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Payload for creating a new site document. `createdAt` is set once
  /// here and must stay immutable afterwards (enforced by firestore.rules).
  Map<String, Object?> toCreatePayload() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'enabled': enabled,
      'provisioningStatus': provisioningStatus,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Payload for updating an existing site document. Never includes
  /// `createdAt` — it is immutable after creation.
  Map<String, Object?> toUpdatePayload() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'enabled': enabled,
      'provisioningStatus': provisioningStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AgroSite &&
        other.id == id &&
        other.tenantId == tenantId &&
        other.name == name &&
        other.description == description &&
        other.enabled == enabled &&
        other.provisioningStatus == provisioningStatus &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    tenantId,
    name,
    description,
    enabled,
    provisioningStatus,
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
