import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/board_preview/cell_layout_canvas.dart';
import 'package:agro_data_control/board_preview/cell_editor_tokens.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_editor_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset_catalog.dart';
import 'package:agro_data_control/device_metric_catalogs/reference_metric_catalogs.dart';
import 'board_preview_test.dart' as f;
import 'n6_3_2_cell_ux_test.dart' as ux;

CellLayoutPreset sparse() => CellLayoutPreset(
  id: 'sparse',
  name: 'Sparse',
  widthCells: 2,
  heightCells: 2,
  elements: [
    for (final (i, type) in [
      CellElementType.label,
      CellElementType.value,
      CellElementType.unit,
      CellElementType.icon,
      CellElementType.indicator,
    ].indexed)
      CellLayoutElement(
        id: type.name,
        type: type,
        placement: InternalGridPlacement(
          x: i * 3,
          y: 0,
          widthUnits: 2,
          heightUnits: 2,
        ),
        indicatorSlot: type == CellElementType.indicator ? 0 : null,
      ),
  ],
);
void main() {
  testWidgets(
    'C1 occupied element wins hit test and moving remains armed for every kind',
    (t) async {
      final c = CellLayoutPresetCatalog(initial: [sparse()]);
      await ux.pump(
        t,
        CellLayoutEditorPage(isOwner: true, presetId: 'sparse', catalog: c),
      );
      await ux.tap(t, 'cell-editor-element-value');
      await ux.tap(t, 'cell-editor-move-with-click');
      for (final id in ['unit', 'icon', 'label', 'indicator']) {
        await ux.tap(t, 'cell-editor-element-$id');
        expect(
          t
              .widget<FilterChip>(
                find.byKey(const ValueKey('cell-editor-move-with-click')),
              )
              .selected,
          isTrue,
        );
        final canvas = t.widget<CellLayoutCanvas>(
          find.byType(CellLayoutCanvas),
        );
        expect(canvas.selectedElementId, id);
        final before = t.widget<Positioned>(
          find.byKey(ValueKey('cell-editor-element-$id')),
        );
        // Each new destination is free and preserves a two-unit footprint.
        final y = 4 + ['unit', 'icon', 'label', 'indicator'].indexOf(id) * 3;
        await ux.tap(t, 'cell-editor-tap-0-$y');
        final after = t.widget<Positioned>(
          find.byKey(ValueKey('cell-editor-element-$id')),
        );
        expect(after.top, greaterThan(before.top!));
        expect(
          t
              .widget<CellLayoutCanvas>(find.byType(CellLayoutCanvas))
              .selectedElementId,
          id,
        );
        expect(
          t
              .widget<FilterChip>(
                find.byKey(const ValueKey('cell-editor-move-with-click')),
              )
              .selected,
          isTrue,
        );
      }
      expect(find.byKey(const ValueKey('cell-editor-issues')), findsNothing);
      await ux.tap(t, 'cell-editor-save');
      expect(
        c
            .byId('sparse')!
            .elements
            .firstWhere((e) => e.id == 'value')
            .placement
            .x,
        3,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'C2 all footprints, hidden selectable, selected contrast; no editor borders in preview',
    (t) async {
      final c = CellLayoutPresetCatalog(initial: [sparse()]);
      await ux.pump(
        t,
        CellLayoutEditorPage(isOwner: true, presetId: 'sparse', catalog: c),
      );
      Border border(String id) =>
          (t
                          .widget<DecoratedBox>(
                            find
                                .descendant(
                                  of: find.byKey(
                                    ValueKey('cell-editor-element-$id'),
                                  ),
                                  matching: find.byType(DecoratedBox),
                                )
                                .first,
                          )
                          .decoration
                      as BoxDecoration)
                  .border!
              as Border;
      for (final e in sparse().elements) {
        expect(border(e.id).top.color, cellEditorElementBorder);
      }
      await ux.tap(t, 'cell-editor-element-value');
      expect(border('value').top.color, cellEditorElementBorderSelected);
      expect(border('value').top.width, greaterThan(border('unit').top.width));
      await ux.tap(t, 'cell-editor-visible');
      expect(
        find.byKey(const ValueKey('cell-editor-element-value')),
        findsOneWidget,
      );
      await ux.tap(t, 'cell-editor-element-unit');
      expect(border('value').top.color, cellEditorElementBorderHidden);
      await ux.tap(t, 'cell-editor-element-value');
      expect(
        t
            .widget<CellLayoutCanvas>(find.byType(CellLayoutCanvas))
            .selectedElementId,
        'value',
      );
      await ux.tap(t, 'cell-editor-save');
      await t.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 320,
              child: CellLayoutCanvas(
                columns: 16,
                rows: 16,
                rawElements: c.byId('sparse')!.elements,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('cell-element-value')), findsNothing);
      for (final box in t.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration && decoration.border is Border) {
          expect((decoration.border as Border).top.color, Colors.transparent);
        }
      }
      expect(t.takeException(), isNull);
    },
  );
  test(
    'C3 compatible serialization, copy/clear, invalid type, item roundtrip',
    () {
      final original = MetricBoardContent(metricKey: 'tempInterior');
      expect(original.toMap().containsKey('labelOverride'), isFalse);
      final custom = original.copyWith(
        labelOverride: 'Temp. Sala',
        unitOverride: '°C interior',
      );
      final item = f.cell(custom);
      final roundtrip =
          BoardContentItem.fromMap(item.toMap()).content as MetricBoardContent;
      expect(roundtrip.labelOverride, 'Temp. Sala');
      expect(roundtrip.unitOverride, '°C interior');
      expect(roundtrip.copyWith(indicatorKeys: []).labelOverride, 'Temp. Sala');
      expect(
        roundtrip.copyWith(clearLabelOverride: true).labelOverride,
        isNull,
      );
      expect(roundtrip.copyWith(unitOverride: '   ').unitOverride, isNull);
      expect(
        () => MetricBoardContent.fromMap({
          ...original.toMap(),
          'labelOverride': 42,
        }),
        throwsArgumentError,
      );
    },
  );
  testWidgets(
    'C3 same metric in two items, independent presentation and fallback',
    (t) async {
      final catalog = referenceMetricCatalogById('environment_room_v1')!;
      final metric = catalog.metricByKey('tempInterior')!;
      final originalLabel = metric.label, originalUnit = metric.unit;
      final custom = MetricBoardContent(
        metricKey: 'tempInterior',
        labelOverride: 'Temp. Sala',
        unitOverride: '°C interior',
      );
      await f.pump(
        t,
        f.render(
          f.board([
            f.cell(custom, id: 'a'),
            f.cell(
              custom.copyWith(
                labelOverride: 'Otro ambiente',
                unitOverride: 'grados',
              ),
              id: 'b',
              x: 1,
            ),
          ]),
        ),
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('metric-a-label'))).data,
        'Temp. Sala',
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('metric-b-label'))).data,
        'Otro ambiente',
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('metric-a-unit'))).data,
        '°C interior',
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('metric-b-unit'))).data,
        'grados',
      );
      expect(metric.label, originalLabel);
      expect(metric.unit, originalUnit);
      await f.pump(
        t,
        f.render(
          f.board([
            f.cell(
              custom.copyWith(
                clearLabelOverride: true,
                clearUnitOverride: true,
              ),
              id: 'a',
            ),
          ]),
        ),
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('metric-a-label'))).data,
        originalLabel,
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('metric-a-unit'))).data,
        originalUnit,
      );
    },
  );
  testWidgets(
    'C3 typing updates preview without Enter; selection and design preserve overrides',
    (t) async {
      await ux.pump(t, const BoardEditorPage(isOwner: true));
      await ux.tap(t, 'edit-placement-humidity');
      final label = find.byKey(const ValueKey('editor-metric-label-override'));
      final unit = find.byKey(const ValueKey('editor-metric-unit-override'));
      await t.enterText(label, 'Mi etiqueta');
      await t.pumpAndSettle();
      await t.enterText(unit, 'mi unidad');
      await t.pumpAndSettle();
      expect(
        t
            .widget<Text>(find.byKey(const ValueKey('metric-humidity-label')))
            .data,
        'Mi etiqueta',
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('metric-humidity-unit'))).data,
        'mi unidad',
      );
      await ux.tap(t, 'editor-create-design-from-default');
      await t.tap(find.text('Volver al Board'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<Text>(find.byKey(const ValueKey('metric-humidity-label')))
            .data,
        'Mi etiqueta',
      );
      await ux.tap(t, 'edit-placement-ammonia');
      await ux.tap(t, 'edit-placement-humidity');
      expect(t.widget<TextField>(label).controller!.text, 'Mi etiqueta');
      await t.enterText(label, '');
      await t.enterText(unit, '');
      await t.pumpAndSettle();
      expect(
        t
            .widget<Text>(find.byKey(const ValueKey('metric-humidity-label')))
            .data,
        'Humedad interior',
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final role in [CellSizeRole.xxl, CellSizeRole.hero]) {
    for (final type in [CellElementType.value, CellElementType.icon]) {
      testWidgets(
        'C4 ${role.name} ${type.name}: footprint clips, never scales; global unit still scales',
        (t) async {
          double? naturalSize;
          for (final width in [8, 1]) {
            final e = CellLayoutElement(
              id: type.name,
              type: type,
              sizeRole: role,
              placement: InternalGridPlacement(
                x: 0,
                y: 0,
                widthUnits: width,
                heightUnits: 1,
              ),
            );
            Future<void> render(double side) async {
              await t.pumpWidget(
                MaterialApp(
                  home: Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: CellLayoutCanvas(
                        columns: 16,
                        rows: 16,
                        rawElements: [e],
                      ),
                    ),
                  ),
                ),
              );
              await t.pumpAndSettle();
            }

            await render(320);
            final footprint = find.byKey(ValueKey('cell-element-${type.name}'));
            final size = type == CellElementType.value
                ? t
                      .widget<Text>(
                        find.byKey(const ValueKey('metric-cell-value')),
                      )
                      .style!
                      .fontSize!
                : t.widget<Icon>(find.byType(Icon)).size!;
            naturalSize ??= size;
            expect(size, naturalSize);
            expect(
              find.descendant(of: footprint, matching: find.byType(FittedBox)),
              findsNothing,
            );
            final clip = find
                .descendant(of: footprint, matching: find.byType(ClipRect))
                .first;
            expect(t.widget<ClipRect>(clip).clipBehavior, Clip.hardEdge);
            expect(t.getSize(clip).width, width * 20 - 6);
            if (width == 1) {
              final child = type == CellElementType.value
                  ? find.byKey(const ValueKey('metric-cell-value'))
                  : find.byType(Icon);
              expect(
                t.getSize(child).width,
                greaterThan(t.getSize(clip).width),
              );
            }
            await render(160);
            final smaller = type == CellElementType.value
                ? t
                      .widget<Text>(
                        find.byKey(const ValueKey('metric-cell-value')),
                      )
                      .style!
                      .fontSize!
                : t.widget<Icon>(find.byType(Icon)).size!;
            expect(smaller, size / 2);
            expect(t.takeException(), isNull);
          }
        },
      );
    }
  }
}
