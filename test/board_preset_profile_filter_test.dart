import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/board_preview/board_editor_canvas.dart';
import 'package:agro_data_control/board_preview/board_editor_controller.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/device_board_config/apply_board_preset_to_device.dart';
import 'package:agro_data_control/device_capabilities/capability_library_store.dart';
import 'package:agro_data_control/device_capabilities/capability_metric_definition.dart';
import 'package:agro_data_control/device_capabilities/device_capability_profile.dart';
import 'package:agro_data_control/device_capabilities/device_capability_profile_store.dart';
import 'package:agro_data_control/device_capabilities/global_capability_catalog.dart';
import 'package:agro_data_control/device_capabilities/metric_binding.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/ui_templates/enums/metric_display_type.dart';

typedef _Fixture = ({
  MetricLibraryStore metrics,
  IndicatorLibraryStore indicators,
  DeviceCapabilityProfile environment,
  DeviceCapabilityProfile arch,
  DeviceCapabilityProfileStore profiles,
});

_Fixture _fixture() {
  final metrics = MetricLibraryStore(
    initial: [
      CapabilityMetricDefinition(
        key: 'tempInterior',
        label: 'Temperatura interior',
        defaultUnit: '°C',
        icon: 'thermometer',
        displayType: MetricDisplayType.number,
        decimals: 1,
      ),
      CapabilityMetricDefinition(
        key: 'vehiclesTotalDaily',
        label: 'Vehículos diarios',
        defaultUnit: '',
        icon: 'truck',
        displayType: MetricDisplayType.number,
        decimals: 0,
      ),
    ],
  );
  final indicators = IndicatorLibraryStore();
  final environment = DeviceCapabilityProfile(
    id: 'environment_room_v1',
    name: 'Ambiente',
    metricKeys: const ['tempInterior'],
    metricBindings: {
      'tempInterior': MetricBinding(sourceField: 'environment.temp'),
    },
  );
  final arch = DeviceCapabilityProfile(
    id: 'disinfection_arch_v1',
    name: 'Arco',
    metricKeys: const ['vehiclesTotalDaily'],
    metricBindings: {
      'vehiclesTotalDaily': MetricBinding(sourceField: 'arch.daily'),
    },
  );
  return (
    metrics: metrics,
    indicators: indicators,
    environment: environment,
    arch: arch,
    profiles: DeviceCapabilityProfileStore(initial: [environment, arch]),
  );
}

BoardPreset _mixedPreset() => BoardPreset(
  id: 'mixed',
  name: 'Mixto',
  layoutTemplateId: 'grid_6x4',
  capabilityProfileId: 'environment_room_v1',
  requiredMetricKeys: const ['tempInterior'],
  optionalMetricKeys: const ['vehiclesTotalDaily'],
  items: [
    BoardContentItem(
      id: 'metric-temp',
      placement: GridPlacement(x: 0, y: 0, widthCells: 1, heightCells: 1),
      content: MetricBoardContent(metricKey: 'tempInterior'),
    ),
    BoardContentItem(
      id: 'metric-vehicles',
      placement: GridPlacement(x: 1, y: 0, widthCells: 1, heightCells: 1),
      content: MetricBoardContent(metricKey: 'vehiclesTotalDaily'),
    ),
  ],
);

Future<void> _pumpEditor(
  WidgetTester tester, {
  required BoardPresetCatalog presets,
  required _Fixture data,
}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: BoardEditorPage(
        isOwner: true,
        presetId: presets.presets.single.id,
        presetCatalog: presets,
        capabilityProfileStore: data.profiles,
        metricLibrary: data.metrics,
        indicatorLibrary: data.indicators,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

BoardEditorController _controller(WidgetTester tester) =>
    tester.widget<BoardEditorCanvas>(find.byType(BoardEditorCanvas)).controller;

void main() {
  test('catálogo global valida un BoardPreset que mezcla perfiles', () {
    final data = _fixture();
    final catalog = buildGlobalCapabilityCatalog(
      metrics: data.metrics,
      indicators: data.indicators,
    );
    final editor = BoardEditorController.forPreset(
      preset: _mixedPreset(),
      catalog: catalog,
    );
    addTearDown(editor.dispose);

    expect(editor.issues(CellLayoutCatalog(const [])), isEmpty);
    expect(catalog.metrics.map((item) => item.key), {
      'tempInterior',
      'vehiclesTotalDaily',
    });
  });

  testWidgets(
    'cambiar filtros repetidamente no cambia Board, dirty ni versión',
    (tester) async {
      final data = _fixture();
      final presets = BoardPresetCatalog(initial: [_mixedPreset()]);
      await _pumpEditor(tester, presets: presets, data: data);
      final before = presets.presets.single.toMap();
      final version = presets.presets.single.presetVersion;

      for (final label in ['Arco', 'Todas las métricas', 'Ambiente']) {
        await tester.tap(
          find.byKey(const ValueKey('editor-capability-profile')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining(label).last);
        await tester.pumpAndSettle();
      }

      expect(presets.presets.single.toMap(), before);
      expect(presets.presets.single.presetVersion, version);
      expect(_controller(tester).dirty, isFalse);
      expect(_controller(tester).issues(CellLayoutCatalog(const [])), isEmpty);
    },
  );

  testWidgets('Todas las métricas muestra claves de más de un perfil', (
    tester,
  ) async {
    final data = _fixture();
    final preset = _mixedPreset().copyWith(items: const []);
    final presets = BoardPresetCatalog(initial: [preset]);
    await _pumpEditor(tester, presets: presets, data: data);

    await tester.tap(find.byKey(const ValueKey('editor-capability-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas las métricas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byKey(const ValueKey('editor-pending-metric-key')),
    );
    expect(dropdown.items!.map((item) => item.value), {
      'tempInterior',
      'vehiclesTotalDaily',
    });
  });

  testWidgets(
    'smoke: Ambiente + Arco se guarda y reabre sin metric_not_found',
    (tester) async {
      final data = _fixture();
      final empty = _mixedPreset().copyWith(items: const []);
      final presets = BoardPresetCatalog(initial: [empty]);
      await _pumpEditor(tester, presets: presets, data: data);

      await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey('editor-pending-metric-key')),
            )
            .value,
        'tempInterior',
      );
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('editor-capability-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Arco').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-side-tab-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-add-type-metric')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey('editor-pending-metric-key')),
            )
            .value,
        'vehiclesTotalDaily',
      );
      await tester.tap(find.byKey(const ValueKey('editor-pending-x-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-confirm-add')));
      await tester.pumpAndSettle();

      final saved = BoardPreset.fromMap(presets.presets.single.toMap());
      expect(
        saved.items.map(
          (item) => (item.content as MetricBoardContent).metricKey,
        ),
        ['tempInterior', 'vehiclesTotalDaily'],
      );
      expect(_controller(tester).issues(CellLayoutCatalog(const [])), isEmpty);

      await tester.pumpWidget(const SizedBox());
      final reopened = BoardPresetCatalog(initial: [saved]);
      await _pumpEditor(tester, presets: reopened, data: data);
      expect(_controller(tester).issues(CellLayoutCatalog(const [])), isEmpty);
      expect(
        reopened.presets.single.items.map(
          (item) => (item.content as MetricBoardContent).metricKey,
        ),
        ['tempInterior', 'vehiclesTotalDaily'],
      );
    },
  );

  test('Device Ambiente rechaza la métrica exclusiva de Arco', () {
    final data = _fixture();
    final result = applyBoardPresetToDevice(
      deviceId: 'device-environment',
      preset: _mixedPreset(),
      profile: data.environment,
      metricsLibrary: data.metrics,
      indicatorsLibrary: data.indicators,
      cellLayoutCatalog: CellLayoutCatalog(const []),
      nextLayoutVersion: 1,
      capabilityProfileId: data.environment.id,
    );

    expect(result.isBlocked, isTrue);
    expect(
      result.issues,
      contains(
        isA<dynamic>()
            .having((issue) => issue.code, 'code', 'metric_not_found')
            .having(
              (issue) => issue.metricKey,
              'metricKey',
              'vehiclesTotalDaily',
            ),
      ),
    );
  });

  test('persistir y reabrir conserva ambas métricas válidas', () {
    final data = _fixture();
    final restored = BoardPreset.fromMap(_mixedPreset().toMap());
    final editor = BoardEditorController.forPreset(
      preset: restored,
      catalog: buildGlobalCapabilityCatalog(
        metrics: data.metrics,
        indicators: data.indicators,
      ),
    );
    addTearDown(editor.dispose);

    expect(
      restored.items.map(
        (item) => (item.content as MetricBoardContent).metricKey,
      ),
      ['tempInterior', 'vehiclesTotalDaily'],
    );
    expect(editor.issues(CellLayoutCatalog(const [])), isEmpty);
  });
}
