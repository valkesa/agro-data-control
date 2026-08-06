import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_device_room.dart';
import 'agro_device_service.dart';
import 'snapshot_unit_key_service.dart';
import 'structural_id_helpers.dart';

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
  const AgroDeviceRoomService({this.deviceService = const AgroDeviceService()});

  final AgroDeviceService deviceService;

  static const Duration _cacheTtl = Duration(minutes: 5);
  static final Map<String, _CacheEntry<List<AgroDeviceRoom>>> _listCache =
      <String, _CacheEntry<List<AgroDeviceRoom>>>{};

  /// Lists the *enabled* Rooms for a single Device. Disabled Rooms never
  /// reach the caller, matching [AgroDeviceService.listBySite]'s semantics.
  ///
  /// Set [includeDisabled] to `true` for administrative listings that need
  /// to see (and re-enable) disabled Rooms too.
  Future<List<AgroDeviceRoom>> listByDevice({
    required String tenantId,
    required String deviceId,
    bool includeDisabled = false,
  }) async {
    final String cacheKey = includeDisabled
        ? 'device|$tenantId|$deviceId|all'
        : 'device|$tenantId|$deviceId';
    final _CacheEntry<List<AgroDeviceRoom>>? cached = _listCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final String path = FirestorePaths.deviceRoomsCollection(
      tenantId,
      deviceId,
    );
    debugPrint(
      '[AgroDeviceRoom] listByDevice path=$path includeDisabled=$includeDisabled',
    );
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
        path,
      );
      if (!includeDisabled) {
        query = query.where('enabled', isEqualTo: true);
      }
      final QuerySnapshot<Map<String, dynamic>> snap = await query.get();
      final List<AgroDeviceRoom> rooms =
          snap.docs
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
    bool includeDisabled = false,
  }) async {
    final List<List<AgroDeviceRoom>> results = await Future.wait(
      deviceIds.map(
        (deviceId) => listByDevice(
          tenantId: tenantId,
          deviceId: deviceId,
          includeDisabled: includeDisabled,
        ),
      ),
    );
    return <String, List<AgroDeviceRoom>>{
      for (int i = 0; i < deviceIds.length; i++) deviceIds[i]: results[i],
    };
  }

  /// Creates a new Room under an existing Device — the "addRoomToDevice"
  /// operation for future provisioning flows. `name` must be non-empty, and
  /// [deviceId] must reference a Device that actually exists in this
  /// tenant (mirrors the site-existence check already done by
  /// [AgroSectorService.create]/[AgroDeviceService.create] — previously
  /// missing here, relying purely on firestore.rules' `existsAfter()`).
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
    final String trimmedName = requireNonEmptyField(
      name,
      'AgroDeviceRoom.name',
    );
    final bool deviceExistsInTenant =
        await deviceService.getById(tenantId: tenantId, deviceId: deviceId) !=
        null;
    if (!deviceExistsInTenant) {
      throw StateError(
        'AgroDeviceRoom.deviceId "$deviceId" does not belong to tenant "$tenantId"',
      );
    }
    // Site-wide, not just within this Device — see SnapshotUnitKeyValidator's
    // doc comment for why this isn't an injected field.
    await const SnapshotUnitKeyValidator().ensureUnique(
      tenantId: tenantId,
      siteId: siteId,
      candidateKey: snapshotUnitKey,
    );

    final String path = FirestorePaths.deviceRoomDoc(
      tenantId,
      deviceId,
      roomId,
    );
    final Map<String, Object?> payload = buildAgroDeviceRoomCreatePayload(
      tenantId: tenantId,
      deviceId: deviceId,
      roomId: roomId,
      siteId: siteId,
      name: trimmedName,
      enabled: enabled,
      sortOrder: sortOrder,
      snapshotUnitKey: snapshotUnitKey,
    );
    await FirebaseFirestore.instance.doc(path).set(payload);
    invalidateCache(tenantId: tenantId, deviceId: deviceId);
    debugPrint('[AgroDeviceRoom] created path=$path name=$trimmedName');
  }

  /// Updates an existing Room. [siteId] is NOT written (immutable, matches
  /// firestore.rules) — it's only used here to scope the site-wide
  /// snapshotUnitKey uniqueness check to the right Site.
  Future<void> update({
    required String tenantId,
    required String deviceId,
    required String roomId,
    required String siteId,
    required String name,
    bool enabled = true,
    int sortOrder = 0,
    String? snapshotUnitKey,
  }) async {
    final String trimmedName = requireNonEmptyField(
      name,
      'AgroDeviceRoom.name',
    );
    await const SnapshotUnitKeyValidator().ensureUnique(
      tenantId: tenantId,
      siteId: siteId,
      candidateKey: snapshotUnitKey,
      excludeDeviceId: deviceId,
      excludeRoomId: roomId,
    );
    final String path = FirestorePaths.deviceRoomDoc(
      tenantId,
      deviceId,
      roomId,
    );
    final Map<String, Object?> payload = buildAgroDeviceRoomUpdatePayload(
      name: trimmedName,
      enabled: enabled,
      sortOrder: sortOrder,
      snapshotUnitKey: snapshotUnitKey,
    );
    await FirebaseFirestore.instance
        .doc(path)
        .set(payload, SetOptions(merge: true));
    invalidateCache(tenantId: tenantId, deviceId: deviceId);
    debugPrint('[AgroDeviceRoom] updated path=$path name=$trimmedName');
  }

  /// Explicitly invalidates cached Room lists. [deviceId] narrows to just
  /// that device's `enabled`-only AND `all` cache entries; omit it to clear
  /// every Room cache entry under [tenantId] (e.g. after a bulk change).
  /// Public so administrative writes going through a different code
  /// path/instance can still force a fresh read.
  void invalidateCache({required String tenantId, String? deviceId}) {
    if (deviceId == null) {
      _listCache.removeWhere((key, _) => key.contains('|$tenantId|'));
      return;
    }
    _listCache.remove('device|$tenantId|$deviceId');
    _listCache.remove('device|$tenantId|$deviceId|all');
  }
}

class _CacheEntry<T> {
  _CacheEntry({required this.value, required this.expiresAt});

  final T value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Builds the Firestore payload for creating a new Room.
Map<String, Object?> buildAgroDeviceRoomCreatePayload({
  required String tenantId,
  required String deviceId,
  required String roomId,
  required String siteId,
  required String name,
  bool enabled = true,
  int sortOrder = 0,
  String? snapshotUnitKey,
}) {
  return AgroDeviceRoom(
    id: roomId,
    tenantId: tenantId,
    deviceId: deviceId,
    siteId: siteId,
    name: name,
    enabled: enabled,
    createdAt: null,
    updatedAt: null,
    sortOrder: sortOrder,
    snapshotUnitKey: snapshotUnitKey,
  ).toCreatePayload();
}

/// Builds the Firestore payload for updating an existing Room. `siteId` is
/// intentionally not a parameter — immutable after creation.
Map<String, Object?> buildAgroDeviceRoomUpdatePayload({
  required String name,
  bool enabled = true,
  int sortOrder = 0,
  String? snapshotUnitKey,
}) {
  return AgroDeviceRoom(
    id: '',
    tenantId: '',
    deviceId: '',
    siteId: '',
    name: name,
    enabled: enabled,
    createdAt: null,
    updatedAt: null,
    sortOrder: sortOrder,
    snapshotUnitKey: snapshotUnitKey,
  ).toUpdatePayload();
}
