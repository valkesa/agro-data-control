import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_tenant.dart';
import 'structural_id_helpers.dart';

/// Read/administer access to [AgroTenant] documents at `tenants/{tenantId}`.
///
/// Creation of a brand-new tenant stays in `UserManagementService.createTenant`
/// (a single atomic transaction that also seeds the initial site/sectors/
/// devices) — this service is for administering a tenant that already
/// exists: listing, reading one, and updating its `name`/`active` fields.
/// Every write here is owner-only, enforced by `firestore.rules`
/// (`tenants/{tenantId}` `allow update`).
///
/// No permanent listeners: every read is a one-shot `.get()`, cached in
/// memory for a short TTL, matching the other structural services
/// (`AgroSiteService`, `AgroSectorService`, `AgroDeviceService`,
/// `AgroDeviceRoomService`).
class AgroTenantService {
  const AgroTenantService();

  static const Duration _cacheTtl = Duration(minutes: 5);
  static const String _listCacheKey = 'all';
  static final Map<String, _CacheEntry<List<AgroTenant>>> _listCache =
      <String, _CacheEntry<List<AgroTenant>>>{};

  /// Lists every tenant, including `active == false` ones — administration
  /// screens need to see (and re-enable) disabled tenants, unlike the
  /// dashboard's own tenant discovery (`SiteConfigService.fetchActiveTenants`,
  /// which stays untouched and keeps filtering to active tenants only).
  ///
  /// Unlike every other structural service's list method, a Firestore
  /// failure here is RETHROWN rather than swallowed into an empty list.
  /// This is the deliberate exception: it's the entry point of an admin
  /// screen (`TenantManagementPage`) whose whole job is to tell an owner
  /// "no tenants" apart from "your read was denied" or "you're offline" —
  /// swallowing here would make a permissions problem look identical to a
  /// genuinely empty tenants collection. The dashboard-facing list methods
  /// (`AgroSiteService`/`AgroSectorService`/`AgroDeviceService.listByTenant`)
  /// intentionally keep swallowing — a transient read failure there must
  /// not crash the live dashboard.
  Future<List<AgroTenant>> listTenantsForAdministration() async {
    final _CacheEntry<List<AgroTenant>>? cached = _listCache[_listCacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final String path = FirestorePaths.tenantsCollection();
    debugPrint('[AgroTenant] listTenantsForAdministration path=$path');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(path)
          .get();
      final List<AgroTenant> tenants =
          snap.docs
              .map((doc) => AgroTenant.fromFirestore(doc.id, doc.data()))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      _listCache[_listCacheKey] = _CacheEntry<List<AgroTenant>>(
        value: tenants,
        expiresAt: DateTime.now().add(_cacheTtl),
      );
      return tenants;
    } catch (error) {
      debugPrint(
        '[AgroTenant] listTenantsForAdministration error path=$path error=$error — rethrowing for the admin UI to surface',
      );
      rethrow;
    }
  }

  Future<AgroTenant?> getTenantById(String tenantId) async {
    final String path = FirestorePaths.tenantDoc(tenantId);
    debugPrint('[AgroTenant] getTenantById path=$path');
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .doc(path)
          .get();
      if (!doc.exists) {
        return null;
      }
      return AgroTenant.fromFirestore(
        doc.id,
        doc.data() ?? const <String, Object?>{},
      );
    } catch (error) {
      debugPrint(
        '[AgroTenant] getTenantById error path=$path error=$error — returning null',
      );
      return null;
    }
  }

  /// Updates an existing tenant's `name`/`active`. Never touches `createdAt`,
  /// `createdByUid`, or `createdByEmail` — those are immutable audit fields,
  /// enforced both here (the payload never includes them) and by
  /// firestore.rules (`allow update`'s key allowlist excludes them).
  Future<void> updateTenant({
    required String tenantId,
    required String name,
    required bool active,
  }) async {
    final String trimmedName = requireNonEmptyField(
      name,
      'El nombre del tenant',
    );
    final String path = FirestorePaths.tenantDoc(tenantId);
    final Map<String, Object?> payload = buildAgroTenantUpdatePayload(
      name: trimmedName,
      active: active,
    );
    await FirebaseFirestore.instance
        .doc(path)
        .set(payload, SetOptions(merge: true));
    invalidateCache();
    debugPrint('[AgroTenant] updated path=$path name=$trimmedName');
  }

  /// Clears the tenant list cache. There is only ever one list (all
  /// tenants), so — unlike the per-tenant-scoped services — this has no
  /// narrower scope to target.
  void invalidateCache() {
    _listCache.remove(_listCacheKey);
  }
}

class _CacheEntry<T> {
  _CacheEntry({required this.value, required this.expiresAt});

  final T value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Builds the Firestore payload for creating a new tenant document.
/// Used by `UserManagementService.createTenant` inside its transaction,
/// replacing what used to be an inline raw map literal.
Map<String, Object?> buildAgroTenantCreatePayload({
  required String name,
  required String createdByUid,
  String? createdByEmail,
}) {
  return <String, Object?>{
    'name': name,
    'active': true,
    'createdByUid': createdByUid,
    if (createdByEmail != null && createdByEmail.isNotEmpty)
      'createdByEmail': createdByEmail,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Builds a PARTIAL update payload containing only `name`, `active`, and
/// `updatedAt` — never `createdAt`/`createdByUid`/`createdByEmail`. Written
/// via `.set(payload, SetOptions(merge: true))`, so omitted fields on the
/// existing document are left untouched.
Map<String, Object?> buildAgroTenantUpdatePayload({
  required String name,
  required bool active,
}) {
  return <String, Object?>{
    'name': name,
    'active': active,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
