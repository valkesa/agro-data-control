import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import 'agro_device_room_service.dart';
import 'agro_device_service.dart';
import 'agro_sector_service.dart';
import 'snapshot_unit_key_service.dart';
import 'structural_id_helpers.dart';

/// One Room to create alongside a new Device, as drafted by the "Agregar
/// device" form before anything is written. Plain data holder — no
/// Firestore access.
class AgroDeviceRoomDraft {
  const AgroDeviceRoomDraft({
    required this.id,
    required this.name,
    this.enabled = true,
    this.sortOrder = 0,
    this.snapshotUnitKey,
  });

  final String id;
  final String name;
  final bool enabled;
  final int sortOrder;
  final String? snapshotUnitKey;
}

/// Orchestrates the one operation that spans both [AgroDeviceService] and
/// [AgroDeviceRoomService]: creating a multi-Room Device and all of its
/// Rooms as a single atomic write. Kept as its own service — rather than a
/// method on either of those two — to avoid a circular dependency
/// (`AgroDeviceRoomService` already depends on `AgroDeviceService`).
///
/// Mirrors `UserManagementService.createTenant`'s existing pattern of
/// orchestrating several entity services around one atomic Firestore
/// write, reusing each entity's own `build*Payload` functions instead of
/// duplicating payload construction.
class AgroDeviceProvisioningService {
  const AgroDeviceProvisioningService({
    this.deviceService = const AgroDeviceService(),
    this.roomService = const AgroDeviceRoomService(),
    this.sectorService = const AgroSectorService(),
    this.snapshotUnitKeyValidator = const SnapshotUnitKeyValidator(),
  });

  final AgroDeviceService deviceService;
  final AgroDeviceRoomService roomService;
  final AgroSectorService sectorService;
  final SnapshotUnitKeyValidator snapshotUnitKeyValidator;

  /// Creates a Device and, when [rooms] is non-empty, every one of its
  /// Rooms in a single Firestore batch — if any part fails, nothing is
  /// written (no partial device, no partial rooms).
  ///
  /// [rooms] may be empty: that's the "single-room" device type, which
  /// relies on the existing implicit-Room fallback in
  /// `DeviceDashboardEntry.listFrom` and never gets Room documents.
  ///
  /// Validation order: site (must exist in this tenant) → sectors (must
  /// exist in this tenant AND belong to the same site) → device ID (must
  /// not already exist) → room IDs (each non-empty, no duplicates within
  /// this request). A room-by-room existence check against Firestore is
  /// deliberately skipped: Rooms live under `devices/{deviceId}/rooms`, so
  /// if the device doesn't exist yet (just verified), no room under it can
  /// exist either through any normal write path this app exposes.
  Future<void> createDeviceWithRooms({
    required String tenantId,
    required String siteId,
    required String deviceId,
    required String name,
    required String type,
    String model = '',
    String description = '',
    bool enabled = true,
    int sortOrder = 0,
    String? snapshotUnitKey,
    List<String> sectorIds = const <String>[],
    List<AgroDeviceRoomDraft> rooms = const <AgroDeviceRoomDraft>[],
  }) async {
    final String trimmedSiteId = requireNonEmptyField(
      siteId,
      'AgroDevice.siteId',
    );
    final String trimmedName = requireNonEmptyField(name, 'AgroDevice.name');
    final String trimmedType = requireNonEmptyField(type, 'AgroDevice.type');

    final Set<String> seenRoomIds = <String>{};
    final Set<String> seenSnapshotUnitKeys = <String>{};
    for (final AgroDeviceRoomDraft room in rooms) {
      final String roomId = requireNonEmptyField(room.id, 'AgroDeviceRoom.id');
      if (!seenRoomIds.add(roomId)) {
        throw StateError('El Room ID "$roomId" está duplicado.');
      }
      requireNonEmptyField(room.name, 'AgroDeviceRoom.name');
      final String? key = room.snapshotUnitKey;
      if (key != null && key.isNotEmpty && !seenSnapshotUnitKeys.add(key)) {
        throw StateError('El snapshotUnitKey "$key" está duplicado.');
      }
    }

    final bool siteExistsInTenant =
        await deviceService.siteService.getById(
          tenantId: tenantId,
          siteId: trimmedSiteId,
        ) !=
        null;
    if (!siteExistsInTenant) {
      throw StateError(
        'AgroDevice.siteId "$trimmedSiteId" does not belong to tenant "$tenantId"',
      );
    }
    for (final String sectorId in sectorIds) {
      final sector = await sectorService.getById(
        tenantId: tenantId,
        sectorId: sectorId,
      );
      if (sector == null || sector.siteId != trimmedSiteId) {
        throw StateError('El sector "$sectorId" no pertenece a este site.');
      }
    }

    final bool deviceAlreadyExists =
        await deviceService.getById(tenantId: tenantId, deviceId: deviceId) !=
        null;
    if (deviceAlreadyExists) {
      throw StateError('Ya existe un device con ese ID.');
    }

    // Skip the site-wide read entirely when there's nothing to check — the
    // common case for a device still `pending_backend` with no keys
    // configured on itself or any of its Rooms yet.
    final bool hasAnyCandidateKey =
        (snapshotUnitKey != null && snapshotUnitKey.trim().isNotEmpty) ||
        rooms.any(
          (AgroDeviceRoomDraft room) =>
              room.snapshotUnitKey != null &&
              room.snapshotUnitKey!.trim().isNotEmpty,
        );

    // One site-wide index fetch, reused to check the device's own key (for
    // a no-Rooms device) AND every Room's key — instead of one
    // `SnapshotUnitKeyValidator.ensureUnique` round-trip per candidate.
    // Nothing to exclude: this device (and every one of its Rooms) is
    // brand new.
    final Map<String, SnapshotUnitKeyOwner> existingKeys = hasAnyCandidateKey
        ? await snapshotUnitKeyValidator.loadSiteIndex(
            tenantId: tenantId,
            siteId: trimmedSiteId,
          )
        : const <String, SnapshotUnitKeyOwner>{};
    void checkAgainstSite(String? candidateKey) {
      final String? trimmed = candidateKey?.trim();
      if (trimmed == null || trimmed.isEmpty) return;
      final SnapshotUnitKeyOwner? owner = existingKeys[trimmed];
      if (owner == null) return;
      throw StateError(
        'La snapshotUnitKey "$trimmed" ya está utilizada por '
        '${owner.describe()} en este site.',
      );
    }

    checkAgainstSite(snapshotUnitKey);
    for (final AgroDeviceRoomDraft room in rooms) {
      checkAgainstSite(room.snapshotUnitKey);
    }

    final WriteBatch batch = FirebaseFirestore.instance.batch();
    final String devicePath = FirestorePaths.deviceDoc(tenantId, deviceId);
    batch.set(
      FirebaseFirestore.instance.doc(devicePath),
      buildAgroDeviceCreatePayload(
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
      ),
    );
    for (final AgroDeviceRoomDraft room in rooms) {
      final String roomPath = FirestorePaths.deviceRoomDoc(
        tenantId,
        deviceId,
        room.id,
      );
      batch.set(
        FirebaseFirestore.instance.doc(roomPath),
        buildAgroDeviceRoomCreatePayload(
          tenantId: tenantId,
          deviceId: deviceId,
          roomId: room.id,
          siteId: trimmedSiteId,
          name: room.name,
          enabled: room.enabled,
          sortOrder: room.sortOrder,
          snapshotUnitKey: room.snapshotUnitKey,
        ),
      );
    }

    await batch.commit();
    deviceService.invalidateCache(tenantId: tenantId, siteId: trimmedSiteId);
    roomService.invalidateCache(tenantId: tenantId, deviceId: deviceId);
    debugPrint(
      '[AgroDeviceProvisioning] created device path=$devicePath '
      'with ${rooms.length} room(s)',
    );
  }
}
