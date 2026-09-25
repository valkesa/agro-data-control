import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CellLayoutPresetCatalog', () {
    test('seeds from initialCellLayoutCatalog (7 presets)', () {
      final catalog = CellLayoutPresetCatalog();
      expect(catalog.presets, hasLength(7));
      expect(catalog.byId('default_1x1'), isNotNull);
      expect(catalog.isSeedGlobal('default_1x1'), isTrue);
    });

    test('create builds a new design from the default composition', () {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'Custom 1x1', width: 1, height: 1);
      expect(preset.name, 'Custom 1x1');
      expect(preset.widthCells, 1);
      expect(preset.heightCells, 1);
      expect(preset.elements, isNotEmpty);
      expect(catalog.isSeedGlobal(preset.id), isFalse);
      expect(catalog.byId(preset.id), isNotNull);
    });

    test(
      'duplicate creates a new id with a deep copy; original stays independent',
      () {
        final catalog = CellLayoutPresetCatalog();
        final original = catalog.byId('default_1x1')!;
        final copy = catalog.duplicate('default_1x1');

        expect(copy.id, isNot(original.id));
        expect(
          copy.elements.map((e) => e.id),
          original.elements.map((e) => e.id),
        );

        // Editing the copy's composition never touches the original.
        catalog.update(
          copy.id,
          elements: [
            for (final e in copy.elements)
              if (e.id == 'value')
                CellLayoutElement(
                  id: e.id,
                  type: e.type,
                  placement: InternalGridPlacement(
                    x: 0,
                    y: 0,
                    widthUnits: 4,
                    heightUnits: 4,
                  ),
                  textStyle: e.textStyle,
                  sizeRole: e.sizeRole,
                )
              else
                e,
          ],
        );
        final originalAfter = catalog.byId('default_1x1')!;
        final copyAfter = catalog.byId(copy.id)!;
        final originalValue = originalAfter.elements.firstWhere(
          (e) => e.id == 'value',
        );
        final copyValue = copyAfter.elements.firstWhere((e) => e.id == 'value');
        expect(originalValue.placement.widthUnits, isNot(4));
        expect(copyValue.placement.widthUnits, 4);
      },
    );

    test('rename changes name/description but preserves the id', () {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'A', width: 1, height: 1);
      catalog.rename(preset.id, name: 'B', description: 'nueva desc');
      final updated = catalog.byId(preset.id)!;
      expect(updated.id, preset.id);
      expect(updated.name, 'B');
      expect(catalog.descriptionOf(preset.id), 'nueva desc');
    });

    test('update bumps presetVersion', () {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'A', width: 1, height: 1);
      expect(preset.presetVersion, 1);
      catalog.update(preset.id, elements: preset.elements);
      expect(catalog.byId(preset.id)!.presetVersion, 2);
    });

    test('availableForSpan filters by enabled + matching span', () {
      final catalog = CellLayoutPresetCatalog();
      final for1x1 = catalog.availableForSpan(1, 1);
      expect(for1x1, isNotEmpty);
      expect(
        for1x1.every((p) => p.widthCells == 1 && p.heightCells == 1),
        isTrue,
      );
      expect(catalog.availableForSpan(9, 9), isEmpty);
    });

    test('delete is blocked when referenced', () {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final preset = catalog.create(name: 'A', width: 1, height: 1);
      final blocked = catalog.delete(preset.id, isReferenced: (_) => true);
      expect(blocked.ok, isFalse);
      expect(catalog.byId(preset.id), isNotNull);

      final allowed = catalog.delete(preset.id, isReferenced: (_) => false);
      expect(allowed.ok, isTrue);
      expect(catalog.byId(preset.id), isNull);
    });

    test('resolveLayoutTemplateId-style ids stay unique across creates', () {
      final catalog = CellLayoutPresetCatalog(initial: []);
      final a = catalog.create(name: 'A', width: 1, height: 1);
      final b = catalog.create(name: 'B', width: 1, height: 1);
      expect(a.id, isNot(b.id));
    });
  });
}
