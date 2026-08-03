import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_sector.dart';
import 'agro_site_service.dart';

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
        '[AgroSector] listByTenant error path=$path error=$error — returning empty list',
      );
      return const <AgroSector>[];
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

  /// Creates a new Sector. `siteId` must reference a Site in this SAME
  /// tenant. Firestore Rules validate that relation with `existsAfter()`,
  /// so atomic provisioning may create the Site in the same transaction.
  /// `name` must be non-empty.
  Future<void> create({
    required String tenantId,
    required String sectorId,
    required String siteId,
    required String name,
    String description = '',
    bool enabled = true,
  }) async {
    final String trimmedSiteId = siteId.trim();
    final String trimmedName = name.trim();
    if (trimmedSiteId.isEmpty) {
      throw StateError('AgroSector.siteId is required');
    }
    if (trimmedName.isEmpty) {
      throw StateError('AgroSector.name is required');
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
    final Map<String, Object?> payload = AgroSector(
      id: sectorId,
      tenantId: tenantId,
      siteId: trimmedSiteId,
      name: trimmedName,
      description: description,
      enabled: enabled,
      createdAt: null,
      updatedAt: null,
    ).toCreatePayload();
    await FirebaseFirestore.instance.doc(path).set(payload);
    _clearCache(tenantId);
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
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError('AgroSector.name is required');
    }
    final String path = FirestorePaths.sectorDoc(tenantId, sectorId);
    final Map<String, Object?> payload = AgroSector(
      id: sectorId,
      tenantId: tenantId,
      siteId: '',
      name: trimmedName,
      description: description,
      enabled: enabled,
      createdAt: null,
      updatedAt: null,
    ).toUpdatePayload();
    await FirebaseFirestore.instance
        .doc(path)
        .set(payload, SetOptions(merge: true));
    _clearCache(tenantId);
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

  void _clearCache(String tenantId) {
    _listCache.removeWhere(
      (key, _) => key.contains('|$tenantId|') || key.endsWith('|$tenantId'),
    );
  }
}

class _CacheEntry<T> {
  _CacheEntry({required this.value, required this.expiresAt});

  final T value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
