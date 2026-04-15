import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/temperature_history_point.dart';
import '../services/temperature_history_repository.dart';

class TemperatureHistoryMiniChartsCard extends StatefulWidget {
  const TemperatureHistoryMiniChartsCard({
    super.key,
    required this.unitName,
    required this.lowerLimit,
    required this.upperLimit,
    this.tenantId,
    this.siteId,
    this.plcId,
    this.repository,
  });

  final String unitName;
  final double lowerLimit;
  final double upperLimit;
  final String? tenantId;
  final String? siteId;
  final String? plcId;
  final TemperatureHistoryRepository? repository;

  @override
  State<TemperatureHistoryMiniChartsCard> createState() =>
      _TemperatureHistoryMiniChartsCardState();
}

class _TemperatureHistoryMiniChartsCardState
    extends State<TemperatureHistoryMiniChartsCard> {
  late Future<_TemperatureHistoryBundle> _historyFuture;
  _ChartMode _mode = _ChartMode.hourly;
  int? _selectedIndex;
  late final TemperatureHistoryRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? TemperatureHistoryRepository();
    _historyFuture = _loadHistory();
  }

  @override
  void didUpdateWidget(covariant TemperatureHistoryMiniChartsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitName != widget.unitName ||
        oldWidget.tenantId != widget.tenantId ||
        oldWidget.siteId != widget.siteId ||
        oldWidget.plcId != widget.plcId) {
      _selectedIndex = null;
      _historyFuture = _loadHistory();
    }
  }

  Future<_TemperatureHistoryBundle> _loadHistory() async {
    final String? tenantId = widget.tenantId;
    final String? siteId = widget.siteId;
    final String? plcId = widget.plcId;
    if (tenantId == null ||
        tenantId.trim().isEmpty ||
        siteId == null ||
        siteId.trim().isEmpty ||
        plcId == null ||
        plcId.trim().isEmpty) {
      return const _TemperatureHistoryBundle.notConfigured();
    }

    final List<Object> results = await Future.wait<Object>(<Future<Object>>[
      _repository.fetchTemperatureHourlyHistory(
        tenantId: tenantId,
        siteId: siteId,
        plcId: plcId,
      ),
      _repository.fetchTemperatureDailyHistory(
        tenantId: tenantId,
        siteId: siteId,
        plcId: plcId,
      ),
    ]);
    return _TemperatureHistoryBundle(
      hourly: results[0] as List<TemperatureHourlyPoint>,
      daily: results[1] as List<TemperatureDailyPoint>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF162133),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF223046)),
      ),
      child: FutureBuilder<_TemperatureHistoryBundle>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _HistoryState(
              message: 'Cargando historial...',
              showLoader: true,
            );
          }
          if (snapshot.hasError) {
            return _HistoryState(
              message: 'No se pudo cargar el historial.',
              detail: snapshot.error.toString(),
            );
          }

          final _TemperatureHistoryBundle bundle =
              snapshot.data ?? const _TemperatureHistoryBundle.empty();
          if (bundle.notConfigured) {
            return const _HistoryState(
              message: 'Historial no disponible.',
              detail: 'Esta cuenta no tiene una instalación asignada.',
            );
          }
          final List<TemperatureHistoryPointBase> points =
              _mode == _ChartMode.hourly ? bundle.hourly : bundle.daily;
          final bool hasData = points.isNotEmpty;
          final int effectiveIndex = hasData
              ? (_selectedIndex == null
                    ? points.length - 1
                    : _selectedIndex!.clamp(0, points.length - 1))
              : -1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  _ModeChip(
                    label: 'Horario',
                    selected: _mode == _ChartMode.hourly,
                    onTap: () {
                      setState(() {
                        _mode = _ChartMode.hourly;
                        _selectedIndex = null;
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                  _ModeChip(
                    label: 'Diario',
                    selected: _mode == _ChartMode.daily,
                    onTap: () {
                      setState(() {
                        _mode = _ChartMode.daily;
                        _selectedIndex = null;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!hasData)
                const _HistoryState(
                  message:
                      'Todavia no hay historial de temperatura suficiente para mostrar.',
                )
              else ...[
                Text(
                  _buildRangeLabel(points, _mode),
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 160,
                  child: _MiniLineChart(
                    points: points,
                    mode: _mode,
                    selectedIndex: effectiveIndex,
                    lowerLimit: widget.lowerLimit,
                    upperLimit: widget.upperLimit,
                    onIndexChanged: (int? index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MiniLineChart extends StatefulWidget {
  const _MiniLineChart({
    required this.points,
    required this.mode,
    required this.selectedIndex,
    required this.lowerLimit,
    required this.upperLimit,
    required this.onIndexChanged,
  });

  final List<TemperatureHistoryPointBase> points;
  final _ChartMode mode;
  final int selectedIndex;
  final double lowerLimit;
  final double upperLimit;
  final ValueChanged<int?> onIndexChanged;

  @override
  State<_MiniLineChart> createState() => _MiniLineChartState();
}

class _MiniLineChartState extends State<_MiniLineChart> {
  Timer? _tooltipTimer;
  bool _showTooltip = true;

  @override
  void initState() {
    super.initState();
    _scheduleTooltipHide();
  }

  @override
  void didUpdateWidget(covariant _MiniLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points ||
        oldWidget.mode != widget.mode ||
        oldWidget.selectedIndex != widget.selectedIndex) {
      _scheduleTooltipHide();
    }
  }

  @override
  void dispose() {
    _tooltipTimer?.cancel();
    super.dispose();
  }

  void _scheduleTooltipHide() {
    _tooltipTimer?.cancel();
    if (!_showTooltip) {
      setState(() {
        _showTooltip = true;
      });
    }
    _tooltipTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showTooltip = false;
      });
    });
  }

  void _updateSelection(Offset localPosition, Size size) {
    if (widget.points.isEmpty) {
      widget.onIndexChanged(null);
      return;
    }
    final double chartWidth = math.max(1, size.width - 12);
    final double ratio = (localPosition.dx.clamp(0, chartWidth)) / chartWidth;
    final int index = (ratio * (widget.points.length - 1)).round();
    _scheduleTooltipHide();
    widget.onIndexChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);
        final TemperatureHistoryPointBase selectedPoint =
            widget.points[widget.selectedIndex];

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _updateSelection(details.localPosition, size),
          onHorizontalDragStart: (details) =>
              _updateSelection(details.localPosition, size),
          onHorizontalDragUpdate: (details) =>
              _updateSelection(details.localPosition, size),
          child: MouseRegion(
            onHover: (event) => _updateSelection(event.localPosition, size),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MiniChartPainter(
                      points: widget.points,
                      selectedIndex: widget.selectedIndex,
                      mode: widget.mode,
                      lowerLimit: widget.lowerLimit,
                      upperLimit: widget.upperLimit,
                    ),
                  ),
                ),
                if (_showTooltip)
                  Positioned(
                    left: _tooltipLeft(
                      size.width,
                      widget.points.length,
                      widget.selectedIndex,
                    ),
                    top: 0,
                    child: _ChartTooltip(
                      avgLabel: _tooltipAvgLabel(selectedPoint),
                      timestampLabel: _tooltipTimestamp(
                        selectedPoint,
                        widget.mode,
                      ),
                      lines: _tooltipLines(selectedPoint, widget.mode),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _tooltipLeft(double width, int count, int index) {
    if (count <= 1) {
      return 8;
    }
    final double ratio = index / (count - 1);
    final double anchor = ratio * math.max(0, width - 24);
    final double left = anchor - 58;
    return left.clamp(8, math.max(8, width - 124));
  }
}

class _MiniChartPainter extends CustomPainter {
  const _MiniChartPainter({
    required this.points,
    required this.selectedIndex,
    required this.mode,
    required this.lowerLimit,
    required this.upperLimit,
  });

  final List<TemperatureHistoryPointBase> points;
  final int selectedIndex;
  final _ChartMode mode;
  final double lowerLimit;
  final double upperLimit;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect chartRect = Rect.fromLTWH(0, 30, size.width, size.height - 46);
    final Paint gridPaint = Paint()
      ..color = const Color(0xFF223046)
      ..strokeWidth = 1;
    final Paint linePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint lowerLimitPaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.8)
      ..strokeWidth = 1;
    final Paint upperLimitPaint = Paint()
      ..color = const Color(0xFFDC2626).withValues(alpha: 0.8)
      ..strokeWidth = 1;
    final Paint averageFillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x3338BDF8), Color(0x0038BDF8)],
      ).createShader(chartRect);
    final Paint bandPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x2256CCF2), Color(0x0D56CCF2)],
      ).createShader(chartRect);

    for (int index = 0; index < 3; index += 1) {
      final double y = chartRect.top + ((chartRect.height / 2) * index);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    if (points.length == 1) {
      final TemperatureHistoryPointBase single = points.first;
      final double minValue = single.minTemp;
      final double maxValue = single.maxTemp;
      final double y =
          chartRect.bottom -
          (((single.avgTemp - minValue) /
                  math.max(1, maxValue - minValue + 1)) *
              chartRect.height);
      final Offset point = Offset(chartRect.center.dx, y);
      canvas.drawCircle(point, 3.5, Paint()..color = const Color(0xFF38BDF8));
      _paintXAxisLabels(canvas, size, chartRect);
      return;
    }

    final double minValue = points.map((item) => item.minTemp).reduce(math.min);
    final double maxValue = points.map((item) => item.maxTemp).reduce(math.max);
    final double effectiveMinValue = math.min(minValue, lowerLimit);
    final double effectiveMaxValue = math.max(maxValue, upperLimit);
    final double rawRange = (effectiveMaxValue - effectiveMinValue).abs() < 0.001
        ? 1
        : (effectiveMaxValue - effectiveMinValue);
    final double verticalPadding = math.max(0.35, rawRange * 0.08);
    final double chartMin = effectiveMinValue - verticalPadding;
    final double chartMax = effectiveMaxValue + verticalPadding;
    final double safeRange = math.max(1, chartMax - chartMin);
    final double stepX = chartRect.width / (points.length - 1);

    final double lowerLimitY =
        chartRect.bottom -
        (((lowerLimit - chartMin) / safeRange) * chartRect.height);
    final double upperLimitY =
        chartRect.bottom -
        (((upperLimit - chartMin) / safeRange) * chartRect.height);

    _paintDashedHorizontalLine(
      canvas: canvas,
      start: Offset(chartRect.left, lowerLimitY),
      end: Offset(chartRect.right, lowerLimitY),
      paint: lowerLimitPaint,
    );
    _paintDashedHorizontalLine(
      canvas: canvas,
      start: Offset(chartRect.left, upperLimitY),
      end: Offset(chartRect.right, upperLimitY),
      paint: upperLimitPaint,
    );

    final Path linePath = Path();
    final Path fillPath = Path();
    final Path upperBandPath = Path();
    final Path lowerBandPath = Path();
    final List<Offset> avgOffsets = <Offset>[];
    final List<Offset> maxOffsets = <Offset>[];
    final List<Offset> minOffsets = <Offset>[];

    for (int index = 0; index < points.length; index += 1) {
      final TemperatureHistoryPointBase point = points[index];
      final double dx = chartRect.left + (stepX * index);
      final double avgNormalized = (point.avgTemp - chartMin) / safeRange;
      final double maxNormalized = (point.maxTemp - chartMin) / safeRange;
      final double minNormalized = (point.minTemp - chartMin) / safeRange;
      final Offset avgOffset = Offset(
        dx,
        chartRect.bottom - (avgNormalized * chartRect.height),
      );
      final Offset maxOffset = Offset(
        dx,
        chartRect.bottom - (maxNormalized * chartRect.height),
      );
      final Offset minOffset = Offset(
        dx,
        chartRect.bottom - (minNormalized * chartRect.height),
      );
      avgOffsets.add(avgOffset);
      maxOffsets.add(maxOffset);
      minOffsets.add(minOffset);
      if (index == 0) {
        linePath.moveTo(avgOffset.dx, avgOffset.dy);
        fillPath.moveTo(avgOffset.dx, chartRect.bottom);
        fillPath.lineTo(avgOffset.dx, avgOffset.dy);
        upperBandPath.moveTo(maxOffset.dx, maxOffset.dy);
        lowerBandPath.moveTo(minOffset.dx, minOffset.dy);
      } else {
        linePath.lineTo(avgOffset.dx, avgOffset.dy);
        fillPath.lineTo(avgOffset.dx, avgOffset.dy);
        upperBandPath.lineTo(maxOffset.dx, maxOffset.dy);
        lowerBandPath.lineTo(minOffset.dx, minOffset.dy);
      }
    }

    final Path bandPath = Path.from(upperBandPath);
    for (int index = minOffsets.length - 1; index >= 0; index -= 1) {
      bandPath.lineTo(minOffsets[index].dx, minOffsets[index].dy);
    }
    bandPath.close();

    fillPath
      ..lineTo(avgOffsets.last.dx, chartRect.bottom)
      ..close();

    canvas.drawPath(bandPath, bandPaint);
    canvas.drawPath(fillPath, averageFillPaint);
    canvas.drawPath(linePath, linePaint);

    final Offset selectedOffset = avgOffsets[selectedIndex];
    canvas.drawLine(
      Offset(selectedOffset.dx, chartRect.top),
      Offset(selectedOffset.dx, chartRect.bottom),
      Paint()
        ..color = const Color(0x3348CCF8)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      selectedOffset,
      4.5,
      Paint()..color = const Color(0xFFE5E7EB),
    );
    canvas.drawCircle(
      selectedOffset,
      2.5,
      Paint()..color = const Color(0xFF38BDF8),
    );

    _paintXAxisLabels(canvas, size, chartRect);
  }

  void _paintDashedHorizontalLine({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Paint paint,
  }) {
    const double dashWidth = 6;
    const double dashSpace = 4;
    double currentX = start.dx;
    while (currentX < end.dx) {
      final double nextX = math.min(currentX + dashWidth, end.dx);
      canvas.drawLine(Offset(currentX, start.dy), Offset(nextX, end.dy), paint);
      currentX += dashWidth + dashSpace;
    }
  }

  void _paintXAxisLabels(Canvas canvas, Size size, Rect chartRect) {
    final TextStyle style = const TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 10,
    );
    final int labelCount = math.min(10, points.length);
    for (int labelIndex = 0; labelIndex < labelCount; labelIndex += 1) {
      final int pointIndex = labelCount == 1
          ? 0
          : ((points.length - 1) * (labelIndex / (labelCount - 1))).round();
      final double dx =
          chartRect.left +
          ((chartRect.width / math.max(1, points.length - 1)) * pointIndex);
      final String label = _axisLabel(points[pointIndex], mode);
      final TextPainter textPainter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          (dx - (textPainter.width / 2)).clamp(
            0,
            size.width - textPainter.width,
          ),
          size.height - textPainter.height,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.mode != mode ||
        oldDelegate.lowerLimit != lowerLimit ||
        oldDelegate.upperLimit != upperLimit;
  }
}

class _ChartTooltip extends StatelessWidget {
  const _ChartTooltip({
    required this.avgLabel,
    required this.timestampLabel,
    required this.lines,
  });

  final String avgLabel;
  final String timestampLabel;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 116),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF223046)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              avgLabel,
              style: const TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(timestampLabel),
            const SizedBox(height: 2),
            for (final String line in lines) Text(line),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF38BDF8).withValues(alpha: 0.18)
              : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF38BDF8) : const Color(0xFF223046),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFFBAE6FD) : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _HistoryState extends StatelessWidget {
  const _HistoryState({
    required this.message,
    this.detail,
    this.showLoader = false,
  });

  final String message;
  final String? detail;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF223046)),
          ),
          child: Row(
            children: [
              if (showLoader) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 12,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TemperatureHistoryBundle {
  const _TemperatureHistoryBundle({required this.hourly, required this.daily})
    : notConfigured = false;

  const _TemperatureHistoryBundle.empty()
    : hourly = const <TemperatureHourlyPoint>[],
      daily = const <TemperatureDailyPoint>[],
      notConfigured = false;

  const _TemperatureHistoryBundle.notConfigured()
    : hourly = const <TemperatureHourlyPoint>[],
      daily = const <TemperatureDailyPoint>[],
      notConfigured = true;

  final List<TemperatureHourlyPoint> hourly;
  final List<TemperatureDailyPoint> daily;
  final bool notConfigured;
}

enum _ChartMode { hourly, daily }

String _buildRangeLabel(
  List<TemperatureHistoryPointBase> points,
  _ChartMode mode,
) {
  final TemperatureHistoryPointBase first = points.first;
  final TemperatureHistoryPointBase last = points.last;
  return mode == _ChartMode.hourly
      ? '${_formatDate(first.timestamp)} ${_formatHour(first.timestamp)} - ${_formatDate(last.timestamp)} ${_formatHour(last.timestamp)}'
      : '${_formatDate(first.timestamp)} - ${_formatDate(last.timestamp)}';
}

String _tooltipAvgLabel(TemperatureHistoryPointBase point) =>
    'Prom ${point.avgTemp.toStringAsFixed(1)} °C';

String _tooltipTimestamp(TemperatureHistoryPointBase point, _ChartMode mode) =>
    mode == _ChartMode.hourly
        ? '${_formatDate(point.timestamp)} ${_formatHour(point.timestamp)}'
        : _formatDate(point.timestamp);

List<String> _tooltipLines(TemperatureHistoryPointBase point, _ChartMode mode) {
  final List<String> lines = <String>[
    'Min ${point.minTemp.toStringAsFixed(1)} °C',
    'Max ${point.maxTemp.toStringAsFixed(1)} °C',
  ];
  if (mode == _ChartMode.hourly && point is TemperatureHourlyPoint) {
    lines.add('Samples ${point.samplesCount}');
  } else if (mode == _ChartMode.daily && point is TemperatureDailyPoint) {
    lines.add('Hours ${point.hoursCount}');
  }
  return lines;
}

String _axisLabel(TemperatureHistoryPointBase point, _ChartMode mode) {
  return mode == _ChartMode.hourly
      ? _formatAxisHour(point.timestamp)
      : _formatAxisDay(point.timestamp);
}

String _formatHour(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:00';

String _formatAxisHour(DateTime value) => value.hour.toString();

String _formatAxisDay(DateTime value) => value.day.toString();

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
