import 'package:agro_data_control_backend/src/differential_pressure_history_service.dart';
import 'package:agro_data_control_backend/src/firestore_differential_pressure_history_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';

Future<void> main() async {
  await _testBackoffAfterLoadFailure();
  await _testBackoffAfterSaveFailure();
  await _testRecoversAfterBackoffWindow();
  // ignore: avoid_print
  print('All differential_pressure_history_service tests passed.');
}

DifferentialPressureHistoryConfig _config() {
  return DifferentialPressureHistoryConfig(
    enabled: true,
    sourcePath: 'munters1.presionDiferencial',
    tenantId: 'tenant-a',
    siteId: 'site-a',
    plcId: 'munters1',
    firestoreProjectId: 'test-project',
    firestoreDatabaseId: '(default)',
    firestoreServiceAccountPath: 'fake-path.json',
  );
}

Map<String, Object?> _unitsJson(num pressure) {
  return <String, Object?>{
    'munters1': <String, Object?>{'presionDiferencial': pressure},
  };
}

Future<void> _testBackoffAfterLoadFailure() async {
  final _FailingLoadRepository repository = _FailingLoadRepository(
    config: _config(),
  );
  final DifferentialPressureHistoryService service =
      DifferentialPressureHistoryService(
        config: _config(),
        repository: repository,
      );

  final DateTime baseTime = DateTime.utc(2026, 7, 16, 12, 0, 0);
  for (int i = 0; i < 20; i += 1) {
    service.handleSnapshot(
      unitsJson: _unitsJson(200 + i),
      observedAtUtc: baseTime.add(Duration(seconds: i * 3)),
    );
  }
  await service.dispose();

  _expect(
    repository.loadAttempts == 1,
    'expected exactly 1 loadDaily attempt within the backoff window after a '
    'failure, got ${repository.loadAttempts}',
  );
}

Future<void> _testBackoffAfterSaveFailure() async {
  final _FailingSaveRepository repository = _FailingSaveRepository(
    config: _config(),
  );
  final DifferentialPressureHistoryService service =
      DifferentialPressureHistoryService(
        config: _config(),
        repository: repository,
      );

  final DateTime baseTime = DateTime.utc(2026, 7, 16, 12, 0, 0);
  for (int i = 0; i < 20; i += 1) {
    service.handleSnapshot(
      unitsJson: _unitsJson(200 + i),
      observedAtUtc: baseTime.add(Duration(seconds: i * 3)),
    );
  }
  await service.dispose();

  _expect(
    repository.saveAttempts == 1,
    'expected exactly 1 saveDaily attempt within the backoff window after a '
    'failure, got ${repository.saveAttempts}',
  );
}

Future<void> _testRecoversAfterBackoffWindow() async {
  final _FailingLoadRepository repository = _FailingLoadRepository(
    config: _config(),
  );
  final DifferentialPressureHistoryService service =
      DifferentialPressureHistoryService(
        config: _config(),
        repository: repository,
      );

  final DateTime baseTime = DateTime.utc(2026, 7, 16, 12, 0, 0);
  service.handleSnapshot(
    unitsJson: _unitsJson(200),
    observedAtUtc: baseTime,
  );
  await service.dispose();
  _expect(repository.loadAttempts == 1, 'first attempt should run');

  service.handleSnapshot(
    unitsJson: _unitsJson(200),
    observedAtUtc: baseTime.add(const Duration(minutes: 6)),
  );
  await service.dispose();
  _expect(
    repository.loadAttempts == 2,
    'a new attempt should run once the backoff window has elapsed',
  );
}

class _FailingLoadRepository
    extends FirestoreDifferentialPressureHistoryRepository {
  _FailingLoadRepository({required super.config});

  int loadAttempts = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<DifferentialPressureDailyRecord?> loadDaily(String dateKey) async {
    loadAttempts += 1;
    throw FirestoreDifferentialPressureHistoryException(
      'Firestore GET failed status=429 path=fake body={"error":{"code":429}}',
    );
  }
}

class _FailingSaveRepository
    extends FirestoreDifferentialPressureHistoryRepository {
  _FailingSaveRepository({required super.config});

  int saveAttempts = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<DifferentialPressureDailyRecord?> loadDaily(String dateKey) async {
    return null;
  }

  @override
  Future<void> saveDaily(DifferentialPressureDailyRecord record) async {
    saveAttempts += 1;
    throw FirestoreDifferentialPressureHistoryException(
      'Firestore commit failed status=429 path=fake body={"error":{"code":429}}',
    );
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('Assertion failed: $message');
  }
}
