import 'firebase_request_auth.dart';

const Set<String> roomWashWriterRoles = <String>{
  'owner',
  'tenant_admin',
  'tenant_operator',
};

RoomWashAuthorizationResult canRegisterRoomWash({
  required AuthenticatedBackendUser user,
  required String siteId,
}) {
  final String role = user.role?.trim() ?? '';
  final String tenantId = user.tenantId?.trim() ?? '';
  final String normalizedSiteId = siteId.trim();
  if (role.isEmpty || !roomWashWriterRoles.contains(role)) {
    return RoomWashAuthorizationResult.denied(
      reason: 'role_not_allowed',
      tenantId: tenantId,
      role: role,
    );
  }
  if (tenantId.isEmpty) {
    return RoomWashAuthorizationResult.denied(
      reason: 'missing_tenant',
      tenantId: tenantId,
      role: role,
    );
  }
  if (normalizedSiteId.isEmpty) {
    return RoomWashAuthorizationResult.denied(
      reason: 'missing_site',
      tenantId: tenantId,
      role: role,
    );
  }
  final List<String> allowedSiteIds = user.allowedSiteIds;
  if (allowedSiteIds.isNotEmpty && !allowedSiteIds.contains(normalizedSiteId)) {
    return RoomWashAuthorizationResult.denied(
      reason: 'site_not_allowed',
      tenantId: tenantId,
      role: role,
    );
  }
  return RoomWashAuthorizationResult.allowed(
    tenantId: tenantId,
    role: role,
    siteValidation: allowedSiteIds.isEmpty
        ? RoomWashSiteValidation.tenantOnly
        : RoomWashSiteValidation.allowedSitesClaim,
  );
}

enum RoomWashSiteValidation { allowedSitesClaim, tenantOnly }

class RoomWashAuthorizationResult {
  const RoomWashAuthorizationResult._({
    required this.allowed,
    required this.reason,
    required this.tenantId,
    required this.role,
    required this.siteValidation,
  });

  const RoomWashAuthorizationResult.allowed({
    required String tenantId,
    required String role,
    required RoomWashSiteValidation siteValidation,
  }) : this._(
         allowed: true,
         reason: 'allowed',
         tenantId: tenantId,
         role: role,
         siteValidation: siteValidation,
       );

  const RoomWashAuthorizationResult.denied({
    required String reason,
    required String tenantId,
    required String role,
  }) : this._(
         allowed: false,
         reason: reason,
         tenantId: tenantId,
         role: role,
         siteValidation: null,
       );

  final bool allowed;
  final String reason;
  final String tenantId;
  final String role;
  final RoomWashSiteValidation? siteValidation;
}
