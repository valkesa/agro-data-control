import '../models/agro_device.dart';
import '../models/agro_device_room.dart';
import 'agro_device_room_service.dart';
import 'agro_device_service.dart';

/// Identifies whichever Device or Room owns a given `snapshotUnitKey`
/// within a Site — everything a conflict message needs to name the other
/// side without exposing raw ids when a real name exists.
class SnapshotUnitKeyOwner {
  const SnapshotUnitKeyOwner({
    required this.deviceId,
    required this.deviceName,
    this.roomId,
    this.roomName,
  });

  final String deviceId;
  final String deviceName;

  /// Null when the owner is the DEVICE itself (a no-Rooms device using its
  /// own `snapshotUnitKey`) rather than one of its Rooms.
  final String? roomId;
  final String? roomName;

  bool get isRoom => roomId != null;

  String get _deviceLabel => deviceName.isEmpty ? deviceId : deviceName;

  /// Human-readable description for error messages, e.g. `la room "Sala 1"
  /// del device "PLC Maternidad"` or `el device "PLC Maternidad"`.
  String describe() {
    if (isRoom) {
      final String roomLabel = (roomName == null || roomName!.isEmpty)
          ? roomId!
          : roomName!;
      return 'la room "$roomLabel" del device "$_deviceLabel"';
    }
    return 'el device "$_deviceLabel"';
  }

  @override
  bool operator ==(Object other) {
    return other is SnapshotUnitKeyOwner &&
        other.deviceId == deviceId &&
        other.roomId == roomId;
  }

  @override
  int get hashCode => Object.hash(deviceId, roomId);
}

/// One raw `(key, owner)` pair as actually stored, BEFORE any trimming —
/// used only by [auditSnapshotUnitKeys], which needs to report whitespace
/// issues rather than silently normalize them away.
class _RawEntry {
  const _RawEntry(this.rawKey, this.owner);
  final String rawKey;
  final SnapshotUnitKeyOwner owner;
}

List<_RawEntry> _collectRawEntries({
  required List<AgroDevice> devices,
  required Map<String, List<AgroDeviceRoom>> roomsByDeviceId,
}) {
  final List<_RawEntry> entries = <_RawEntry>[];
  for (final AgroDevice device in devices) {
    final List<AgroDeviceRoom> rooms =
        roomsByDeviceId[device.id] ?? const <AgroDeviceRoom>[];
    if (rooms.isEmpty) {
      // Matches `DeviceDashboardEntry.listFrom`'s own branch: a Device
      // with zero Room documents joins the snapshot via its OWN key. Once
      // it has Rooms, its own `snapshotUnitKey` is never read by the
      // dashboard, so it's excluded here too — including it would report
      // false conflicts against a field the app never actually uses.
      final String? key = device.snapshotUnitKey;
      if (key != null) {
        entries.add(
          _RawEntry(
            key,
            SnapshotUnitKeyOwner(deviceId: device.id, deviceName: device.name),
          ),
        );
      }
    } else {
      for (final AgroDeviceRoom room in rooms) {
        final String? key = room.snapshotUnitKey;
        if (key != null) {
          entries.add(
            _RawEntry(
              key,
              SnapshotUnitKeyOwner(
                deviceId: device.id,
                deviceName: device.name,
                roomId: room.id,
                roomName: room.name,
              ),
            ),
          );
        }
      }
    }
  }
  return entries;
}

/// Builds a `snapshotUnitKey (trimmed) → owner` index for one Site, from
/// already-fetched [devices] (any Site, filtered by the caller — see
/// [SnapshotUnitKeyValidator.loadSiteIndex]) and their [roomsByDeviceId].
///
/// Pure — no Firestore access, safe to unit test directly. Keys are
/// trimmed before indexing (see the module doc comment on trimming vs.
/// case-sensitivity); an empty/whitespace-only key is never indexed — an
/// unconfigured `snapshotUnitKey` is allowed to repeat across every Device
/// still `pending_backend`.
///
/// If the input already contains a genuine duplicate (shouldn't happen if
/// every write went through [SnapshotUnitKeyValidator], but historical
/// data might not have), the LAST owner encountered wins — this index is
/// for conflict-checking a NEW candidate, not for reporting existing
/// duplicates; use [auditSnapshotUnitKeys] for that.
Map<String, SnapshotUnitKeyOwner> buildSiteSnapshotUnitKeyIndex({
  required List<AgroDevice> devices,
  required Map<String, List<AgroDeviceRoom>> roomsByDeviceId,
}) {
  final Map<String, SnapshotUnitKeyOwner> index =
      <String, SnapshotUnitKeyOwner>{};
  for (final _RawEntry entry in _collectRawEntries(
    devices: devices,
    roomsByDeviceId: roomsByDeviceId,
  )) {
    final String trimmed = entry.rawKey.trim();
    if (trimmed.isEmpty) continue;
    index[trimmed] = entry.owner;
  }
  return index;
}

/// Full audit of every `snapshotUnitKey` in [devices]/[roomsByDeviceId] —
/// a diagnostic tool, not a write-path guard. Reusable from tests and,
/// later, from a controlled diagnostic script (never run automatically
/// against production — see the Etapa 4.1 report §9).
class SnapshotUnitKeyAuditResult {
  const SnapshotUnitKeyAuditResult({
    required this.uniqueKeys,
    required this.duplicateGroups,
    required this.emptyOwners,
    required this.untrimmedRawKeys,
    required this.caseOnlyDuplicateGroups,
  });

  /// Trimmed keys used by exactly one owner.
  final List<String> uniqueKeys;

  /// Trimmed key → every owner using it, only present when 2+ owners
  /// share the exact same trimmed key (a real conflict).
  final Map<String, List<SnapshotUnitKeyOwner>> duplicateGroups;

  /// Owners whose `snapshotUnitKey` is explicitly stored as blank/
  /// whitespace-only after trimming — expected/allowed for a Device still
  /// `pending_backend`, reported here purely for visibility, not as an
  /// error. A `snapshotUnitKey` that was simply NEVER SET (`null`) is not
  /// included: only a genuinely-stored empty string is — there's nothing
  /// to audit about a field that doesn't exist at all, only about a field
  /// that exists but ended up empty.
  final List<SnapshotUnitKeyOwner> emptyOwners;

  /// Raw (untrimmed) key → owners, only present when the raw stored value
  /// has leading/trailing whitespace.
  final Map<String, List<SnapshotUnitKeyOwner>> untrimmedRawKeys;

  /// Lowercased key → owners, only present when 2+ DIFFERENT raw keys
  /// collide once lowercased (e.g. "Sala-1" vs "sala-1") AND are not
  /// already reported as an exact duplicate above.
  final Map<String, List<SnapshotUnitKeyOwner>> caseOnlyDuplicateGroups;

  bool get hasIssues =>
      duplicateGroups.isNotEmpty ||
      untrimmedRawKeys.isNotEmpty ||
      caseOnlyDuplicateGroups.isNotEmpty;
}

SnapshotUnitKeyAuditResult auditSnapshotUnitKeys({
  required List<AgroDevice> devices,
  required Map<String, List<AgroDeviceRoom>> roomsByDeviceId,
}) {
  final List<_RawEntry> rawEntries = _collectRawEntries(
    devices: devices,
    roomsByDeviceId: roomsByDeviceId,
  );

  final List<SnapshotUnitKeyOwner> emptyOwners = <SnapshotUnitKeyOwner>[];
  final Map<String, List<SnapshotUnitKeyOwner>> untrimmedRawKeys =
      <String, List<SnapshotUnitKeyOwner>>{};
  final Map<String, List<SnapshotUnitKeyOwner>> byTrimmedKey =
      <String, List<SnapshotUnitKeyOwner>>{};

  for (final _RawEntry entry in rawEntries) {
    final String trimmed = entry.rawKey.trim();
    if (trimmed.isEmpty) {
      emptyOwners.add(entry.owner);
      continue;
    }
    if (trimmed != entry.rawKey) {
      untrimmedRawKeys.putIfAbsent(entry.rawKey, () => []).add(entry.owner);
    }
    byTrimmedKey.putIfAbsent(trimmed, () => []).add(entry.owner);
  }

  final List<String> uniqueKeys = <String>[];
  final Map<String, List<SnapshotUnitKeyOwner>> duplicateGroups =
      <String, List<SnapshotUnitKeyOwner>>{};
  byTrimmedKey.forEach((key, owners) {
    if (owners.length > 1) {
      duplicateGroups[key] = owners;
    } else {
      uniqueKeys.add(key);
    }
  });

  // Case-only collisions: group exact (already-deduplicated) trimmed keys
  // by their lowercase form; a group of 2+ DIFFERENT exact keys means a
  // case-only difference. Keys already in `duplicateGroups` (exact
  // duplicates) are excluded — that's a stronger finding, no need to
  // report it twice under a different name.
  final Map<String, Set<String>> byLowercase = <String, Set<String>>{};
  for (final String key in byTrimmedKey.keys) {
    byLowercase.putIfAbsent(key.toLowerCase(), () => <String>{}).add(key);
  }
  final Map<String, List<SnapshotUnitKeyOwner>> caseOnlyDuplicateGroups =
      <String, List<SnapshotUnitKeyOwner>>{};
  byLowercase.forEach((lower, exactKeys) {
    if (exactKeys.length < 2) return;
    final List<SnapshotUnitKeyOwner> owners = <SnapshotUnitKeyOwner>[
      for (final String exactKey in exactKeys) ...byTrimmedKey[exactKey]!,
    ];
    caseOnlyDuplicateGroups[lower] = owners;
  });

  return SnapshotUnitKeyAuditResult(
    uniqueKeys: uniqueKeys,
    duplicateGroups: duplicateGroups,
    emptyOwners: emptyOwners,
    untrimmedRawKeys: untrimmedRawKeys,
    caseOnlyDuplicateGroups: caseOnlyDuplicateGroups,
  );
}

/// Enforces `snapshotUnitKey` uniqueness across an entire Site — not just
/// within one Device, which is all Etapa 4 originally checked. The
/// frontend joins live telemetry via `DashboardSnapshot.unitsByKey`, a
/// single flat map per Site's backend, so two Rooms (or a Room and a
/// no-Rooms Device) sharing a key would silently collide on the same
/// telemetry unit.
///
/// Deliberately does NOT hold `AgroDeviceService`/`AgroDeviceRoomService`
/// as constructor-injected fields with `const` defaults: those two
/// services would need a reciprocal default pointing back at THIS class
/// (to validate on every write), and Dart's `const` evaluator rejects
/// that kind of mutual default-value cycle at compile time. Instead, this
/// class owns its OWN default `deviceService`/`roomService` instances
/// (functionally identical to any other instance — both services keep
/// their caches in `static` fields, not instance fields), and
/// `AgroDeviceService`/`AgroDeviceRoomService` construct
/// `const SnapshotUnitKeyValidator()` locally inside `create()`/`update()`
/// instead of storing it as a field.
class SnapshotUnitKeyValidator {
  const SnapshotUnitKeyValidator({
    this.deviceService = const AgroDeviceService(),
    this.roomService = const AgroDeviceRoomService(),
  });

  final AgroDeviceService deviceService;
  final AgroDeviceRoomService roomService;

  /// Fetches every Device (including disabled) in [siteId] and, for each
  /// one, its Rooms (including disabled) — the minimal read set for a
  /// complete Site-wide index. Cost: 1 query (Devices) + up to N parallel
  /// queries (Rooms, one per Device — via
  /// [AgroDeviceRoomService.listForDevices], already batched with
  /// `Future.wait`). Only ever called from a write path (create/update),
  /// never from a render path or on dialog-open — see the Etapa 4.1 report
  /// §6 for why this cost is acceptable here.
  Future<Map<String, SnapshotUnitKeyOwner>> loadSiteIndex({
    required String tenantId,
    required String siteId,
  }) async {
    final List<AgroDevice> devices = await deviceService.listBySite(
      tenantId: tenantId,
      siteId: siteId,
      includeDisabled: true,
    );
    final Map<String, List<AgroDeviceRoom>> roomsByDeviceId = await roomService
        .listForDevices(
          tenantId: tenantId,
          deviceIds: [for (final AgroDevice device in devices) device.id],
          includeDisabled: true,
        );
    return buildSiteSnapshotUnitKeyIndex(
      devices: devices,
      roomsByDeviceId: roomsByDeviceId,
    );
  }

  /// Throws a [StateError] with a specific message if [candidateKey]
  /// (trimmed) is already used by a DIFFERENT Device/Room in this Site. A
  /// null/blank key never conflicts (see the module-level trimming
  /// policy). Pass [excludeDeviceId]/[excludeRoomId] to identify the
  /// entity being EDITED so re-saving its own unchanged key isn't reported
  /// as a conflict with itself — leave both null when creating something
  /// new (nothing to self-exclude yet).
  Future<void> ensureUnique({
    required String tenantId,
    required String siteId,
    required String? candidateKey,
    String? excludeDeviceId,
    String? excludeRoomId,
  }) async {
    final String? trimmed = candidateKey?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final Map<String, SnapshotUnitKeyOwner> index = await loadSiteIndex(
      tenantId: tenantId,
      siteId: siteId,
    );
    final SnapshotUnitKeyOwner? owner = index[trimmed];
    if (owner == null) return;
    final bool isSelf =
        owner.deviceId == excludeDeviceId && owner.roomId == excludeRoomId;
    if (isSelf) return;
    throw StateError(
      'La snapshotUnitKey "$trimmed" ya está utilizada por '
      '${owner.describe()} en este site.',
    );
  }
}
