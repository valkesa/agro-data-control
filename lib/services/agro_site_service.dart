import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_site.dart';
import 'structural_id_helpers.dart';

/// Read/write access to the new-schema [AgroSite] documents, which live at
/// `tenants/{tenantId}/sites/{siteId}` — the SAME Firestore path already
/// used by the legacy PLC LOGO! schema (see `site_config_service.dart` /
/// `site_plc_config_service.dart`, left untouched by this service). See
/// [AgroSite] for why writes here never disturb legacy fields on that
/// document.
///
/// No permanent listeners: every read is a one-shot `.get()`, cached in
/// memory for a short TTL to avoid repeated reads when the UI re-lists the
/// same tenant back to back.
class AgroSiteService {
  const AgroSiteService();

  static const Duration _cacheTtl = Duration(minutes: 5);
  static final Map<String, _CacheEntry<List<AgroSite>>> _listCache =
      <String, _CacheEntry<List<AgroSite>>>{};

  /// Lists every AgroSite document under a tenant (both sites created
  /// through the new schema and legacy sites that already had `plcs`
  /// before this change — they share the same collection).
  ///
  /// Unlike `listBySite`-style methods used by the LIVE dashboard (none of
  /// which exist on this service — the dashboard never calls
  /// `AgroSiteService` at all, only `SiteConfigService`), a Firestore
  /// failure here is RETHROWN rather than swallowed. This method has
  /// exactly one caller today, `TenantManagementPage`, whose whole job is
  /// to show an owner "this tenant has no sites" apart from "your read was
  /// denied" — see `AgroTenantService.listTenantsForAdministration`'s doc
  /// comment for the same reasoning, applied here for the same reason.
  Future<List<AgroSite>> listByTenant(String tenantId) async {
    final _CacheEntry<List<AgroSite>>? cached = _listCache[tenantId];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final String path = FirestorePaths.tenantSitesCollection(tenantId);
    debugPrint('[AgroSite] listByTenant path=$path');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(path)
          .get();
      final List<AgroSite> sites =
          snap.docs
              .map(
                (doc) => AgroSite.fromFirestore(
                  doc.id,
                  tenantId: tenantId,
                  data: doc.data(),
                ),
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      _listCache[tenantId] = _CacheEntry<List<AgroSite>>(
        value: sites,
        expiresAt: DateTime.now().add(_cacheTtl),
      );
      return sites;
    } catch (error) {
      debugPrint(
        '[AgroSite] listByTenant error path=$path error=$error — rethrowing for the admin UI to surface',
      );
      rethrow;
    }
  }

  Future<AgroSite?> getById({
    required String tenantId,
    required String siteId,
  }) async {
    final String path = FirestorePaths.siteDoc(tenantId, siteId);
    debugPrint('[AgroSite] getById path=$path');
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .doc(path)
          .get();
      if (!doc.exists) {
        return null;
      }
      return AgroSite.fromFirestore(
        doc.id,
        tenantId: tenantId,
        data: doc.data() ?? const <String, Object?>{},
      );
    } catch (error) {
      debugPrint(
        '[AgroSite] getById error path=$path error=$error — returning null',
      );
      return null;
    }
  }

  /// Creates a brand new site. Only valid when no document exists yet at
  /// this path — extending an existing (legacy) site must go through
  /// [update] instead, matching firestore.rules (`allow create` requires
  /// the resulting document to contain ONLY the new-schema fields).
  ///
  /// Explicitly checks for an existing document first, for a specific
  /// "Ya existe un site con ese ID." message. This isn't the only thing
  /// standing between a caller and silently overwriting an existing site —
  /// firestore.rules independently rejects it too (a `.set()` against an
  /// existing document is evaluated as an `update`, and `toCreatePayload()`
  /// always sets a fresh `createdAt`, which isn't in the `allow update`
  /// allowlist) — this pre-check exists purely so the failure is a clear,
  /// specific message instead of a generic permission-denied.
  Future<void> create({
    required String tenantId,
    required String siteId,
    required String name,
    String description = '',
    bool enabled = true,
  }) async {
    final String trimmedName = requireNonEmptyField(name, 'AgroSite.name');
    final bool alreadyExists =
        await getById(tenantId: tenantId, siteId: siteId) != null;
    if (alreadyExists) {
      throw StateError('Ya existe un site con ese ID.');
    }
    final String path = FirestorePaths.siteDoc(tenantId, siteId);
    final Map<String, Object?> payload = buildAgroSiteCreatePayload(
      tenantId: tenantId,
      siteId: siteId,
      name: trimmedName,
      description: description,
      enabled: enabled,
    );
    await FirebaseFirestore.instance.doc(path).set(payload);
    invalidateCache(tenantId: tenantId);
    debugPrint('[AgroSite] created path=$path name=$trimmedName');
  }

  /// Updates an existing site (legacy or new-schema). Always merges, so
  /// legacy fields (technicalId/backendUrl/active) are preserved untouched.
  ///
  /// [provisioningStatus] is OPTIONAL and defaults to `null`: when omitted,
  /// the payload simply doesn't include that key, so the merge write leaves
  /// whatever value is already stored on the document untouched. Pass it
  /// explicitly only when you actually intend to change it (e.g. flipping a
  /// site from `ready` to `error`). Bug fix: this used to unconditionally
  /// hardcode `provisioningStatus: pending_backend` on every call, silently
  /// resetting a `ready` site back to pending on a plain name/description
  /// edit — see the regression test `AgroSiteService.update no resetea
  /// provisioningStatus` in test/agro_structural_schema_test.dart.
  Future<void> update({
    required String tenantId,
    required String siteId,
    required String name,
    String description = '',
    bool enabled = true,
    String? provisioningStatus,
  }) async {
    final String trimmedName = requireNonEmptyField(name, 'AgroSite.name');
    final String path = FirestorePaths.siteDoc(tenantId, siteId);
    final Map<String, Object?> payload = buildAgroSiteUpdatePayload(
      name: trimmedName,
      description: description,
      enabled: enabled,
      provisioningStatus: provisioningStatus,
    );
    await FirebaseFirestore.instance
        .doc(path)
        .set(payload, SetOptions(merge: true));
    invalidateCache(tenantId: tenantId);
    debugPrint('[AgroSite] updated path=$path name=$trimmedName');
  }

  /// Explicitly invalidates the cached site list for [tenantId]. Exposed as
  /// a public method (rather than only clearing internally after a write)
  /// so administrative flows that write through a different code path can
  /// still force a fresh read on the next `listByTenant` call.
  void invalidateCache({required String tenantId}) {
    _listCache.remove(tenantId);
  }
}

class _CacheEntry<T> {
  _CacheEntry({required this.value, required this.expiresAt});

  final T value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Builds the Firestore payload for creating a new Site with the current
/// structural schema only.
///
/// Legacy site fields (`technicalId`, `backendUrl`, `active`) are intentionally
/// absent. They are preserved on existing documents by update flows, but new
/// tenants and new Site features must not introduce them.
Map<String, Object?> buildAgroSiteCreatePayload({
  required String tenantId,
  required String siteId,
  required String name,
  String description = '',
  bool enabled = true,
}) {
  return AgroSite(
    id: siteId,
    tenantId: tenantId,
    name: name,
    description: description,
    enabled: enabled,
    provisioningStatus: SiteProvisioningStatus.pendingBackend,
    createdAt: null,
    updatedAt: null,
  ).toCreatePayload();
}

/// Builds a PARTIAL update payload for an existing Site: `name`,
/// `description`, `enabled`, and `updatedAt` always; `provisioningStatus`
/// ONLY when explicitly provided (non-null). This is what makes
/// [AgroSiteService.update] safe to call for a plain name/description edit
/// without silently resetting `provisioningStatus` — the key is simply
/// absent from the map, and since writes use
/// `SetOptions(merge: true)`, an absent key leaves the stored value alone.
///
/// Deliberately does NOT go through `AgroSite(...).toUpdatePayload()` (that
/// instance method always includes `provisioningStatus`, since `AgroSite`'s
/// field is non-nullable — appropriate when you already have a full,
/// freshly-read `AgroSite` to write back, but not for a partial edit where
/// the caller never read the current status).
Map<String, Object?> buildAgroSiteUpdatePayload({
  required String name,
  String description = '',
  bool enabled = true,
  String? provisioningStatus,
}) {
  return <String, Object?>{
    'name': name,
    'description': description,
    'enabled': enabled,
    if (provisioningStatus != null) 'provisioningStatus': provisioningStatus,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
