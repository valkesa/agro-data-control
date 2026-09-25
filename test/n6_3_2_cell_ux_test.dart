import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_presets/board_preset_catalog.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/board_preview/board_render_config.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_editor_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset_catalog.dart';

Future<void> pump(WidgetTester t, Widget page) async {
  t.view.physicalSize = const Size(1400, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: page));
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  test('hero is semantic, roundtrips and scales with the internal unit', () {
    final catalog = CellLayoutPresetCatalog();
    final json = catalog.byId('default_1x1')!.toMap();
    final elements = json['elements'] as List;
    for (final e in elements) {
      (e as Map)['sizeRole'] = 'hero';
    }
    final decoded = CellLayoutPreset.fromMap(json);
    expect(
      decoded.elements.every((e) => e.sizeRole == CellSizeRole.hero),
      isTrue,
    );
    expect(BoardRenderConfig.elementSize(CellSizeRole.hero, 8), 32);
    expect(BoardRenderConfig.elementSize(CellSizeRole.hero, 4), 16);
    expect(
      BoardRenderConfig.elementSize(CellSizeRole.hero, 8),
      greaterThan(BoardRenderConfig.elementSize(CellSizeRole.xxl, 8)),
    );
    expect(decoded.toMap().toString(), isNot(contains('fontSize')));
  });
  for (final remove in [0, 1, 2]) {
    testWidgets(
      'remove slot $remove, preserve other geometry and reindex; allow zero',
      (t) async {
        final c = CellLayoutPresetCatalog(initial: []);
        final p = c.create(name: 'Slots', width: 2, height: 2);
        final before = p.elements
            .where((e) => e.type == CellElementType.indicator)
            .toList();
        await pump(
          t,
          CellLayoutEditorPage(isOwner: true, presetId: p.id, catalog: c),
        );
        await tap(t, 'cell-editor-select-slot-$remove');
        expect(find.text('Elemento: Indicator slot $remove'), findsOneWidget);
        await tap(t, 'cell-editor-delete-selected-slot');
        await tap(t, 'cell-editor-save');
        final after = c
            .byId(p.id)!
            .elements
            .where((e) => e.type == CellElementType.indicator)
            .toList();
        expect(after.map((e) => e.indicatorSlot), [0, 1]);
        expect(
          after.map((e) => e.id),
          before.where((e) => e.indicatorSlot != remove).map((e) => e.id),
        );
        for (var i = 0; i < 2; i++) {
          await tap(t, 'cell-editor-select-slot-0');
          await tap(t, 'cell-editor-delete-selected-slot');
        }
        await tap(t, 'cell-editor-save');
        expect(
          c
              .byId(p.id)!
              .elements
              .where((e) => e.type == CellElementType.indicator),
          isEmpty,
        );
        await tap(t, 'cell-editor-add-slot');
        await tap(t, 'cell-editor-save');
        expect(
          c
              .byId(p.id)!
              .elements
              .where((e) => e.type == CellElementType.indicator)
              .single
              .indicatorSlot,
          0,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'hero value and icon render narrowly; non-slot has no delete action',
    (t) async {
      final c = CellLayoutPresetCatalog(initial: []);
      final p = c.create(name: 'Hero', width: 2, height: 2, icon: true);
      await pump(
        t,
        CellLayoutEditorPage(isOwner: true, presetId: p.id, catalog: c),
      );
      for (final id in ['value', 'icon']) {
        await tap(t, 'cell-editor-element-$id');
        expect(
          find.byKey(const ValueKey('cell-editor-delete-selected-slot')),
          findsNothing,
        );
        await tap(t, 'cell-editor-size-role');
        await t.tap(find.text('hero').last);
        await t.pumpAndSettle();
        await tap(t, 'cell-editor-save');
      }
      expect(
        c
            .byId(p.id)!
            .elements
            .where((e) => ['value', 'icon'].contains(e.id))
            .every((e) => e.sizeRole == CellSizeRole.hero),
        isTrue,
      );
      t.view.physicalSize = const Size(390, 1000);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'preset title survives reopening, clears to Device fallback and showTitle works',
    (t) async {
      final c = BoardPresetCatalog(initial: []);
      final p = c.create(
        name: 'Nombre administrativo',
        layout: buildLayoutTemplate(6, 4),
      );
      await pump(
        t,
        BoardEditorPage(isOwner: true, presetId: p.id, presetCatalog: c),
      );
      expect(find.text('Título por defecto del Board'), findsOneWidget);
      expect(find.textContaining('Opcional. Si queda vacío'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('editor-title-override')),
        'Título visible',
      );
      await t.pumpAndSettle();
      expect(c.byId(p.id)!.name, 'Nombre administrativo');
      expect(c.byId(p.id)!.titleOverride, 'Título visible');
      await t.pumpWidget(const SizedBox());
      await pump(
        t,
        BoardEditorPage(isOwner: true, presetId: p.id, presetCatalog: c),
      );
      expect(
        t
            .widget<TextField>(
              find.byKey(const ValueKey('editor-title-override')),
            )
            .controller!
            .text,
        'Título visible',
      );
      await t.enterText(
        find.byKey(const ValueKey('editor-title-override')),
        '',
      );
      await t.pumpAndSettle();
      expect(c.byId(p.id)!.titleOverride, isNull);
      expect(
        find.textContaining('Nombre del Device (al aplicar)'),
        findsWidgets,
      );
      await tap(t, 'editor-show-title');
      expect(c.byId(p.id)!.showTitleDefault, isFalse);
    },
  );
  testWidgets(
    'create from default, edit twice with same id; fewer slots exposes issue without changing indicators',
    (t) async {
      final c = BoardPresetCatalog(initial: []);
      // N6.5.1: no more silent default catalog.
      final p = c.create(
        name: 'Reedición',
        layout: buildLayoutTemplate(6, 4),
        capabilityProfileId: 'environment_room_v1',
      );
      await pump(
        t,
        BoardEditorPage(isOwner: true, presetId: p.id, presetCatalog: c),
      );
      await tap(t, 'editor-side-tab-add');
      await tap(t, 'editor-add-type-metric');
      await tap(t, 'editor-confirm-add');
      await tap(t, 'editor-side-tab-selected');
      await tap(t, 'editor-create-design-from-default');
      await t.tap(find.text('Volver al Board'));
      await t.pumpAndSettle();
      MetricBoardContent content() =>
          c.byId(p.id)!.items.single.content as MetricBoardContent;
      final id = content().cellLayoutPresetId!;
      for (final role in ['hero', 'xl']) {
        await tap(t, 'editor-open-cell-layout-editor');
        expect(
          find.byKey(const ValueKey('cell-editor-duplicate')),
          findsNothing,
        );
        await tap(t, 'cell-editor-element-value');
        await tap(t, 'cell-editor-size-role');
        await t.tap(find.text(role).last);
        await t.pumpAndSettle();
        await tap(t, 'cell-editor-save');
        await t.tap(find.text('Volver al Board'));
        await t.pumpAndSettle();
        expect(content().cellLayoutPresetId, id);
        expect(
          sharedCellLayoutPresetCatalog
              .byId(id)!
              .elements
              .firstWhere((e) => e.type == CellElementType.value)
              .sizeRole
              .name,
          role,
        );
      }
      for (final key in [
        'calefaccionEtapa1',
        'calefaccionEtapa2',
        'humidificacion',
      ]) {
        final chip = t.widget<FilterChip>(
          find.byKey(ValueKey('editor-indicator-$key')),
        );
        if (!chip.selected) await tap(t, 'editor-indicator-$key');
      }
      final indicatorsBefore = List.of(content().indicatorKeys);
      expect(indicatorsBefore, hasLength(3));
      await tap(t, 'editor-open-cell-layout-editor');
      await tap(t, 'cell-editor-select-slot-1');
      await tap(t, 'cell-editor-delete-selected-slot');
      await tap(t, 'cell-editor-save');
      await t.tap(find.text('Volver al Board'));
      await t.pumpAndSettle();
      expect(content().indicatorKeys, indicatorsBefore);
      expect(find.textContaining('insufficient_indicator_slots'), findsWidgets);
      expect(find.text('Duplicar diseño'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
