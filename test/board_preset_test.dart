import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:flutter_test/flutter_test.dart';

BoardContentItem _metricItem(String id) => BoardContentItem(
  id: id,
  placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 1),
  content: MetricBoardContent(metricKey: 'tempInterior'),
);

void main() {
  group('BoardPreset model', () {
    test('requires no tenant/site/device identity', () {
      // Compiles and constructs without any Tenant/Site/Device field —
      // the type itself has none to pass (N6.2 §6/§15).
      final preset = BoardPreset(
        id: 'p1',
        name: 'Preset genérico',
        layoutTemplateId: 'grid_6x4',
      );
      expect(preset.items, isEmpty);
      expect(preset.requiredMetricKeys, isEmpty);
      expect(preset.optionalMetricKeys, isEmpty);
    });

    test('rejects an empty id/name/layoutTemplateId', () {
      expect(
        () => BoardPreset(id: '', name: 'x', layoutTemplateId: 'grid_6x1'),
        throwsArgumentError,
      );
      expect(
        () => BoardPreset(id: 'x', name: '', layoutTemplateId: 'grid_6x1'),
        throwsArgumentError,
      );
      expect(
        () => BoardPreset(id: 'x', name: 'x', layoutTemplateId: ''),
        throwsArgumentError,
      );
    });

    test('copyWith rebuilds an independent items list', () {
      final original = BoardPreset(
        id: 'p1',
        name: 'Original',
        layoutTemplateId: 'grid_6x1',
        items: [_metricItem('a')],
      );
      final copy = original.copyWith(
        items: [_metricItem('a'), _metricItem('b')],
      );
      expect(original.items, hasLength(1));
      expect(copy.items, hasLength(2));
    });
  });

  group('resolveLayoutTemplateId / buildLayoutTemplate', () {
    test('resolves generic catalog ids', () {
      final t = resolveLayoutTemplateId('grid_6x4');
      expect(t.columns, 6);
      expect(t.rows, 4);
    });

    test('resolves a fixture-only id like grid_6x7 (Arco)', () {
      final t = resolveLayoutTemplateId('grid_6x7');
      expect(t.columns, 6);
      expect(t.rows, 7);
    });

    test('supports dynamic layouts beyond the generic catalog (8x4)', () {
      final t = buildLayoutTemplate(8, 4);
      expect(t.id, 'grid_8x4');
      expect(t.columns, 8);
      expect(t.rows, 4);
    });

    test('throws for a non-grid-shaped id', () {
      expect(() => resolveLayoutTemplateId('nonsense'), throwsStateError);
    });
  });

  group('BoardPresetCatalog', () {
    test('seed catalog has no tenant/site/device coupling', () {
      final catalog = BoardPresetCatalog();
      expect(catalog.presets, isNotEmpty);
      for (final preset in catalog.presets) {
        expect(preset.id, isNotEmpty);
        expect(preset.layoutTemplateId, isNotEmpty);
      }
    });

    test('create starts with an empty board on the given layout', () {
      final catalog = BoardPresetCatalog(initial: []);
      final layout = buildLayoutTemplate(8, 4);
      final preset = catalog.create(
        name: 'Maternidad estándar',
        description: 'Prueba',
        layout: layout,
      );
      expect(preset.name, 'Maternidad estándar');
      expect(preset.layoutTemplateId, 'grid_8x4');
      expect(preset.items, isEmpty);
      expect(catalog.byId(preset.id), isNotNull);
    });

    test('duplicate creates a new id with the same initial content', () {
      final catalog = BoardPresetCatalog(initial: []);
      final layout = buildLayoutTemplate(6, 4);
      final created = catalog.create(name: 'A', layout: layout);
      catalog.updateContent(
        created.id,
        layout: layout,
        items: [_metricItem('temp')],
        showTitle: true,
      );
      final original = catalog.byId(created.id)!;
      final copy = catalog.duplicate(original.id);
      expect(copy.id, isNot(original.id));
      expect(copy.items.map((i) => i.id), original.items.map((i) => i.id));
      expect(copy.name, contains('copia'));
    });

    test('editing the duplicate never changes the original', () {
      final catalog = BoardPresetCatalog(initial: []);
      final layout = buildLayoutTemplate(6, 4);
      final original = catalog.create(name: 'A', layout: layout);
      catalog.updateContent(
        original.id,
        layout: layout,
        items: [_metricItem('temp')],
        showTitle: true,
      );
      final copy = catalog.duplicate(original.id);

      catalog.updateContent(
        copy.id,
        layout: layout,
        items: [_metricItem('temp'), _metricItem('humidity')],
        showTitle: false,
      );

      final originalAfter = catalog.byId(original.id)!;
      final copyAfter = catalog.byId(copy.id)!;
      expect(originalAfter.items, hasLength(1));
      expect(copyAfter.items, hasLength(2));
      expect(originalAfter.showTitleDefault, isTrue);
      expect(copyAfter.showTitleDefault, isFalse);
    });

    test('rename changes name/description but never the id', () {
      final catalog = BoardPresetCatalog(initial: []);
      final preset = catalog.create(
        name: 'Original',
        layout: buildLayoutTemplate(6, 1),
      );
      catalog.rename(preset.id, name: 'Renombrado', description: 'Nueva desc');
      final updated = catalog.byId(preset.id)!;
      expect(updated.id, preset.id);
      expect(updated.name, 'Renombrado');
      expect(updated.description, 'Nueva desc');
    });

    test('supports dynamic layouts (6x4, 8x4)', () {
      final catalog = BoardPresetCatalog(initial: []);
      final a = catalog.create(name: 'A', layout: buildLayoutTemplate(6, 4));
      final b = catalog.create(name: 'B', layout: buildLayoutTemplate(8, 4));
      expect(a.layoutTemplateId, 'grid_6x4');
      expect(b.layoutTemplateId, 'grid_8x4');
    });
  });
}
