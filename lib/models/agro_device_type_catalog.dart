/// Centralized catalog of device `type` values that are actually
/// implemented by this frontend today. This is deliberately small — see
/// the Etapa 4 delivery report (§4/§5) for the audit behind it.
///
/// [AgroDevice.type] itself stays a plain `String`, not a closed enum:
/// existing documents (e.g. La Payana's `plc-maternidad`, stored with
/// `type: "unknown"` by an earlier out-of-band script) and any future type
/// this catalog doesn't know about yet must remain readable without
/// crashing — [describeDeviceType] handles that fallback. What this
/// catalog controls is strictly forward-looking: which types a NEW device
/// is allowed to be created as, and whether creating one also means
/// creating Rooms.
///
/// The two entries below are the only ones with real, distinct behavior in
/// `DeviceDashboardEntry.listFrom` (`lib/models/device_dashboard_entry.dart`):
/// a Device with zero Room documents joins the snapshot via its own
/// `effectiveSnapshotUnitKey`; a Device with Room documents joins per-Room
/// instead. `usesRooms` on a catalog entry is exactly that branch — not a
/// speculative flag for a UI that doesn't exist yet.
library;

enum AgroDeviceRoomsMode {
  /// The Device itself is the only telemetry unit — no Room documents are
  /// created. Matches `DeviceDashboardEntry`'s fallback behavior for a
  /// Device with an empty Rooms subcollection.
  none,

  /// The Device exposes one or more logical Rooms, each with its own
  /// `snapshotUnitKey`. At least 1 Room is required at creation.
  multiple,
}

class AgroDeviceTypeDefinition {
  const AgroDeviceTypeDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.roomsMode,
    required this.capabilities,
    this.selectableForNewDevices = true,
    this.defaultRoomCount = 1,
  });

  /// Stable technical id — this is what's actually stored in
  /// `AgroDevice.type`. Never change an existing id once a real device
  /// might reference it.
  final String id;

  /// Short human label for selectors/lists (Spanish, matches the rest of
  /// the admin UI).
  final String label;

  final String description;

  final AgroDeviceRoomsMode roomsMode;

  /// Free-form capability tags (e.g. `temperature`, `humidity`) — informational
  /// only today, not read by any dashboard logic. Kept as data instead of
  /// code so a future capability-aware widget doesn't need a new field.
  final List<String> capabilities;

  /// Whether a NEW device can be created with this type from the admin UI.
  /// `false` is reserved for entries kept only for backward-compatible
  /// reads (none exist yet — every catalog entry today is selectable).
  final bool selectableForNewDevices;

  /// Sensible starting point for the room-count generator in the "Agregar
  /// device" form when [roomsMode] is [AgroDeviceRoomsMode.multiple]. Purely
  /// a UI default — the user can change the count before saving.
  final int defaultRoomCount;

  bool get usesRooms => roomsMode == AgroDeviceRoomsMode.multiple;
}

/// The full catalog, in display order. Centralized here on purpose — see
/// the class doc comment: no other file should hardcode a switch over
/// device type ids.
const List<AgroDeviceTypeDefinition> agroDeviceTypeCatalog =
    <AgroDeviceTypeDefinition>[
      AgroDeviceTypeDefinition(
        id: 'environment_single_room',
        label: 'Ambiente — una sola sala',
        description:
            'Un PLC/gateway que expone la telemetría de una única sala '
            '(temperatura/humedad) directamente bajo su propia clave de '
            'snapshot. Es el caso histórico de "1 device = 1 unidad".',
        roomsMode: AgroDeviceRoomsMode.none,
        capabilities: <String>['temperature', 'humidity'],
      ),
      AgroDeviceTypeDefinition(
        id: 'environment_multi_room',
        label: 'Ambiente — multisala',
        description:
            'Un PLC/gateway físico que expone varias salas lógicas '
            '(temperatura/humedad), cada una con su propia clave de '
            'snapshot — el caso de "PLC Maternidad" en La Payana.',
        roomsMode: AgroDeviceRoomsMode.multiple,
        capabilities: <String>['temperature', 'humidity'],
        defaultRoomCount: 8,
      ),
    ];

AgroDeviceTypeDefinition? findAgroDeviceType(String type) {
  for (final AgroDeviceTypeDefinition definition in agroDeviceTypeCatalog) {
    if (definition.id == type) {
      return definition;
    }
  }
  return null;
}

List<AgroDeviceTypeDefinition> selectableAgroDeviceTypes() {
  return agroDeviceTypeCatalog
      .where((AgroDeviceTypeDefinition type) => type.selectableForNewDevices)
      .toList(growable: false);
}

/// Human label for any stored `type` value, including ones this catalog
/// doesn't know about (legacy/historic — e.g. `"unknown"`, or a value
/// written by a future version of this app before this catalog knew about
/// it). Never throws.
String describeDeviceType(String type) {
  final AgroDeviceTypeDefinition? known = findAgroDeviceType(type);
  if (known != null) {
    return known.label;
  }
  if (type.trim().isEmpty) {
    return 'Sin tipo';
  }
  return 'Tipo histórico/no catalogado ($type)';
}
