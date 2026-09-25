import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_validator.dart';
import 'package:agro_data_control/device_board_layouts/device_board_layout.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';

void main() {
  group('N6.3.1 §2/§3 — resolveDefaultCellLayoutForSpan', () {
    test('resolves for a span the seed catalog never hardcoded (4x2)', () {
      final preset = resolveDefaultCellLayoutForSpan(4, 2);
      expect(preset.widthCells, 4);
      expect(preset.heightCells, 2);
      expect(preset.elements, isNotEmpty);
    });

    test('produces a valid, non-colliding, in-bounds preset for a range of '
        'spans — not a hardcoded per-span table', () {
      for (final span in [(1, 1), (2, 1), (2, 2), (3, 1), (4, 2), (5, 3)]) {
        final (width, height) = span;
        final preset = resolveDefaultCellLayoutForSpan(width, height);
        final template = LayoutTemplate(
          id: 'template_${width}x$height',
          name: 'template_${width}x$height',
          columns: width,
          rows: height,
        );
        final item = DeviceBoardLayoutItem(
          id: 'probe',
          metricKey: 'tempInterior',
          placement: GridPlacement(
            x: 0,
            y: 0,
            widthCells: width,
            heightCells: height,
          ),
        );
        final issues = CellLayoutValidator.validate(preset, item, template);
        expect(
          issues,
          isEmpty,
          reason: 'span ${width}x$height produced: $issues',
        );
      }
    });

    test('CellLayoutCatalog.resolve falls back to it for an unsupported '
        'span instead of throwing cell_preset_not_found', () {
      final catalog = CellLayoutCatalog(const []);
      final item = DeviceBoardLayoutItem(
        id: 'temperature-main',
        metricKey: 'tempInterior',
        placement: GridPlacement(x: 0, y: 0, widthCells: 4, heightCells: 2),
      );
      final resolved = catalog.resolve(item);
      expect(resolved.widthCells, 4);
      expect(resolved.heightCells, 2);
    });

    test('a seeded default is still preferred over the generic fallback', () {
      // initialCellLayoutCatalog seeds a real default for 2x2.
      final item = DeviceBoardLayoutItem(
        id: 'x',
        metricKey: 'tempInterior',
        placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 2),
      );
      final resolved = initialCellLayoutCatalog.resolve(item);
      expect(resolved.id, 'default_2x2');
    });

    test('an explicit but unknown cellLayoutPresetId still fails — the '
        'fallback only applies to the null/"(default por span)" case', () {
      final catalog = CellLayoutCatalog(const []);
      final item = DeviceBoardLayoutItem(
        id: 'x',
        metricKey: 'tempInterior',
        placement: GridPlacement(x: 0, y: 0, widthCells: 1, heightCells: 1),
        cellLayoutPresetId: 'nonexistent',
      );
      expect(() => catalog.resolve(item), throwsA(anything));
    });
  });
}
