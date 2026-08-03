import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_device.dart';
import 'agro_site_service.dart';

/// Read/write access to [AgroDevice] documents at
/// `tenants/{tenantId}/devices/{deviceId}` — a brand new collection,
/// independent of the legacy `sites/{siteId}/plcs/{plcId}` schema.
///
/// No permanent listeners: every read is a one-shot `.get()`, cached in
/// memory for a short TTL. `listBySite` uses a single grouped `where()`
/// query instead of reading each Device document individually.
class AgroDeviceService {
  const AgroDeviceService({this.siteService = const AgroSiteService()});

  final AgroSiteService siteService;

  static const Duration _cacheTtl = Duration(minutes: 5);
  static final Map<String, _CacheEntry<List<AgroDevice>>> _listCache =
      <String, _CacheEntry<List<AgroDevice>>>{};

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
        '[AgroDevice] listByTenant error path=$path error=$error — returning empty list',
      );
      return const <AgroDevice>[];
    }
  }

  /// Lists Devices for a single Site with one grouped query — never reads
  /// documents one by one.
  Future<List<AgroDevice>> listBySite({
    required String tenantId,
    required String siteId,
  }) async {
    final String cacheKey = 'site|$tenantId|$siteId';
    final _CacheEntry<List<AgroDevice>>? cached = _listCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final String path = FirestorePaths.tenantDevicesCollection(tenantId);
    debugPrint('[AgroDevice] listBySite path=$path siteId=$siteId');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(path)
          .where('siteId', isEqualTo: siteId)
          .get();
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
  Future<void> create({
    required String tenantId,
    required String deviceId,
    required String siteId,
    required String name,
    required String type,
    String model = '',
    String description = '',
    bool enabled = true,
  }) async {
    final String trimmedSiteId = siteId.trim();
    final String trimmedName = name.trim();
    final String trimmedType = type.trim();
    if (trimmedSiteId.isEmpty) {
      throw StateError('AgroDevice.siteId is required');
    }
    if (trimmedName.isEmpty) {
      throw StateError('AgroDevice.name is required');
    }
    if (trimmedType.isEmpty) {
      throw StateError('AgroDevice.type is required');
    }
    final bool siteExistsInTenant =
        await siteService.getById(tenantId: tenantId, siteId: trimmedSiteId) !=
        null;
    if (!siteExistsInTenant) {
      throw StateError(
        'AgroDevice.siteId "$trimmedSiteId" does not belong to tenant "$tenantId"',
      );
    }

    final String path = FirestorePaths.deviceDoc(tenantId, deviceId);
    final Map<String, Object?> payload = AgroDevice(
      id: deviceId,
      tenantId: tenantId,
      siteId: trimmedSiteId,
      name: trimmedName,
      type: trimmedType,
      model: model,
      description: description,
      enabled: enabled,
      createdAt: null,
      updatedAt: null,
    ).toCreatePayload();
    await FirebaseFirestore.instance.doc(path).set(payload);
    _clearCache(tenantId);
    debugPrint(
      '[AgroDevice] created path=$path name=$trimmedName type=$trimmedType',
    );
  }

  /// Updates an existing Device. `siteId` cannot be changed here (a Device
  /// does not move between Sites — matches firestore.rules).
  Future<void> update({
    required String tenantId,
    required String deviceId,
    required String name,
    required String type,
    String model = '',
    String description = '',
    bool enabled = true,
  }) async {
    final String trimmedName = name.trim();
    final String trimmedType = type.trim();
    if (trimmedName.isEmpty) {
      throw StateError('AgroDevice.name is required');
    }
    if (trimmedType.isEmpty) {
      throw StateError('AgroDevice.type is required');
    }
    final String path = FirestorePaths.deviceDoc(tenantId, deviceId);
    final Map<String, Object?> payload = AgroDevice(
      id: deviceId,
      tenantId: tenantId,
      siteId: '',
      name: trimmedName,
      type: trimmedType,
      model: model,
      description: description,
      enabled: enabled,
      createdAt: null,
      updatedAt: null,
    ).toUpdatePayload();
    await FirebaseFirestore.instance
        .doc(path)
        .set(payload, SetOptions(merge: true));
    _clearCache(tenantId);
    debugPrint('[AgroDevice] updated path=$path name=$trimmedName');
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
