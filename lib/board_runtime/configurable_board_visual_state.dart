import 'package:flutter/material.dart';

import '../models/dashboard_range_settings.dart';
import '../ui_templates/board/template_data_resolver.dart';
import '../ui_templates/enums/metric_status_behavior.dart';
import '../ui_templates/models/metric_definition.dart';
import '../ui_templates/shared/template_visual_state.dart';

/// Presentation state for one configurable-board metric.
///
/// This adapter deliberately delegates every threshold decision to the same
/// resolver used by the legacy board. It adds no demo-specific rules.
class ConfigurableBoardMetricVisualState {
  const ConfigurableBoardMetricVisualState({
    required this.level,
    required this.valueColor,
    required this.iconColor,
    required this.borderColor,
    required this.borderWidth,
  });

  const ConfigurableBoardMetricVisualState.neutral()
    : level = TemplateAlarmLevel.unavailable,
      valueColor = const Color(0xFFE5E7EB),
      iconColor = const Color(0xFF7DD3FC),
      borderColor = null,
      borderWidth = 1;

  final TemplateAlarmLevel level;
  final Color valueColor;
  final Color iconColor;
  final Color? borderColor;
  final double borderWidth;

  bool get isSensorFailure => level == TemplateAlarmLevel.sensorFailure;
}

ConfigurableBoardMetricVisualState resolveConfigurableBoardMetricVisualState({
  required MetricDefinition metric,
  required Object? deviceData,
  required DashboardRangeSettings rangeSettings,
}) {
  const resolver = TemplateDataResolver();
  final Object? value = resolver.resolveMetric(metric, deviceData);
  if (value == null || metric.statusBehavior == MetricStatusBehavior.none) {
    return const ConfigurableBoardMetricVisualState.neutral();
  }
  final level = resolveTemplateAlarmLevel(
    metric: metric,
    value: value,
    deviceData: deviceData,
    rangeSettings: rangeSettings,
  );
  final color = templateAlarmLevelColor(level);
  return ConfigurableBoardMetricVisualState(
    level: level,
    valueColor: color,
    iconColor: level == TemplateAlarmLevel.unavailable
        ? const Color(0xFFCBD5E1)
        : color,
    borderColor: switch (level) {
      TemplateAlarmLevel.warning => const Color(0xFFFACC15),
      TemplateAlarmLevel.alarm => const Color(0xFFEF4444),
      TemplateAlarmLevel.sensorFailure => const Color(0xFFEF4444),
      _ => null,
    },
    borderWidth:
        level == TemplateAlarmLevel.alarm ||
            level == TemplateAlarmLevel.sensorFailure
        ? 2
        : 1.2,
  );
}
