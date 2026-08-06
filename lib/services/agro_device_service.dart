import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_device.dart';
import 'agro_sector_service.dart';
import 'agro_site_service.dart';
import 'snapshot_unit_key_service.dart';
import 'structural_id_helpers.dart';

/// Display order for a site's Devices: ascending [AgroDevice.sortOrder],
/// then [AgroDevice.name] as a stable tiebreaker for devices left at the
/// same (e.g. default) sortOrder. Pulled out as a standalone function so it
/// can be unit-tested without a live/faked Firestore.
int compareAgroDevicesForDisplay(AgroDevice a, AgroDevice b) {
  final int bySortOrder = a.sortOrder.compareTo(b.sortOrder);
  return bySortOrder != 0 ? bySortOrder : a.name.compareTo(b.name);
}

/// Read/write access to [AgroDevice] documents at
/// `tenants/{tenantId}/devices/{deviceId}` — a brand new collection,
/// independent of the legacy `sites/{siteId}/plcs/{plcId}` schema.
///
/// No permanent listeners: every read is a one-shot `.get()`, cached in
/// memory for a short TTL. `listBySite` uses a single grouped `where()`
/// query instead of reading each Device document individually.
class AgroDeviceService {
  const AgroDeviceService({
    this.siteService = const AgroSiteService(),
    this.sectorService = const AgroSectorService(),
  });

  final AgroSiteService siteService;
  final AgroSectorService sectorService;

  static const Duration _cacheTtl = Duration(minutes: 5);
  static final Map<String, _CacheEntry<List<AgroDevice>>> _listCache =
      <String, _CacheEntry<List<AgroDevice>>>{};

  /// Same rethrow-instead-of-swallow reasoning as
  /// `AgroSiteService.listByTenant` — this method has exactly one caller
  /// today (`TenantManagementPage`), never the live dashboard (which only
  /// ever calls `listBySite`, untouched, still swallows).
  Future<List<AgroDevice>> listByTenant(String tenantId) async {
    final String cacheKey = 'tenant|$tenantId';
    final _CacheEntry<List<AgroDevice>>? cached = _listCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final String path = FirestorePaths.tenantDevicesCollection(tenantId);
    debugPrint('[AgroDevice] listByTenant path=$path');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(path)
          .get();
      final List<AgroDevice> devices = _sortedFromSnapshot(snap, tenantId);
      _listCache[cacheKey] = _CacheEntry<List<AgroDevice>>(
        value: devices,
        expiresAt: DateTime.now().add(_cacheTtl),
      );
      return devices;
    } catch (error) {
      debugPrint(
        '[AgroDevice] listByTenant error path=$path error=$error — rethrowing for the admin UI to surface',
      );
      rethrow;
    }
  }

  /// Lists the *enabled* Devices for a single Site with one grouped query —
  /// never reads documents one by one. Disabled Devices never reach the
  /// caller; they don't exist for display purposes.
  ///
  /// Set [includeDisabled] to `true` for administrative listings that need
  /// to see (and re-enable) disabled Devices too — the dashboard's own call
  /// sites must keep passing the default (`false`) so their behavior stays
  /// unchanged.
  Future<List<AgroDevice>> listBySite({
    required String tenantId,
    required String siteId,
    bool includeDisabled = false,
  }) async {
    final String cacheKey = includeDisabled
        ? 'site|$tenantId|$siteId|all'
        : 'site|$tenantId|$siteId';
    final _CacheEntry<List<AgroDevice>>? cached = _listCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final String path = FirestorePaths.tenantDevicesCollection(tenantId);
    debugPrint(
      '[AgroDevice] listBySite path=$path siteId=$siteId includeDisabled=$includeDisabled',
    );
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection(path)
          .where('siteId', isEqualTo: siteId);
      if (!includeDisabled) {
        query = query.where('enabled', isEqualTo: true);
      }
      final QuerySnapshot<Map<String, dynamic>> snap = await query.get();
      final List<AgroDevice> devices = _sortedFromSnapshot(snap, tenantId);
      _listCache[cacheKey] = _CacheEntry<List<AgroDevice>>(
        value: devices,
        expiresAt: DateTime.now().add(_cacheTtl),
      );
      return devices;
    } catch (error) {
      debugPrint(
        '[AgroDevice] listBySite error path=$path siteId=$siteId error=$error — returning empty list',
      );
      return const <AgroDevice>[];
    }
  }

  Future<AgroDevice?> getById({
    required String tenantId,
    required String deviceId,
  }) async {
    final String path = FirestorePaths.deviceDoc(tenantId, deviceId);
    debugPrint('[AgroDevice] getById path=$path');
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .doc(path)
          .get();
      if (!doc.exists) {
        return null;
      }
      return AgroDevice.fromFirestore(
        doc.id,
        tenantId: tenantId,
        data: doc.data() ?? const <String, Object?>{},
      );
    } catch (error) {
      debugPrint(
        '[AgroDevice] getById error path=$path error=$error — returning null',
      );
      return null;
    }
  }

  /// Creates a new Device. `siteId` must reference a Site in this SAME
  /// tenant. Firestore Rules validate that relation with `existsAfter()`,
  /// so atomic provisioning may create the Site in the same transaction.
  /// `name` and `type` must be non-empty.
  /// `type` is a free-form normalized string (see [AgroDeviceType]) — not
  /// a closed enum, so new device types never require a code change here.
  /// Creates a new Device — the "addDeviceToSite" operation for future
  /// provisioning flows.
  Future<void> create({
    required String tenantId,
    required String deviceId,
    required String siteId,
    required String name,
    required String type,
    String model = '',
    String description = '',
    bool enabled = true,
    int sortOrder = 0,
    String? snapshotUnitKey,
    List<String> sectorIds = const <String>[],
  }) async {
    final String trimmedSiteId = requireNonEmptyField(
      siteId,
      'AgroDevice.siteId',
    );
    final String trimmedName = requireNonEmptyField(name, 'AgroDevice.name');
    final String trimmedType = requireNonEmptyField(type, 'AgroDevice.type');
    final bool alreadyExists =
        await getById(tenantId: tenantId, deviceId: deviceId) != null;
    if (alreadyExists) {
      throw StateError('Ya existe un device con ese ID.');
    }
    final bool siteExistsInTenant =
        await siteService.getById(tenantId: tenantId, siteId: trimmedSiteId) !=
        null;
    if (!siteExistsInTenant) {
      throw StateError(
        'AgroDevice.siteId "$trimmedSiteId" does not belong to tenant "$tenantId"',
      );
    }
    await _validateSectorIds(
      tenantId: tenantId,
      siteId: trimmedSiteId,
      sectorIds: sectorIds,
    );
    // Site-wide, not just within this Device — see SnapshotUnitKeyValidator's
    // doc comment for why this isn't an injected field.
    await const SnapshotUnitKeyValidator().ensureUnique(
      tenantId: tenantId,
      siteId: trimmedSiteId,
      candidateKey: snapshotUnitKey,
    );

    final String path = FirestorePaths.deviceDoc(tenantId, deviceId);
    final Map<String, Object?> payload = buildAgroDeviceCreatePayload(
      tenantId: tenantId,
      deviceId: deviceId,
      siteId: trimmedSiteId,
      name: trimmedName,
      type: trimmedType,
      model: model,
      description: description,
      enabled: enabled,
      sortOrder: sortOrder,
      snapshotUnitKey: snapshotUnitKey,
      sectorIds: sectorIds,
    );
    await FirebaseFirestore.instance.doc(path).set(payload);
    invalidateCache(tenantId: tenantId, siteId: trimmedSiteId);
    debugPrint(
      '[AgroDevice] created path=$path name=$trimmedName type=$trimmedType',
    );
  }

  /// Updates an existing Device. `siteId` cannot be changed here (a Device
  /// does not move between Sites — matches firestore.rules). `type` is
  /// intentionally still accepted (the field itself is mutable at the rules
  /// layer), but the admin UI treats it as read-only after creation — see
  /// the Etapa 4 report §13 for why changing it isn't exposed there.
  Future<void> update({
    required String tenantId,
    required String deviceId,
    required String siteId,
    required String name,
    required String type,
    String model = '',
    String description = '',
    bool enabled = true,
    int sortOrder = 0,
    String? snapshotUnitKey,
    List<String> sectorIds = const <String>[],
  }) async {
    final String trimmedName = requireNonEmptyField(name, 'AgroDevice.name');
    final String trimmedType = requireNonEmptyField(type, 'AgroDevice.type');
    await _validateSectorIds(
      tenantId: tenantId,
      siteId: siteId,
      sectorIds: sectorIds,
    );
    await const SnapshotUnitKeyValidator().ensureUnique(
      tenantId: tenantId,
      siteId: siteId,
      candidateKey: snapshotUnitKey,
      excludeDeviceId: deviceId,
    );
    final String path = FirestorePaths.deviceDoc(tenantId, deviceId);
    final Map<String, Object?> payload = buildAgroDeviceUpdatePayload(
      name: trimmedName,
      type: trimmedType,
      model: model,
      description: description,
      enabled: enabled,
      sortOrder: sortOrder,
      snapshotUnitKey: snapshotUnitKey,
      sectorIds: sectorIds,
    );
    await FirebaseFirestore.instance
        .doc(path)
        .set(payload, SetOptions(merge: true));
    invalidateCache(tenantId: tenantId);
    debugPrint('[AgroDevice] updated path=$path name=$trimmedName');
  }

  /// Every Sector a Device references must belong to the SAME tenant AND
  /// SAME site as the Device itself (`deviceAndSectorBelongToSameSite` in
  /// `agro_site_hierarchy_service.dart`). Reads are one `getById` per
  /// sectorId — acceptable here because this only runs on a write, never on
  /// the list/read paths the dashboard depends on.
  Future<void> _validateSectorIds({
    required String tenantId,
    required String siteId,
    required List<String> sectorIds,
  }) async {
    for (final String sectorId in sectorIds) {
      final sector = await sectorService.getById(
        tenantId: tenantId,
        sectorId: sectorId,
      );
      if (sector == null || sector.siteId != siteId) {
        throw StateError('El sector "$sectorId" no pertenece a este site.');
      }
    }
  }

  List<AgroDevice> _sortedFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
    String tenantId,
  ) {
    return snap.docs
        .map(
          (doc) => AgroDevice.fromFirestore(
            doc.id,
            tenantId: tenantId,
            data: doc.data(),
          ),
        )
        .toList()
      ..sort(compareAgroDevicesForDisplay);
  }

  /// Explicitly invalidates cached Device lists for [tenantId] — and, when
  /// [siteId] is given, narrows to that site's `enabled`-only AND `all`
  /// cache entries (both variants created by [listBySite]'s
  /// `includeDisabled` flag) PLUS the tenant-wide `listByTenant` entry
  /// (also stale after a single-site write — matches
  /// [AgroSectorService.invalidateCache]'s narrow-case behavior). Public so
  /// administrative writes going through a different code path/instance can
  /// still force a fresh read.
  void invalidateCache({required String tenantId, String? siteId}) {
    if (siteId == null) {
      _listCache.removeWhere(
        (key, _) => key.contains('|$tenantId|') || key.endsWith('|$tenantId'),
      );
      return;
    }
    _listCache.remove('tenant|$tenantId');
    _listCache.remove('site|$tenantId|$siteId');
    _listCache.remove('site|$tenantId|$siteId|all');
  }
}

class _CacheEntry<T> {
  _CacheEntry({required this.value, required this.expiresAt});

  final T value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Builds the Firestore payload for creating a new Device.
Map<String, Object?> buildAgroDeviceCreatePayload({
  required String tenantId,
  required String deviceId,
  required String siteId,
  required String name,
  required String type,
  String model = '',
  String description = '',
  bool enabled = true,
  int sortOrder = 0,
  String? snapshotUnitKey,
  List<String> sectorIds = const <String>[],
}) {
  return AgroDevice(
    id: deviceId,
    tenantId: tenantId,
    siteId: siteId,
    name: name,
    type: type,
    model: model,
    description: description,
    enabled: enabled,
    createdAt: null,
    updatedAt: null,
    sortOrder: sortOrder,
    snapshotUnitKey: snapshotUnitKey,
    sectorIds: sectorIds,
  ).toCreatePayload();
}

/// Builds the Firestore payload for updating an existing Device. `siteId`
/// is intentionally not a parameter — immutable after creation.
Map<String, Object?> buildAgroDeviceUpdatePayload({
  required String name,
  required String type,
  String model = '',
  String description = '',
  bool enabled = true,
  int sortOrder = 0,
  String? snapshotUnitKey,
  List<String> sectorIds = const <String>[],
}) {
  return AgroDevice(
    id: '',
    tenantId: '',
    siteId: '',
    name: name,
    type: type,
    model: model,
    description: description,
    enabled: enabled,
    createdAt: null,
    updatedAt: null,
    sortOrder: sortOrder,
    snapshotUnitKey: snapshotUnitKey,
    sectorIds: sectorIds,
  ).toUpdatePayload();
}
