import 'package:agro_data_control_backend/src/auth_claims_policy.dart';
import 'package:agro_data_control_backend/src/firebase_custom_claims_service.dart';

void main() {
  _testValidOperationalRoles();
  _testPendingAndDisabledClearOperationalClaims();
  _testInvalidProfiles();
  _testSiteNormalization();
  _testClaimMerge();
  _testFirestoreParsing();
}

void _testValidOperationalRoles() {
  const AuthClaimsPolicy policy = AuthClaimsPolicy();
  for (final String role in <String>[
    AgroDataRole.owner,
    AgroDataRole.tenantAdmin,
    AgroDataRole.tenantOperator,
  ]) {
    final AuthClaimsBuildResult result = policy.buildClaims(
      _profile(role: role),
    );
    _expect(result.success, '$role builds claims');
    _expect(result.claims['role'] == role, '$role claim is canonical');
    _expect(
      result.claims['activeTenantId'] == 'tenant-a',
      '$role tenant claim is canonical',
    );
    _expect(
      result.claims['allowedSiteIds'] is List<String>,
      '$role allowedSiteIds is a list',
    );
    _expect(result.operationalAccess, '$role has operational access');
  }
}

void _testPendingAndDisabledClearOperationalClaims() {
  const AuthClaimsPolicy policy = AuthClaimsPolicy();
  final AuthClaimsBuildResult pending = policy.buildClaims(
    _profile(role: AgroDataRole.pending, active: true, sites: const <String>[]),
  );
  _expect(pending.success, 'pending produces safe claims');
  _expect(pending.claims['role'] == AgroDataRole.pending, 'pending role kept');
  _expect(
    !pending.claims.containsKey('activeTenantId'),
    'pending has no tenant',
  );
  _expect(
    (pending.claims['allowedSiteIds'] as List).isEmpty,
    'pending has no sites',
  );
  _expect(!pending.operationalAccess, 'pending has no operational access');

  final AuthClaimsBuildResult disabled = policy.buildClaims(
    _profile(role: AgroDataRole.tenantOperator, active: false),
  );
  _expect(disabled.success, 'disabled produces safe claims');
  _expect(
    disabled.claims['role'] == AgroDataRole.pending,
    'disabled user is downgraded to pending claims',
  );
  _expect(!disabled.operationalAccess, 'disabled has no operational access');
}

void _testInvalidProfiles() {
  const AuthClaimsPolicy policy = AuthClaimsPolicy();
  _expect(
    !policy.buildClaims(_profile(role: 'bad_role')).success,
    'unknown role rejected',
  );
  _expect(
    !policy
        .buildClaims(_profile(role: AgroDataRole.tenantOperator, tenant: ''))
        .success,
    'tenant role without tenant rejected',
  );
  _expect(
    !policy
        .buildClaims(
          _profile(role: AgroDataRole.tenantOperator, sites: const <String>[]),
        )
        .success,
    'tenant role without sites rejected',
  );
}

void _testSiteNormalization() {
  const AuthClaimsPolicy policy = AuthClaimsPolicy();
  final AuthClaimsBuildResult result = policy.buildClaims(
    _profile(sites: const <String>[' site-a ', 'site-a', '', 'site-b']),
  );
  _expect(result.success, 'duplicate sites profile valid');
  final List<String> sites = result.claims['allowedSiteIds']! as List<String>;
  _expect(sites.length == 2, 'duplicate sites removed');
  _expect(sites.first == 'site-a', 'sites are trimmed');
  _expect(sites.last == 'site-b', 'site order preserved');
}

void _testClaimMerge() {
  const AuthClaimsPolicy policy = AuthClaimsPolicy();
  final Map<String, Object?> merged = policy.mergeWithExistingClaims(
    existingClaims: const <String, Object?>{
      'role': 'owner',
      'tenantRole': 'tenant_admin',
      'activeTenantId': 'old-tenant',
      'tenantId': 'old-tenant',
      'allowedSiteIds': <String>['old-site'],
      'externalFlag': true,
    },
    agroDataClaims: const <String, Object?>{
      'role': AgroDataRole.tenantOperator,
      'activeTenantId': 'tenant-a',
      'allowedSiteIds': <String>['site-a'],
    },
  );
  _expect(merged['externalFlag'] == true, 'external claims preserved');
  _expect(merged['role'] == AgroDataRole.tenantOperator, 'role replaced');
  _expect(merged['activeTenantId'] == 'tenant-a', 'tenant replaced');
  _expect(
    merged.containsKey('tenantRole') == false,
    'tenantRole alias removed',
  );
  _expect(merged.containsKey('tenantId') == false, 'tenantId alias removed');
}

void _testFirestoreParsing() {
  final PersistedUserAccessProfile profile = firestoreUserProfileFromDocument(
    'uid-1',
    <String, dynamic>{
      'fields': <String, dynamic>{
        'role': <String, dynamic>{'stringValue': AgroDataRole.tenantOperator},
        'activeTenantId': <String, dynamic>{'stringValue': 'tenant-a'},
        'active': <String, dynamic>{'booleanValue': true},
        'allowedSiteIds': <String, dynamic>{
          'arrayValue': <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{'stringValue': 'site-a'},
              <String, dynamic>{'stringValue': 'site-b'},
            ],
          },
        },
      },
    },
  );
  _expect(profile.uid == 'uid-1', 'uid parsed');
  _expect(profile.role == AgroDataRole.tenantOperator, 'role parsed');
  _expect(profile.activeTenantId == 'tenant-a', 'tenant parsed');
  _expect(profile.active, 'active parsed');
  _expect(profile.allowedSiteIds.length == 2, 'sites parsed');
}

PersistedUserAccessProfile _profile({
  String role = AgroDataRole.tenantOperator,
  String tenant = 'tenant-a',
  bool active = true,
  List<String> sites = const <String>['site-a'],
}) {
  return PersistedUserAccessProfile(
    uid: 'uid-1',
    role: role,
    activeTenantId: tenant,
    allowedSiteIds: sites,
    active: active,
  );
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
