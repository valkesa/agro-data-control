// N7.1 §12/§20 — widget tests for [DeviceBoardConfigPage]: apply a
// compatible preset, block on a missing capability, filter the preset
// dropdown to only compatible presets, and surface a
// [FirestoreVersionConflict]. Fakes subclass the real repository classes
// and override just the methods this page calls — same convention as
// `_FakeDeviceTemplateRepository` in `test/device_template_registry_test.dart`
// — so no real Firestore/emulator is involved.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/device_board_config/apply_board_preset_to_device.dart';
import 'package:agro_data_control/device_capabilities/capability_library_store.dart';
import 'package:agro_data_control/device_capabilities/device_capability_profile.dart';
import 'package:agro_data_control/device_capabilities/indicator_binding.dart';
import 'package:agro_data_control/device_capabilities/metric_binding.dart';
import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/pages/device_board_config_page.dart';
import 'package:agro_data_control/services/board_preset_repository.dart';
import 'package:agro_data_control/services/capability_profile_repository.dart';
import 'package:agro_data_control/services/device_board_config_repository.dart';
import 'package:agro_data_control/services/firestore_version_conflict.dart';

class _FakeCapabilityProfileRepository extends CapabilityProfileRepository {
  _FakeCapabilityProfileRepository(this.profiles) : super();
  final List<DeviceCapabilityProfile> profiles;

  @override
  Future<List<CapabilityProfileRecord>> fetchAll() async => [
    for (final profile in profiles) CapabilityProfileRecord(profile: profile),
  ];
}

class _FakeBoardPresetRepository extends BoardPresetRepository {
  _FakeBoardPresetRepository(this.presets) : super();
  final List<BoardPreset> presets;

  @override
  Future<List<BoardPreset>> fetchAll() async => presets;
}

class _FakeDeviceBoardConfigRepository extends DeviceBoardConfigRepository {
  _FakeDeviceBoardConfigRepository({this.applyError}) : super();
  BoardContentLayout? initial;
  final Object? applyError;
  int applyCallCount = 0;

  @override
  Future<BoardContentLayout?> fetchOne({
    required String tenantId,
    required String deviceId,
  }) async => initial;

  @override
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
    applyCallCount++;
    if (applyError != null) throw applyError!;
    final result = applyBoardPresetToDevice(
      deviceId: deviceId,
      preset: preset,
      profile: profile,
      metricsLibrary: metricsLibrary,
      indicatorsLibrary: indicatorsLibrary,
      cellLayoutCatalog: cellLayoutCatalog,
      nextLayoutVersion: expectedLayoutVersion + 1,
      capabilityProfileId: profileId,
    );
    if (!result.isBlocked) initial = result.layout;
    return result;
  }

  @override
  Future<int> saveLayout({
    required String tenantId,
    required String deviceId,
    required BoardContentLayout layout,
    required int expectedLayoutVersion,
    required DeviceMetricCatalog metricCatalog,
    required CellLayoutCatalog cellLayoutCatalog,
  }) async => expectedLayoutVersion + 1;
}

AgroDevice _device() => AgroDevice(
  id: 'device-1',
  tenantId: 'tenant-a',
  siteId: 'site-a',
  name: 'Sala 1',
  type: 'other',
  model: '',
  description: '',
  enabled: true,
  createdAt: null,
  updatedAt: null,
);

BoardPreset _presetCompatibleWith(DeviceCapabilityProfile profile) =>
    BoardPreset(
      id: 'preset_a',
      name: 'Preset A',
      layoutTemplateId: 'grid_6x4',
      presetVersion: 1,
      items: [
        BoardContentItem(
          id: 'metric-0',
          placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 2),
          content: MetricBoardContent(
            metricKey: 'tempInterior',
            indicatorKeys: const ['calefaccionEtapa1'],
          ),
        ),
      ],
    );

DeviceCapabilityProfile _salaA() => DeviceCapabilityProfile(
  id: 'sala_a',
  name: 'Sala A',
  metricKeys: const ['tempInterior'],
  indicatorKeys: const ['calefaccionEtapa1'],
  metricBindings: {'tempInterior': MetricBinding(sourceField: 'temp_interior')},
  indicatorBindings: {
    'calefaccionEtapa1': IndicatorBinding(sourceField: 'calefaccionEtapa1_on'),
  },
);

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

void main() {
  group('N7.1 §12/§8 — DeviceBoardConfigPage apply flow', () {
    testWidgets('shows "sin configurar" then applies a compatible preset', (
      tester,
    ) async {
      final profile = _salaA();
      final preset = _presetCompatibleWith(profile);
      final deviceRepo = _FakeDeviceBoardConfigRepository();
      await pump(
        tester,
        DeviceBoardConfigPage(
          isOwner: true,
          tenantId: 'tenant-a',
          device: _device(),
          deviceBoardConfigRepository: deviceRepo,
          capabilityProfileRepository: _FakeCapabilityProfileRepository([
            profile,
          ]),
          boardPresetRepository: _FakeBoardPresetRepository([preset]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Este Device todavía no tiene un Board configurado.'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('device-board-config-profile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sala A').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('device-board-config-preset')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preset A').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('device-board-config-apply')));
      await tester.pumpAndSettle();

      expect(deviceRepo.applyCallCount, 1);
      expect(find.textContaining('DeviceBoardLayout v1'), findsOneWidget);
      expect(find.text('Preset aplicado: Preset A (v1)'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<String?>>(
              find.byKey(const ValueKey('device-board-config-preset')),
            )
            .value,
        'preset_a',
      );
    });

    testWidgets('a preset missing a capability the chosen profile lacks is not '
        'offered in the dropdown (compatibility filter)', (tester) async {
      final profile = DeviceCapabilityProfile(
        id: 'sala_b',
        name: 'Sala B',
        metricKeys: const ['tempInterior'],
        metricBindings: {
          'tempInterior': MetricBinding(sourceField: 'temp_interior'),
        },
      ); // no `calefaccionEtapa1` indicator
      final incompatiblePreset = _presetCompatibleWith(_salaA());
      await pump(
        tester,
        DeviceBoardConfigPage(
          isOwner: true,
          tenantId: 'tenant-a',
          device: _device(),
          deviceBoardConfigRepository: _FakeDeviceBoardConfigRepository(),
          capabilityProfileRepository: _FakeCapabilityProfileRepository([
            profile,
          ]),
          boardPresetRepository: _FakeBoardPresetRepository([
            incompatiblePreset,
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('device-board-config-profile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sala B').last);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('oculto(s) por no ser compatibles'),
        findsOneWidget,
      );
    });

    testWidgets('a FirestoreVersionConflict during apply shows the dialog', (
      tester,
    ) async {
      final profile = _salaA();
      final preset = _presetCompatibleWith(profile);
      await pump(
        tester,
        DeviceBoardConfigPage(
          isOwner: true,
          tenantId: 'tenant-a',
          device: _device(),
          deviceBoardConfigRepository: _FakeDeviceBoardConfigRepository(
            applyError: const FirestoreVersionConflict(
              entityType: 'deviceBoardConfig',
              entityId: 'tenant-a/device-1',
              expectedVersion: 0,
              actualVersion: 1,
            ),
          ),
          capabilityProfileRepository: _FakeCapabilityProfileRepository([
            profile,
          ]),
          boardPresetRepository: _FakeBoardPresetRepository([preset]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('device-board-config-profile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sala A').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('device-board-config-preset')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preset A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('device-board-config-apply')));
      await tester.pumpAndSettle();

      expect(find.text('configuration_conflict'), findsOneWidget);
    });
  });
}
