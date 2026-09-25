import 'dart:convert';

import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';
import 'package:agro_data_control/layout_templates/layout_template_catalog.dart';
import 'package:agro_data_control/layout_templates/layout_template_validator.dart';
import 'package:flutter_test/flutter_test.dart';

LayoutTemplate _layout({int columns = 8, int rows = 4}) => LayoutTemplate(
  id: 'grid_${columns}x$rows',
  name: '$columns × $rows',
  columns: columns,
  rows: rows,
);

void main() {
  group('Local catalog', () {
    for (var rows = 1; rows <= 4; rows++) {
      test('grid_6x$rows', () {
        final layout = initialLayoutTemplateCatalog.byId('grid_6x$rows')!;
        expect(layout.columns, 6);
        expect(layout.rows, rows);
        expect(layout.name, '6 × $rows');
      });
    }
    test('IDs are unique and catalog cannot be mutated', () {
      expect(initialLayoutTemplateCatalog.templates, hasLength(4));
      expect(
        () => LayoutTemplateCatalog([_layout(), _layout()]),
        throwsArgumentError,
      );
      expect(
        () => initialLayoutTemplateCatalog.templates.clear(),
        throwsUnsupportedError,
      );
      expect(initialLayoutTemplateCatalog.byId('unknown'), isNull);
    });
    for (final dimensions in [(7, 4), (8, 4), (10, 5)]) {
      test(
        'arbitrary ${dimensions.$1} columns work through catalog and bounds',
        () {
          final layout = _layout(columns: dimensions.$1, rows: dimensions.$2);
          final catalog = LayoutTemplateCatalog([layout]);
          expect(catalog.byId(layout.id), same(layout));
          final lastCell = GridPlacement(
            x: layout.columns - 1,
            y: layout.rows - 1,
            widthCells: 1,
            heightCells: 1,
          );
          expect(lastCell.fitsWithin(layout), isTrue);
          lastCell.validateWithin(layout);
          final full = GridPlacement(
            x: 0,
            y: 0,
            widthCells: layout.columns,
            heightCells: layout.rows,
          );
          expect(full.internalColumns(layout), layout.columns * 8);
          expect(
            LayoutTemplate.fromMap(layout.toMap()).toMap(),
            layout.toMap(),
          );
        },
      );
    }
  });

  group('Placement and subgrid', () {
    for (final span in [
      (1, 1, 8, 8),
      (2, 1, 16, 8),
      (1, 2, 8, 16),
      (2, 2, 16, 16),
      (3, 2, 24, 16),
    ]) {
      test('${span.$1}x${span.$2} -> ${span.$3}x${span.$4}', () {
        final placement = GridPlacement(
          x: 1,
          y: 1,
          widthCells: span.$1,
          heightCells: span.$2,
        );
        expect(placement.fitsWithin(_layout()), isTrue);
        expect(placement.internalColumns(_layout()), span.$3);
        expect(placement.internalRows(_layout()), span.$4);
      });
    }
    for (final span in [
      (7, 0, 2, 1),
      (0, 3, 1, 2),
      (8, 0, 1, 1),
      (0, 4, 1, 1),
    ]) {
      test('rejects out-of-bounds $span', () {
        final placement = GridPlacement(
          x: span.$1,
          y: span.$2,
          widthCells: span.$3,
          heightCells: span.$4,
        );
        expect(placement.fitsWithin(_layout()), isFalse);
        expect(() => placement.validateWithin(_layout()), throwsArgumentError);
        expect(() => placement.internalColumns(_layout()), throwsArgumentError);
        expect(() => placement.internalRows(_layout()), throwsArgumentError);
      });
    }
    for (final span in [
      (-1, 0, 1, 1),
      (0, -1, 1, 1),
      (0, 0, 0, 1),
      (0, 0, 1, 0),
      (0, 0, -1, 1),
      (0, 0, 1, -1),
    ]) {
      test('rejects invalid dimensions $span in constructor', () {
        expect(
          () => GridPlacement(
            x: span.$1,
            y: span.$2,
            widthCells: span.$3,
            heightCells: span.$4,
          ),
          throwsArgumentError,
        );
      });
    }
    test('persisted asymmetric resolution governs spans', () {
      final map = _layout().toMap()
        ..['internalUnitsPerCellX'] = 12
        ..['internalUnitsPerCellY'] = 10
        ..['templateVersion'] = 2;
      final layout = LayoutTemplate.fromMap(map);
      final placement = GridPlacement(
        x: 0,
        y: 0,
        widthCells: 2,
        heightCells: 2,
      );
      expect(placement.internalColumns(layout), 24);
      expect(placement.internalRows(layout), 20);
      expect(layout.toMap(), map);
      expect(_layout().internalUnitsPerCellX, 8);
    });
  });

  group('Serialization and validation', () {
    test('all fields survive map and JSON round trips', () {
      final layout = LayoutTemplate(
        id: 'grid_8x4',
        name: '8 × 4',
        columns: 8,
        rows: 4,
        templateVersion: 3,
        enabled: false,
        createdAt: DateTime.parse('2026-09-11T10:00:00-03:00'),
        updatedAt: DateTime.utc(2026, 9, 11, 14),
      );
      final decoded = LayoutTemplate.fromMap(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(layout.toMap())) as Map,
        ),
      );
      expect(decoded.toMap(), layout.toMap());
      expect(decoded.createdAt!.isAtSameMomentAs(layout.createdAt!), isTrue);
      expect(decoded.updatedAt, layout.updatedAt);
      expect(decoded.enabled, isFalse);
      expect(LayoutTemplate.fromMap(_layout().toMap()).createdAt, isNull);
    });
    test('DateTime input is accepted at the boundary', () {
      final now = DateTime.utc(2026);
      expect(
        LayoutTemplate.fromMap(
          _layout().toMap()..['createdAt'] = now,
        ).createdAt,
        now,
      );
    });
    test('unknown optional fields are tolerated', () {
      expect(
        LayoutTemplate.fromMap(
          _layout().toMap()..['futureField'] = true,
        ).toMap(),
        _layout().toMap(),
      );
    });
    final invalid = <String, List<Object?>>{
      'id': ['', '   ', null, 2],
      'name': ['', null, true],
      'columns': [0, -1, 1025, 8.5, '8', null],
      'rows': [0, -1, 1025, 4.5, '4', null],
      'schemaVersion': [0, 2, null, '1'],
      'templateVersion': [0, -1, 1.5, null],
      'enabled': [null, 'true', 1],
      'internalUnitsPerCellX': [0, -1, 1025, null, 8.5],
      'internalUnitsPerCellY': [0, -1, 1025, null, '8'],
      'createdAt': ['invalid', '2026-02-31T00:00:00.000Z', '2026-09-11', 123],
      'updatedAt': ['invalid', false],
    };
    for (final entry in invalid.entries) {
      for (final value in entry.value) {
        test('rejects ${entry.key}=$value', () {
          expect(
            () =>
                LayoutTemplate.fromMap(_layout().toMap()..[entry.key] = value),
            throwsArgumentError,
          );
        });
      }
    }
    test('required serialized fields cannot be omitted', () {
      for (final key in _layout().toMap().keys.where(
        (key) => key != 'createdAt' && key != 'updatedAt',
      )) {
        expect(
          () => LayoutTemplate.fromMap(_layout().toMap()..remove(key)),
          throwsArgumentError,
          reason: key,
        );
      }
    });
    test(
      'technical cell budget applies independently of preset dimensions',
      () {
        expect(() => _layout(columns: 1024, rows: 1024), throwsArgumentError);
        expect(
          _layout(
            columns: LayoutTemplateValidator.maxAxisCells,
            rows: 1,
          ).columns,
          1024,
        );
        expect(_layout(columns: 256, rows: 256).rows, 256);
      },
    );
    test(
      'direct construction also validates schema, identity and resolution',
      () {
        expect(
          () => LayoutTemplate(id: ' ', name: 'grid', columns: 8, rows: 4),
          throwsArgumentError,
        );
        expect(
          () => LayoutTemplate(
            id: 'grid',
            name: 'grid',
            columns: 8,
            rows: 4,
            schemaVersion: 2,
          ),
          throwsArgumentError,
        );
        expect(
          () => LayoutTemplate(
            id: 'grid',
            name: 'grid',
            columns: 8,
            rows: 4,
            internalUnitsPerCellX: 0,
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
