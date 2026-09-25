import '../device_board_layouts/board_parsing.dart';
import '../device_board_layouts/device_board_layout.dart';
import '../layout_templates/layout_template.dart';
import '../ui_templates/models/metric_definition.dart';
import 'cell_layout_preset.dart';
import 'cell_layout_validator.dart';

class ResolvedCellElement {
  const ResolvedCellElement({
    required this.element,
    this.text,
    this.iconRef,
    this.indicatorKey,
    this.valuePending = false,
  });
  final CellLayoutElement element;
  final String? text;
  final String? iconRef;
  final String? indicatorKey;
  final bool valuePending;
  bool get emptyIndicator =>
      element.type == CellElementType.indicator && indicatorKey == null;
}

abstract final class CellContentResolver {
  /// N3 catalog validation remains a prerequisite. Template context additionally
  /// prevents resolving invalid geometry. No snapshots, SDKs or Flutter widgets.
  static List<ResolvedCellElement> resolve(
    MetricDefinition metric,
    DeviceBoardLayoutItem item,
    CellLayoutPreset preset, {
    required LayoutTemplate template,
  }) {
    if (metric.key != item.metricKey) {
      BoardParsing.fail('metric_mismatch', 'Metric differs from N3 selection');
    }
    final issues = CellLayoutValidator.validate(preset, item, template);
    if (issues.isNotEmpty) {
      BoardParsing.fail(issues.first.code, issues.first.message);
    }
    return List.unmodifiable(
      preset.elements.map(
        (element) => switch (element.type) {
          CellElementType.label => ResolvedCellElement(
            element: element,
            text: metric.label,
          ),
          CellElementType.unit => ResolvedCellElement(
            element: element,
            text: metric.unit,
          ),
          CellElementType.icon => ResolvedCellElement(
            element: element,
            iconRef: metric.icon,
          ),
          CellElementType.value => ResolvedCellElement(
            element: element,
            valuePending: true,
          ),
          CellElementType.indicator => ResolvedCellElement(
            element: element,
            indicatorKey: element.indicatorSlot! < item.indicatorKeys.length
                ? item.indicatorKeys[element.indicatorSlot!]
                : null,
          ),
        },
      ),
    );
  }
}
