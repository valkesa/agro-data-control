const Set<String> validAgroDataRoles = <String>{
  AgroDataRole.owner,
  AgroDataRole.valkeTechnician,
  AgroDataRole.tenantAdmin,
  AgroDataRole.tenantOperator,
  AgroDataRole.pending,
};

const Set<String> administrativeAgroDataRoles = <String>{
  AgroDataRole.owner,
  AgroDataRole.tenantAdmin,
};

const Set<String> operationalAgroDataRoles = <String>{
  AgroDataRole.owner,
  AgroDataRole.tenantAdmin,
  AgroDataRole.tenantOperator,
};

const Set<String> noTenantAgroDataRoles = <String>{AgroDataRole.pending};

const Set<String> agroDataManagedClaimKeys = <String>{
  'role',
  'tenantRole',
  'activeTenantId',
  'tenantId',
  'allowedSiteIds',
};

class AgroDataRole {
  const AgroDataRole._();

  static const String owner = 'owner';
  static const String valkeTechnician = 'valke_technician';
  static const String tenantAdmin = 'tenant_admin';
  static const String tenantOperator = 'tenant_operator';
  static const String pending = 'pending';
}

class PersistedUserAccessProfile {
  const PersistedUserAccessProfile({
    required this.uid,
    required this.role,
    required this.activeTenantId,
    required this.allowedSiteIds,
    required this.active,
  });

  final String uid;
  final String? role;
  final String? activeTenantId;
  final List<String> allowedSiteIds;
  final bool active;
}

class AuthClaimsBuildResult {
  const AuthClaimsBuildResult._({
    required this.success,
    required this.claims,
    required this.role,
    required this.activeTenantId,
    required this.allowedSiteIds,
    required this.operationalAccess,
    required this.reason,
  });

  const AuthClaimsBuildResult.success({
    required Map<String, Object?> claims,
    required String role,
    required String activeTenantId,
    required List<String> allowedSiteIds,
    required bool operationalAccess,
    required String reason,
  }) : this._(
         success: true,
         claims: claims,
         role: role,
         activeTenantId: activeTenantId,
         allowedSiteIds: allowedSiteIds,
         operationalAccess: operationalAccess,
         reason: reason,
       );

  const AuthClaimsBuildResult.failure({
    required String reason,
    String? role,
    String? activeTenantId,
    List<String> allowedSiteIds = const <String>[],
  }) : this._(
         success: false,
         claims: const <String, Object?>{},
         role: role,
         activeTenantId: activeTenantId,
         allowedSiteIds: allowedSiteIds,
         operationalAccess: false,
         reason: reason,
       );

  final bool success;
  final Map<String, Object?> claims;
  final String? role;
  final String? activeTenantId;
  final List<String> allowedSiteIds;
  final bool operationalAccess;
  final String reason;
}

class AuthClaimsPolicy {
  const AuthClaimsPolicy();

  AuthClaimsBuildResult buildClaims(PersistedUserAccessProfile profile) {
    final String role = (profile.role ?? '').trim();
    final String tenantId = (profile.activeTenantId ?? '').trim();
    final List<String> siteIds = _normalizeSites(profile.allowedSiteIds);

    if (role.isEmpty) {
      return const AuthClaimsBuildResult.failure(reason: 'missing_role');
    }
    if (!validAgroDataRoles.contains(role)) {
      return AuthClaimsBuildResult.failure(
        reason: 'unknown_role',
        role: role,
        activeTenantId: tenantId.isEmpty ? null : tenantId,
        allowedSiteIds: siteIds,
      );
    }
    if (!profile.active || role == AgroDataRole.pending) {
      return const AuthClaimsBuildResult.success(
        claims: <String, Object?>{
          'role': AgroDataRole.pending,
          'allowedSiteIds': <String>[],
        },
        role: AgroDataRole.pending,
        activeTenantId: '',
        allowedSiteIds: <String>[],
        operationalAccess: false,
        reason: 'no_operational_access',
      );
    }

    if (tenantId.isEmpty) {
      return AuthClaimsBuildResult.failure(
        reason: 'missing_active_tenant',
        role: role,
        allowedSiteIds: siteIds,
      );
    }

    if (role == AgroDataRole.tenantAdmin ||
        role == AgroDataRole.tenantOperator ||
        role == AgroDataRole.valkeTechnician) {
      if (siteIds.isEmpty) {
        return AuthClaimsBuildResult.failure(
          reason: 'missing_allowed_sites',
          role: role,
          activeTenantId: tenantId,
        );
      }
    }

    return AuthClaimsBuildResult.success(
      claims: <String, Object?>{
        'role': role,
        'activeTenantId': tenantId,
        'allowedSiteIds': siteIds,
      },
      role: role,
      activeTenantId: tenantId,
      allowedSiteIds: siteIds,
      operationalAccess: operationalAgroDataRoles.contains(role),
      reason: 'operational_claims',
    );
  }

  Map<String, Object?> mergeWithExistingClaims({
    required Map<String, Object?> existingClaims,
    required Map<String, Object?> agroDataClaims,
  }) {
    final Map<String, Object?> merged = <String, Object?>{
      for (final MapEntry<String, Object?> entry in existingClaims.entries)
        if (!agroDataManagedClaimKeys.contains(entry.key))
          entry.key: entry.value,
    };
    for (final MapEntry<String, Object?> entry in agroDataClaims.entries) {
      if (entry.value != null) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  List<String> _normalizeSites(List<String> raw) {
    final Set<String> seen = <String>{};
    final List<String> normalized = <String>[];
    for (final String siteId in raw) {
      final String trimmed = siteId.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) {
        continue;
      }
      seen.add(trimmed);
      normalized.add(trimmed);
    }
    return List<String>.unmodifiable(normalized);
  }
}
