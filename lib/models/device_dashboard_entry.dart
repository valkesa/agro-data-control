import 'package:flutter/foundation.dart';

import 'agro_device.dart';
import 'agro_device_room.dart';
import 'dashboard_snapshot.dart';
import 'munters_model.dart';
import '../services/agro_device_room_service.dart';

/// Presentation-layer join between a Device's Firestore metadata and its
/// live telemetry from the backend snapshot — for Sites using the dynamic
/// Devices architecture (`SiteDocument.usesDynamicDevices`). Legacy Sites
/// never build this; they keep using `munters1`/`munters2` directly.
///
/// One entry is produced per logical Room the Device exposes: a Device with
/// zero [AgroDeviceRoom] documents is treated as exposing exactly one
/// implicit Room (itself) — the original 1 Device = 1 snapshot unit
/// behavior, preserved bit-for-bit so every Device that predates the Rooms
/// concept keeps working unchanged.
///
/// Built once per rebuild via [DeviceDashboardEntry.listFrom] — a pure
/// function with no Firestore/network access of its own, so it's free to
/// call from `build()`.
class DeviceDashboardEntry {
  const DeviceDashboardEntry({
    required this.device,
    required this.roomName,
    required this.liveUnit,
  });

  final AgroDevice device;

  /// What to actually display as this row's label: the Room's name when the
  /// Device has explicit Rooms, otherwise the Device's own name.
  final String roomName;

  /// Null when this Room has no matching telemetry in the current
  /// snapshot yet — never configured, backend offline, or a
  /// `snapshotUnitKey` that doesn't (yet) match anything the backend sent.
  final MuntersModel? liveUnit;

  String get displayName => roomName;

  bool get hasTelemetry => liveUnit != null;

  /// What to actually feed into the existing card/row widgets: the live
  /// unit when present, otherwise an explicit "no data" placeholder
  /// carrying the Room's (or Device's) real name — never a fabricated
  /// value and never the legacy "Munters 1/2" fallback.
  MuntersModel get displayUnit =>
      liveUnit ?? MuntersModel.placeholder(name: roomName);

  /// Joins [devices] against [snapshot], expanding each enabled Device into
  /// one entry per enabled Room in [roomsByDeviceId] — or, when a Device has
  /// no Room documents (the common case today), one implicit entry keyed by
  /// `AgroDevice.effectiveSnapshotUnitKey` → `DashboardSnapshot.unitsByKey`,
  /// exactly as before Rooms existed.
  ///
  /// - Entries are ordered by device (the caller — `AgroDeviceService.listBySite`
  ///   — already sorts by `sortOrder`; this only defensively re-excludes
  ///   disabled devices in case a future caller ever feeds in an unfiltered
  ///   list), then by Room `sortOrder`/name within each device.
  /// - A Device whose Rooms are ALL disabled produces zero entries for that
  ///   Device — it does NOT fall back to the implicit single-Room behavior,
  ///   since that would resurrect a Room the operator explicitly turned off.
  /// - A snapshot unit whose key doesn't match any device/room is silently
  ///   skipped — no phantom cards for orphaned telemetry — with an optional
  ///   debug log to help spot a misconfigured `snapshotUnitKey`.
  /// - 0 devices simply returns an empty list; callers must not fabricate
  ///   entries to fill the gap.
  static List<DeviceDashboardEntry> listFrom({
    required List<AgroDevice> devices,
    required DashboardSnapshot snapshot,
    Map<String, List<AgroDeviceRoom>> roomsByDeviceId =
        const <String, List<AgroDeviceRoom>>{},
  }) {
    final Map<String, MuntersModel> unitsByKey = snapshot.unitsByKey;
    final List<AgroDevice> enabledDevices = devices
        .where((AgroDevice device) => device.enabled)
        .toList(growable: false);

    final Set<String> matchedKeys = <String>{};
    final List<DeviceDashboardEntry> entries = <DeviceDashboardEntry>[];

    for (final AgroDevice device in enabledDevices) {
      final List<AgroDeviceRoom> allRooms =
          roomsByDeviceId[device.id] ?? const <AgroDeviceRoom>[];

      // No Room documents at all -> this Device predates (or never opted
      // into) the Rooms concept: fall back to the implicit single-Room
      // behavior, unchanged from before Rooms existed.
      if (allRooms.isEmpty) {
        final String key = device.effectiveSnapshotUnitKey;
        final MuntersModel? unit = unitsByKey[key];
        if (unit != null) {
          matchedKeys.add(key);
        }
        entries.add(
          DeviceDashboardEntry(
            device: device,
            roomName: device.name,
            liveUnit: unit,
          ),
        );
        continue;
      }

      // Room documents exist but every one of them is disabled -> this
      // Device is intentionally fully disabled at the Room level. Zero
      // entries, NOT the implicit single-Room fallback above.
      final List<AgroDeviceRoom> enabledRooms =
          allRooms.where((AgroDeviceRoom room) => room.enabled).toList()
            ..sort(compareAgroDeviceRoomsForDisplay);

      if (enabledRooms.isEmpty) {
        continue;
      }

      for (final AgroDeviceRoom room in enabledRooms) {
        final String key = room.effectiveSnapshotUnitKey;
        final MuntersModel? unit = unitsByKey[key];
        if (unit != null) {
          matchedKeys.add(key);
        }
        entries.add(
          DeviceDashboardEntry(
            device: device,
            roomName: room.name,
            liveUnit: unit,
          ),
        );
      }
    }

    if (kDebugMode) {
      final Set<String> orphanKeys = unitsByKey.keys.toSet()
        ..removeAll(matchedKeys);
      for (final String orphanKey in orphanKeys) {
        debugPrint(
          '[DeviceDashboardEntry] snapshot unit "$orphanKey" has no matching '
          'AgroDevice/AgroDeviceRoom (checked ${enabledDevices.length} '
          'enabled device(s)) — ignored, no card shown.',
        );
      }
    }

    return entries;
  }
}
