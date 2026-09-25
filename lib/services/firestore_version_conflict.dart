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
