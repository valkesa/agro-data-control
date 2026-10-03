import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_content/data_source_binding.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/device_board_layouts/layout_validation_issue.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:flutter_test/flutter_test.dart';

DataSourceBinding _sampleBinding() => const DataSourceBinding(
  tenantId: 'the-gene-pig',
  siteId: 'genetica-1',
  deviceId: 'sala1',
  metricKey: 'tempInterior',
);

GridPlacement _placement() =>
    GridPlacement(x: 0, y: 0, widthCells: 1, heightCells: 1);

void main() {
  group('A. Serialización', () {
    test('binding -> toMap -> fromMap -> mismo binding', () {
      final binding = _sampleBinding();
      final roundTripped = DataSourceBinding.fromMap(binding.toMap());
      expect(roundTripped, binding);
      expect(roundTripped.toMap(), binding.toMap());
    });

    test('rechaza campos desconocidos', () {
      expect(
        () => DataSourceBinding.fromMap({
          ..._sampleBinding().toMap(),
          'sourceField': 'DB10.DBD0',
        }),
        throwsA(isA<LayoutValidationException>()),
      );
    });

    test('rechaza campos vacíos (validación estructural)', () {
      for (final field in ['tenantId', 'siteId', 'deviceId', 'metricKey']) {
        final map = {..._sampleBinding().toMap(), field: ''};
        expect(
          () => DataSourceBinding.fromMap(map),
          throwsA(isA<LayoutValidationException>()),
          reason: '$field vacío debería fallar',
        );
      }
    });
  });

  group('B. Documento legacy', () {
    test('sin dataSource -> binding=null, item válido', () {
      final item = MetricBoardContent.fromMap(const {
        'metricKey': 'tempInterior',
        'cellLayoutPresetId': null,
        'indicatorKeys': <Object?>[],
      });
      expect(item.dataSourceBinding, isNull);
    });

    test('MetricBoardContent construido sin binding es válido', () {
      final item = MetricBoardContent(metricKey: 'tempInterior');
      expect(item.dataSourceBinding, isNull);
      expect(item.toMap().containsKey('dataSource'), isFalse);
    });
  });

  group('C. BoardPreset genérico', () {
    test('items de preset sin IDs concretos siguen siendo válidos', () {
      final preset = BoardPreset(
        id: 'preset-1',
        name: 'Clima',
        layoutTemplateId: 'template-1',
        items: [
          BoardContentItem(
            id: 'item-1',
            placement: _placement(),
            content: MetricBoardContent(metricKey: 'tempInterior'),
          ),
        ],
      );
      final content = preset.items.single.content as MetricBoardContent;
      expect(content.dataSourceBinding, isNull);
      expect(content.metricKey, 'tempInterior');
    });
  });

  group('D. DeviceBoardLayout concreto', () {
    test('binding persiste y reaparece tras toMap/fromMap', () {
      final binding = _sampleBinding();
      final layout = BoardContentLayout(
        deviceId: 'sala1',
        layoutTemplateId: 'template-1',
        items: [
          BoardContentItem(
            id: 'item-1',
            placement: _placement(),
            content: MetricBoardContent(
              metricKey: 'tempInterior',
              dataSourceBinding: binding,
            ),
          ),
        ],
      );
      final reloaded = BoardContentLayout.fromMap(layout.toMap());
      final content = reloaded.items.single.content as MetricBoardContent;
      expect(content.dataSourceBinding, binding);
    });

    test('documento viejo (schemaVersion 1, sin dataSource) sigue cargando', () {
      final legacyMap = {
        'schemaVersion': 1,
        'deviceId': 'sala1',
        'layoutTemplateId': 'template-1',
        'showTitle': true,
        'layoutVersion': 1,
        'items': [
          {
            'id': 'item-1',
            'metricKey': 'tempInterior',
            'placement': {'x': 0, 'y': 0, 'widthCells': 1, 'heightCells': 1},
            'indicatorKeys': <Object?>[],
          },
        ],
      };
      final layout = BoardContentLayout.fromMap(legacyMap);
      final content = layout.items.single.content as MetricBoardContent;
      expect(content.dataSourceBinding, isNull);
    });

    test('copyWith preserva el binding al tocar otros campos', () {
      final binding = _sampleBinding();
      final content = MetricBoardContent(
        metricKey: 'tempInterior',
        dataSourceBinding: binding,
      );
      final edited = content.copyWith(indicatorKeys: ['min']);
      expect(edited.dataSourceBinding, binding);
    });

    test('clearDataSourceBinding limpia el binding explícitamente', () {
      final content = MetricBoardContent(
        metricKey: 'tempInterior',
        dataSourceBinding: _sampleBinding(),
      );
      final cleared = content.copyWith(clearDataSourceBinding: true);
      expect(cleared.dataSourceBinding, isNull);
    });
  });
}
