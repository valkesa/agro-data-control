import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/differential_pressure_history_point.dart';
import '../services/differential_pressure_history_repository.dart';

class DifferentialPressureHistoryCard extends StatefulWidget {
  const DifferentialPressureHistoryCard({
    super.key,
    required this.unitName,
    this.tenantId,
    this.siteId,
    this.plcId,
    this.repository,
    this.horizontalMargin = 0,
  });

  final String unitName;
  final String? tenantId;
  final String? siteId;
  final String? plcId;
  final DifferentialPressureHistoryRepository? repository;
  final double horizontalMargin;

  @override
  State<DifferentialPressureHistoryCard> createState() =>
      _DifferentialPressureHistoryCardState();
}

class _DifferentialPressureHistoryCardState
    extends State<DifferentialPressureHistoryCard> {
  late final DifferentialPressureHistoryRepository _repository;
  late Future<_PressureHistoryBundle> _historyFuture;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DifferentialPressureHistoryRepository();
    _historyFuture = _loadHistory();
  }

  @override
  void didUpdateWidget(covariant DifferentialPressureHistoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitName != widget.unitName ||
        oldWidget.tenantId != widget.tenantId ||
        oldWidget.siteId != widget.siteId ||
        oldWidget.plcId != widget.plcId) {
      _selectedIndex = null;
      _historyFuture = _loadHistory();
    }
  }

  Future<_PressureHistoryBundle> _loadHistory() async {
    final String? tenantId = widget.tenantId;
    final String? siteId = widget.siteId;
    final String? plcId = widget.plcId;
    if (tenantId == null ||
        tenantId.trim().isEmpty ||
        siteId == null ||
        siteId.trim().isEmpty ||
        plcId == null ||
        plcId.trim().isEmpty) {
      return const _PressureHistoryBundle.notConfigured();
    }

    final List<DifferentialPressureDailyPoint> daily = await _repository
        .fetchDifferentialPressureDailyHistory(
          tenantId: tenantId,
          siteId: siteId,
          plcId: plcId,
        );
    return _PressureHistoryBundle(daily: daily);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: widget.horizontalMargin),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF162133),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF223046)),
      ),
      child: FutureBuilder<_PressureHistoryBundle>(
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

          final _PressureHistoryBundle bundle =
              snapshot.data ?? const _PressureHistoryBundle.empty();
          if (bundle.notConfigured) {
            return const _HistoryState(
              message: 'Historial no disponible.',
              detail: 'Esta cuenta no tiene una instalación asignada.',
            );
          }
          if (bundle.daily.isEmpty) {
            return const _HistoryState(
              message:
                  'Todavia no hay historial diario de presion diferencial.',
            );
          }

          final int selectedIndex =
              _selectedIndex?.clamp(0, bundle.daily.length - 1) ??
              bundle.daily.length - 1;
          final DifferentialPressureDailyPoint selected =
              bundle.daily[selectedIndex];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Presion diferencial diaria',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    selected.dateKey,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails details) {
                    final RenderBox box =
                        context.findRenderObject()! as RenderBox;
                    final Offset local = box.globalToLocal(
                      details.globalPosition,
                    );
                    setState(() {
                      _selectedIndex = _nearestIndex(
                        local.dx,
                        box.size.width,
                        bundle.daily.length,
                      );
                    });
                  },
                  child: CustomPaint(
                    painter: _PressureChartPainter(
                      points: bundle.daily,
                      selectedIndex: selectedIndex,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _MetricChip(
                    label: 'Prom',
                    value: selected.avgPressureDifferential,
                  ),
                  _MetricChip(
                    label: 'Min',
                    value: selected.minPressureDifferential,
                  ),
                  _MetricChip(
                    label: 'Max',
                    value: selected.maxPressureDifferential,
                  ),
                  Text(
                    '${selected.samplesCount} muestras',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

int _nearestIndex(double dx, double width, int count) {
  if (count <= 1 || width <= 0) {
    return 0;
  }
  final double t = (dx / width).clamp(0, 1);
  return (t * (count - 1)).round().clamp(0, count - 1);
}

class _PressureChartPainter extends CustomPainter {
  const _PressureChartPainter({
    required this.points,
    required this.selectedIndex,
  });

  final List<DifferentialPressureDailyPoint> points;
  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    const EdgeInsets padding = EdgeInsets.fromLTRB(4, 8, 4, 20);
    final Rect chartRect = Rect.fromLTWH(
      padding.left,
      padding.top,
      math.max(0, size.width - padding.horizontal),
      math.max(0, size.height - padding.vertical),
    );
    if (chartRect.width <= 0 || chartRect.height <= 0) {
      return;
    }

    double minY = points.first.minPressureDifferential;
    double maxY = points.first.maxPressureDifferential;
    for (final DifferentialPressureDailyPoint p in points) {
      minY = math.min(minY, p.minPressureDifferential);
      maxY = math.max(maxY, p.maxPressureDifferential);
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    final double pad = (maxY - minY) * 0.12;
    minY -= pad;
    maxY += pad;

    final Paint gridPaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i += 1) {
      final double y = chartRect.top + chartRect.height * i / 3;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    Offset pointOffset(int index, double value) {
      final double x = points.length == 1
          ? chartRect.center.dx
          : chartRect.left + chartRect.width * index / (points.length - 1);
      final double y =
          chartRect.bottom -
          ((value - minY) / (maxY - minY)) * chartRect.height;
      return Offset(x, y);
    }

    final Paint rangePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.42)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final Paint linePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    final Path avgPath = Path();

    for (int i = 0; i < points.length; i += 1) {
      final DifferentialPressureDailyPoint p = points[i];
      final Offset min = pointOffset(i, p.minPressureDifferential);
      final Offset max = pointOffset(i, p.maxPressureDifferential);
      canvas.drawLine(min, max, rangePaint);
      final Offset avg = pointOffset(i, p.avgPressureDifferential);
      if (i == 0) {
        avgPath.moveTo(avg.dx, avg.dy);
      } else {
        avgPath.lineTo(avg.dx, avg.dy);
      }
    }
    canvas.drawPath(avgPath, linePaint);

    final int safeSelected = selectedIndex.clamp(0, points.length - 1);
    final Offset selected = pointOffset(
      safeSelected,
      points[safeSelected].avgPressureDifferential,
    );
    canvas.drawCircle(selected, 4, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(
      selected,
      6,
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final TextPainter minLabel = _label('${minY.round()} Pa');
    minLabel.paint(canvas, Offset(chartRect.left, chartRect.bottom + 4));
    final TextPainter maxLabel = _label('${maxY.round()} Pa');
    maxLabel.paint(
      canvas,
      Offset(chartRect.right - maxLabel.width, chartRect.bottom + 4),
    );
  }

  TextPainter _label(String text) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant _PressureChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selectedIndex != selectedIndex;
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label ${value.toStringAsFixed(0)} Pa',
      style: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontSize: 11,
        fontWeight: FontWeight.w600,
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 96),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLoader) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PressureHistoryBundle {
  const _PressureHistoryBundle({required this.daily}) : notConfigured = false;

  const _PressureHistoryBundle.empty()
    : daily = const <DifferentialPressureDailyPoint>[],
      notConfigured = false;

  const _PressureHistoryBundle.notConfigured()
    : daily = const <DifferentialPressureDailyPoint>[],
      notConfigured = true;

  final List<DifferentialPressureDailyPoint> daily;
  final bool notConfigured;
}
