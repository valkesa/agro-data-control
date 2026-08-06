import 'package:cloud_firestore/cloud_firestore.dart';

/// A Tenant: the top-level client/organization boundary. Lives at
/// `tenants/{tenantId}` as a raw map today (no dedicated model existed
/// before this) — `createTenant`'s bulk-provisioning transaction
/// (`UserManagementService.createTenant`) still writes the initial
/// document directly, but this model is the read/administer surface for
/// EXISTING tenants: [AgroTenantService.listTenantsForAdministration],
/// [AgroTenantService.getTenantById], [AgroTenantService.updateTenant].
///
/// Deliberately separate from `TenantDocument` in `site_config_service.dart`
/// (the dashboard's read-only DTO, `tenantId`/`name`/`active` only) — that
/// one stays the lightweight shape the live dashboard already depends on;
/// this one carries the full document (including audit fields) for
/// administration.
class AgroTenant {
  const AgroTenant({
    required this.id,
    required this.name,
    required this.active,
    required this.createdByUid,
    this.createdByEmail,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AgroTenant.fromFirestore(String id, Map<String, Object?> data) {
    return AgroTenant(
      id: id,
      name: data['name'] is String ? data['name'] as String : '',
      active: data['active'] is bool ? data['active'] as bool : true,
      createdByUid: data['createdByUid'] is String
          ? data['createdByUid'] as String
          : '',
      createdByEmail: data['createdByEmail'] is String
          ? data['createdByEmail'] as String
          : null,
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
    );
  }

  final String id;
  final String name;
  final bool active;

  // Audit fields — read-only. Never part of an update payload (see
  // buildAgroTenantUpdatePayload in agro_tenant_service.dart), matching
  // firestore.rules' `allow update` allowlist (name/active/updatedAt only).
  final String createdByUid;
  final String? createdByEmail;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  @override
  bool operator ==(Object other) {
    return other is AgroTenant &&
        other.id == id &&
        other.name == name &&
        other.active == active &&
        other.createdByUid == createdByUid &&
        other.createdByEmail == createdByEmail &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    active,
    createdByUid,
    createdByEmail,
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
