/// N7.1 §15 — thrown by every N7.1 repository's versioned write when the
/// document's stored version no longer matches the version the caller last
/// read (someone else wrote in between). This is the `configuration_conflict`
/// case the prompt names: the write is refused, nothing is overwritten
/// silently, and the caller decides how to reconcile (reload and retry,
/// show the user a warning, etc).
///
/// Plays the same role `DeviceTemplateVersionConflict`
/// (`lib/services/device_template_repository.dart`) plays for
/// `deviceTemplates/{id}` — kept as one shared, entity-agnostic type here
/// instead of six near-identical copies (`BoardPresetVersionConflict`,
/// `CapabilityProfileVersionConflict`, ...) since every N7.1 repository
/// needs exactly the same three facts about the conflict.
class FirestoreVersionConflict implements Exception {
  const FirestoreVersionConflict({
    required this.entityType,
    required this.entityId,
    required this.expectedVersion,
    required this.actualVersion,
  });

  /// e.g. `'boardPreset'`, `'capabilityProfile'`, `'deviceBoardConfig'`.
  final String entityType;
  final String entityId;
  final int expectedVersion;
  final int actualVersion;

  @override
  String toString() =>
      'FirestoreVersionConflict($entityType/$entityId '
      'expected=$expectedVersion actual=$actualVersion)';
}

/// N7.1.1 §10/§11 (finding A6) — thrown by every global repository's
/// [create] when a document with the same id already exists. Together with
/// [FirestoreVersionConflict] this is the pair of typed conflict errors
/// §11 asks for ("`FirestoreVersionConflict` / `FirestoreAlreadyExists` o
/// equivalente"). Like [FirestoreVersionConflict], every `create()` throws
/// this from *outside* the `runTransaction` callback (a sentinel is
/// returned from inside it instead) — the same Flutter-Web JS-Promise
/// type-loss workaround `DeviceBoardConfigRepository` already established
/// (see its doc comments), now applied consistently to every repository's
/// `create()`, not just `DeviceBoardConfigRepository`'s `applyPreset`/
/// `saveLayout`.
class FirestoreAlreadyExists implements Exception {
  const FirestoreAlreadyExists({
    required this.entityType,
    required this.entityId,
  });

  /// e.g. `'boardPreset'`, `'layoutTemplate'`.
  final String entityType;
  final String entityId;

  @override
  String toString() => 'FirestoreAlreadyExists($entityType/$entityId)';
}

/// Internal transaction result used to preserve typed Dart exceptions on
/// Flutter Web. Repositories return this through the JS promise boundary and
/// throw [FirestoreVersionConflict] afterwards in plain Dart.
class FirestoreVersionMismatchResult {
  const FirestoreVersionMismatchResult(this.actualVersion);
  final int actualVersion;
}
