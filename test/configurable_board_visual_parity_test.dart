import 'package:agro_data_control/board_runtime/configurable_board_visual_state.dart';
import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_preview/board_content_renderer.dart';
import 'package:agro_data_control/board_preview/preview_board_data.dart';
import 'package:agro_data_control/device_metric_catalogs/reference_metric_catalogs.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';
import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/ui_templates/board/template_data_resolver.dart';
import 'package:agro_data_control/ui_templates/models/metric_definition.dart';
import 'package:agro_data_control/ui_templates/models/template_data_context.dart';
import 'package:agro_data_control/ui_templates/shared/template_visual_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

const DashboardRangeSettings ranges = DashboardRangeSettings.defaults();
final catalog = referenceMetricCatalogById('environment_room_v1')!;

MetricDefinition metric(String key) => catalog.metricByKey(key)!;

void expectParity(String key, Map<String, Object?> data) {
  final definition = metric(key);
  const resolver = TemplateDataResolver();
  final value = resolver.resolveMetric(definition, data);
  final legacy = resolveTemplateAlarmLevel(
    metric: definition,
    value: value,
    deviceData: data,
    rangeSettings: ranges,
  );
  final configurable = resolveConfigurableBoardMetricVisualState(
    metric: definition,
    deviceData: data,
    rangeSettings: ranges,
  );
  expect(configurable.level, legacy);
  if (value != null) {
    expect(configurable.valueColor, templateAlarmLevelColor(legacy));
  }
}

void main() {
  group('ETAPA 2C — paridad semántica legacy/configurable', () {
    test('temperatura: normal, rojo, límites y falla técnica', () {
      for (final value in <double>[15, 24, 32, 32.1, 14.9, -0.1]) {
        expectParity('tempInterior', <String, Object?>{'tempInterior': value});
      }
      expect(
        resolveConfigurableBoardMetricVisualState(
          metric: metric('tempInterior'),
          deviceData: const <String, Object?>{'tempInterior': -0.1},
          rangeSettings: ranges,
        ).level,
        TemplateAlarmLevel.sensorFailure,
      );
    });

    test('humedad: normal, amarillo, rojo y límites existentes', () {
      for (final value in <double>[84.9, 85, 95, 95.1]) {
        expectParity('humedadInterior', <String, Object?>{
          'humInterior': value,
        });
      }
      expect(
        resolveConfigurableBoardMetricVisualState(
          metric: metric('humedadInterior'),
          deviceData: const <String, Object?>{'humInterior': 85},
          rangeSettings: ranges,
        ).level,
        TemplateAlarmLevel.warning,
      );
      expect(
        resolveConfigurableBoardMetricVisualState(
          metric: metric('humedadInterior'),
          deviceData: const <String, Object?>{'humInterior': 95.1},
          rangeSettings: ranges,
        ).level,
        TemplateAlarmLevel.alarm,
      );
    });

    test('Delta PR se deriva de temperatura y humedad', () {
      const data = <String, Object?>{'tempInterior': 24.0, 'humInterior': 95.0};
      expectParity('dewPointDelta', data);
      final state = resolveConfigurableBoardMetricVisualState(
        metric: metric('dewPointDelta'),
        deviceData: data,
        rangeSettings: ranges,
      );
      expect(state.level, TemplateAlarmLevel.alarm);
    });

    test('presión: normal y rojo usan el umbral compartido', () {
      expectParity('presion', const {'presionDiferencial': 30.0});
      expectParity('presion', const {'presionDiferencial': 30.1});
    });

    test('puertas conservan activo/inactivo separado de falla técnica', () {
      expectParity('puertaSala', const {'salaAbierta': false});
      expectParity('puertaSala', const {'salaAbierta': true});
      expect(
        resolveConfigurableBoardMetricVisualState(
          metric: metric('puertaSala'),
          deviceData: const {'salaAbierta': true},
          rangeSettings: ranges,
        ).level,
        TemplateAlarmLevel.alarm,
      );
    });

    test('sin datos permanece unavailable y no se confunde con falla', () {
      final state = resolveConfigurableBoardMetricVisualState(
        metric: metric('tempInterior'),
        deviceData: const <String, Object?>{},
        rangeSettings: ranges,
      );
      expect(state.level, TemplateAlarmLevel.unavailable);
      expect(state.isSensorFailure, isFalse);
      expect(state.borderColor, isNull);
    });

    test('métricas sin alarmState no inventan severidad', () {
      final state = resolveConfigurableBoardMetricVisualState(
        metric: metric('tempExterior'),
        deviceData: const {'tempExterior': 80.0},
        rangeSettings: ranges,
      );
      expect(state.level, TemplateAlarmLevel.unavailable);
      expect(state.borderColor, isNull);
    });

    testWidgets('el renderer configurable pinta amarillo, rojo y falla', (
      tester,
    ) async {
      Future<void> pumpValue(double value) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 500,
              child: BoardContentRenderer(
                board: BoardContentLayout(
                  deviceId: 'qa-device',
                  layoutTemplateId: 'grid_6x4',
                  items: <BoardContentItem>[
                    BoardContentItem(
                      id: 'humidity',
                      placement: GridPlacement(
                        x: 0,
                        y: 0,
                        widthCells: 2,
                        heightCells: 2,
                      ),
                      content: MetricBoardContent(metricKey: 'humedadInterior'),
                    ),
                  ],
                ),
                template: LayoutTemplate(
                  id: 'grid_6x4',
                  name: '6x4',
                  columns: 6,
                  rows: 4,
                ),
                catalog: catalog,
                data: PreviewBoardDataProvider(
                  metricData: TemplateDataContext(
                    source: <String, Object?>{'humInterior': value},
                  ),
                  rangeSettings: ranges,
                ),
                deviceName: 'QA',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpValue(85);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('metric-humidity-value')))
            .style!
            .color,
        templateAlarmLevelColor(TemplateAlarmLevel.warning),
      );
      await pumpValue(96);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('metric-humidity-value')))
            .style!
            .color,
        templateAlarmLevelColor(TemplateAlarmLevel.alarm),
      );
    });
  });
}
