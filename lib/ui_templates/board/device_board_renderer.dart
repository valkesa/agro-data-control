import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dashboard_range_settings.dart';
import '../../models/munters_model.dart';
import '../../models/plc_unit_diagnostics.dart';
import '../../utils/fan_animation.dart';
import '../enums/board_preset.dart';
import '../enums/board_slot_size.dart';
import '../enums/indicator_position.dart';
import '../enums/metric_display_type.dart';
import '../enums/metric_status_behavior.dart';
import '../models/board_slot.dart';
import '../models/device_template.dart';
import '../models/indicator_definition.dart';
import '../models/metric_definition.dart';
import '../shared/template_visual_state.dart';
import 'template_data_resolver.dart';
import 'template_icon_resolver.dart';
import 'template_value_formatter.dart';

const TextStyle _cardTitleTextStyle = TextStyle(
  color: Color(0xFFE5E7EB),
  fontSize: 15,
  fontWeight: FontWeight.w800,
);

/// A small, generic tap action a caller can attach to one metric slot by its
/// [MetricDefinition.key] (via [DeviceBoardRenderer.metricActions]) — e.g. a
/// history-chart shortcut on `tempInterior`/`humedadInterior`. The renderer
/// only ever matches this by key; it has no idea what "history" or
/// "temperature" mean, so a new action type never requires touching this
/// file. `onTap` receives the slot tile's own [BuildContext] (valid at tap
/// time) rather than one captured earlier by the caller.
class BoardSlotAction {
  const BoardSlotAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final void Function(BuildContext context) onTap;
}

class DeviceBoardRenderer extends StatelessWidget {
  const DeviceBoardRenderer({
    super.key,
    required this.template,
    required this.deviceData,
    this.title,
    this.resolver = const TemplateDataResolver(),
    this.rangeSettings = const DashboardRangeSettings.defaults(),
    this.showSnapshotPulse = false,
    this.snapshotStale = false,
    this.metricActions,
  });

  final DeviceTemplate template;
  final Object? deviceData;
  final String? title;
  final TemplateDataResolver resolver;
  final DashboardRangeSettings rangeSettings;
  final bool showSnapshotPulse;
  final bool snapshotStale;

  /// Keyed by [MetricDefinition.key] (e.g. `'tempInterior'`), not by any
  /// tenant/Device identity — see [BoardSlotAction].
  final Map<String, BoardSlotAction>? metricActions;

  @override
  Widget build(BuildContext context) {
    final List<BoardSlot> visibleSlots =
        template.boardSlots
            .where((BoardSlot slot) => slot.visible)
            .toList(growable: false)
          ..sort(
            (BoardSlot a, BoardSlot b) => a.position.compareTo(b.position),
          );
    final _BoardPresetGeometry geometry = _geometryForPreset(
      template.boardPreset,
    );
    final Map<String, MetricDefinition> metricsByKey =
        <String, MetricDefinition>{
          for (final MetricDefinition metric in template.metrics)
            metric.key: metric,
        };
    final Map<String, IndicatorDefinition> indicatorsByKey =
        <String, IndicatorDefinition>{
          for (final IndicatorDefinition indicator in template.indicators)
            indicator.key: indicator,
        };

    final Widget card = Container(
      padding: EdgeInsets.all(geometry.padding),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: template.boardPreset == BoardPreset.large
          ? _LargeBoardPresetLayout(
              slots: visibleSlots,
              metricsByKey: metricsByKey,
              indicatorsByKey: indicatorsByKey,
              deviceData: deviceData,
              resolver: resolver,
              geometry: geometry,
              displayName: title,
              rangeSettings: rangeSettings,
              showSnapshotPulse: showSnapshotPulse,
              snapshotStale: snapshotStale,
              metricActions: metricActions,
            )
          : _FlowBoardPresetLayout(
              title: title ?? template.name,
              slots: visibleSlots,
              metricsByKey: metricsByKey,
              indicatorsByKey: indicatorsByKey,
              deviceData: deviceData,
              resolver: resolver,
              geometry: geometry,
              rangeSettings: rangeSettings,
              metricActions: metricActions,
            ),
    );

    if (geometry.minWidth <= 0) {
      return card;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!constraints.hasBoundedWidth ||
            constraints.maxWidth >= geometry.minWidth) {
          return card;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: geometry.minWidth, child: card),
        );
      },
    );
  }
}

class _FlowBoardPresetLayout extends StatelessWidget {
  const _FlowBoardPresetLayout({
    required this.title,
    required this.slots,
    required this.metricsByKey,
    required this.indicatorsByKey,
    required this.deviceData,
    required this.resolver,
    required this.geometry,
    required this.rangeSettings,
    this.metricActions,
  });

  final String title;
  final List<BoardSlot> slots;
  final Map<String, MetricDefinition> metricsByKey;
  final Map<String, IndicatorDefinition> indicatorsByKey;
  final Object? deviceData;
  final TemplateDataResolver resolver;
  final _BoardPresetGeometry geometry;
  final DashboardRangeSettings rangeSettings;
  final Map<String, BoardSlotAction>? metricActions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (title.isNotEmpty) ...<Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cardTitleTextStyle,
          ),
          SizedBox(height: geometry.gap),
        ],
        if (geometry.horizontalFlow)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < slots.length; i++) ...<Widget>[
                _DeviceBoardSlotTile(
                  key: Key('device-board-slot-${slots[i].metricKey}'),
                  slot: slots[i],
                  metric: metricsByKey[slots[i].metricKey],
                  indicatorsByKey: indicatorsByKey,
                  deviceData: deviceData,
                  resolver: resolver,
                  geometry: geometry,
                  rangeSettings: rangeSettings,
                  action: metricActions?[slots[i].metricKey],
                ),
                if (i != slots.length - 1) SizedBox(width: geometry.gap),
              ],
            ],
          )
        else
          Wrap(
            spacing: geometry.gap,
            runSpacing: geometry.gap,
            children: <Widget>[
              for (final BoardSlot slot in slots)
                _DeviceBoardSlotTile(
                  key: Key('device-board-slot-${slot.metricKey}'),
                  slot: slot,
                  metric: metricsByKey[slot.metricKey],
                  indicatorsByKey: indicatorsByKey,
                  deviceData: deviceData,
                  resolver: resolver,
                  geometry: geometry,
                  rangeSettings: rangeSettings,
                  action: metricActions?[slot.metricKey],
                ),
            ],
          ),
      ],
    );
  }
}

class _LargeBoardPresetLayout extends StatelessWidget {
  const _LargeBoardPresetLayout({
    required this.slots,
    required this.metricsByKey,
    required this.indicatorsByKey,
    required this.deviceData,
    required this.resolver,
    required this.geometry,
    required this.displayName,
    required this.rangeSettings,
    required this.showSnapshotPulse,
    required this.snapshotStale,
    this.metricActions,
  });

  final List<BoardSlot> slots;
  final Map<String, MetricDefinition> metricsByKey;
  final Map<String, IndicatorDefinition> indicatorsByKey;
  final Object? deviceData;
  final TemplateDataResolver resolver;
  final _BoardPresetGeometry geometry;
  final String? displayName;
  final DashboardRangeSettings rangeSettings;
  final bool showSnapshotPulse;
  final bool snapshotStale;
  final Map<String, BoardSlotAction>? metricActions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('device-board-large-layout'),
      height: geometry.largeLayoutHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DeviceBoardHeader(
            title: displayName,
            deviceData: deviceData,
            showSnapshotPulse: showSnapshotPulse,
            snapshotStale: snapshotStale,
          ),
          SizedBox(height: geometry.gap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: geometry.largeWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(height: geometry.largeHeight, child: _slot(1)),
                      SizedBox(height: geometry.gap),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Expanded(child: _slot(2)),
                            SizedBox(width: geometry.gap),
                            Expanded(child: _slot(3)),
                          ],
                        ),
                      ),
                      SizedBox(height: geometry.gap),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Expanded(child: _slot(4)),
                            SizedBox(width: geometry.gap),
                            Expanded(child: _slot(5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: geometry.gap),
                SizedBox(
                  width: geometry.largeRightColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        height: geometry.largeHeight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Expanded(child: _rightPair(6, 7)),
                            SizedBox(height: geometry.gap),
                            Expanded(child: _rightPair(8, 9)),
                          ],
                        ),
                      ),
                      SizedBox(height: geometry.gap),
                      Expanded(child: _rightPair(10, 11)),
                      SizedBox(height: geometry.gap),
                      Expanded(child: _rightPair(12, 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rightPair(int leftPosition, int rightPosition) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: _slot(leftPosition)),
        SizedBox(width: geometry.gap),
        Expanded(child: _slot(rightPosition)),
      ],
    );
  }

  Widget _slot(int position) {
    final BoardSlot? slot = _slotByPosition(position);
    if (slot == null) {
      return const SizedBox.shrink();
    }
    return _DeviceBoardSlotTile(
      key: Key('device-board-slot-${slot.metricKey}'),
      slot: slot,
      metric: metricsByKey[slot.metricKey],
      indicatorsByKey: indicatorsByKey,
      deviceData: deviceData,
      resolver: resolver,
      geometry: geometry,
      fillParent: true,
      displayValueOverride: slot.metricKey == 'deviceName' ? displayName : null,
      visualSize: position <= 5 ? slot.size : BoardSlotSize.small,
      rangeSettings: rangeSettings,
      action: metricActions?[slot.metricKey],
    );
  }

  BoardSlot? _slotByPosition(int position) {
    for (final BoardSlot slot in slots) {
      if (slot.position == position) {
        return slot;
      }
    }
    return null;
  }
}

enum _TemplateDotMode { blinking, fixed }

class _MetricVisualState {
  const _MetricVisualState({
    required this.level,
    required this.valueColor,
    required this.iconColor,
    this.borderColor,
    this.borderWidth = 1,
  });

  const _MetricVisualState.neutral()
    : level = TemplateAlarmLevel.unavailable,
      valueColor = const Color(0xFFE5E7EB),
      iconColor = const Color(0xFFCBD5E1),
      borderColor = null,
      borderWidth = 1;

  final TemplateAlarmLevel level;
  final Color valueColor;
  final Color iconColor;
  final Color? borderColor;
  final double borderWidth;
}

class _DeviceBoardHeader extends StatelessWidget {
  const _DeviceBoardHeader({
    required this.title,
    required this.deviceData,
    required this.showSnapshotPulse,
    required this.snapshotStale,
  });

  final String? title;
  final Object? deviceData;
  final bool showSnapshotPulse;
  final bool snapshotStale;

  @override
  Widget build(BuildContext context) {
    final String label = title?.trim().isNotEmpty == true
        ? title!.trim()
        : readTemplateText(deviceData, 'name') ?? '';
    final TemplateAlarmLevel power = _resolvePowerLevel(deviceData);
    final _DotVisual witness = _resolveWitnessDot(deviceData);
    return Row(
      key: const Key('device-board-header'),
      children: <Widget>[
        Icon(Icons.memory, size: 15, color: templateAlarmLevelColor(power)),
        const SizedBox(width: 5),
        Tooltip(
          message: 'PLC funcionando',
          child: _TemplateBlinkDot(
            key: const Key('device-board-dot-plc'),
            color: witness.color,
            mode: witness.mode,
          ),
        ),
        const SizedBox(width: 3),
        Tooltip(
          message: snapshotStale ? 'Backend sin datos' : 'Backend con datos',
          child: _TemplatePulseDot(
            key: const Key('device-board-dot-backend'),
            active: showSnapshotPulse,
            backendAlive: !snapshotStale,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cardTitleTextStyle,
          ),
        ),
      ],
    );
  }
}

class _DotVisual {
  const _DotVisual({required this.color, required this.mode});

  final Color color;
  final _TemplateDotMode mode;
}

class _TemplateBlinkDot extends StatefulWidget {
  const _TemplateBlinkDot({super.key, required this.color, required this.mode});

  final Color color;
  final _TemplateDotMode mode;

  @override
  State<_TemplateBlinkDot> createState() => _TemplateBlinkDotState();
}

class _TemplateBlinkDotState extends State<_TemplateBlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      value: 0.43,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == _TemplateDotMode.fixed) {
      return _dot(widget.color, 1);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        final double pulse = t < 0.22
            ? Curves.easeOut.transform(t / 0.22)
            : (t < 0.44 ? 1 - Curves.easeIn.transform((t - 0.22) / 0.22) : 0);
        return _dot(widget.color, 0.16 + pulse * 0.84);
      },
    );
  }
}

class _TemplatePulseDot extends StatelessWidget {
  const _TemplatePulseDot({
    super.key,
    required this.active,
    required this.backendAlive,
  });

  final bool active;
  final bool backendAlive;

  @override
  Widget build(BuildContext context) {
    if (!backendAlive) {
      return _dot(const Color(0xFFEF4444), 1);
    }
    return AnimatedOpacity(
      opacity: active ? 1 : 0.12,
      duration: const Duration(milliseconds: 140),
      child: _dot(const Color(0xFF22C55E), 1),
    );
  }
}

Widget _dot(Color color, double opacity) {
  return Opacity(
    opacity: opacity,
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withAlpha(120),
            blurRadius: 6,
            spreadRadius: 0.6,
          ),
        ],
      ),
    ),
  );
}

class _DeviceBoardSlotTile extends StatelessWidget {
  _DeviceBoardSlotTile({
    super.key,
    required this.slot,
    required this.metric,
    required this.indicatorsByKey,
    required this.deviceData,
    required this.resolver,
    required this.geometry,
    required this.rangeSettings,
    this.fillParent = false,
    this.displayValueOverride,
    this.action,
    BoardSlotSize? visualSize,
  }) : visualSize = visualSize ?? slot.size;

  final BoardSlot slot;
  final MetricDefinition? metric;
  final Map<String, IndicatorDefinition> indicatorsByKey;
  final Object? deviceData;
  final TemplateDataResolver resolver;
  final _BoardPresetGeometry geometry;
  final DashboardRangeSettings rangeSettings;
  final bool fillParent;
  final Object? displayValueOverride;
  final BoardSlotSize visualSize;

  /// Set by the caller via [DeviceBoardRenderer.metricActions] keyed by
  /// [MetricDefinition.key] — this tile never knows what the action means.
  final BoardSlotAction? action;

  @override
  Widget build(BuildContext context) {
    final MetricDefinition? resolvedMetric = metric;
    if (resolvedMetric == null) {
      return _slotFrame(
        visualState: const _MetricVisualState.neutral(),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline, color: Color(0xFFF87171)),
            SizedBox(height: 6),
            Text(
              'Unknown metric',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Color(0xFFF87171), fontSize: 11),
            ),
          ],
        ),
      );
    }

    final Object? value =
        displayValueOverride ??
        resolver.resolveMetric(resolvedMetric, deviceData);
    final String formattedValue = formatTemplateMetricValue(
      resolvedMetric,
      value,
    );
    final String formattedUnit = formatTemplateMetricUnit(
      resolvedMetric,
      value,
    );
    final String? contextualValueLabel =
        resolvedMetric.valueLabelSourceField == null
        ? null
        : resolver
              .resolveSourceField(
                resolvedMetric.valueLabelSourceField!,
                deviceData,
              )
              ?.toString();
    final String displayLabel = visualSize == BoardSlotSize.large
        ? resolvedMetric.label
        : resolvedMetric.shortLabel ?? resolvedMetric.label;
    final bool centerCompactLabel =
        visualSize == BoardSlotSize.small && slot.showLabel;
    final Widget valueWidget = _MetricValue(
      metric: resolvedMetric,
      value: value,
      formattedValue: formattedValue,
      formattedUnit: formattedUnit,
      contextualLabel: contextualValueLabel,
      geometry: geometry,
      slotSize: visualSize,
      visualState: _resolveMetricVisualState(
        metric: resolvedMetric,
        value: value,
        deviceData: deviceData,
        rangeSettings: rangeSettings,
      ),
    );
    final List<_ResolvedIndicator> indicators = _resolveIndicators();
    final _MetricVisualState visualState = _resolveMetricVisualState(
      metric: resolvedMetric,
      value: value,
      deviceData: deviceData,
      rangeSettings: rangeSettings,
    );

    return _slotFrame(
      visualState: visualState,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (centerCompactLabel)
            SizedBox(
              height: geometry.iconSizeFor(visualSize),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  if (slot.showIcon)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TemplateMetricIcon(
                        iconId: resolvedMetric.icon,
                        value: value,
                        deviceData: deviceData,
                        size: geometry.iconSizeFor(visualSize),
                        color: visualState.iconColor,
                      ),
                    ),
                  Center(
                    child: Text(
                      displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFCBD5E1),
                        fontSize: geometry.labelFontSizeFor(visualSize),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              mainAxisAlignment: slot.showLabel
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: <Widget>[
                if (slot.showIcon)
                  _TemplateMetricIcon(
                    iconId: resolvedMetric.icon,
                    value: value,
                    deviceData: deviceData,
                    size: geometry.iconSizeFor(visualSize),
                    color: visualState.iconColor,
                  ),
                if (slot.showLabel) ...<Widget>[
                  if (slot.showIcon) SizedBox(width: geometry.gap * 0.65),
                  Flexible(
                    child: Text(
                      displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFCBD5E1),
                        fontSize: geometry.labelFontSizeFor(visualSize),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _IndicatorAwareValue(
                  value: valueWidget,
                  indicators: indicators,
                  geometry: geometry,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotFrame({
    required Widget child,
    required _MetricVisualState visualState,
  }) {
    final Widget frame = Container(
      padding: geometry.tilePaddingFor(visualSize),
      decoration: BoxDecoration(
        color: const Color(0xFF162133),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: visualState.borderColor ?? const Color(0xFF5B6B82),
          width: visualState.borderColor == null
              ? 0.75
              : visualState.borderWidth,
        ),
      ),
      child: child,
    );
    final BoardSlotAction? slotAction = action;
    final Widget framed = slotAction == null
        ? frame
        : Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              frame,
              Positioned(
                top: 4,
                right: 4,
                child: _BoardSlotActionButton(action: slotAction),
              ),
            ],
          );
    if (fillParent) {
      return SizedBox.expand(
        key: Key('device-board-slot-position-${slot.position}'),
        child: framed,
      );
    }
    return SizedBox(
      key: Key('device-board-slot-position-${slot.position}'),
      width: geometry.widthFor(visualSize),
      height: geometry.heightFor(visualSize),
      child: framed,
    );
  }

  List<_ResolvedIndicator> _resolveIndicators() {
    final List<_ResolvedIndicator> resolved = <_ResolvedIndicator>[];
    for (final String indicatorKey in slot.indicators) {
      final IndicatorDefinition? indicator = indicatorsByKey[indicatorKey];
      if (indicator == null) {
        continue;
      }
      final Object? value = resolver.resolveSourceField(
        indicator.sourceField,
        deviceData,
      );
      resolved.add(
        _ResolvedIndicator(indicator, active: value == indicator.condition),
      );
    }
    return resolved;
  }
}

/// Small discreet badge for a [BoardSlotAction], rendered inside the metric
/// slot's own box (not floating over the whole card) — see
/// Prompt_Fix_Etapa_1_de_2_Accesos_Historicos_en_Las_Heras §4.
class _BoardSlotActionButton extends StatelessWidget {
  const _BoardSlotActionButton({required this.action});
  final BoardSlotAction action;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: action.tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => action.onTap(context),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: const Color(0xCC0F172A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3A4A61)),
        ),
        child: Icon(action.icon, size: 12, color: const Color(0xFFCBD5E1)),
      ),
    ),
  );
}

class _MetricValue extends StatelessWidget {
  const _MetricValue({
    required this.metric,
    required this.value,
    required this.formattedValue,
    required this.formattedUnit,
    required this.contextualLabel,
    required this.geometry,
    required this.slotSize,
    required this.visualState,
  });

  final MetricDefinition metric;
  final Object? value;
  final String formattedValue;
  final String formattedUnit;
  final String? contextualLabel;
  final _BoardPresetGeometry geometry;
  final BoardSlotSize slotSize;
  final _MetricVisualState visualState;

  @override
  Widget build(BuildContext context) {
    if (visualState.level == TemplateAlarmLevel.sensorFailure) {
      return Tooltip(
        message: 'Falla sensor (cod. ${formatSensorFailureCode(value)})',
        child: Icon(
          Icons.error_outline,
          key: const Key('device-board-sensor-failure'),
          color: const Color(0xFFEF4444),
          size: geometry.valueIconSizeFor(slotSize),
        ),
      );
    }

    if (metric.displayType == MetricDisplayType.boolean && value is bool) {
      final String label =
          contextualLabel ?? metric.shortLabel ?? formattedValue;
      if (metric.icon == 'door' || metric.icon == 'equipmentDoor') {
        return Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: visualState.valueColor,
            fontSize: geometry.valueFontSizeFor(slotSize) * 0.58,
            fontWeight: FontWeight.w800,
          ),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            value == true ? Icons.check_circle : Icons.cancel,
            color: value == true
                ? const Color(0xFF22C55E)
                : const Color(0xFF64748B),
            size: geometry.valueIconSizeFor(slotSize),
          ),
          SizedBox(width: geometry.gap * 0.55),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFE5E7EB),
              fontSize: geometry.valueFontSizeFor(slotSize) * 0.55,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          formattedValue,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: value == null
                ? const Color(0xFF94A3B8)
                : visualState.valueColor,
            fontSize: value == null
                ? geometry.valueFontSizeFor(slotSize) * 0.42
                : geometry.valueFontSizeFor(slotSize),
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        if (formattedUnit.isNotEmpty) ...<Widget>[
          SizedBox(width: geometry.gap * 0.3),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              formattedUnit,
              style: TextStyle(
                color: value == null
                    ? const Color(0xFF94A3B8)
                    : visualState.valueColor,
                fontSize: geometry.unitFontSizeFor(slotSize),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _IndicatorAwareValue extends StatelessWidget {
  const _IndicatorAwareValue({
    required this.value,
    required this.indicators,
    required this.geometry,
  });

  final Widget value;
  final List<_ResolvedIndicator> indicators;
  final _BoardPresetGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final List<Widget> left = _iconsFor(IndicatorPosition.leftOfValue);
    final List<Widget> right = _iconsFor(IndicatorPosition.rightOfValue);
    final List<Widget> above = _iconsFor(IndicatorPosition.aboveValue);
    final List<Widget> below = _iconsFor(IndicatorPosition.belowValue);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (above.isNotEmpty) _indicatorRow(above),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (left.isNotEmpty) ...<Widget>[
              _indicatorRow(left),
              SizedBox(width: geometry.gap * 0.6),
            ],
            value,
            if (right.isNotEmpty) ...<Widget>[
              SizedBox(width: geometry.gap * 0.6),
              _indicatorRow(right),
            ],
          ],
        ),
        if (below.isNotEmpty) _indicatorRow(below),
      ],
    );
  }

  List<Widget> _iconsFor(IndicatorPosition position) {
    return indicators
        .where(
          (_ResolvedIndicator indicator) =>
              indicator.definition.position == position,
        )
        .map(
          (_ResolvedIndicator indicator) => _TemplateIndicatorIcon(
            key: Key('device-board-indicator-${indicator.definition.key}'),
            stateKey: Key(
              'device-board-indicator-state-${indicator.definition.key}-${indicator.active ? 'active' : 'inactive'}',
            ),
            iconId: indicator.definition.icon,
            active: indicator.active,
            size: geometry.indicatorIconSize,
          ),
        )
        .toList(growable: false);
  }

  Widget _indicatorRow(List<Widget> icons) {
    return Row(mainAxisSize: MainAxisSize.min, children: icons);
  }
}

class _ResolvedIndicator {
  const _ResolvedIndicator(this.definition, {required this.active});

  final IndicatorDefinition definition;
  final bool active;
}

class _TemplateIndicatorIcon extends StatelessWidget {
  const _TemplateIndicatorIcon({
    super.key,
    required this.stateKey,
    required this.iconId,
    required this.active,
    required this.size,
  });

  final Key stateKey;
  final String iconId;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String normalizedIcon = iconId.trim();
    final Color activeColor = normalizedIcon == 'snowflake'
        ? const Color(0xFF38BDF8)
        : const Color(0xFFF97316);
    final Widget icon = normalizedIcon == 'flame'
        ? _TemplateAnimatedHeatingFlameIcon(active: active, size: size)
        : Icon(
            resolveTemplateIcon(iconId),
            color: active ? activeColor : const Color(0xFF64748B),
            size: size,
          );
    return Opacity(key: stateKey, opacity: active ? 1 : 0.34, child: icon);
  }
}

class _TemplateMetricIcon extends StatelessWidget {
  const _TemplateMetricIcon({
    required this.iconId,
    required this.value,
    required this.deviceData,
    required this.size,
    required this.color,
  });

  final String iconId;
  final Object? value;
  final Object? deviceData;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final Object? metricValue = value;
    return switch (iconId.trim()) {
      'fan' => TemplateFanIcon(
        key: const Key('device-board-animated-fan'),
        running: resolveFanRunning(deviceData, metricValue),
        speedPercent: metricValue is num ? metricValue.toDouble() : null,
        size: size,
      ),
      'dewPoint' => _TemplateAnimatedDewPointIcon(
        key: const Key('device-board-animated-dew-point'),
        color: color,
        size: size,
      ),
      'door' || 'equipmentDoor' => Icon(
        value == true ? Icons.door_front_door : resolveTemplateIcon(iconId),
        size: size,
        color: color,
      ),
      'pig' => _PigBodyIcon(
        key: const Key('device-board-custom-pig-icon'),
        color: color,
        width: size * 1.45,
        height: size * 0.78,
      ),
      _ => Icon(resolveTemplateIcon(iconId), size: size, color: color),
    };
  }
}

class _TemplateAnimatedHeatingFlameIcon extends StatefulWidget {
  const _TemplateAnimatedHeatingFlameIcon({
    required this.active,
    required this.size,
  });

  final bool active;
  final double size;

  @override
  State<_TemplateAnimatedHeatingFlameIcon> createState() =>
      _TemplateAnimatedHeatingFlameIconState();
}

class _PigBodyIcon extends StatelessWidget {
  const _PigBodyIcon({
    super.key,
    required this.color,
    required this.width,
    required this.height,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _PigBodyIconPainter(color)),
    );
  }
}

class _PigBodyIconPainter extends CustomPainter {
  const _PigBodyIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = math.min(size.width / 96, size.height / 48);
    final double dx = (size.width - 96 * scale) / 2;
    final double dy = (size.height - 48 * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final Path body = Path()
      ..moveTo(16.1, 7)
      ..lineTo(15.3, 1.7)
      ..lineTo(21.3, 4.9)
      ..cubicTo(26, 2.9, 31.8, 1.8, 38.4, 1.8)
      ..lineTo(55.1, 1.8)
      ..cubicTo(69.8, 1.8, 80.9, 7.4, 85.1, 16.9)
      ..lineTo(90.7, 12.5)
      ..cubicTo(91.8, 11.6, 88.91, 15.95, 87.55, 15.95)
      ..cubicTo(87.52, 15.95, 86.11, 21.92, 86.11, 21.92)
      ..cubicTo(86.4, 33.53, 84.54, 35.4, 81.5, 41.6)
      ..lineTo(81, 46.7)
      ..cubicTo(80.9, 47.5, 80.3, 48, 79.5, 48)
      ..lineTo(73.3, 48)
      ..cubicTo(72.7, 48, 72.2, 47.6, 71.9, 47.1)
      ..lineTo(70.2, 43.4)
      ..cubicTo(66.4, 44.2, 62.1, 44.6, 57.5, 44.6)
      ..lineTo(42.8, 44.6)
      ..cubicTo(38.4, 44.6, 34.4, 44.2, 30.8, 43.5)
      ..lineTo(28.8, 47.2)
      ..cubicTo(28.5, 47.7, 28, 48, 27.4, 48)
      ..lineTo(21.2, 48)
      ..cubicTo(20.4, 48, 19.7, 47.3, 19.7, 46.5)
      ..lineTo(19.7, 40.6)
      ..cubicTo(17.6, 39.1, 15.9, 37.3, 14.7, 35.2)
      ..cubicTo(14.7, 35.2, 6.26, 37.23, 6.91, 35.46)
      ..lineTo(4.72, 35.52)
      ..cubicTo(4.93, 31.86, 4.72, 29.78, 3.81, 25.06)
      ..cubicTo(4.75, 25.74, 6.2, 25.3, 6.2, 25.3)
      ..cubicTo(6.2, 25.3, 14.07, 17.59, 16.1, 7)
      ..close();
    final Path tail = Path()
      ..moveTo(84.1, 18.5)
      ..cubicTo(86.2, 14.8, 89.3, 10.6, 93.4, 12.6)
      ..cubicTo(96.1, 13.9, 95.7, 17.8, 93, 18.5)
      ..cubicTo(91.7, 18.8, 90.2, 18.4, 88.7, 17.4)
      ..cubicTo(87.9, 18.3, 87.2, 19.4, 86.5, 20.5)
      ..close();
    final Path tailTip = Path()
      ..moveTo(89.9, 15.1)
      ..cubicTo(90.8, 15.8, 91.7, 16, 92.4, 15.8)
      ..cubicTo(93.1, 15.6, 93.2, 14.6, 92.5, 14.2)
      ..cubicTo(91.7, 13.8, 90.8, 14.2, 89.9, 15.1)
      ..close();

    canvas.drawPath(body, fill);
    canvas.drawPath(tail, fill);
    canvas.drawPath(tailTip, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PigBodyIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _TemplateAnimatedHeatingFlameIconState
    extends State<_TemplateAnimatedHeatingFlameIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Icon(
        Icons.local_fire_department,
        size: widget.size,
        color: const Color(0xFF64748B),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black,
                      Colors.black,
                    ],
                    stops: <double>[0, 0.58, 1],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: Icon(
                  Icons.local_fire_department,
                  size: widget.size,
                  color: const Color(0xFFF97316),
                ),
              ),
              _FadingHeatingFlameTip(
                animation: _controller,
                phase: 0,
                size: widget.size * 0.64,
                left: widget.size * 0.13,
                top: widget.size * -0.11,
              ),
              _FadingHeatingFlameTip(
                animation: _controller,
                phase: 0.34,
                size: widget.size * 0.68,
                left: widget.size * 0.27,
                top: widget.size * -0.08,
              ),
              _FadingHeatingFlameTip(
                animation: _controller,
                phase: 0.68,
                size: widget.size * 0.56,
                left: widget.size * -0.01,
                top: widget.size * 0.01,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FadingHeatingFlameTip extends StatelessWidget {
  const _FadingHeatingFlameTip({
    required this.animation,
    required this.phase,
    required this.size,
    required this.left,
    required this.top,
  });

  final Animation<double> animation;
  final double phase;
  final double size;
  final double left;
  final double top;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double cycle = (animation.value + phase) % 1;
        final double pulse = 0.5 + math.sin(cycle * math.pi * 2) * 0.5;
        return Positioned(
          left: left,
          top: top,
          child: Opacity(
            opacity: 0.12 + pulse * 0.72,
            child: Transform.scale(
              alignment: Alignment.bottomCenter,
              scale: 0.82 + pulse * 0.2,
              child: Icon(
                Icons.local_fire_department,
                size: size,
                color: const Color(0xFFF97316),
              ),
            ),
          ),
        );
      },
    );
  }
}

class TemplateFanIcon extends StatefulWidget {
  const TemplateFanIcon({
    super.key,
    required this.running,
    required this.speedPercent,
    required this.size,
  });

  final bool? running;
  final double? speedPercent;
  final double size;

  @override
  State<TemplateFanIcon> createState() => TemplateFanIconState();
}

class TemplateFanIconState extends State<TemplateFanIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.running == true
          ? fanSpinDurationForPercent(widget.speedPercent)
          : const Duration(milliseconds: 650),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant TemplateFanIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running ||
        oldWidget.speedPercent != widget.speedPercent) {
      _controller.duration = widget.running == true
          ? fanSpinDurationForPercent(widget.speedPercent)
          : const Duration(milliseconds: 650);
      _sync();
    }
  }

  void _sync() {
    _controller.stop();
    if (widget.running == true) {
      _controller.repeat();
      return;
    }
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool? running = widget.running;
    final Color color = running == null
        ? const Color(0xFF94A3B8)
        : running
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);
    final Widget icon = running == null
        ? Icon(Icons.remove_circle_outline, size: widget.size, color: color)
        : _FanBladeIcon(size: widget.size, color: color);
    return AnimatedBuilder(
      animation: _controller,
      child: icon,
      builder: (BuildContext context, Widget? child) {
        if (running == true) {
          return Transform.rotate(
            angle: _controller.value * math.pi * 2,
            child: child,
          );
        }
        if (running != true) {
          return Opacity(
            opacity: running == null ? 0.8 : 0.35 + _controller.value * 0.65,
            child: child,
          );
        }
        return child!;
      },
    );
  }
}

class _FanBladeIcon extends StatelessWidget {
  const _FanBladeIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _FanBladePainter(color: color)),
    );
  }
}

class _FanBladePainter extends CustomPainter {
  const _FanBladePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final Paint bladePaint = Paint()
      ..color = color.withValues(alpha: 0.86)
      ..style = PaintingStyle.fill;
    final Paint hubPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Path blade1 = Path()
      ..moveTo(31, 28)
      ..cubicTo(20, 13, 27, 5, 38, 4)
      ..cubicTo(50, 3, 55, 12, 49, 22)
      ..cubicTo(45, 28, 38, 30, 33, 31)
      ..close();
    final Path blade2 = Path()
      ..moveTo(36, 34)
      ..cubicTo(54, 32, 59, 41, 54, 51)
      ..cubicTo(49, 62, 37, 63, 31, 53)
      ..cubicTo(27, 47, 29, 40, 32, 35)
      ..close();
    final Path blade3 = Path()
      ..moveTo(27, 35)
      ..cubicTo(20, 52, 9, 52, 3, 43)
      ..cubicTo(-3, 33, 3, 23, 15, 24)
      ..cubicTo(22, 24, 26, 30, 29, 33)
      ..close();

    canvas.drawPath(blade1, bladePaint);
    canvas.drawPath(blade2, bladePaint);
    canvas.drawPath(blade3, bladePaint);
    canvas.drawCircle(const Offset(32, 32), 7, hubPaint);
  }

  @override
  bool shouldRepaint(covariant _FanBladePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _TemplateAnimatedDewPointIcon extends StatefulWidget {
  const _TemplateAnimatedDewPointIcon({
    super.key,
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  State<_TemplateAnimatedDewPointIcon> createState() =>
      _TemplateAnimatedDewPointIconState();
}

class _TemplateAnimatedDewPointIconState
    extends State<_TemplateAnimatedDewPointIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            bottom: 0,
            child: Icon(
              Icons.device_thermostat,
              color: widget.color,
              size: size * 0.82,
            ),
          ),
          _TemplateAnimatedDewDrop(
            animation: _controller,
            color: widget.color,
            size: size * 0.22,
            left: size * 0.62,
            top: size * 0.02,
            delay: 0,
          ),
          _TemplateAnimatedDewDrop(
            animation: _controller,
            color: widget.color,
            size: size * 0.18,
            left: size * 0.82,
            top: size * 0.24,
            delay: 0.33,
          ),
        ],
      ),
    );
  }
}

class _TemplateAnimatedDewDrop extends StatelessWidget {
  const _TemplateAnimatedDewDrop({
    required this.animation,
    required this.color,
    required this.size,
    required this.left,
    required this.top,
    required this.delay,
  });

  final Animation<double> animation;
  final Color color;
  final double size;
  final double left;
  final double top;
  final double delay;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double phase = (animation.value + delay) % 1;
        final double y = math.sin(phase * math.pi) * size * 0.75;
        final double opacity = 0.45 + math.sin(phase * math.pi) * 0.55;
        return Positioned(
          left: left,
          top: top + y,
          child: Opacity(
            opacity: opacity,
            child: Icon(Icons.water_drop, color: color, size: size),
          ),
        );
      },
    );
  }
}

_MetricVisualState _resolveMetricVisualState({
  required MetricDefinition metric,
  required Object? value,
  required Object? deviceData,
  required DashboardRangeSettings rangeSettings,
}) {
  if (value == null || metric.statusBehavior == MetricStatusBehavior.none) {
    return const _MetricVisualState.neutral();
  }
  final TemplateAlarmLevel level = resolveTemplateAlarmLevel(
    metric: metric,
    value: value,
    deviceData: deviceData,
    rangeSettings: rangeSettings,
  );
  final Color color = templateAlarmLevelColor(level);
  return _MetricVisualState(
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

TemplateAlarmLevel _resolvePowerLevel(Object? deviceData) {
  final bool? configured = readTemplateBool(deviceData, 'configured');
  if (configured == false) {
    return TemplateAlarmLevel.unavailable;
  }
  if (readTemplateBool(deviceData, 'backendOnline') == false ||
      readTemplateBool(deviceData, 'plcReachable') == false ||
      readTemplateBool(deviceData, 'plcOnline') == false) {
    return TemplateAlarmLevel.alarm;
  }
  if (readTemplateBool(deviceData, 'plcRunning') == true) {
    return TemplateAlarmLevel.normal;
  }
  final String? estado = readTemplateText(deviceData, 'estadoEquipo');
  if (estado != null && estado.toUpperCase().contains('RUN')) {
    return TemplateAlarmLevel.normal;
  }
  return TemplateAlarmLevel.warning;
}

_DotVisual _resolveWitnessDot(Object? deviceData) {
  final String? stateCode = _diagnosticStateCode(deviceData);
  if (stateCode == PlcUnitDiagnostics.backendDown ||
      stateCode == PlcUnitDiagnostics.plcUnreachable) {
    return const _DotVisual(
      color: Color(0xFFEF4444),
      mode: _TemplateDotMode.fixed,
    );
  }
  if (readTemplateBool(deviceData, 'plcRunning') == true ||
      readTemplateText(
            deviceData,
            'estadoEquipo',
          )?.toUpperCase().contains('RUN') ==
          true) {
    return const _DotVisual(
      color: Color(0xFF4ADE80),
      mode: _TemplateDotMode.blinking,
    );
  }
  return const _DotVisual(
    color: Color(0xFFF59E0B),
    mode: _TemplateDotMode.fixed,
  );
}

String? _diagnosticStateCode(Object? data) {
  if (data is MuntersModel) {
    return data.diagnostics?.stateCode;
  }
  final Object? diagnostics = readTemplateValue(data, 'diagnostics');
  if (diagnostics is Map<String, Object?>) {
    final Object? stateCode = diagnostics['stateCode'];
    return stateCode is String ? stateCode : null;
  }
  return null;
}

class _BoardPresetGeometry {
  const _BoardPresetGeometry({
    required this.padding,
    required this.gap,
    required this.mediumWidth,
    required double mediumHeight,
    required this.smallWidth,
    required this.minWidth,
    required this.largeLayoutHeight,
    this.horizontalFlow = false,
    double? largeHeight,
  }) : _mediumHeight = mediumHeight,
       _largeHeight = largeHeight;

  const _BoardPresetGeometry.large()
    : padding = 8,
      gap = 6,
      mediumWidth = 126,
      _mediumHeight = 0,
      _largeHeight = 124,
      smallWidth = 88,
      minWidth = 406,
      largeLayoutHeight = 281,
      horizontalFlow = false;

  final double padding;
  final double gap;
  final double mediumWidth;
  final double _mediumHeight;
  final double? _largeHeight;
  final double smallWidth;
  final double minWidth;
  final double largeLayoutHeight;
  final bool horizontalFlow;

  double get largeWidth => mediumWidth * 2 + gap;
  double get largeHeight => _largeHeight ?? mediumHeight * 2 + gap;
  double get mediumHeight =>
      _largeHeight == null ? _mediumHeight : (_largeHeight - gap) / 2;
  double get largeSecondaryHeight => mediumHeight;
  double get largeMiniBoxSize => mediumHeight;
  double get largeRightColumnWidth => largeMiniBoxSize * 2 + gap;

  double widthFor(BoardSlotSize size) {
    return switch (size) {
      BoardSlotSize.large => largeWidth,
      BoardSlotSize.medium => mediumWidth,
      BoardSlotSize.small => smallWidth,
    };
  }

  double heightFor(BoardSlotSize size) {
    return switch (size) {
      BoardSlotSize.large => largeHeight,
      BoardSlotSize.medium => mediumHeight,
      BoardSlotSize.small => 88,
    };
  }

  EdgeInsets tilePaddingFor(BoardSlotSize size) {
    return switch (size) {
      BoardSlotSize.large => const EdgeInsets.all(12),
      BoardSlotSize.medium => const EdgeInsets.fromLTRB(1, 1, 1, 4),
      BoardSlotSize.small => const EdgeInsets.all(5),
    };
  }

  double iconSizeFor(BoardSlotSize size) {
    return switch (size) {
      BoardSlotSize.large => 26,
      BoardSlotSize.medium => 22,
      BoardSlotSize.small => 22,
    };
  }

  double labelFontSizeFor(BoardSlotSize size) {
    return switch (size) {
      BoardSlotSize.large => 15,
      BoardSlotSize.medium => 12,
      BoardSlotSize.small => 9.5,
    };
  }

  double valueFontSizeFor(BoardSlotSize size) {
    return switch (size) {
      BoardSlotSize.large => 46,
      BoardSlotSize.medium => 28,
      BoardSlotSize.small => 17,
    };
  }

  double unitFontSizeFor(BoardSlotSize size) {
    return switch (size) {
      BoardSlotSize.large => 16,
      BoardSlotSize.medium => 11,
      BoardSlotSize.small => 9,
    };
  }

  double valueIconSizeFor(BoardSlotSize size) {
    return switch (size) {
      BoardSlotSize.large => 32,
      BoardSlotSize.medium => 22,
      BoardSlotSize.small => 16,
    };
  }

  double get indicatorIconSize => 20;
}

_BoardPresetGeometry _geometryForPreset(BoardPreset preset) {
  return switch (preset) {
    BoardPreset.large => const _BoardPresetGeometry.large(),
    BoardPreset.medium => const _BoardPresetGeometry(
      padding: 12,
      gap: 8,
      mediumWidth: 136,
      mediumHeight: 112,
      smallWidth: 92,
      minWidth: 0,
      largeLayoutHeight: 0,
    ),
    BoardPreset.compact => const _BoardPresetGeometry(
      padding: 8,
      gap: 6,
      mediumWidth: 126,
      mediumHeight: 59,
      smallWidth: 86,
      minWidth: 408,
      largeLayoutHeight: 0,
      horizontalFlow: true,
    ),
  };
}
