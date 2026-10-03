import 'package:cloud_firestore/cloud_firestore.dart';

import '../board_content/board_content_layout.dart';
import '../board_content/board_content_validator.dart';
import '../board_presets/board_preset.dart';
import '../board_presets/board_preset_catalog.dart'
    show resolveLayoutTemplateId;
import '../cell_layout_presets/cell_layout_catalog.dart';
import '../device_board_config/apply_board_preset_to_device.dart';
import '../device_capabilities/capability_library_store.dart';
import '../device_capabilities/device_capability_profile.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../firebase/firestore_paths.dart';
import 'board_validation_rejected.dart';
import 'firestore_timestamp_adapter.dart';
import 'firestore_version_conflict.dart';

/// N7.1 §3/§8/§9/§14/§15 — persistence for
/// `tenants/{tenantId}/devices/{deviceId}/settings/boardConfig`: the single
/// document holding a Device's `capabilityProfileId` assignment plus its
/// independent [BoardContentLayout] (schema-2, including
/// `sourceBoardPresetId`/`sourceBoardPresetVersion` trazability — §6). One
/// read for the whole "Configuración de Board" screen (§5).
///
/// [applyPreset] is the only place `BoardPreset` → Device copying happens;
/// [saveLayout] is what `BoardEditorMode.device` (§13/§14) calls after an
/// edit. Both go through the same versioned-transaction shape as every
/// other N7.1 repository — never a silent overwrite (§15).
class DeviceBoardConfigRepository {
  const DeviceBoardConfigRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  static const List<String> _timestampFields = ['createdAt', 'updatedAt'];

  /// `null` means the Device has no board configuration yet (never applied
  /// a preset, never had a layout saved) — a legitimate, common state, not
  /// an error.
  Future<BoardContentLayout?> fetchOne({
    required String tenantId,
    required String deviceId,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await firestore
        .doc(FirestorePaths.deviceBoardConfigDoc(tenantId, deviceId))
        .get();
    if (!snapshot.exists) return null;
    return BoardContentLayout.fromMap(
      normalizeFirestoreTimestamps(
        snapshot.data() ?? <String, Object?>{},
        timestampFields: _timestampFields,
      ),
    );
  }

  /// N7.1 §8 — the "Aplicar" action: validates preset/profile compatibility
  /// (via [applyBoardPresetToDevice], Firestore-free), then persists the
  /// deep-copied result. `expectedLayoutVersion` is `0` for a Device with no
  /// prior board configuration (first apply); otherwise it must match the
  /// currently-stored `layoutVersion`, exactly like every other N7.1
  /// versioned write (§15).
  Future<BoardPresetApplicationResult> applyPreset({
    required String tenantId,
    required String deviceId,
    required BoardPreset preset,
    required DeviceCapabilityProfile? profile,
    required String? profileId,
    required MetricLibraryStore metricsLibrary,
    required IndicatorLibraryStore indicatorsLibrary,
    required CellLayoutCatalog cellLayoutCatalog,
    required int expectedLayoutVersion,
  }) async {
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.deviceBoardConfigDoc(tenantId, deviceId),
    );
    // The version check throws `FirestoreVersionConflict` here, in plain
    // Dart, after `runTransaction`'s Future has already resolved — never
    // from inside the transaction callback itself. On Flutter Web,
    // cloud_firestore_web's `runTransaction` round-trips the callback
    // through a JS Promise; an object thrown from *inside* that callback
    // loses its Dart type crossing back (surfaces as a generic "Dart
    // exception thrown from converted Future"), so `on
    // FirestoreVersionConflict catch` at the call site would never match it
    // there. Returning a sentinel instead and throwing out here keeps the
    // conflict a real, catchable `FirestoreVersionConflict` on every
    // platform.
    final Object outcome = await firestore.runTransaction<Object>((
      Transaction transaction,
    ) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);
      final int actualVersion = snapshot.exists
          ? ((snapshot.data()?['layoutVersion'] as int?) ?? 0)
          : 0;
      if (actualVersion != expectedLayoutVersion) {
        return _VersionConflictSentinel(actualVersion);
      }
      final BoardPresetApplicationResult result = applyBoardPresetToDevice(
        deviceId: deviceId,
        preset: preset,
        profile: profile,
        metricsLibrary: metricsLibrary,
        indicatorsLibrary: indicatorsLibrary,
        cellLayoutCatalog: cellLayoutCatalog,
        nextLayoutVersion: actualVersion + 1,
        capabilityProfileId: profileId,
      );
      if (result.isBlocked) return result;
      transaction.set(reference, <String, Object?>{
        ...result.layout!.toMap(),
        'createdAt':
            snapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return result;
    });
    if (outcome is _VersionConflictSentinel) {
      throw FirestoreVersionConflict(
        entityType: 'deviceBoardConfig',
        entityId: '$tenantId/$deviceId',
        expectedVersion: expectedLayoutVersion,
        actualVersion: outcome.actualVersion,
      );
    }
    return outcome as BoardPresetApplicationResult;
  }

  /// N7.1 §13/§14, revised N7.1.1 §6 (finding A3) — what
  /// `BoardEditorMode.device`'s "Guardar" calls: persists an already-edited
  /// [layout]. The Board Editor's own Guardar button already gates on
  /// [BoardContentValidator.validate] (§5 — the first, UI-layer defense),
  /// but this is the *second* defense §6 explicitly asks for ("no confiar
  /// solo en el botón"): [metricCatalog]/[cellLayoutCatalog] let this method
  /// re-run the exact same validator right before writing, so a caller that
  /// bypasses the editor entirely (a stale draft, a future programmatic
  /// caller, a test) still can't persist a structurally invalid layout —
  /// [BoardValidationRejected] is thrown instead, before the transaction
  /// even starts. Preserves `sourceBoardPresetId`/`sourceBoardPresetVersion`
  /// exactly as passed in [layout] — editing a Device's board never
  /// fabricates new trazability, it only carries forward whatever the
  /// layout already had.
  Future<int> saveLayout({
    required String tenantId,
    required String deviceId,
    required BoardContentLayout layout,
    required int expectedLayoutVersion,
    required DeviceMetricCatalog metricCatalog,
    required CellLayoutCatalog cellLayoutCatalog,
  }) async {
    final materializedLayout = BoardContentLayout(
      deviceId: layout.deviceId,
      layoutTemplateId: layout.layoutTemplateId,
      showTitle: layout.showTitle,
      titleOverride: layout.titleOverride,
      layoutVersion: layout.layoutVersion,
      capabilityProfileId: layout.capabilityProfileId,
      sourceBoardPresetId: layout.sourceBoardPresetId,
      sourceBoardPresetVersion: layout.sourceBoardPresetVersion,
      items: materializeCellLayoutSnapshots(layout.items, cellLayoutCatalog),
    );
    final issues = BoardContentValidator.validate(
      materializedLayout,
      resolveLayoutTemplateId(materializedLayout.layoutTemplateId),
      metricCatalog,
      cellLayoutCatalog,
    );
    if (issues.isNotEmpty) {
      throw BoardValidationRejected(issues);
    }
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.deviceBoardConfigDoc(tenantId, deviceId),
    );
    // See the matching comment in [applyPreset]: the conflict is thrown out
    // here, in plain Dart, never from inside the transaction callback.
    final Object outcome = await firestore.runTransaction<Object>((
      Transaction transaction,
    ) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);
      final int actualVersion = snapshot.exists
          ? ((snapshot.data()?['layoutVersion'] as int?) ?? 0)
          : 0;
      if (actualVersion != expectedLayoutVersion) {
        return _VersionConflictSentinel(actualVersion);
      }
      final int nextVersion = actualVersion + 1;
      final BoardContentLayout toPersist = BoardContentLayout(
        deviceId: materializedLayout.deviceId,
        layoutTemplateId: materializedLayout.layoutTemplateId,
        showTitle: materializedLayout.showTitle,
        titleOverride: materializedLayout.titleOverride,
        layoutVersion: nextVersion,
        capabilityProfileId: materializedLayout.capabilityProfileId,
        sourceBoardPresetId: materializedLayout.sourceBoardPresetId,
        sourceBoardPresetVersion: materializedLayout.sourceBoardPresetVersion,
        items: materializedLayout.items,
      );
      transaction.set(reference, <String, Object?>{
        ...toPersist.toMap(),
        'createdAt':
            snapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return nextVersion;
    });
    if (outcome is _VersionConflictSentinel) {
      throw FirestoreVersionConflict(
        entityType: 'deviceBoardConfig',
        entityId: '$tenantId/$deviceId',
        expectedVersion: expectedLayoutVersion,
        actualVersion: outcome.actualVersion,
      );
    }
    return outcome as int;
  }
}

/// Returned from inside a transaction callback instead of thrown — see the
/// comment in [DeviceBoardConfigRepository.applyPreset].
class _VersionConflictSentinel {
  const _VersionConflictSentinel(this.actualVersion);
  final int actualVersion;
}
