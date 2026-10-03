import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_preview/board_content_renderer.dart';
import 'package:agro_data_control/board_runtime/qa_device_board_runtime.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/device_capabilities/capability_records.dart';
import 'package:agro_data_control/device_capabilities/reference_capability_seeds.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';
import 'package:agro_data_control/services/capability_profile_repository.dart';
import 'package:agro_data_control/services/device_board_config_repository.dart';
import 'package:agro_data_control/services/global_board_configuration_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBoardRepository extends DeviceBoardConfigRepository {
  _FakeBoardRepository(this.board);

  final BoardContentLayout? board;
  int reads = 0;

  @override
  Future<BoardContentLayout?> fetchOne({
    required String tenantId,
    required String deviceId,
  }) async {
    reads++;
    return board;
  }
}

class _FakeGlobalService extends GlobalBoardConfigurationService {
  _FakeGlobalService(this.snapshot);

  final GlobalBoardConfigurationSnapshot snapshot;
  int loads = 0;

  @override
  Future<GlobalBoardConfigurationSnapshot> load({bool refresh = false}) async {
    loads++;
    return snapshot;
  }
}

BoardContentLayout _board({String metricKey = 'tempInterior'}) =>
    BoardContentLayout(
      deviceId: qaRuntimeDeviceId,
      layoutTemplateId: 'grid_6x4',
      layoutVersion: 3,
      capabilityProfileId: 'environment_room_v1',
      sourceBoardPresetId: 'preset-a',
      sourceBoardPresetVersion: 2,
      items: [
        BoardContentItem(
          id: 'metric-0',
          placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 2),
          content: MetricBoardContent(metricKey: metricKey),
        ),
      ],
    );

GlobalBoardConfigurationSnapshot _global() => GlobalBoardConfigurationSnapshot(
  layouts: [LayoutTemplate(id: 'grid_6x4', name: '6 × 4', columns: 6, rows: 4)],
  cellLayouts: const <CellLayoutPreset>[],
  metrics: [
    for (final metric in sharedMetricLibraryStore.metrics)
      CapabilityMetricRecord(metric: metric, schemaVersion: 1, enabled: true),
  ],
  indicators: [
    for (final indicator in sharedIndicatorLibraryStore.indicators)
      CapabilityIndicatorRecord(
        indicator: indicator,
        schemaVersion: 1,
        enabled: true,
      ),
  ],
  profiles: [CapabilityProfileRecord(profile: referenceCapabilityProfile)],
  boardPresets: const [],
);

QaDeviceBoardRuntimeLoader _loader(_FakeBoardRepository repository) =>
    QaDeviceBoardRuntimeLoader(
      boardConfigs: repository,
      globalConfiguration: _FakeGlobalService(_global()),
    );

void main() {
  testWidgets('A — QA con boardConfig válido usa BoardContentRenderer', (
    tester,
  ) async {
    final repository = _FakeBoardRepository(_board());
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 500,
          child: QaDeviceBoardRuntimeCard(
            tenantId: qaRuntimeTenantId,
            siteId: qaRuntimeSiteId,
            deviceId: qaRuntimeDeviceId,
            deviceName: 'QA Device',
            liveData: const {'tempInterior': 24.6},
            legacyChild: const Text('legacy'),
            loader: _loader(repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BoardContentRenderer), findsOneWidget);
    expect(find.text('legacy'), findsNothing);
    expect(repository.reads, 1);
  });

  testWidgets('B — QA sin boardConfig cae al renderer legacy', (tester) async {
    final repository = _FakeBoardRepository(null);
    await tester.pumpWidget(
      MaterialApp(
        home: QaDeviceBoardRuntimeCard(
          tenantId: qaRuntimeTenantId,
          siteId: qaRuntimeSiteId,
          deviceId: qaRuntimeDeviceId,
          deviceName: 'QA Device',
          liveData: const {},
          legacyChild: const Text('legacy'),
          loader: _loader(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('legacy'), findsOneWidget);
    expect(find.byType(BoardContentRenderer), findsNothing);
  });

  testWidgets('C — QA con board inválido cae al renderer legacy', (
    tester,
  ) async {
    final repository = _FakeBoardRepository(_board(metricKey: 'inexistente'));
    await tester.pumpWidget(
      MaterialApp(
        home: QaDeviceBoardRuntimeCard(
          tenantId: qaRuntimeTenantId,
          siteId: qaRuntimeSiteId,
          deviceId: qaRuntimeDeviceId,
          deviceName: 'QA Device',
          liveData: const {},
          legacyChild: const Text('legacy'),
          loader: _loader(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('legacy'), findsOneWidget);
    expect(find.byType(BoardContentRenderer), findsNothing);
  });

  testWidgets('D — Device no QA conserva legacy aunque tenga boardConfig', (
    tester,
  ) async {
    final repository = _FakeBoardRepository(_board());
    await tester.pumpWidget(
      MaterialApp(
        home: QaDeviceBoardRuntimeCard(
          tenantId: 'the-gene-pig',
          siteId: 'las-heras',
          deviceId: 'device-real',
          deviceName: 'Device real',
          liveData: const {},
          legacyChild: const Text('legacy'),
          loader: _loader(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('legacy'), findsOneWidget);
    expect(repository.reads, 0);
  });

  test('E — la caché de sesión evita releer en rebuilds', () async {
    final repository = _FakeBoardRepository(_board());
    final loader = _loader(repository);

    final first = loader.load(
      tenantId: qaRuntimeTenantId,
      siteId: qaRuntimeSiteId,
      deviceId: qaRuntimeDeviceId,
    );
    final second = loader.load(
      tenantId: qaRuntimeTenantId,
      siteId: qaRuntimeSiteId,
      deviceId: qaRuntimeDeviceId,
    );
    expect(identical(first, second), isTrue);
    expect((await first).status, QaDeviceBoardRuntimeStatus.loaded);
    expect(repository.reads, 1);

    loader.invalidate();
    await loader.load(
      tenantId: qaRuntimeTenantId,
      siteId: qaRuntimeSiteId,
      deviceId: qaRuntimeDeviceId,
    );
    expect(repository.reads, 2);
  });
}
