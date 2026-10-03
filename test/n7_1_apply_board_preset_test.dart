// N7.1 §20 "Aplicación: deep copy; trazabilidad; A/B independientes;
// borrar/editar preset no afecta Devices" + "Perfil: compatibilidad;
// métrica faltante bloquea; indicator faltante bloquea" — exercises the
// pure `applyBoardPresetToDevice`/`missingCapabilityIssues` orchestration
// (Firestore-free by design; see the function's own doc comment).
import 'package:flutter_test/flutter_test.dart';

import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/device_board_config/apply_board_preset_to_device.dart';
import 'package:agro_data_control/device_capabilities/capability_indicator_definition.dart';
import 'package:agro_data_control/device_capabilities/capability_library_store.dart';
import 'package:agro_data_control/device_capabilities/capability_metric_definition.dart';
import 'package:agro_data_control/device_capabilities/device_capability_profile.dart';
import 'package:agro_data_control/device_capabilities/indicator_binding.dart';
import 'package:agro_data_control/device_capabilities/metric_binding.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/ui_templates/enums/metric_display_type.dart';

void main() {
  late MetricLibraryStore metrics;
  late IndicatorLibraryStore indicators;
  late CellLayoutCatalog cellLayouts;

  setUp(() {
    metrics = MetricLibraryStore();
    metrics.upsert(
      CapabilityMetricDefinition(
        key: 'tempInterior',
        label: 'Temperatura interior',
        defaultUnit: '°C',
        icon: 'thermometer',
        displayType: MetricDisplayType.number,
        decimals: 1,
      ),
    );
    indicators = IndicatorLibraryStore();
    indicators.upsert(
      CapabilityIndicatorDefinition(
        key: 'heater',
        label: 'Heater',
        defaultIcon: 'flame',
      ),
    );
    indicators.upsert(
      CapabilityIndicatorDefinition(
        key: 'fan',
        label: 'Fan',
        defaultIcon: 'air',
      ),
    );
    cellLayouts = CellLayoutCatalog(const []);
  });

  BoardPreset presetWithMetricAndIndicators({
    List<String> indicatorKeys = const ['heater'],
  }) => BoardPreset(
    id: 'preset_a',
    name: 'Preset A',
    layoutTemplateId: 'grid_6x4',
    presetVersion: 3,
    items: [
      BoardContentItem(
        id: 'metric-0',
        placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 2),
        content: MetricBoardContent(
          metricKey: 'tempInterior',
          indicatorKeys: indicatorKeys,
        ),
      ),
    ],
  );

  DeviceCapabilityProfile profileWith({
    List<String> indicatorKeys = const ['heater', 'fan'],
  }) => DeviceCapabilityProfile(
    id: 'sala_a',
    name: 'Sala A',
    metricKeys: const ['tempInterior'],
    indicatorKeys: indicatorKeys,
    metricBindings: {
      'tempInterior': MetricBinding(sourceField: 'temp_interior'),
    },
    indicatorBindings: {
      for (final key in indicatorKeys)
        key: IndicatorBinding(sourceField: '${key}_on'),
    },
  );

  group('N7.1 §8/§9 — successful apply: deep copy + trazability', () {
    test('copies items by value and stamps trazability fields', () {
      final preset = presetWithMetricAndIndicators();
      final profile = profileWith();
      final result = applyBoardPresetToDevice(
        deviceId: 'device-1',
        preset: preset,
        profile: profile,
        metricsLibrary: metrics,
        indicatorsLibrary: indicators,
        cellLayoutCatalog: cellLayouts,
        nextLayoutVersion: 1,
        capabilityProfileId: 'sala_a',
      );
      expect(result.isBlocked, isFalse);
      final layout = result.layout!;
      expect(layout.deviceId, 'device-1');
      expect(layout.items, hasLength(1));
      expect(layout.sourceBoardPresetId, 'preset_a');
      expect(layout.sourceBoardPresetVersion, 3);
      expect(layout.capabilityProfileId, 'sala_a');
      expect(layout.layoutVersion, 1);
    });

    test('N7.1 §9: two Devices applying the same preset get independent '
        'layouts — mutating one never touches the other', () {
      final preset = presetWithMetricAndIndicators();
      final profile = profileWith();
      final layoutA = applyBoardPresetToDevice(
        deviceId: 'device-a',
        preset: preset,
        profile: profile,
        metricsLibrary: metrics,
        indicatorsLibrary: indicators,
        cellLayoutCatalog: cellLayouts,
        nextLayoutVersion: 1,
      ).layout!;
      final layoutB = applyBoardPresetToDevice(
        deviceId: 'device-b',
        preset: preset,
        profile: profile,
        metricsLibrary: metrics,
        indicatorsLibrary: indicators,
        cellLayoutCatalog: cellLayouts,
        nextLayoutVersion: 1,
      ).layout!;

      // "Editing" A means building a brand new layout from A's own items
      // (exactly how the Board Editor works) — never mutates the
      // original list in place.
      final editedA = MetricBoardContent(
        metricKey: 'tempInterior',
        indicatorKeys: const ['heater', 'fan'],
      );
      final mutatedItemsA = [
        BoardContentItem(
          id: layoutA.items.first.id,
          placement: layoutA.items.first.placement,
          content: editedA,
        ),
      ];
      expect(mutatedItemsA.first.content, isA<MetricBoardContent>());
      // B's own item list is a completely different List instance/objects
      // — never affected by constructing edits for A.
      expect(
        (layoutB.items.first.content as MetricBoardContent).indicatorKeys,
        ['heater'],
      );
      expect(
        identical(layoutA.items, layoutB.items),
        isFalse,
        reason: 'A and B must never share the same items list instance',
      );
    });

    test('N7.1 §9: mutating the source BoardPreset afterwards (via copyWith) '
        'never affects an already-built layout', () {
      final preset = presetWithMetricAndIndicators();
      final profile = profileWith();
      final layout = applyBoardPresetToDevice(
        deviceId: 'device-1',
        preset: preset,
        profile: profile,
        metricsLibrary: metrics,
        indicatorsLibrary: indicators,
        cellLayoutCatalog: cellLayouts,
        nextLayoutVersion: 1,
      ).layout!;

      // "Editing the preset" always produces a NEW BoardPreset instance
      // (copyWith), never mutates `preset` in place — the already-built
      // `layout` above keeps referencing the original items untouched.
      final editedPreset = preset.copyWith(items: const [], presetVersion: 4);
      expect(editedPreset.items, isEmpty);
      expect(layout.items, hasLength(1));
      expect(layout.sourceBoardPresetVersion, 3);
    });
  });

  test('N7.1.1 A2 — applying snapshots CellLayoutPreset composition', () {
    final cell = CellLayoutPreset(
      id: 'cell-a',
      name: 'Celda A',
      widthCells: 2,
      heightCells: 2,
      presetVersion: 7,
      elements: buildDefaultCellLayoutElements(2, 2),
    );
    final preset = BoardPreset(
      id: 'preset-cell',
      name: 'Preset con celda',
      layoutTemplateId: 'grid_6x4',
      items: [
        BoardContentItem(
          id: 'metric-0',
          placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 2),
          content: MetricBoardContent(
            metricKey: 'tempInterior',
            cellLayoutPresetId: cell.id,
          ),
        ),
      ],
    );
    final result = applyBoardPresetToDevice(
      deviceId: 'device-1',
      preset: preset,
      profile: profileWith(),
      metricsLibrary: metrics,
      indicatorsLibrary: indicators,
      cellLayoutCatalog: CellLayoutCatalog([cell]),
      nextLayoutVersion: 1,
      capabilityProfileId: 'sala_a',
    );

    expect(result.isBlocked, isFalse);
    final content = result.layout!.items.single.content as MetricBoardContent;
    expect(content.cellLayoutSnapshot?.toMap(), cell.toMap());
    expect(content.sourceCellLayoutPresetVersion, 7);
    expect(content.cellLayoutPresetId, 'cell-a', reason: 'trazabilidad');

    final editedGlobal = CellLayoutPreset(
      id: 'cell-a',
      name: 'Celda global modificada',
      widthCells: 2,
      heightCells: 2,
      presetVersion: 8,
      elements: buildDefaultCellLayoutElements(2, 2, icon: true),
    );
    expect(editedGlobal.toMap(), isNot(content.cellLayoutSnapshot!.toMap()));
    expect(content.cellLayoutSnapshot!.name, 'Celda A');
  });

  group('N7.1 §11 — missing capability blocks the apply', () {
    test('metric not in profile blocks with metric_not_found', () {
      final preset = presetWithMetricAndIndicators();
      final profileWithoutMetric = DeviceCapabilityProfile(
        id: 'sala_b',
        name: 'Sala B',
        indicatorKeys: const ['heater'],
        indicatorBindings: {'heater': IndicatorBinding(sourceField: 'x')},
      );
      final result = applyBoardPresetToDevice(
        deviceId: 'device-1',
        preset: preset,
        profile: profileWithoutMetric,
        metricsLibrary: metrics,
        indicatorsLibrary: indicators,
        cellLayoutCatalog: cellLayouts,
        nextLayoutVersion: 1,
      );
      expect(result.isBlocked, isTrue);
      expect(result.issues.any((i) => i.code == 'metric_not_found'), isTrue);
    });

    test('indicator not in profile blocks with indicator_not_available', () {
      final preset = presetWithMetricAndIndicators(
        indicatorKeys: const ['heater', 'fan'],
      );
      final profileMissingFan = profileWith(indicatorKeys: const ['heater']);
      final result = applyBoardPresetToDevice(
        deviceId: 'device-1',
        preset: preset,
        profile: profileMissingFan,
        metricsLibrary: metrics,
        indicatorsLibrary: indicators,
        cellLayoutCatalog: cellLayouts,
        nextLayoutVersion: 1,
      );
      expect(result.isBlocked, isTrue);
      expect(
        result.issues.any((i) => i.code == 'indicator_not_available'),
        isTrue,
      );
    });

    test(
      '"Sin perfil" (null) blocks every metric/indicator the preset uses',
      () {
        final preset = presetWithMetricAndIndicators();
        final result = applyBoardPresetToDevice(
          deviceId: 'device-1',
          preset: preset,
          profile: null,
          metricsLibrary: metrics,
          indicatorsLibrary: indicators,
          cellLayoutCatalog: cellLayouts,
          nextLayoutVersion: 1,
        );
        expect(result.isBlocked, isTrue);
        expect(result.issues, isNotEmpty);
      },
    );

    test('missingCapabilityIssues never mutates preset/profile (pure query, '
        'usable to filter compatible presets in the UI dropdown)', () {
      final preset = presetWithMetricAndIndicators();
      final compatible = profileWith();
      final incompatible = profileWith(indicatorKeys: const ['heater']);
      expect(
        missingCapabilityIssues(preset: preset, profile: compatible),
        isEmpty,
      );
      expect(
        missingCapabilityIssues(
          preset: presetWithMetricAndIndicators(
            indicatorKeys: const ['heater', 'fan'],
          ),
          profile: incompatible,
        ),
        isNotEmpty,
      );
    });
  });
}
