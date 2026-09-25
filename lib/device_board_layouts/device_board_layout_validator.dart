import '../device_metric_catalogs/device_metric_catalog.dart';
import '../layout_templates/grid_placement.dart';
import '../layout_templates/layout_template.dart';
import 'device_board_layout.dart';
import 'layout_validation_issue.dart';

abstract final class DeviceBoardLayoutValidator {
  /// Half-open rectangles: touching edges/corners are not intersections.
  static bool placementsOverlap(GridPlacement a, GridPlacement b) =>
      a.x < b.x + b.widthCells &&
      b.x < a.x + a.widthCells &&
      a.y < b.y + b.heightCells &&
      b.y < a.y + a.heightCells;

  /// O(n²) rectangle comparisons, O(1) geometry storage; no grid allocation.
  /// All pairs are checked once so editors can highlight every collision.
  static List<LayoutValidationIssue> collisions(
    List<DeviceBoardLayoutItem> items,
  ) {
    final issues = <LayoutValidationIssue>[];
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        if (placementsOverlap(items[i].placement, items[j].placement)) {
          issues.add(
            LayoutValidationIssue(
              code: 'placement_collision',
              message: 'Items ${items[i].id} and ${items[j].id} overlap',
              itemId: items[i].id,
              metricKey: items[i].metricKey,
              relatedItemId: items[j].id,
            ),
          );
        }
      }
    }
    return List.unmodifiable(issues);
  }

  static List<LayoutValidationIssue> validate(
    DeviceBoardLayout board,
    LayoutTemplate template,
    DeviceMetricCatalog catalog,
  ) {
    final issues = <LayoutValidationIssue>[];
    if (board.layoutTemplateId != template.id) {
      issues.add(
        const LayoutValidationIssue(
          code: 'layout_template_mismatch',
          message: 'The supplied template does not match layoutTemplateId',
        ),
      );
    }
    if (!template.enabled) {
      issues.add(
        const LayoutValidationIssue(
          code: 'layout_template_disabled',
          message: 'The selected template is disabled',
        ),
      );
    }
    // Versions and title are already enforced by immutable domain constructors.
    final ids = <String>{};
    for (final item in board.items) {
      void issue(String code, String message) => issues.add(
        LayoutValidationIssue(
          code: code,
          message: message,
          itemId: item.id,
          metricKey: item.metricKey,
        ),
      );
      if (!ids.add(item.id)) {
        issue('duplicate_item_id', 'Repeated item ID ${item.id}');
      }
      if (catalog.metricByKey(item.metricKey) == null) {
        issue(
          'metric_not_found',
          'Missing metric ${item.metricKey} in effective catalog',
        );
      }
      if (!item.placement.fitsWithin(template)) {
        issue('placement_out_of_bounds', 'Placement exceeds template bounds');
      }
      final selected = <String>{};
      final available =
          catalog.availableIndicators[item.metricKey] ?? const <String>[];
      for (final key in item.indicatorKeys) {
        if (!selected.add(key)) {
          issue('duplicate_indicator_key', 'Repeated indicator $key');
        }
        if (!available.contains(key) || catalog.indicatorByKey(key) == null) {
          issue(
            'indicator_not_available',
            'Indicator $key is not available for ${item.metricKey}',
          );
        }
      }
    }
    issues.addAll(collisions(board.items));
    return List.unmodifiable(issues);
  }
}
