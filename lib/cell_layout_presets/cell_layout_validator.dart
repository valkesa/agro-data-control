import '../device_board_layouts/device_board_layout.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import '../layout_templates/layout_template.dart';
import 'cell_layout_preset.dart';

abstract final class CellLayoutValidator {
  static bool overlaps(InternalGridPlacement a, InternalGridPlacement b) =>
      a.x < b.x + b.widthUnits &&
      b.x < a.x + a.widthUnits &&
      a.y < b.y + b.heightUnits &&
      b.y < a.y + a.heightUnits;
  static List<LayoutValidationIssue> collisions(
    List<CellLayoutElement> elements,
  ) {
    final issues = <LayoutValidationIssue>[];
    for (var i = 0; i < elements.length; i++) {
      for (var j = i + 1; j < elements.length; j++) {
        if (overlaps(elements[i].placement, elements[j].placement)) {
          issues.add(
            LayoutValidationIssue(
              code: 'internal_collision',
              message: 'Internal elements overlap',
              itemId: elements[i].id,
              relatedItemId: elements[j].id,
            ),
          );
        }
      }
    }
    return List.unmodifiable(issues);
  }

  static List<LayoutValidationIssue> validate(
    CellLayoutPreset preset,
    DeviceBoardLayoutItem item,
    LayoutTemplate template,
  ) {
    final issues = <LayoutValidationIssue>[];
    void issue(String code, String message) => issues.add(
      LayoutValidationIssue(
        code: code,
        message: message,
        itemId: item.id,
        metricKey: item.metricKey,
      ),
    );
    if (item.cellLayoutPresetId != null &&
        item.cellLayoutPresetId != preset.id) {
      issue('cell_preset_mismatch', 'Selected preset ID does not match');
    }
    if (!preset.enabled) issue('cell_preset_disabled', 'Preset is disabled');
    if (preset.widthCells != item.placement.widthCells ||
        preset.heightCells != item.placement.heightCells) {
      issue('cell_span_mismatch', 'Preset span differs from item span');
    }
    if (!item.placement.fitsWithin(template)) {
      issue('placement_out_of_bounds', 'External placement is out of bounds');
    }
    if (preset.widthCells > template.columns ||
        preset.heightCells > template.rows) {
      issue('preset_out_of_bounds', 'Preset span cannot fit template');
    } else {
      final columns = preset.internalColumns(template);
      final rows = preset.internalRows(template);
      for (final element in preset.elements) {
        if (!element.placement.fitsWithin(columns, rows)) {
          issues.add(
            LayoutValidationIssue(
              code: 'internal_out_of_bounds',
              message: 'Element exceeds derived internal grid',
              itemId: element.id,
            ),
          );
        }
      }
    }
    if (item.indicatorKeys.length > preset.indicatorSlotCount) {
      issue(
        'insufficient_indicator_slots',
        'Selected indicators exceed available slots',
      );
    }
    issues.addAll(collisions(preset.elements));
    // IDs, slot topology, versions and enum types are constructor invariants.
    return List.unmodifiable(issues);
  }
}
