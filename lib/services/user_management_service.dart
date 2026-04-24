import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';

class UserAppRole {
  const UserAppRole._();

  // ── Global roles (stored in users/{uid}.role) ──────────────────────────────
  // 'owner'   → full system access, configured directly in Firestore
  // 'valke_technician' → Valke staff read-only access to an assigned tenant
  // 'pending' → registered but not yet assigned to any tenant
  static const String owner = 'owner';
  static const String valkeTechnician = 'valke_technician';
  static const String pending = 'pending';

  // ── Tenant roles (stored in tenants/{tenantId}/members/{uid}.role) ─────────
  // Also stored in users/{uid}.role for display purposes only — never used for
  // tenant-level security decisions (those come from the membership document).
  static const String tenantAdmin = 'tenant_admin';
  static const String tenantOperator = 'tenant_operator';

  // Roles selectable via the UI when assigning a user to a tenant.
  // 'owner' is intentionally excluded — owners are set directly in Firestore.
  static const List<String> all = <String>[
    valkeTechnician,
    tenantAdmin,
    tenantOperator,
  ];

  static String label(String? role) {
    return switch (role) {
      owner => 'Owner',
      valkeTechnician => 'Tecnico Valke',
      tenantAdmin => 'Admin de tenant',
      tenantOperator => 'Operador',
      pending => 'Pendiente',
      _ => 'Sin rol',
    };
  }
}

class TenantInfo {
  const TenantInfo({required this.tenantId, required this.name});

  final String tenantId;
  final String name;
}

class SiteInfo {
  const SiteInfo({required this.siteId, required this.name});

  final String siteId;
  final String name;
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    required this.activeTenantId,
    required this.defaultSiteId,
    required this.allowedSiteIds,
    required this.active,
  });

  final String uid;
  final String? email;
  final String? role;
  final String? activeTenantId;
  final String? defaultSiteId;
  final List<String> allowedSiteIds;
  final bool active;
}

class UserManagementService {
  const UserManagementService();

  Future<List<UserProfile>> listAllUsers() async {
    debugPrint('[UserManagement] listing all users');
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance.collection('users').get();

      return snapshot.docs.map((DocumentSnapshot<Map<String, dynamic>> doc) {
        final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
        return UserProfile(
          uid: doc.id,
          email: data['email']?.toString(),
          role: data['role']?.toString(),
          activeTenantId: data['activeTenantId']?.toString(),
          defaultSiteId: data['defaultSiteId']?.toString(),
          allowedSiteIds: _parseStringList(data['allowedSiteIds']),
          active: data['active'] == true,
        );
      }).toList();
    } catch (error, stackTrace) {
      debugPrint('[UserManagement] listAllUsers error=$error');
      debugPrint('[UserManagement] listAllUsers stack=$stackTrace');
      rethrow;
    }
  }

  Future<List<TenantInfo>> listTenants() async {
    debugPrint('[UserManagement] listing tenants');
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection(FirestorePaths.tenantsCollection())
              .get();

      return snapshot.docs.map((DocumentSnapshot<Map<String, dynamic>> doc) {
        final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
        final String name =
            data['name']?.toString() ??
            data['clientName']?.toString() ??
            doc.id;
        return TenantInfo(tenantId: doc.id, name: name);
      }).toList();
    } catch (error, stackTrace) {
      debugPrint('[UserManagement] listTenants error=$error');
      debugPrint('[UserManagement] listTenants stack=$stackTrace');
      rethrow;
    }
  }

  Future<List<SiteInfo>> listSitesForTenant(String tenantId) async {
    debugPrint('[UserManagement] listing sites for tenantId=$tenantId');
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection(FirestorePaths.tenantSitesCollection(tenantId))
              .get();

      return snapshot.docs.map((DocumentSnapshot<Map<String, dynamic>> doc) {
        final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
        final String name =
            data['name']?.toString() ?? data['siteName']?.toString() ?? doc.id;
        return SiteInfo(siteId: doc.id, name: name);
      }).toList();
    } catch (error, stackTrace) {
      debugPrint(
        '[UserManagement] listSitesForTenant tenantId=$tenantId error=$error',
      );
      debugPrint('[UserManagement] listSitesForTenant stack=$stackTrace');
      rethrow;
    }
  }

  Future<void> updateUserRole(String uid, String? role) async {
    debugPrint('[UserManagement] updateUserRole uid=$uid role=$role');
    await FirebaseFirestore.instance.collection('users').doc(uid).update(
      <String, Object?>{'role': role},
    );
  }

  /// Full access management — callable by owner only.
  ///
  /// Updates role, tenant assignment and allowed sites in both users/{uid} and
  /// tenants/{tenantId}/members/{uid} atomically.
  Future<void> updateUserAccess({
    required String uid,
    required String? role,
    required String? tenantId,
    required List<String> allowedSiteIds,
    required String? previousTenantId,
  }) async {
    if (role == UserAppRole.owner) {
      throw StateError(
        'El rol owner no puede asignarse desde la app. '
        'Configurarlo directamente en Firestore.',
      );
    }
    final bool isTenantRole =
        role == UserAppRole.tenantAdmin || role == UserAppRole.tenantOperator;

    debugPrint(
      '[UserManagement] updateUserAccess uid=$uid role=$role '
      'tenantId=$tenantId sites=$allowedSiteIds previousTenant=$previousTenantId',
    );

    final String? defaultSiteId = allowedSiteIds.isNotEmpty
        ? allowedSiteIds.first
        : null;

    final WriteBatch batch = FirebaseFirestore.instance.batch();

    // Update user profile (role stored here is informational/display only;
    // tenant-level security always reads from members/{uid}.role).
    final DocumentReference<Map<String, dynamic>> userRef = FirebaseFirestore
        .instance
        .collection('users')
        .doc(uid);
    batch.set(userRef, <String, Object?>{
      'role': role,
      'activeTenantId': tenantId,
      'defaultSiteId': defaultSiteId,
      'allowedSiteIds': allowedSiteIds,
      'active': tenantId != null && allowedSiteIds.isNotEmpty,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Upsert tenant membership only for tenant roles. Global Valke roles use
    // users/{uid}.role plus activeTenantId/allowedSiteIds for read-only access.
    if (tenantId != null && isTenantRole) {
      final DocumentReference<Map<String, dynamic>> memberRef =
          FirebaseFirestore.instance.doc(
            FirestorePaths.tenantMemberDoc(tenantId, uid),
          );
      batch.set(memberRef, <String, Object?>{
        'role': role,
        'active': allowedSiteIds.isNotEmpty,
        'siteIds': allowedSiteIds,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // Deactivate old membership if tenant changed, or when switching from a
    // tenant role to a global/non-tenant role such as valke_technician.
    if (previousTenantId != null &&
        previousTenantId.isNotEmpty &&
        (previousTenantId != tenantId || !isTenantRole)) {
      final DocumentReference<Map<String, dynamic>> oldMemberRef =
          FirebaseFirestore.instance.doc(
            FirestorePaths.tenantMemberDoc(previousTenantId, uid),
          );
      batch.set(oldMemberRef, <String, Object?>{
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    debugPrint('[UserManagement] updateUserAccess committed uid=$uid');
  }

  /// Assigns a user as tenant_operator within a tenant.
  ///
  /// Can be called by owner (any role) or tenant_admin (operator only).
  /// Validates privilege escalation at the service layer; Firestore Rules
  /// provide the enforcement layer.
  Future<void> assignOperatorToTenant({
    required String callerUid,
    required String callerTenantRole,
    required String targetUid,
    required String tenantId,
    required List<String> siteIds,
  }) async {
    _assertNotSelf(callerUid, targetUid);
    _assertCanAssignOperator(callerTenantRole);

    debugPrint(
      '[UserManagement] assignOperatorToTenant caller=$callerUid '
      'target=$targetUid tenant=$tenantId sites=$siteIds',
    );

    final DocumentReference<Map<String, dynamic>> memberRef = FirebaseFirestore
        .instance
        .doc(FirestorePaths.tenantMemberDoc(tenantId, targetUid));
    await memberRef.set(<String, Object?>{
      'role': UserAppRole.tenantOperator,
      'active': siteIds.isNotEmpty,
      'siteIds': siteIds,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': callerUid,
    }, SetOptions(merge: true));
    debugPrint(
      '[UserManagement] assignOperatorToTenant done target=$targetUid',
    );
  }

  /// Updates the site list (and active status) of an existing tenant member.
  ///
  /// tenant_admin can only update tenant_operator records.
  /// Owner can update any role.
  Future<void> updateTenantMember({
    required String callerUid,
    required String callerTenantRole,
    required String targetUid,
    required String tenantId,
    required String targetCurrentRole,
    required List<String> siteIds,
  }) async {
    _assertNotSelf(callerUid, targetUid);
    _assertCanModifyMember(callerTenantRole, targetCurrentRole);

    debugPrint(
      '[UserManagement] updateTenantMember caller=$callerUid '
      'target=$targetUid tenant=$tenantId sites=$siteIds',
    );

    final DocumentReference<Map<String, dynamic>> memberRef = FirebaseFirestore
        .instance
        .doc(FirestorePaths.tenantMemberDoc(tenantId, targetUid));
    await memberRef.update(<String, Object?>{
      'active': siteIds.isNotEmpty,
      'siteIds': siteIds,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': callerUid,
    });
    debugPrint('[UserManagement] updateTenantMember done target=$targetUid');
  }

  /// Deactivates a tenant member (sets active=false, does not delete the doc).
  ///
  /// tenant_admin can only remove tenant_operator.
  /// Owner can remove any role.
  Future<void> removeTenantMember({
    required String callerUid,
    required String callerTenantRole,
    required String targetUid,
    required String tenantId,
    required String targetCurrentRole,
  }) async {
    _assertNotSelf(callerUid, targetUid);
    _assertCanModifyMember(callerTenantRole, targetCurrentRole);

    debugPrint(
      '[UserManagement] removeTenantMember caller=$callerUid '
      'target=$targetUid tenant=$tenantId',
    );

    final DocumentReference<Map<String, dynamic>> memberRef = FirebaseFirestore
        .instance
        .doc(FirestorePaths.tenantMemberDoc(tenantId, targetUid));
    await memberRef.update(<String, Object?>{
      'active': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': callerUid,
    });
    debugPrint('[UserManagement] removeTenantMember done target=$targetUid');
  }

  // ── Private validators ────────────────────────────────────────────────────

  static void _assertNotSelf(String callerUid, String targetUid) {
    if (callerUid == targetUid) {
      throw StateError(
        'Acceso denegado: no podés modificar tu propio acceso de tenant.',
      );
    }
  }

  static void _assertCanAssignOperator(String callerTenantRole) {
    if (callerTenantRole != UserAppRole.owner &&
        callerTenantRole != UserAppRole.tenantAdmin) {
      throw StateError(
        'Acceso denegado: se requiere tenant_admin u owner para asignar operadores.',
      );
    }
  }

  // tenant_admin can only modify tenant_operator records.
  // owner can modify any role.
  static void _assertCanModifyMember(
    String callerTenantRole,
    String targetCurrentRole,
  ) {
    if (callerTenantRole == UserAppRole.owner) return;
    if (callerTenantRole != UserAppRole.tenantAdmin) {
      throw StateError('Acceso denegado: se requiere tenant_admin u owner.');
    }
    if (targetCurrentRole != UserAppRole.tenantOperator) {
      throw StateError(
        'Acceso denegado: tenant_admin solo puede modificar tenant_operator.',
      );
    }
  }

  static List<String> _parseStringList(Object? value) {
    if (value is List<dynamic>) {
      return value
          .map((Object? e) => e?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }
}
