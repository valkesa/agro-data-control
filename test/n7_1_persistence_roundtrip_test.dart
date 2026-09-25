// N7.1 §20 "Persistencia: roundtrip; versiones; timestamps; delete;
// enabled" — pure Dart round-trip tests for every model N7.1 persists,
// deliberately Firestore-free (no emulator, no fakes): `toMap()`/`fromMap()`
// are plain functions on `Map<String, Object?>`, exactly the boundary every
// model's own doc comment describes ("a future Firestore adapter must
// convert SDK Timestamp values ... outside this model"). Firestore-specific
// behavior (rules enforcement, transactions, real reads/writes) is covered
// separately by `test/n7_1_firestore_rules_emulator_test.dart`.
import 'package:flutter_test/flutter_test.dart';

import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/device_capabilities/capability_indicator_definition.dart';
import 'package:agro_data_control/device_capabilities/capability_metric_definition.dart';
import 'package:agro_data_control/device_capabilities/capability_records.dart';
import 'package:agro_data_control/device_capabilities/device_capability_profile.dart';
import 'package:agro_data_control/device_capabilities/indicator_binding.dart';
import 'package:agro_data_control/device_capabilities/metric_binding.dart';
import 'package:agro_data_control/device_board_layouts/device_board_layout.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/services/firestore_version_conflict.dart';
import 'package:agro_data_control/ui_templates/enums/metric_display_type.dart';
import 'package:agro_data_control/ui_templates/enums/metric_status_behavior.dart';
import 'package:agro_data_control/ui_templates/enums/metric_transform.dart';

void main() {
  group('N7.1 §20 — MetricBinding/IndicatorBinding roundtrip', () {
    test('MetricBinding survives toMap/fromMap with every field set', () {
      final binding = MetricBinding(
        sourceField: 'room1.temp',
        transform: MetricTransform.voltageToPercent,
        unitOverride: '°F',
        valueLabelSourceField: 'room1.tempLabel',
      );
      final restored = MetricBinding.fromMap(binding.toMap());
      expect(restored.sourceField, 'room1.temp');
      expect(restored.transform, MetricTransform.voltageToPercent);
      expect(restored.unitOverride, '°F');
      expect(restored.valueLabelSourceField, 'room1.tempLabel');
    });

    test('MetricBinding survives roundtrip with optional fields absent', () {
      final binding = MetricBinding(sourceField: 'plc.temperature');
      final restored = MetricBinding.fromMap(binding.toMap());
      expect(restored.sourceField, 'plc.temperature');
      expect(restored.transform, MetricTransform.none);
      expect(restored.unitOverride, isNull);
      expect(restored.valueLabelSourceField, isNull);
    });

    test('IndicatorBinding survives toMap/fromMap', () {
      final binding = IndicatorBinding(
        sourceField: 'calefaccionEtapa1',
        condition: true,
      );
      final restored = IndicatorBinding.fromMap(binding.toMap());
      expect(restored.sourceField, 'calefaccionEtapa1');
      expect(restored.condition, true);
    });
  });

  group(
    'N7.1 §20 — CapabilityMetricDefinition/CapabilityIndicatorDefinition',
    () {
      test('CapabilityMetricDefinition survives toMap/fromMap', () {
        final metric = CapabilityMetricDefinition(
          key: 'tempInterior',
          label: 'Temperatura interior',
          shortLabel: 'Temp. int.',
          defaultUnit: '°C',
          icon: 'thermometer',
          displayType: MetricDisplayType.number,
          decimals: 1,
          statusBehavior: MetricStatusBehavior.alarmState,
        );
        final restored = CapabilityMetricDefinition.fromMap(metric.toMap());
        expect(restored.key, 'tempInterior');
        expect(restored.label, 'Temperatura interior');
        expect(restored.shortLabel, 'Temp. int.');
        expect(restored.defaultUnit, '°C');
        expect(restored.icon, 'thermometer');
        expect(restored.displayType, MetricDisplayType.number);
        expect(restored.decimals, 1);
        expect(restored.statusBehavior, MetricStatusBehavior.alarmState);
      });

      test('CapabilityIndicatorDefinition survives toMap/fromMap', () {
        final indicator = CapabilityIndicatorDefinition(
          key: 'heater',
          label: 'Heater',
          defaultIcon: 'flame',
        );
        final restored = CapabilityIndicatorDefinition.fromMap(
          indicator.toMap(),
        );
        expect(restored.key, 'heater');
        expect(restored.label, 'Heater');
        expect(restored.defaultIcon, 'flame');
      });
    },
  );

  group('N7.1 §20 — CapabilityMetricRecord/CapabilityIndicatorRecord: '
      'schemaVersion/enabled/recordVersion/timestamps', () {
    test('roundtrips every lifecycle field', () {
      final record = CapabilityMetricRecord(
        metric: CapabilityMetricDefinition(
          key: 'tempInterior',
          label: 'Temperatura interior',
          defaultUnit: '°C',
          icon: 'thermometer',
          displayType: MetricDisplayType.number,
          decimals: 1,
        ),
        schemaVersion: 1,
        enabled: false,
        recordVersion: 3,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 9, 19),
      );
      final restored = CapabilityMetricRecord.fromMap(record.toMap());
      expect(restored, isNotNull);
      expect(restored!.metric.key, 'tempInterior');
      expect(restored.enabled, false);
      expect(restored.recordVersion, 3);
      expect(restored.createdAt, DateTime.utc(2026, 1, 1));
      expect(restored.updatedAt, DateTime.utc(2026, 9, 19));
    });

    test(
      'defensive parse: unsupported schemaVersion returns null, never throws',
      () {
        final map = <String, Object?>{
          'key': 'x',
          'label': 'X',
          'defaultUnit': '',
          'icon': 'generic',
          'displayType': 'number',
          'decimals': 0,
          'statusBehavior': 'none',
          'schemaVersion': 999,
          'enabled': true,
          'recordVersion': 1,
        };
        expect(CapabilityMetricRecord.fromMap(map), isNull);
      },
    );

    test('defensive parse: malformed doc returns null, never throws', () {
      final map = <String, Object?>{
        'key': 'x',
        // missing required 'label'/'defaultUnit'/'icon'/'displayType'/'decimals'
        'schemaVersion': 1,
        'enabled': true,
      };
      expect(CapabilityMetricRecord.fromMap(map), isNull);
    });

    test('CapabilityIndicatorRecord roundtrips symmetrically', () {
      final record = CapabilityIndicatorRecord(
        indicator: CapabilityIndicatorDefinition(
          key: 'heater',
          label: 'Heater',
          defaultIcon: 'flame',
        ),
        schemaVersion: 1,
        enabled: true,
        recordVersion: 2,
      );
      final restored = CapabilityIndicatorRecord.fromMap(record.toMap());
      expect(restored!.indicator.key, 'heater');
      expect(restored.recordVersion, 2);
    });
  });

  group('N7.1 §20 — DeviceCapabilityProfile roundtrip', () {
    test('survives toMap/fromMap with bindings and suggestions', () {
      final profile = DeviceCapabilityProfile(
        id: 'sala_a',
        name: 'Sala A',
        description: 'Perfil de prueba',
        enabled: true,
        metricKeys: ['tempInterior'],
        indicatorKeys: ['heater', 'fan'],
        metricBindings: {
          'tempInterior': MetricBinding(sourceField: 'temp_interior'),
        },
        indicatorBindings: {
          'heater': IndicatorBinding(sourceField: 'heater_on'),
          'fan': IndicatorBinding(sourceField: 'fan_on'),
        },
        suggestedIndicatorsByMetric: {
          'tempInterior': ['heater'],
        },
        profileVersion: 4,
      );
      final restored = DeviceCapabilityProfile.fromMap(profile.toMap());
      expect(restored.id, 'sala_a');
      expect(restored.name, 'Sala A');
      expect(restored.metricKeys, ['tempInterior']);
      expect(restored.indicatorKeys, ['heater', 'fan']);
      expect(
        restored.metricBindings['tempInterior']!.sourceField,
        'temp_interior',
      );
      expect(restored.indicatorBindings['heater']!.sourceField, 'heater_on');
      expect(restored.suggestedIndicatorsByMetric['tempInterior'], ['heater']);
      expect(restored.profileVersion, 4);
    });
  });

  group('N7.1 §20/§6/§7 — BoardPreset: enabled/timestamps/roundtrip', () {
    test('survives toMap/fromMap including enabled and timestamps', () {
      final preset = BoardPreset(
        id: 'preset_a',
        name: 'Preset A',
        layoutTemplateId: 'grid_6x4',
        capabilityProfileId: 'sala_a',
        items: [
          BoardContentItem(
            id: 'metric-0',
            placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 2),
            content: MetricBoardContent(
              metricKey: 'tempInterior',
              indicatorKeys: const ['heater'],
            ),
          ),
        ],
        presetVersion: 2,
        enabled: false,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 9, 19),
      );
      final restored = BoardPreset.fromMap(preset.toMap());
      expect(restored.id, 'preset_a');
      expect(restored.capabilityProfileId, 'sala_a');
      expect(restored.items, hasLength(1));
      expect(restored.presetVersion, 2);
      expect(restored.enabled, false);
      expect(restored.createdAt, DateTime.utc(2026, 1, 1));
      expect(restored.updatedAt, DateTime.utc(2026, 9, 19));
    });

    test(
      'enabled defaults to true when absent (pre-N7.1 in-memory presets)',
      () {
        final preset = BoardPreset(
          id: 'p',
          name: 'P',
          layoutTemplateId: 'grid_6x4',
        );
        final map = preset.toMap()..remove('enabled');
        final restored = BoardPreset.fromMap(map);
        expect(restored.enabled, true);
      },
    );
  });

  group(
    'N7.1 §6/§9 — DeviceBoardLayout/BoardContentLayout trazability roundtrip',
    () {
      test('capabilityProfileId/sourceBoardPresetId/sourceBoardPresetVersion '
          'survive DeviceBoardLayout toMap/fromMap', () {
        final layout = DeviceBoardLayout(
          deviceId: 'device-1',
          layoutTemplateId: 'grid_6x4',
          items: const [],
          layoutVersion: 3,
          capabilityProfileId: 'sala_a',
          sourceBoardPresetId: 'preset_a',
          sourceBoardPresetVersion: 2,
        );
        final restored = DeviceBoardLayout.fromMap(layout.toMap());
        expect(restored.capabilityProfileId, 'sala_a');
        expect(restored.sourceBoardPresetId, 'preset_a');
        expect(restored.sourceBoardPresetVersion, 2);
        expect(restored.layoutVersion, 3);
      });

      test(
        'BoardContentLayout (schema 2) proxies the same trazability fields',
        () {
          final layout = BoardContentLayout(
            deviceId: 'device-1',
            layoutTemplateId: 'grid_6x4',
            layoutVersion: 5,
            capabilityProfileId: 'sala_b',
            sourceBoardPresetId: 'preset_b',
            sourceBoardPresetVersion: 7,
            items: const [],
          );
          final restored = BoardContentLayout.fromMap(layout.toMap());
          expect(restored.capabilityProfileId, 'sala_b');
          expect(restored.sourceBoardPresetId, 'preset_b');
          expect(restored.sourceBoardPresetVersion, 7);
          expect(restored.layoutVersion, 5);
        },
      );

      test('fromLegacy/toLegacy preserve trazability fields', () {
        final legacy = DeviceBoardLayout(
          deviceId: 'device-1',
          layoutTemplateId: 'grid_6x4',
          items: const [],
          capabilityProfileId: 'sala_a',
          sourceBoardPresetId: 'preset_a',
          sourceBoardPresetVersion: 1,
        );
        final schema2 = BoardContentLayout.fromLegacy(legacy);
        expect(schema2.capabilityProfileId, 'sala_a');
        final backToLegacy = schema2.toLegacy();
        expect(backToLegacy.sourceBoardPresetId, 'preset_a');
        expect(backToLegacy.sourceBoardPresetVersion, 1);
      });
    },
  );

  group('N7.1 §15 — FirestoreVersionConflict', () {
    test('carries entity/expected/actual and a readable toString', () {
      const conflict = FirestoreVersionConflict(
        entityType: 'boardPreset',
        entityId: 'preset_a',
        expectedVersion: 1,
        actualVersion: 2,
      );
      expect(conflict.entityType, 'boardPreset');
      expect(conflict.entityId, 'preset_a');
      expect(conflict.expectedVersion, 1);
      expect(conflict.actualVersion, 2);
      expect(conflict.toString(), contains('boardPreset/preset_a'));
    });
  });
}
