import '../cell_layout_presets/cell_layout_catalog.dart';
import '../cell_layout_presets/cell_layout_validator.dart';
import '../device_board_layouts/device_board_layout.dart';
import '../device_board_layouts/device_board_layout_validator.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../layout_templates/layout_template.dart';
import 'board_content_config.dart';
import 'board_content_layout.dart';

abstract final class BoardContentValidator {
  static List<LayoutValidationIssue> validate(
    BoardContentLayout board,
    LayoutTemplate template,
    DeviceMetricCatalog catalog,
    CellLayoutCatalog presets,
  ) {
    // Delegate metadata + metric semantics/bounds to existing N3 validator.
    final metricItems = board.items
        .where((i) => i.content is MetricBoardContent)
        .map((i) => i.toMetricItem())
        .toList();
    final legacy = DeviceBoardLayout(
      deviceId: board.deviceId,
      layoutTemplateId: board.layoutTemplateId,
      showTitle: board.showTitle,
      titleOverride: board.titleOverride,
      layoutVersion: board.layoutVersion,
      items: metricItems,
    );
    final issues =
        DeviceBoardLayoutValidator.validate(legacy, template, catalog)
            .where(
              (i) =>
                  i.code != 'duplicate_item_id' &&
                  i.code != 'placement_collision',
            )
            .toList();
    final ids = <String>{};
    for (final item in board.items) {
      if (!ids.add(item.id)) {
        issues.add(
          LayoutValidationIssue(
            code: 'duplicate_item_id',
            message: 'Duplicate board item',
            itemId: item.id,
          ),
        );
      }
      if (item.content is! MetricBoardContent &&
          !item.placement.fitsWithin(template)) {
        issues.add(
          LayoutValidationIssue(
            code: 'placement_out_of_bounds',
            message: 'Content exceeds external bounds',
            itemId: item.id,
          ),
        );
      }
      if (item.content is MetricBoardContent) {
        final metricItem = item.toMetricItem();
        try {
          // N7.1.1 §3 — validate against the item's own independent
          // snapshot when it has one, never a live catalog lookup: deleting
          // or editing the global CellLayoutPreset a Device once applied
          // must never turn into a validation issue (and, via A3's new
          // Guardar gating, never a save-blocking one).
          final snapshot =
              (item.content as MetricBoardContent).cellLayoutSnapshot;
          final preset = snapshot ?? presets.resolve(metricItem);
          for (final issue in CellLayoutValidator.validate(
            preset,
            metricItem,
            template,
          )) {
            if (issue.code == 'placement_out_of_bounds') continue;
            // N6.3: internal_out_of_bounds/internal_collision come back from
            // CellLayoutValidator carrying the *cell element's* id as
            // itemId/relatedItemId (e.g. 'value'/'unit') — never the board
            // item's own id, since N4's validator has no concept of a
            // board. Re-tagged here to the real board item id (as the
            // LayoutValidationException branch right below already does),
            // so the board-level issues panel/canvas can actually attribute
            // the problem to the right item — the original element ids are
            // preserved in the message text instead of lost.
            final isInternal = issue.itemId != metricItem.id;
            issues.add(
              LayoutValidationIssue(
                code: issue.code,
                message: isInternal
                    ? '${issue.message}'
                          '${issue.relatedItemId != null
                              ? ' (${issue.itemId} ↔ ${issue.relatedItemId})'
                              : issue.itemId != null
                              ? ' (${issue.itemId})'
                              : ''}'
                    : issue.message,
                itemId: item.id,
                metricKey: metricItem.metricKey,
              ),
            );
          }
        } on LayoutValidationException catch (error) {
          for (final issue in error.issues) {
            issues.add(
              LayoutValidationIssue(
                code: issue.code,
                message: issue.message,
                itemId: item.id,
                metricKey: metricItem.metricKey,
              ),
            );
          }
        }
      }
    }
    // Every type shares N3's rectangle predicate, including mixed-type pairs.
    for (var a = 0; a < board.items.length; a++) {
      for (var b = a + 1; b < board.items.length; b++) {
        if (DeviceBoardLayoutValidator.placementsOverlap(
          board.items[a].placement,
          board.items[b].placement,
        )) {
          issues.add(
            LayoutValidationIssue(
              code: 'placement_collision',
              message: 'Board contents overlap',
              itemId: board.items[a].id,
              relatedItemId: board.items[b].id,
            ),
          );
        }
      }
    }
    return List.unmodifiable(issues);
  }
}
