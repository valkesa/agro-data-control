import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_site.dart';

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
        '[AgroSite] listByTenant error path=$path error=$error — returning empty list',
      );
      return const <AgroSite>[];
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
  Future<void> create({
    required String tenantId,
    required String siteId,
    required String name,
    String description = '',
    bool enabled = true,
  }) async {
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError('AgroSite.name is required');
    }
    final String path = FirestorePaths.siteDoc(tenantId, siteId);
    final Map<String, Object?> payload = AgroSite(
      id: siteId,
      tenantId: tenantId,
      name: trimmedName,
      description: description,
      enabled: enabled,
      provisioningStatus: SiteProvisioningStatus.pendingBackend,
      createdAt: null,
      updatedAt: null,
    ).toCreatePayload();
    await FirebaseFirestore.instance.doc(path).set(payload);
    _listCache.remove(tenantId);
    debugPrint('[AgroSite] created path=$path name=$trimmedName');
  }

  /// Updates an existing site (legacy or new-schema). Always merges, so
  /// legacy fields (technicalId/backendUrl/active) are preserved untouched.
  /// legacy fields are intentionally never part of this payload — updates to
  /// the new schema must never touch them.
  Future<void> update({
    required String tenantId,
    required String siteId,
    required String name,
    String description = '',
    bool enabled = true,
  }) async {
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError('AgroSite.name is required');
    }
    final String path = FirestorePaths.siteDoc(tenantId, siteId);
    final Map<String, Object?> payload = AgroSite(
      id: siteId,
      tenantId: tenantId,
      name: trimmedName,
      description: description,
      enabled: enabled,
      provisioningStatus: SiteProvisioningStatus.pendingBackend,
      createdAt: null,
      updatedAt: null,
    ).toUpdatePayload();
    await FirebaseFirestore.instance
        .doc(path)
        .set(payload, SetOptions(merge: true));
    _listCache.remove(tenantId);
    debugPrint('[AgroSite] updated path=$path name=$trimmedName');
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
