import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_device_room.dart';

/// Display order for a device's Rooms: ascending [AgroDeviceRoom.sortOrder],
/// then [AgroDeviceRoom.name] as a stable tiebreaker. Mirrors
/// `compareAgroDevicesForDisplay` in `agro_device_service.dart`.
int compareAgroDeviceRoomsForDisplay(AgroDeviceRoom a, AgroDeviceRoom b) {
  final int bySortOrder = a.sortOrder.compareTo(b.sortOrder);
  return bySortOrder != 0 ? bySortOrder : a.name.compareTo(b.name);
}

/// Read/write access to [AgroDeviceRoom] documents at
/// `tenants/{tenantId}/devices/{deviceId}/rooms/{roomId}`.
///
/// No permanent listeners: every read is a one-shot `.get()`, cached in
/// memory for a short TTL. A Device with zero Room documents is a valid,
/// common case (most Devices still expose exactly one implicit Room) — it
/// is the caller's responsibility to fall back accordingly, this service
/// simply returns an empty list.
class AgroDeviceRoomService {
  const AgroDeviceRoomService();

  static const Duration _cacheTtl = Duration(minutes: 5);
  static final Map<String, _CacheEntry<List<AgroDeviceRoom>>> _listCache =
      <String, _CacheEntry<List<AgroDeviceRoom>>>{};

  /// Lists the *enabled* Rooms for a single Device. Disabled Rooms never
  /// reach the caller, matching [AgroDeviceService.listBySite]'s semantics.
  Future<List<AgroDeviceRoom>> listByDevice({
    required String tenantId,
    required String deviceId,
  }) async {
    final String cacheKey = 'device|$tenantId|$deviceId';
    final _CacheEntry<List<AgroDeviceRoom>>? cached = _listCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final String path = FirestorePaths.deviceRoomsCollection(
      tenantId,
      deviceId,
    );
    debugPrint('[AgroDeviceRoom] listByDevice path=$path');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(path)
          .where('enabled', isEqualTo: true)
          .get();
      final List<AgroDeviceRoom> rooms = snap.docs
          .map(
            (doc) => AgroDeviceRoom.fromFirestore(
              doc.id,
              tenantId: tenantId,
              deviceId: deviceId,
              data: doc.data(),
            ),
          )
          .toList()
        ..sort(compareAgroDeviceRoomsForDisplay);
      _listCache[cacheKey] = _CacheEntry<List<AgroDeviceRoom>>(
        value: rooms,
        expiresAt: DateTime.now().add(_cacheTtl),
      );
      return rooms;
    } catch (error) {
      debugPrint(
        '[AgroDeviceRoom] listByDevice error path=$path error=$error — returning empty list',
      );
      return const <AgroDeviceRoom>[];
    }
  }

  /// Lists Rooms for several Devices at once, keyed by `deviceId`. Devices
  /// with zero Room documents are present in the result with an empty list
  /// — that emptiness is the signal callers use to fall back to the
  /// implicit single-Room-per-Device behavior.
  Future<Map<String, List<AgroDeviceRoom>>> listForDevices({
    required String tenantId,
    required List<String> deviceIds,
  }) async {
    final List<List<AgroDeviceRoom>> results = await Future.wait(
      deviceIds.map(
        (deviceId) => listByDevice(tenantId: tenantId, deviceId: deviceId),
      ),
    );
    return <String, List<AgroDeviceRoom>>{
      for (int i = 0; i < deviceIds.length; i++) deviceIds[i]: results[i],
    };
  }

  /// Creates a new Room under an existing Device. `name` must be non-empty.
  Future<void> create({
    required String tenantId,
    required String deviceId,
    required String roomId,
    required String siteId,
    required String name,
    bool enabled = true,
    int sortOrder = 0,
    String? snapshotUnitKey,
  }) async {
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError('AgroDeviceRoom.name is required');
    }
    final String path = FirestorePaths.deviceRoomDoc(
      tenantId,
      deviceId,
      roomId,
    );
    final Map<String, Object?> payload = AgroDeviceRoom(
      id: roomId,
      tenantId: tenantId,
      deviceId: deviceId,
      siteId: siteId,
      name: trimmedName,
      enabled: enabled,
      createdAt: null,
      updatedAt: null,
      sortOrder: sortOrder,
      snapshotUnitKey: snapshotUnitKey,
    ).toCreatePayload();
    await FirebaseFirestore.instance.doc(path).set(payload);
    _clearCache(tenantId, deviceId);
    debugPrint('[AgroDeviceRoom] created path=$path name=$trimmedName');
  }

  /// Updates an existing Room. `siteId` cannot be changed here (matches
  /// firestore.rules).
  Future<void> update({
    required String tenantId,
    required String deviceId,
    required String roomId,
    required String name,
    bool enabled = true,
    int sortOrder = 0,
    String? snapshotUnitKey,
  }) async {
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError('AgroDeviceRoom.name is required');
    }
    final String path = FirestorePaths.deviceRoomDoc(
      tenantId,
      deviceId,
      roomId,
    );
    final Map<String, Object?> payload = AgroDeviceRoom(
      id: roomId,
      tenantId: tenantId,
      deviceId: deviceId,
      siteId: '',
      name: trimmedName,
      enabled: enabled,
      createdAt: null,
      updatedAt: null,
      sortOrder: sortOrder,
      snapshotUnitKey: snapshotUnitKey,
    ).toUpdatePayload();
    await FirebaseFirestore.instance
        .doc(path)
        .set(payload, SetOptions(merge: true));
    _clearCache(tenantId, deviceId);
    debugPrint('[AgroDeviceRoom] updated path=$path name=$trimmedName');
  }

  void _clearCache(String tenantId, String deviceId) {
    _listCache.remove('device|$tenantId|$deviceId');
  }
}

class _CacheEntry<T> {
  _CacheEntry({required this.value, required this.expiresAt});

  final T value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
