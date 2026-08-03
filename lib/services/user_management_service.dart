import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_device.dart';
import '../models/agro_sector.dart';
import '../models/agro_site.dart';
import 'custom_claims_sync_service.dart';

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

class CreateTenantResult {
  const CreateTenantResult({
    required this.tenantId,
    required this.siteId,
    required this.sectorIds,
    required this.deviceIds,
  });

  final String tenantId;
  final String siteId;
  final List<String> sectorIds;
  final List<String> deviceIds;

  String userMessage() {
    return 'Tenant $tenantId creado con site $siteId, '
        '${sectorIds.length} sectores y ${deviceIds.length} devices.';
  }
}

class SectorCreateInput {
  const SectorCreateInput({
    required this.sectorId,
    required this.name,
    this.description = '',
    this.enabled = true,
  });

  final String sectorId;
  final String name;
  final String description;
  final bool enabled;

  SectorCreateInput normalized() {
    return SectorCreateInput(
      sectorId: _normalizeDocumentId(sectorId),
      name: name.trim(),
      description: description.trim(),
      enabled: enabled,
    );
  }
}

class DeviceCreateInput {
  const DeviceCreateInput({
    required this.deviceId,
    required this.name,
    required this.type,
    this.model = '',
    this.description = '',
    this.enabled = true,
  });

  final String deviceId;
  final String name;
  final String type;
  final String model;
  final String description;
  final bool enabled;

  DeviceCreateInput normalized() {
    return DeviceCreateInput(
      deviceId: _normalizeDocumentId(deviceId),
      name: name.trim(),
      type: _normalizeDocumentId(type),
      model: model.trim(),
      description: description.trim(),
      enabled: enabled,
    );
  }
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
  const UserManagementService({
    CustomClaimsSyncService customClaimsSyncService =
        const CustomClaimsSyncService(),
  }) : _customClaimsSyncService = customClaimsSyncService;

  final CustomClaimsSyncService _customClaimsSyncService;

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

  Future<CreateTenantResult> createTenant({
    required String tenantId,
    required String tenantName,
    required String siteId,
    required String siteName,
    String siteDescription = '',
    required List<SectorCreateInput> sectors,
    required List<DeviceCreateInput> devices,
  }) async {
    final String cleanTenantId = _normalizeDocumentId(tenantId);
    final String cleanTenantName = tenantName.trim();
    final String cleanSiteId = _normalizeDocumentId(siteId);
    final String cleanSiteName = siteName.trim();
    final String cleanSiteDescription = siteDescription.trim();
    final List<SectorCreateInput> cleanSectors = sectors
        .map((SectorCreateInput sector) => sector.normalized())
        .where((SectorCreateInput sector) => sector.sectorId.isNotEmpty)
        .toList(growable: false);
    final List<DeviceCreateInput> cleanDevices = devices
        .map((DeviceCreateInput device) => device.normalized())
        .where((DeviceCreateInput device) => device.deviceId.isNotEmpty)
        .toList(growable: false);

    if (cleanTenantId.isEmpty) {
      throw StateError('El tenantId es requerido.');
    }
    if (cleanTenantName.isEmpty) {
      throw StateError('El nombre del tenant es requerido.');
    }
    if (cleanSiteId.isEmpty) {
      throw StateError('El siteId es requerido.');
    }
    if (cleanSiteName.isEmpty) {
      throw StateError('El nombre del site es requerido.');
    }
    if (cleanSectors.isEmpty) {
      throw StateError('Configurá al menos un sector.');
    }
    if (cleanDevices.isEmpty) {
      throw StateError('Configurá al menos un device.');
    }
    if (cleanSectors.any((SectorCreateInput sector) => sector.name.isEmpty)) {
      throw StateError('Todos los sectores deben tener nombre.');
    }
    if (cleanDevices.any((DeviceCreateInput device) => device.name.isEmpty)) {
      throw StateError('Todos los devices deben tener nombre.');
    }
    if (cleanDevices.any((DeviceCreateInput device) => device.type.isEmpty)) {
      throw StateError('Todos los devices deben tener tipo.');
    }
    final Set<String> sectorIds = cleanSectors
        .map((SectorCreateInput sector) => sector.sectorId)
        .toSet();
    if (sectorIds.length != cleanSectors.length) {
      throw StateError('Los Sector ID no pueden repetirse.');
    }
    final Set<String> deviceIds = cleanDevices
        .map((DeviceCreateInput device) => device.deviceId)
        .toSet();
    if (deviceIds.length != cleanDevices.length) {
      throw StateError('Los Device ID no pueden repetirse.');
    }
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String? createdByUid = currentUser?.uid.trim();
    if (createdByUid == null || createdByUid.isEmpty) {
      throw StateError('No hay usuario autenticado para auditar el alta.');
    }
    final String? createdByEmail = currentUser?.email?.trim();

    final FirebaseFirestore db = FirebaseFirestore.instance;
    final DocumentReference<Map<String, dynamic>> tenantRef = db
        .collection(FirestorePaths.tenantsCollection())
        .doc(cleanTenantId);
    final DocumentReference<Map<String, dynamic>> siteRef = db.doc(
      FirestorePaths.siteDoc(cleanTenantId, cleanSiteId),
    );
    final Map<String, DocumentReference<Map<String, dynamic>>> sectorRefs =
        <String, DocumentReference<Map<String, dynamic>>>{
          for (final SectorCreateInput sector in cleanSectors)
            sector.sectorId: db.doc(
              FirestorePaths.sectorDoc(cleanTenantId, sector.sectorId),
            ),
        };
    final Map<String, DocumentReference<Map<String, dynamic>>> deviceRefs =
        <String, DocumentReference<Map<String, dynamic>>>{
          for (final DeviceCreateInput device in cleanDevices)
            device.deviceId: db.doc(
              FirestorePaths.deviceDoc(cleanTenantId, device.deviceId),
            ),
        };

    await db.runTransaction((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> tenantSnapshot =
          await transaction.get(tenantRef);
      if (tenantSnapshot.exists) {
        throw StateError('Ya existe un tenant con id $cleanTenantId.');
      }
      final DocumentSnapshot<Map<String, dynamic>> siteSnapshot =
          await transaction.get(siteRef);
      if (siteSnapshot.exists) {
        throw StateError('Ya existe el site $cleanSiteId en $cleanTenantId.');
      }
      for (final MapEntry<String, DocumentReference<Map<String, dynamic>>> entry
          in sectorRefs.entries) {
        final DocumentSnapshot<Map<String, dynamic>> sectorSnapshot =
            await transaction.get(entry.value);
        if (sectorSnapshot.exists) {
          throw StateError(
            'Ya existe el sector ${entry.key} en $cleanTenantId.',
          );
        }
      }
      for (final MapEntry<String, DocumentReference<Map<String, dynamic>>> entry
          in deviceRefs.entries) {
        final DocumentSnapshot<Map<String, dynamic>> deviceSnapshot =
            await transaction.get(entry.value);
        if (deviceSnapshot.exists) {
          throw StateError(
            'Ya existe el device ${entry.key} en $cleanTenantId.',
          );
        }
      }

      transaction.set(tenantRef, <String, Object?>{
        'name': cleanTenantName,
        'active': true,
        'createdByUid': createdByUid,
        if (createdByEmail != null && createdByEmail.isNotEmpty)
          'createdByEmail': createdByEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(
        siteRef,
        AgroSite(
          id: cleanSiteId,
          tenantId: cleanTenantId,
          name: cleanSiteName,
          description: cleanSiteDescription,
          enabled: true,
          provisioningStatus: SiteProvisioningStatus.pendingBackend,
          createdAt: null,
          updatedAt: null,
        ).toCreatePayload(),
      );

      for (final SectorCreateInput sector in cleanSectors) {
        transaction.set(
          sectorRefs[sector.sectorId]!,
          AgroSector(
            id: sector.sectorId,
            tenantId: cleanTenantId,
            siteId: cleanSiteId,
            name: sector.name,
            description: sector.description,
            enabled: sector.enabled,
            createdAt: null,
            updatedAt: null,
          ).toCreatePayload(),
        );
      }

      for (final DeviceCreateInput device in cleanDevices) {
        transaction.set(
          deviceRefs[device.deviceId]!,
          AgroDevice(
            id: device.deviceId,
            tenantId: cleanTenantId,
            siteId: cleanSiteId,
            name: device.name,
            type: device.type,
            model: device.model,
            description: device.description,
            enabled: device.enabled,
            createdAt: null,
            updatedAt: null,
          ).toCreatePayload(),
        );
      }
    });

    return CreateTenantResult(
      tenantId: cleanTenantId,
      siteId: cleanSiteId,
      sectorIds: cleanSectors
          .map((SectorCreateInput sector) => sector.sectorId)
          .toList(),
      deviceIds: cleanDevices
          .map((DeviceCreateInput device) => device.deviceId)
          .toList(),
    );
  }

  /// Full access management — callable by owner only.
  ///
  /// Updates role, tenant assignment and allowed sites in both users/{uid} and
  /// tenants/{tenantId}/members/{uid} atomically.
  Future<UserAccessUpdateResult> updateUserAccess({
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

    final CustomClaimsSyncResponse sync = await _customClaimsSyncService
        .syncUser(uid);
    final bool isCurrentUser = FirebaseAuth.instance.currentUser?.uid == uid;
    bool tokenRefreshed = false;
    String? tokenRefreshError;
    if (sync.success && isCurrentUser) {
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        tokenRefreshed = true;
      } catch (error) {
        tokenRefreshError = error.toString();
      }
    }
    return UserAccessUpdateResult(
      firestoreSaved: true,
      claimsSynced: sync.success,
      selfUpdated: isCurrentUser,
      tokenRefreshed: tokenRefreshed,
      claimsMessage: sync.message,
      tokenRefreshError: tokenRefreshError,
    );
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

String _normalizeDocumentId(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

class UserAccessUpdateResult {
  const UserAccessUpdateResult({
    required this.firestoreSaved,
    required this.claimsSynced,
    required this.selfUpdated,
    required this.tokenRefreshed,
    required this.claimsMessage,
    this.tokenRefreshError,
  });

  final bool firestoreSaved;
  final bool claimsSynced;
  final bool selfUpdated;
  final bool tokenRefreshed;
  final String claimsMessage;
  final String? tokenRefreshError;

  String userMessage() {
    if (!claimsSynced) {
      return 'Los datos del usuario fueron guardados, pero sus permisos de acceso no pudieron actualizarse inmediatamente.';
    }
    if (selfUpdated && !tokenRefreshed) {
      return 'Los permisos fueron actualizados. Cerrá sesión y volvé a ingresar para aplicarlos.';
    }
    if (selfUpdated) {
      return 'Los permisos fueron actualizados.';
    }
    return 'Los permisos fueron actualizados. El usuario deberá renovar su sesión para aplicarlos.';
  }
}
