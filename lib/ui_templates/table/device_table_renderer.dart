import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dashboard_range_settings.dart';
import '../board/device_board_renderer.dart' show TemplateFanIcon;
import '../board/template_data_resolver.dart';
import '../board/template_icon_resolver.dart';
import '../board/template_value_formatter.dart';
import '../enums/metric_display_type.dart';
import '../enums/metric_status_behavior.dart';
import '../models/device_template.dart';
import '../models/indicator_definition.dart';
import '../models/metric_definition.dart';
import '../models/table_column.dart';
import '../shared/template_visual_state.dart';

const double _firstColumnWidth = 128;
const double _dataColumnWidth = 76;
const double _dataRowHeight = 38;

/// One row of the dynamic TABLA: a resolved device/template pair plus the
/// display title already used for its TABLERO card (kept consistent with
/// the room/device naming convention established there).
class DeviceTableEntry {
  const DeviceTableEntry({
    required this.template,
    required this.deviceData,
    required this.title,
    this.deviceGroupTitle,
  });

  final DeviceTemplate template;
  final Object? deviceData;
  final String title;

  /// Name of the physical Device this row's Sala belongs to (e.g. "PLC
  /// Maternidad" grouping several Salas of the same multi-room Device).
  /// `null` means no grouping was requested for this entry (legacy
  /// PLC1/PLC2 dashboards). A run of consecutive entries sharing the same
  /// non-null [deviceGroupTitle] gets one spanning title row above them —
  /// same convention already used by TABLERO's card grouping.
  final String? deviceGroupTitle;
}

/// Renders [entries] as a TABLA grouped by `DeviceTemplate.tableSection`,
/// one header per section, reusing `MetricDefinition`/`TableColumn` from
/// the templates already stabilized for TABLERO. Does not replace the
/// productive TABLA (`EnvironmentTablePage`) — Etapa 5A builds and
/// validates this renderer in isolation; the productive swap is Etapa 5B.
class DeviceTableRenderer extends StatelessWidget {
  const DeviceTableRenderer({
    super.key,
    required this.entries,
    this.resolver = const TemplateDataResolver(),
    this.rangeSettings = const DashboardRangeSettings.defaults(),
  });

  final List<DeviceTableEntry> entries;
  final TemplateDataResolver resolver;
  final DashboardRangeSettings rangeSettings;

  @override
  Widget build(BuildContext context) {
    final List<_TableSection> sections = _groupIntoSections(entries);
    return Column(
      key: const Key('device-table-renderer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < sections.length; i++) ...<Widget>[
          if (i != 0) const SizedBox(height: 22),
          _TableSectionView(
            section: sections[i],
            resolver: resolver,
            rangeSettings: rangeSettings,
          ),
        ],
      ],
    );
  }
}

class _TableSection {
  _TableSection({
    required this.name,
    required this.columns,
    required this.metricsByKey,
    required this.indicatorsByKey,
  }) : entries = <DeviceTableEntry>[];

  final String name;
  final List<TableColumn> columns;
  final Map<String, MetricDefinition> metricsByKey;
  final Map<String, IndicatorDefinition> indicatorsByKey;
  final List<DeviceTableEntry> entries;
}

/// Groups entries by `tableSection`, in the order sections first appear
/// among [entries] — not alphabetically, so the on-screen order matches
/// whatever order devices are already listed in (same convention as
/// TABLERO's device grouping). The column set for a section comes from the
/// template of the first entry that opens it: sections are meant to hold
/// devices that share the same template/structure (see prompt Etapa 5A
/// section 4), so later entries in the same section reuse those columns.
List<_TableSection> _groupIntoSections(List<DeviceTableEntry> entries) {
  final Map<String, _TableSection> byName = <String, _TableSection>{};
  final List<_TableSection> ordered = <_TableSection>[];
  for (final DeviceTableEntry entry in entries) {
    final String sectionName = entry.template.tableSection;
    _TableSection? section = byName[sectionName];
    if (section == null) {
      final List<TableColumn> columns =
          entry.template.tableColumns
              .where((TableColumn column) => column.visible)
              .toList(growable: false)
            ..sort(
              (TableColumn a, TableColumn b) => a.order.compareTo(b.order),
            );
      section = _TableSection(
        name: sectionName,
        columns: columns,
        metricsByKey: <String, MetricDefinition>{
          for (final MetricDefinition metric in entry.template.metrics)
            metric.key: metric,
        },
        indicatorsByKey: <String, IndicatorDefinition>{
          for (final IndicatorDefinition indicator in entry.template.indicators)
            indicator.key: indicator,
        },
      );
      byName[sectionName] = section;
      ordered.add(section);
    }
    section.entries.add(entry);
  }
  return ordered;
}

class _EntryGroup {
  const _EntryGroup({required this.title, required this.entries});

  final String? title;
  final List<DeviceTableEntry> entries;
}

/// Splits [entries] into runs of consecutive entries sharing the same
/// [DeviceTableEntry.deviceGroupTitle] — e.g. `[PLC A, PLC A, PLC B]`
/// groups into `[(PLC A, [e0, e1]), (PLC B, [e2])]`. A `null`
/// `deviceGroupTitle` starts (and stays in) its own untitled group, so
/// legacy PLC1/PLC2 rows (no Device concept, no grouping requested) never
/// get a spanning title row.
List<_EntryGroup> _groupConsecutiveByDeviceTitle(
  List<DeviceTableEntry> entries,
) {
  final List<_EntryGroup> groups = <_EntryGroup>[];
  int start = 0;
  for (int i = 1; i <= entries.length; i++) {
    if (i == entries.length ||
        entries[i].deviceGroupTitle != entries[start].deviceGroupTitle) {
      groups.add(
        _EntryGroup(
          title: entries[start].deviceGroupTitle,
          entries: entries.sublist(start, i),
        ),
      );
      start = i;
    }
  }
  return groups;
}

bool _isIdentityColumn(String metricKey) {
  return metricKey == 'deviceName' || metricKey == 'equipment';
}

double _widthForColumn(TableColumn column) {
  return _isIdentityColumn(column.metricKey)
      ? _firstColumnWidth
      : _dataColumnWidth;
}

class _TableSectionView extends StatelessWidget {
  const _TableSectionView({
    required this.section,
    required this.resolver,
    required this.rangeSettings,
  });

  final _TableSection section;
  final TemplateDataResolver resolver;
  final DashboardRangeSettings rangeSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('device-table-section-${section.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            section.name,
            key: Key('device-table-section-title-${section.name}'),
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
        _sizedTable(),
      ],
    );
  }

  Widget _sizedTable() {
    final double minWidth = section.columns
        .map(_widthForColumn)
        .fold<double>(0, (double sum, double width) => sum + width);
    final Table table = Table(
      border: TableBorder.all(color: const Color(0xFF243247), width: 0.75),
      columnWidths: <int, TableColumnWidth>{
        for (int i = 0; i < section.columns.length; i++)
          i: FixedColumnWidth(_widthForColumn(section.columns[i])),
      },
      children: <TableRow>[
        _headerRow(),
        for (final _EntryGroup group in _groupConsecutiveByDeviceTitle(
          section.entries,
        )) ...<TableRow>[
          if (_showGroupTitleRow(group)) _groupTitleRow(group.title!),
          for (final DeviceTableEntry entry in group.entries) _dataRow(entry),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth >= minWidth) {
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: minWidth, child: table),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: table),
        );
      },
    );
  }

  TableRow _headerRow() {
    return TableRow(
      key: const ValueKey<String>('device-table-header-row'),
      decoration: const BoxDecoration(color: Color(0xFF16233A)),
      children: <Widget>[
        for (final TableColumn column in section.columns)
          _HeaderCell(
            metric: section.metricsByKey[column.metricKey],
            columnWidth: _widthForColumn(column),
          ),
      ],
    );
  }

  /// A device group with a single row whose title already repeats the row's
  /// own name (e.g. Device "Sala1" grouping just its one Sala "Sala1") gets
  /// no group header — showing `Sala1` twice in a row added height without
  /// new information. Multi-row groups (Sala 1/2/3 under "PLC Maternidad")
  /// and single-row groups whose title differs from the row (still useful
  /// context) keep the header.
  bool _showGroupTitleRow(_EntryGroup group) {
    final String? title = group.title;
    if (title == null) {
      return false;
    }
    if (group.entries.length == 1 && group.entries.single.title == title) {
      return false;
    }
    return true;
  }

  /// A full-width divider row naming the Device a run of rows belongs to.
  /// `Table` has no real column-span, so — same trick the legacy TABLA grid
  /// already used — `TableRow.decoration` paints as one continuous band
  /// under every cell in the row regardless of each cell's own content, so
  /// a title in the first cell plus empty cells elsewhere reads as a
  /// spanning bar without breaking column alignment with the data rows.
  TableRow _groupTitleRow(String title) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFF16233A)),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.memory, size: 14, color: Color(0xFF6FD8C4)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  key: Key('device-table-group-title-$title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (int i = 1; i < section.columns.length; i++)
          const SizedBox.shrink(),
      ],
    );
  }

  TableRow _dataRow(DeviceTableEntry entry) {
    return TableRow(
      children: <Widget>[
        for (final TableColumn column in section.columns)
          _DataCell(
            // `TableRow.key` is only used internally by `Table` for row
            // diffing — it is not attached to any widget `find.byKey` can
            // locate. Each cell is keyed individually instead, which is a
            // real widget and lets tests/tools address any row+column pair.
            key: ValueKey<String>(
              'device-table-cell-${entry.title}-${column.metricKey}',
            ),
            column: column,
            metric: section.metricsByKey[column.metricKey],
            indicatorsByKey: section.indicatorsByKey,
            entry: entry,
            resolver: resolver,
            rangeSettings: rangeSettings,
          ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.metric, required this.columnWidth});

  final MetricDefinition? metric;
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    final MetricDefinition? metric = this.metric;
    if (metric == null) {
      return const SizedBox(height: 34);
    }
    final bool isDewPoint = metric.icon.trim() == 'dewPoint';
    return Padding(
      key: Key('device-table-header-cell-${metric.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: SizedBox(
        width: columnWidth - 8,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              isDewPoint
                  ? const _TableAnimatedDewPointIcon(
                      color: Color(0xFF6FD8C4),
                      size: 18,
                    )
                  : Icon(
                      resolveTemplateIcon(metric.icon),
                      size: 13,
                      color: const Color(0xFF6FD8C4),
                    ),
              const SizedBox(height: 2),
              Text(
                _headerLabel(metric),
                key: Key('device-table-header-${metric.key}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _headerLabel(MetricDefinition metric) {
    final String label = metric.shortLabel ?? metric.label;
    if (metric.unit.isEmpty ||
        metric.displayType == MetricDisplayType.boolean) {
      return label;
    }
    return '$label ${metric.unit}';
  }
}

/// Animated "punto de rocio" (dew point) header icon, ported verbatim from
/// the legacy TABLA grid's `_AnimatedDewPointIcon`
/// (`comparison_page.dart:6276-6389`) — a thermostat icon with three water
/// drops bobbing/fading on independent phase offsets, looping every 1500ms.
/// Kept local (rather than reusing `device_board_renderer.dart`'s TABLERO
/// copy) because that copy only renders two of the three drops; porting
/// straight from the legacy source keeps the original three-drop look and
/// avoids touching TABLERO code.
class _TableAnimatedDewPointIcon extends StatefulWidget {
  const _TableAnimatedDewPointIcon({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_TableAnimatedDewPointIcon> createState() =>
      _TableAnimatedDewPointIconState();
}

class _TableAnimatedDewPointIconState extends State<_TableAnimatedDewPointIcon>
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
          _TableAnimatedDewDrop(
            animation: _controller,
            color: widget.color,
            size: size * 0.22,
            left: size * 0.62,
            top: size * 0.02,
            delay: 0,
          ),
          _TableAnimatedDewDrop(
            animation: _controller,
            color: widget.color,
            size: size * 0.18,
            left: size * 0.82,
            top: size * 0.24,
            delay: 0.33,
          ),
          _TableAnimatedDewDrop(
            animation: _controller,
            color: widget.color,
            size: size * 0.14,
            left: size * 0.68,
            top: size * 0.48,
            delay: 0.66,
          ),
        ],
      ),
    );
  }
}

class _TableAnimatedDewDrop extends StatelessWidget {
  const _TableAnimatedDewDrop({
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
        final double opacity = 0.45 + (math.sin(phase * math.pi) * 0.55);
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

String _formatTableMetricValue(MetricDefinition metric, Object? value) {
  final String formattedValue = formatTemplateMetricValue(metric, value);
  return formattedValue == templateNoDataLabel ? '-' : formattedValue;
}

class _FixedHeightCell extends StatelessWidget {
  const _FixedHeightCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _dataRowHeight,
      child: Center(child: child),
    );
  }
}

class _TableIndicatorGrid extends StatelessWidget {
  const _TableIndicatorGrid({
    required this.indicators,
    required this.deviceData,
    required this.resolver,
  });

  final List<IndicatorDefinition> indicators;
  final Object? deviceData;
  final TemplateDataResolver resolver;

  @override
  Widget build(BuildContext context) {
    if (indicators.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: 24,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 1,
        runSpacing: 0,
        children: <Widget>[
          for (final IndicatorDefinition indicator in indicators)
            _TableIndicatorIcon(
              indicator: indicator,
              active:
                  resolver.resolveSourceField(
                    indicator.sourceField,
                    deviceData,
                  ) ==
                  indicator.condition,
            ),
        ],
      ),
    );
  }
}

/// One indicator icon inside `_TableIndicatorGrid`. `flame` gets the
/// animated multi-tip icon ported from the legacy TABLA grid
/// (`_AnimatedHeatingFlameIcon` in `comparison_page.dart`) — its own
/// active/inactive colors (orange/slate) apply regardless of the generic
/// yellow/gray used by every other indicator icon.
class _TableIndicatorIcon extends StatelessWidget {
  const _TableIndicatorIcon({required this.indicator, required this.active});

  final IndicatorDefinition indicator;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (indicator.icon.trim() == 'flame') {
      return _TableAnimatedHeatingFlameIcon(active: active, size: 11);
    }
    return Icon(
      resolveTemplateIcon(indicator.icon),
      size: 11,
      color: active ? const Color(0xFFFACC15) : const Color(0xFF475569),
    );
  }
}

/// Animated flame icon ported verbatim from the legacy TABLA grid's
/// `_AnimatedHeatingFlameIcon` (`comparison_page.dart`) — three overlaid,
/// independently-pulsing flame tips over a top-faded base icon, looping
/// every 1250ms while `active`. Kept local to this file (rather than
/// importing the near-duplicate already ported into
/// `device_board_renderer.dart` for TABLERO) to reuse the legacy version's
/// correct start/stop behavior: that TABLERO copy always keeps its
/// controller running even while inactive.
class _TableAnimatedHeatingFlameIcon extends StatefulWidget {
  const _TableAnimatedHeatingFlameIcon({
    required this.active,
    required this.size,
  });

  final bool active;
  final double size;

  @override
  State<_TableAnimatedHeatingFlameIcon> createState() =>
      _TableAnimatedHeatingFlameIconState();
}

class _TableAnimatedHeatingFlameIconState
    extends State<_TableAnimatedHeatingFlameIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _TableAnimatedHeatingFlameIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.active
        ? const Color(0xFFF97316)
        : const Color(0xFF64748B);
    if (!widget.active) {
      return Icon(Icons.local_fire_department, size: widget.size, color: color);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.transparent, Colors.black, Colors.black],
                stops: <double>[0, 0.58, 1],
              ).createShader(bounds);
            },
            child: Icon(
              Icons.local_fire_department,
              size: widget.size,
              color: color,
            ),
          ),
          _TableFadingHeatingFlameTip(
            animation: _controller,
            phase: 0,
            left: widget.size * 0.13,
            top: widget.size * -0.11,
            size: widget.size * 0.64,
            color: color,
          ),
          _TableFadingHeatingFlameTip(
            animation: _controller,
            phase: 0.34,
            left: widget.size * 0.27,
            top: widget.size * -0.08,
            size: widget.size * 0.68,
            color: color,
          ),
          _TableFadingHeatingFlameTip(
            animation: _controller,
            phase: 0.68,
            left: widget.size * -0.01,
            top: widget.size * 0.01,
            size: widget.size * 0.56,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _TableFadingHeatingFlameTip extends StatelessWidget {
  const _TableFadingHeatingFlameTip({
    required this.animation,
    required this.phase,
    required this.left,
    required this.top,
    required this.size,
    required this.color,
  });

  final Animation<double> animation;
  final double phase;
  final double left;
  final double top;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, Widget? child) {
          final double cycle = (animation.value + phase) % 1;
          final double pulse = 0.5 + (math.sin(cycle * math.pi * 2) * 0.5);
          return Opacity(
            opacity: 0.12 + (pulse * 0.72),
            child: Transform.scale(
              scale: 0.82 + (pulse * 0.2),
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          );
        },
        child: Icon(Icons.local_fire_department, size: size, color: color),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({
    super.key,
    required this.column,
    required this.metric,
    required this.indicatorsByKey,
    required this.entry,
    required this.resolver,
    required this.rangeSettings,
  });

  final TableColumn column;
  final MetricDefinition? metric;
  final Map<String, IndicatorDefinition> indicatorsByKey;
  final DeviceTableEntry entry;
  final TemplateDataResolver resolver;
  final DashboardRangeSettings rangeSettings;

  @override
  Widget build(BuildContext context) {
    final MetricDefinition? metric = this.metric;
    if (metric == null) {
      return const SizedBox(height: 38);
    }

    // El nombre de fila (deviceName / equipment) usa el mismo título que ya
    // se resolvió para la card de TABLERO en vez de releer `metric` — es la
    // misma distinción Room vs. device.name que fijó el bug de Vista Tabla.
    if (metric.key == 'deviceName' || metric.key == 'equipment') {
      return _TextCell(
        text: entry.title,
        bold: true,
        textAlign: TextAlign.left,
      );
    }

    final Object? value = resolver.resolveMetric(metric, entry.deviceData);

    if (metric.displayType == MetricDisplayType.boolean) {
      return _DoorCell(
        metric: metric,
        value: value,
        deviceData: entry.deviceData,
        rangeSettings: rangeSettings,
      );
    }

    if (metric.key == 'fan') {
      return _FanCell(
        metric: metric,
        value: value,
        deviceData: entry.deviceData,
      );
    }

    final TemplateAlarmLevel level = _levelFor(metric, value, entry.deviceData);
    if (level == TemplateAlarmLevel.sensorFailure) {
      return _SensorFailureCell(value: value);
    }

    final String formattedValue = _formatTableMetricValue(metric, value);
    final Color color = metric.statusBehavior == MetricStatusBehavior.alarmState
        ? templateAlarmLevelColor(level)
        : const Color(0xFFE5E7EB);
    final bool alert =
        metric.statusBehavior == MetricStatusBehavior.alarmState &&
        (level == TemplateAlarmLevel.warning ||
            level == TemplateAlarmLevel.alarm);
    final List<IndicatorDefinition> indicators = column.indicators
        .map((String key) => indicatorsByKey[key])
        .whereType<IndicatorDefinition>()
        .toList(growable: false);

    return _ValueCell(
      formattedValue: formattedValue,
      color: color,
      alert: alert,
      indicators: indicators,
      deviceData: entry.deviceData,
      resolver: resolver,
    );
  }

  TemplateAlarmLevel _levelFor(
    MetricDefinition metric,
    Object? value,
    Object? deviceData,
  ) {
    if (metric.statusBehavior != MetricStatusBehavior.alarmState) {
      return TemplateAlarmLevel.unavailable;
    }
    return resolveTemplateAlarmLevel(
      metric: metric,
      value: value,
      deviceData: deviceData,
      rangeSettings: rangeSettings,
    );
  }
}

class _SensorFailureCell extends StatelessWidget {
  const _SensorFailureCell({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    return _FixedHeightCell(
      child: Tooltip(
        message: 'Falla sensor (cod. ${formatSensorFailureCode(value)})',
        child: const Icon(
          Icons.error_outline,
          key: Key('device-table-sensor-failure'),
          color: Color(0xFFEF4444),
          size: 18,
        ),
      ),
    );
  }
}

class _TextCell extends StatelessWidget {
  const _TextCell({
    required this.text,
    this.bold = false,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final bool bold;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final Alignment alignment = textAlign == TextAlign.left
        ? Alignment.centerLeft
        : Alignment.center;
    return SizedBox(
      height: _dataRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: alignment,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(
              color: const Color(0xFFE5E7EB),
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell({
    required this.formattedValue,
    required this.color,
    required this.alert,
    required this.indicators,
    required this.deviceData,
    required this.resolver,
  });

  final String formattedValue;
  final Color color;

  /// Whether this value is in an alert state (warning/alarm) — ports the
  /// legacy TABLA grid's pill highlight (`_EnvironmentTableGrid._valueCell`
  /// in `comparison_page.dart`) so alert values get the same colored bubble
  /// there, not just colored text.
  final bool alert;
  final List<IndicatorDefinition> indicators;
  final Object? deviceData;
  final TemplateDataResolver resolver;

  @override
  Widget build(BuildContext context) {
    final Widget valueText = Text(
      formattedValue,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
    );
    final Widget value = alert
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: valueText,
          )
        : valueText;
    return _FixedHeightCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: Align(
                alignment: indicators.isEmpty
                    ? Alignment.center
                    : Alignment.centerRight,
                child: value,
              ),
            ),
            if (indicators.isNotEmpty) ...<Widget>[
              const SizedBox(width: 3),
              _TableIndicatorGrid(
                indicators: indicators,
                deviceData: deviceData,
                resolver: resolver,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DoorCell extends StatelessWidget {
  const _DoorCell({
    required this.metric,
    required this.value,
    required this.deviceData,
    required this.rangeSettings,
  });

  final MetricDefinition metric;
  final Object? value;
  final Object? deviceData;
  final DashboardRangeSettings rangeSettings;

  @override
  Widget build(BuildContext context) {
    final Color color = value is bool
        ? templateAlarmLevelColor(
            resolveTemplateAlarmLevel(
              metric: metric,
              value: value,
              deviceData: deviceData,
              rangeSettings: rangeSettings,
            ),
          )
        : const Color(0xFF64748B);
    return _FixedHeightCell(
      child: Icon(resolveTemplateIcon(metric.icon), size: 18, color: color),
    );
  }
}

class _FanCell extends StatelessWidget {
  const _FanCell({
    required this.metric,
    required this.value,
    required this.deviceData,
  });

  final MetricDefinition metric;
  final Object? value;
  final Object? deviceData;

  @override
  Widget build(BuildContext context) {
    final Object? resolvedValue = value;
    final double? speedPercent = resolvedValue is num
        ? resolvedValue.toDouble()
        : null;
    final bool? running = resolveFanRunning(deviceData, value);
    final String label = speedPercent == null
        ? '-'
        : formatTemplateMetricValue(metric, value);
    return _FixedHeightCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TemplateFanIcon(
              running: running,
              speedPercent: speedPercent,
              size: 15,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
