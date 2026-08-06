import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_sector.dart';
import 'agro_site_service.dart';
import 'structural_id_helpers.dart';

/// Read/write access to [AgroSector] documents at
/// `tenants/{tenantId}/sectors/{sectorId}` — a brand new collection,
/// independent of the legacy `sites/{siteId}/plcs/{plcId}` schema.
///
/// No permanent listeners: every read is a one-shot `.get()`, cached in
/// memory for a short TTL. `listBySite` uses a single grouped `where()`
/// query instead of reading each Sector document individually.
class AgroSectorService {
  const AgroSectorService({this.siteService = const AgroSiteService()});

  final AgroSiteService siteService;

  static const Duration _cacheTtl = Duration(minutes: 5);
  static final Map<String, _CacheEntry<List<AgroSector>>> _listCache =
      <String, _CacheEntry<List<AgroSector>>>{};

  /// Same rethrow-instead-of-swallow reasoning as
  /// `AgroSiteService.listByTenant` — this method has exactly one caller
  /// today (`TenantManagementPage`), never the live dashboard.
  Future<List<AgroSector>> listByTenant(String tenantId) async {
    final String cacheKey = 'tenant|$tenantId';
    final _CacheEntry<List<AgroSector>>? cached = _listCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final String path = FirestorePaths.tenantSectorsCollection(tenantId);
    debugPrint('[AgroSector] listByTenant path=$path');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(path)
          .get();
      final List<AgroSector> sectors = _sortedFromSnapshot(snap, tenantId);
      _listCache[cacheKey] = _CacheEntry<List<AgroSector>>(
        value: sectors,
        expiresAt: DateTime.now().add(_cacheTtl),
      );
      return sectors;
    } catch (error) {
      debugPrint(
        '[AgroSector] listByTenant error path=$path error=$error — rethrowing for the admin UI to surface',
      );
      rethrow;
    }
  }

  /// Lists Sectors for a single Site with one grouped query — never reads
  /// documents one by one.
  Future<List<AgroSector>> listBySite({
    required String tenantId,
    required String siteId,
  }) async {
    final String cacheKey = 'site|$tenantId|$siteId';
    final _CacheEntry<List<AgroSector>>? cached = _listCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final String path = FirestorePaths.tenantSectorsCollection(tenantId);
    debugPrint('[AgroSector] listBySite path=$path siteId=$siteId');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(path)
          .where('siteId', isEqualTo: siteId)
          .get();
      final List<AgroSector> sectors = _sortedFromSnapshot(snap, tenantId);
      _listCache[cacheKey] = _CacheEntry<List<AgroSector>>(
        value: sectors,
        expiresAt: DateTime.now().add(_cacheTtl),
      );
      return sectors;
    } catch (error) {
      debugPrint(
        '[AgroSector] listBySite error path=$path siteId=$siteId error=$error — returning empty list',
      );
      return const <AgroSector>[];
    }
  }

  Future<AgroSector?> getById({
    required String tenantId,
    required String sectorId,
  }) async {
    final String path = FirestorePaths.sectorDoc(tenantId, sectorId);
    debugPrint('[AgroSector] getById path=$path');
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .doc(path)
          .get();
      if (!doc.exists) {
        return null;
      }
      return AgroSector.fromFirestore(
        doc.id,
        tenantId: tenantId,
        data: doc.data() ?? const <String, Object?>{},
      );
    } catch (error) {
      debugPrint(
        '[AgroSector] getById error path=$path error=$error — returning null',
      );
      return null;
    }
  }

  /// Creates a new Sector — the "addSectorToSite" operation for future
  /// provisioning flows. `siteId` must reference a Site in this SAME
  /// tenant. Firestore Rules validate that relation with `existsAfter()`,
  /// so atomic provisioning may create the Site in the same transaction.
  /// `name` must be non-empty. Rejects a duplicate `sectorId` with a
  /// specific message (see `AgroSiteService.create`'s doc comment for why
  /// this pre-check exists alongside the rules-level protection).
  Future<void> create({
    required String tenantId,
    required String sectorId,
    required String siteId,
    required String name,
    String description = '',
    bool enabled = true,
  }) async {
    final String trimmedSiteId = requireNonEmptyField(
      siteId,
      'AgroSector.siteId',
    );
    final String trimmedName = requireNonEmptyField(name, 'AgroSector.name');
    final bool alreadyExists =
        await getById(tenantId: tenantId, sectorId: sectorId) != null;
    if (alreadyExists) {
      throw StateError('Ya existe un sector con ese ID.');
    }
    final bool siteExistsInTenant =
        await siteService.getById(tenantId: tenantId, siteId: trimmedSiteId) !=
        null;
    if (!siteExistsInTenant) {
      throw StateError(
        'AgroSector.siteId "$trimmedSiteId" does not belong to tenant "$tenantId"',
      );
    }

    final String path = FirestorePaths.sectorDoc(tenantId, sectorId);
    final Map<String, Object?> payload = buildAgroSectorCreatePayload(
      tenantId: tenantId,
      sectorId: sectorId,
      siteId: trimmedSiteId,
      name: trimmedName,
      description: description,
      enabled: enabled,
    );
    await FirebaseFirestore.instance.doc(path).set(payload);
    invalidateCache(tenantId: tenantId, siteId: trimmedSiteId);
    debugPrint('[AgroSector] created path=$path name=$trimmedName');
  }

  /// Updates an existing Sector. `siteId` cannot be changed here (a Sector
  /// does not move between Sites — matches firestore.rules).
  Future<void> update({
    required String tenantId,
    required String sectorId,
    required String name,
    String description = '',
    bool enabled = true,
  }) async {
    final String trimmedName = requireNonEmptyField(name, 'AgroSector.name');
    final String path = FirestorePaths.sectorDoc(tenantId, sectorId);
    final Map<String, Object?> payload = buildAgroSectorUpdatePayload(
      name: trimmedName,
      description: description,
      enabled: enabled,
    );
    await FirebaseFirestore.instance
        .doc(path)
        .set(payload, SetOptions(merge: true));
    invalidateCache(tenantId: tenantId);
    debugPrint('[AgroSector] updated path=$path name=$trimmedName');
  }

  List<AgroSector> _sortedFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
    String tenantId,
  ) {
    return snap.docs
        .map(
          (doc) => AgroSector.fromFirestore(
            doc.id,
            tenantId: tenantId,
            data: doc.data(),
          ),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Explicitly invalidates cached Sector lists for [tenantId] — and, when
  /// [siteId] is given, narrows to just that site's cache entry (still also
  /// clearing the tenant-wide list, since it would otherwise go stale too).
  /// Public so administrative writes going through a different code path
  /// (or a different `AgroSectorService` instance) can still force a fresh
  /// read on the next `listByTenant`/`listBySite` call.
  void invalidateCache({required String tenantId, String? siteId}) {
    if (siteId == null) {
      _listCache.removeWhere(
        (key, _) => key.contains('|$tenantId|') || key.endsWith('|$tenantId'),
      );
      return;
    }
    _listCache.remove('tenant|$tenantId');
    _listCache.remove('site|$tenantId|$siteId');
  }
}

class _CacheEntry<T> {
  _CacheEntry({required this.value, required this.expiresAt});

  final T value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Builds the Firestore payload for creating a new Sector.
Map<String, Object?> buildAgroSectorCreatePayload({
  required String tenantId,
  required String sectorId,
  required String siteId,
  required String name,
  String description = '',
  bool enabled = true,
}) {
  return AgroSector(
    id: sectorId,
    tenantId: tenantId,
    siteId: siteId,
    name: name,
    description: description,
    enabled: enabled,
    createdAt: null,
    updatedAt: null,
  ).toCreatePayload();
}

/// Builds the Firestore payload for updating an existing Sector. `siteId`
/// is intentionally not a parameter here — it's immutable after creation
/// (matches firestore.rules) and `toUpdatePayload()` never includes it.
Map<String, Object?> buildAgroSectorUpdatePayload({
  required String name,
  String description = '',
  bool enabled = true,
}) {
  return AgroSector(
    id: '',
    tenantId: '',
    siteId: '',
    name: name,
    description: description,
    enabled: enabled,
    createdAt: null,
    updatedAt: null,
  ).toUpdatePayload();
}
