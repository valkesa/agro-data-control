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
    this.isLegacyStructure = false,
  });

  factory AgroSite.fromFirestore(
    String id, {
    required String tenantId,
    required Map<String, Object?> data,
  }) {
    // `provisioningStatus` is only ever set on documents written through the
    // new Sites/Sectors/Devices schema (see `buildAgroSiteCreatePayload`,
    // always sets it). A site whose raw stored value is absent/invalid
    // predates that schema — the legacy PLC LOGO! sites (`sites/{siteId}/plcs`
    // subcollection), sharing this SAME `sites` collection. Read that BEFORE
    // defaulting, so administration UIs can tell "legacy" apart from "new
    // site, still pending_backend" — both would otherwise collapse to the
    // same defaulted string.
    final String? storedProvisioningStatus = SiteProvisioningStatus.normalize(
      data['provisioningStatus'],
    );
    return AgroSite(
      id: id,
      tenantId: tenantId,
      name: data['name'] is String ? data['name'] as String : '',
      description: data['description'] is String
          ? data['description'] as String
          : '',
      enabled: data['enabled'] is bool ? data['enabled'] as bool : true,
      provisioningStatus:
          storedProvisioningStatus ?? SiteProvisioningStatus.pendingBackend,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
      isLegacyStructure: storedProvisioningStatus == null,
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

  /// True when this Site document has no stored `provisioningStatus` at
  /// all — i.e. it predates the Sites/Sectors/Devices schema and is only
  /// reachable via the legacy `sites/{siteId}/plcs/{plcId}` subcollection.
  /// Defaults to `false` for hand-built instances (every real caller that
  /// constructs an `AgroSite` directly — `create`/`update` payload builders
  /// — is always building a new-schema site).
  final bool isLegacyStructure;

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
      isLegacyStructure: isLegacyStructure,
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
        other.updatedAt == updatedAt &&
        other.isLegacyStructure == isLegacyStructure;
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
    isLegacyStructure,
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
