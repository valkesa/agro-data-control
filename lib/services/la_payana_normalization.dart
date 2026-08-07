/// Etapa 5B — a ONE-TIME, hardcoded maintenance operation, not a general
/// migration tool. Normalizes the single real device
/// `tenants/la-payana/devices/plc-maternidad`: `type: "unknown"` →
/// `"environment_multi_room"`, and adds `sectorIds: ['maternidad']` (today
/// absent — the device predates Etapa 4's association field). No other
/// field changes. See the Etapa 5B delivery report for why this is safe
/// (§8 of the Etapa 4.1 report already confirmed the 8 real rooms are a
/// clean, exact match for `environment_multi_room`).
///
/// Deliberately pure (no `cloud_firestore`/Flutter import) — this file is
/// shared between `flutter test` (unit tests, no Firestore) and
/// `tool/normalize_la_payana_device.dart` (a plain `dart run` script, which
/// CANNOT import `cloud_firestore` at all — that package requires the
/// Flutter engine's plugin registration). The script fetches data over the
/// same Firestore REST technique already used elsewhere in this project,
/// converts it into the small value types below, and calls
/// [validateLaPayanaNormalization] before writing anything.
library;

const String laPayanaTenantId = 'la-payana';
const String laPayanaSiteId = 'roque-perez';
const String laPayanaSectorId = 'maternidad';
const String laPayanaDeviceId = 'plc-maternidad';
const String laPayanaOldType = 'unknown';
const String laPayanaNewType = 'environment_multi_room';
const int laPayanaExpectedRoomCount = 8;
final List<String> laPayanaExpectedRoomIds = List.unmodifiable(
  List.generate(laPayanaExpectedRoomCount, (i) => 'sala-${i + 1}'),
);

/// A Room as read from Firestore, reduced to just what validation needs.
class LaPayanaRoomSnapshot {
  const LaPayanaRoomSnapshot({required this.id, this.snapshotUnitKey});

  final String id;
  final String? snapshotUnitKey;
}

/// Everything [validateLaPayanaNormalization] needs, already fetched by the
/// caller — this function itself never touches Firestore.
class LaPayanaNormalizationInput {
  const LaPayanaNormalizationInput({
    required this.tenantExists,
    required this.siteExists,
    required this.sectorExists,
    required this.sectorSiteId,
    required this.deviceExists,
    required this.deviceSiteId,
    required this.deviceType,
    required this.deviceSectorIds,
    required this.rooms,
  });

  final bool tenantExists;
  final bool siteExists;
  final bool sectorExists;
  final String? sectorSiteId;
  final bool deviceExists;
  final String? deviceSiteId;
  final String? deviceType;
  final List<String> deviceSectorIds;
  final List<LaPayanaRoomSnapshot> rooms;
}

class LaPayanaValidationResult {
  const LaPayanaValidationResult._({
    required this.error,
    required this.alreadyNormalized,
  });

  const LaPayanaValidationResult.ok({bool alreadyNormalized = false})
    : this._(error: null, alreadyNormalized: alreadyNormalized);

  const LaPayanaValidationResult.abort(String error)
    : this._(error: error, alreadyNormalized: false);

  /// Null means validation passed — safe to proceed.
  final String? error;

  /// True when the device already has `type: environment_multi_room` and
  /// `sectorIds: [maternidad]` — the operation is a no-op (idempotent).
  final bool alreadyNormalized;

  bool get isValid => error == null;
}

/// Validates every precondition from the Etapa 5B spec (§5-6) — hardcoded
/// to La Payana's exact real shape, aborting (never guessing/coercing) on
/// anything unexpected. Pure and synchronous: safe and fast to unit test.
LaPayanaValidationResult validateLaPayanaNormalization(
  LaPayanaNormalizationInput input,
) {
  if (!input.tenantExists) {
    return const LaPayanaValidationResult.abort(
      'El tenant "$laPayanaTenantId" no existe.',
    );
  }
  if (!input.siteExists) {
    return const LaPayanaValidationResult.abort(
      'El site "$laPayanaSiteId" no existe bajo "$laPayanaTenantId".',
    );
  }
  if (!input.sectorExists) {
    return const LaPayanaValidationResult.abort(
      'El sector "$laPayanaSectorId" no existe bajo "$laPayanaTenantId".',
    );
  }
  if (input.sectorSiteId != laPayanaSiteId) {
    return LaPayanaValidationResult.abort(
      'El sector "$laPayanaSectorId" pertenece al site '
      '"${input.sectorSiteId}", se esperaba "$laPayanaSiteId".',
    );
  }
  if (!input.deviceExists) {
    return const LaPayanaValidationResult.abort(
      'El device "$laPayanaDeviceId" no existe bajo "$laPayanaTenantId".',
    );
  }
  if (input.deviceSiteId != laPayanaSiteId) {
    return LaPayanaValidationResult.abort(
      'device.siteId es "${input.deviceSiteId}", se esperaba '
      '"$laPayanaSiteId" — abortando por seguridad.',
    );
  }
  if (input.deviceType != laPayanaOldType &&
      input.deviceType != laPayanaNewType) {
    return LaPayanaValidationResult.abort(
      'device.type es "${input.deviceType}", solo se acepta '
      '"$laPayanaOldType" o "$laPayanaNewType".',
    );
  }
  final bool sectorIdsAlreadyNormalized =
      input.deviceSectorIds.length == 1 &&
      input.deviceSectorIds.first == laPayanaSectorId;
  if (input.deviceSectorIds.isNotEmpty && !sectorIdsAlreadyNormalized) {
    return LaPayanaValidationResult.abort(
      'device.sectorIds ya tiene un valor inesperado: '
      '${input.deviceSectorIds}.',
    );
  }
  if (input.rooms.length != laPayanaExpectedRoomCount) {
    return LaPayanaValidationResult.abort(
      'Se esperaban $laPayanaExpectedRoomCount rooms, se encontraron '
      '${input.rooms.length}.',
    );
  }
  final Set<String> roomIds = input.rooms.map((r) => r.id).toSet();
  for (final String expectedId in laPayanaExpectedRoomIds) {
    if (!roomIds.contains(expectedId)) {
      return LaPayanaValidationResult.abort('Falta la room "$expectedId".');
    }
  }
  final Set<String> seenKeys = <String>{};
  for (final LaPayanaRoomSnapshot room in input.rooms) {
    final String? key = room.snapshotUnitKey;
    if (key == null || key.trim().isEmpty) {
      return LaPayanaValidationResult.abort(
        'La room "${room.id}" no tiene snapshotUnitKey.',
      );
    }
    if (!seenKeys.add(key)) {
      return LaPayanaValidationResult.abort(
        'snapshotUnitKey duplicada detectada: "$key".',
      );
    }
  }

  final bool typeAlreadyNormalized = input.deviceType == laPayanaNewType;
  return LaPayanaValidationResult.ok(
    alreadyNormalized: typeAlreadyNormalized && sectorIdsAlreadyNormalized,
  );
}

/// The exact (and ONLY) fields the write is allowed to touch — used both
/// by the script (as the Firestore `updateMask`) and by tests asserting
/// nothing else is ever included.
const List<String> laPayanaNormalizationUpdateMask = <String>[
  'type',
  'sectorIds',
  'updatedAt',
];
