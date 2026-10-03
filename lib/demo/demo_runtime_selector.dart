import '../models/dashboard_snapshot.dart';
import 'demo_access_gate.dart';
import 'demo_signal_definition.dart';
import 'demo_snapshot_builder.dart';

/// Stable identity of the one Device/Room whose presentation is simulated.
/// Labels and list positions are deliberately absent.
class DemoRuntimeScope {
  DemoRuntimeScope({
    required this.tenantId,
    required this.siteId,
    required this.deviceId,
    required this.snapshotUnitKey,
  }) {
    for (final entry in <String, String>{
      'tenantId': tenantId,
      'siteId': siteId,
      'deviceId': deviceId,
      'snapshotUnitKey': snapshotUnitKey,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        throw ArgumentError.value(entry.value, entry.key, 'Must not be empty');
      }
    }
  }

  final String tenantId;
  final String siteId;
  final String deviceId;
  final String snapshotUnitKey;
}

/// In-memory real/demo selector for Stage 2B.
///
/// It never owns or updates the real snapshot. The caller continues storing
/// real snapshots in its existing polling state and passes the latest one to
/// [selectForPresentation]. While active, this class returns one frozen demo
/// snapshot; after [stop], the very next selection returns the caller's latest
/// real instance exactly.
class DemoRuntimeSelector {
  DemoRuntimeSelector({bool buildEnabled = agroDemoBuildEnabled})
    : _buildEnabled = buildEnabled;

  final bool _buildEnabled;
  DemoRuntimeScope? _scope;
  DashboardSnapshot? _baselineSnapshot;
  DashboardSnapshot? _displaySnapshot;
  bool _disposed = false;

  bool get isActive => _displaySnapshot != null;
  DemoRuntimeScope? get scope => _scope;
  DashboardSnapshot? get baselineSnapshot => _baselineSnapshot;

  bool isAvailableForRole(String? role) =>
      DemoAccessGate.canAccess(role: role, buildEnabled: _buildEnabled);

  /// Freezes [realSnapshot], then derives a separate presentation snapshot.
  /// Returns false when the build/role gate is closed and changes no state.
  bool activate({
    required String? role,
    required DashboardSnapshot realSnapshot,
    required DemoRuntimeScope scope,
    required Map<DemoSignalKey, Object?> overrides,
  }) {
    _ensureUsable();
    if (!isAvailableForRole(role)) return false;

    final baseline = DemoSnapshotBuilder.applyOverrides(
      realSnapshot: realSnapshot,
      targetSnapshotUnitKey: scope.snapshotUnitKey,
      overrides: const <DemoSignalKey, Object?>{},
    );
    final display = DemoSnapshotBuilder.applyOverrides(
      realSnapshot: baseline,
      targetSnapshotUnitKey: scope.snapshotUnitKey,
      overrides: overrides,
    );
    _scope = scope;
    _baselineSnapshot = baseline;
    _displaySnapshot = display;
    return true;
  }

  DashboardSnapshot selectForPresentation(DashboardSnapshot realSnapshot) {
    _ensureUsable();
    return _displaySnapshot ?? realSnapshot;
  }

  /// Replaces only the in-memory presentation frame of the active session.
  /// The frozen baseline and scope remain unchanged.
  void updatePresentation(Map<DemoSignalKey, Object?> overrides) {
    _ensureUsable();
    final scope = _scope;
    final baseline = _baselineSnapshot;
    if (scope == null || baseline == null) {
      throw StateError('Demo is not active');
    }
    _displaySnapshot = DemoSnapshotBuilder.applyOverrides(
      realSnapshot: baseline,
      targetSnapshotUnitKey: scope.snapshotUnitKey,
      overrides: overrides,
    );
  }

  void stop() {
    _scope = null;
    _baselineSnapshot = null;
    _displaySnapshot = null;
  }

  void onTenantChanged(String tenantId) {
    if (_scope?.tenantId != tenantId) stop();
  }

  void onSiteChanged(String siteId) {
    if (_scope?.siteId != siteId) stop();
  }

  void onDeviceChanged({
    required String deviceId,
    required String snapshotUnitKey,
  }) {
    final current = _scope;
    if (current != null &&
        (current.deviceId != deviceId ||
            current.snapshotUnitKey != snapshotUnitKey)) {
      stop();
    }
  }

  void onLogout() => stop();

  void dispose() {
    stop();
    _disposed = true;
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('DemoRuntimeSelector has been disposed');
    }
  }
}

enum DemoLiveView { board, table, detail, comparison }

/// Explicit data-flow boundary: live views receive [displaySnapshot], while
/// every productive side effect and historical flow receives [realSnapshot].
class DemoSnapshotSelection {
  DemoSnapshotSelection._({
    required this.realSnapshot,
    required this.displaySnapshot,
  });

  factory DemoSnapshotSelection.resolve({
    required DashboardSnapshot realSnapshot,
    required DemoRuntimeSelector selector,
  }) => DemoSnapshotSelection._(
    realSnapshot: realSnapshot,
    displaySnapshot: selector.selectForPresentation(realSnapshot),
  );

  final DashboardSnapshot realSnapshot;
  final DashboardSnapshot displaySnapshot;

  DashboardSnapshot forLiveView(DemoLiveView view) => displaySnapshot;
  DashboardSnapshot get forProductiveSideEffects => realSnapshot;
  DashboardSnapshot get forHistoricalViews => realSnapshot;
}
