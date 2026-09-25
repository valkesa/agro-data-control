import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/device_environment_history_repository.dart';

const _monthAbbreviations = [
  'ENE',
  'FEB',
  'MAR',
  'ABR',
  'MAY',
  'JUN',
  'JUL',
  'AGO',
  'SEP',
  'OCT',
  'NOV',
  'DIC',
];

/// One ART calendar month already fetched for Diario, with its points.
class _MonthState {
  const _MonthState(this.month, this.points);
  final EnvironmentHistoryMonth month;
  final List<EnvironmentHistoryPoint> points;
}

class DeviceEnvironmentHistoryCard extends StatefulWidget {
  const DeviceEnvironmentHistoryCard({
    super.key,
    required this.repository,
    required this.tenantId,
    required this.unitId,
    required this.visible,
    this.initialMetric = EnvironmentHistoryMetric.temperature,
    this.initialMode = EnvironmentHistoryMode.hourly,
    this.initialLoadedMonths,
    this.isExpandedInstance = false,
    this.chartHeight = 200,
  });
  final DeviceEnvironmentHistoryRepository repository;
  final String? tenantId, unitId;
  final bool visible;
  final EnvironmentHistoryMetric initialMetric;
  final EnvironmentHistoryMode initialMode;

  /// Etapa 2/2: months already loaded elsewhere (Diario only), seeded when
  /// opening the expanded dialog so it starts with the SAME dataset instead
  /// of resetting to just the current month. Rehydrated via
  /// [DeviceEnvironmentHistoryRepository.fetchMonth], which resolves from
  /// cache — 0 new reads (see `_openExpanded`).
  final List<EnvironmentHistoryMonth>? initialLoadedMonths;

  /// True only for the copy rendered inside the "ampliar" dialog — hides its
  /// own expand button so tapping it can't nest another dialog on top.
  final bool isExpandedInstance;
  final double chartHeight;

  @override
  State<DeviceEnvironmentHistoryCard> createState() => _HistoryState();
}

class _HistoryState extends State<DeviceEnvironmentHistoryCard> {
  static const double _dayWidth = 26;

  late EnvironmentHistoryMetric _metric = widget.initialMetric;
  late EnvironmentHistoryMode _mode = widget.initialMode;

  // Horario: unchanged single-Future flow (fixed "latest 24" window).
  Future<List<EnvironmentHistoryPoint>>? _hourlyFuture;

  // Diario: Etapa 2/2 month pagination. Ascending by month; concatenating
  // each month's already-ascending points yields one ascending series.
  List<_MonthState> _dailyMonths = [];
  bool _dailyLoadingInitial = false;
  bool _dailyLoadingPrevious = false;
  String? _dailyInitialError;
  String? _dailyPreviousError;
  // Set once a "mes anterior" request comes back empty from BOTH legacy and
  // modern — treated as the floor of available history for this scope. A
  // documented simplification (see report "limitaciones"): a genuine gap
  // month with no data at all would also disable the button, but the real
  // data here is continuous since legacy's 2026-04 start.
  bool _noMoreBefore = false;

  final ScrollController _dailyScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final seedMonths = widget.initialLoadedMonths;
    if (_mode == EnvironmentHistoryMode.daily &&
        seedMonths != null &&
        seedMonths.isNotEmpty) {
      _rehydrateMonths(seedMonths);
    } else if (widget.visible) {
      _ensureLoaded();
    }
  }

  @override
  void didUpdateWidget(covariant DeviceEnvironmentHistoryCard old) {
    super.didUpdateWidget(old);
    if (old.tenantId != widget.tenantId ||
        old.unitId != widget.unitId ||
        old.repository != widget.repository) {
      _hourlyFuture = null;
      _dailyMonths = [];
      _noMoreBefore = false;
      _dailyInitialError = null;
      _dailyPreviousError = null;
    }
    if (widget.visible) _ensureLoaded();
  }

  @override
  void dispose() {
    _dailyScrollController.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (_mode == EnvironmentHistoryMode.hourly) {
      if (_hourlyFuture == null) _loadHourly();
    } else if (_dailyMonths.isEmpty && !_dailyLoadingInitial) {
      _loadInitialMonth();
    }
  }

  void _loadHourly() {
    final tenant = widget.tenantId;
    final unit = widget.unitId;
    final repo = widget.repository;
    setState(() {
      _hourlyFuture = tenant == null || unit == null
          ? Future.error(StateError('Missing scope'))
          : repo
                .resolve(tenant, unit)
                .then((scope) => repo.fetch(scope, EnvironmentHistoryMode.hourly));
    });
  }

  EnvironmentHistoryMonth _currentArtMonth() {
    final art = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return EnvironmentHistoryMonth(art.year, art.month);
  }

  void _loadInitialMonth() {
    final tenant = widget.tenantId;
    final unit = widget.unitId;
    if (tenant == null || unit == null) {
      setState(() => _dailyInitialError = 'No se pudo cargar el histórico');
      return;
    }
    final repo = widget.repository;
    final month = _currentArtMonth();
    setState(() {
      _dailyLoadingInitial = true;
      _dailyInitialError = null;
    });
    repo
        .resolve(tenant, unit)
        .then((scope) => repo.fetchMonth(scope, month))
        .then((points) {
          if (!mounted) return;
          setState(() {
            _dailyMonths = [_MonthState(month, points)];
            _dailyLoadingInitial = false;
          });
          _jumpScrollToEnd();
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            _dailyLoadingInitial = false;
            _dailyInitialError = 'No se pudo cargar el histórico';
          });
        });
  }

  void _rehydrateMonths(List<EnvironmentHistoryMonth> months) {
    final tenant = widget.tenantId;
    final unit = widget.unitId;
    if (tenant == null || unit == null) return;
    final repo = widget.repository;
    setState(() => _dailyLoadingInitial = true);
    repo
        .resolve(tenant, unit)
        .then((scope) async {
          final results = <_MonthState>[];
          for (final m in months) {
            results.add(_MonthState(m, await repo.fetchMonth(scope, m)));
          }
          return results;
        })
        .then((results) {
          if (!mounted) return;
          setState(() {
            _dailyMonths = results;
            _dailyLoadingInitial = false;
          });
          _jumpScrollToEnd();
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            _dailyLoadingInitial = false;
            _dailyInitialError = 'No se pudo cargar el histórico';
          });
        });
  }

  void _loadPreviousMonth() {
    if (_dailyLoadingPrevious || _noMoreBefore || _dailyMonths.isEmpty) return;
    final tenant = widget.tenantId;
    final unit = widget.unitId;
    if (tenant == null || unit == null) return;
    final repo = widget.repository;
    final target = _dailyMonths.first.month.previous;
    setState(() {
      _dailyLoadingPrevious = true;
      _dailyPreviousError = null;
    });
    repo
        .resolve(tenant, unit)
        .then((scope) => repo.fetchMonth(scope, target))
        .then((points) {
          if (!mounted) return;
          setState(() {
            _dailyLoadingPrevious = false;
            if (points.isEmpty) {
              _noMoreBefore = true;
            } else {
              _dailyMonths = [_MonthState(target, points), ..._dailyMonths];
            }
          });
          if (points.isNotEmpty) _preserveScrollAfterPrepend(points.length);
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            _dailyLoadingPrevious = false;
            _dailyPreviousError = 'No se pudo cargar el mes anterior';
          });
        });
  }

  void _jumpScrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dailyScrollController.hasClients) return;
      _dailyScrollController.jumpTo(
        _dailyScrollController.position.maxScrollExtent,
      );
    });
  }

  void _preserveScrollAfterPrepend(int addedDays) {
    final addedWidth = addedDays * _dayWidth;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dailyScrollController.hasClients) return;
      final target = (_dailyScrollController.offset + addedWidth).clamp(
        0.0,
        _dailyScrollController.position.maxScrollExtent,
      );
      _dailyScrollController.jumpTo(target);
    });
  }

  /// Etapa 2/2 §12-13: opens the SAME widget/repository in a bigger dialog,
  /// seeded with the current mode/metric/loaded-months so it starts already
  /// caught up — every fetch it issues on init is a cache hit (0 new reads).
  void _openExpanded(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Histórico ampliado',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: DeviceEnvironmentHistoryCard(
                      repository: widget.repository,
                      tenantId: widget.tenantId,
                      unitId: widget.unitId,
                      visible: true,
                      initialMetric: _metric,
                      initialMode: _mode,
                      initialLoadedMonths: _mode == EnvironmentHistoryMode.daily
                          ? _dailyMonths.map((m) => m.month).toList()
                          : null,
                      isExpandedInstance: true,
                      chartHeight: 440,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF162133),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF223046)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Wrap(
                spacing: 6,
                children: [
                  _metricChip(
                    EnvironmentHistoryMetric.temperature,
                    Icons.thermostat,
                    'Temperatura',
                  ),
                  _metricChip(
                    EnvironmentHistoryMetric.humidity,
                    Icons.water_drop,
                    'Humedad',
                  ),
                  _metricChip(
                    EnvironmentHistoryMetric.both,
                    Icons.stacked_line_chart,
                    'Ambas',
                  ),
                ],
              ),
              const Spacer(),
              if (!widget.isExpandedInstance)
                Tooltip(
                  message: 'Ampliar',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _openExpanded(context),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.open_in_full,
                        size: 16,
                        color: Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final m in EnvironmentHistoryMode.values)
                ChoiceChip(
                  label: Text(
                    m == EnvironmentHistoryMode.hourly ? 'Horario' : 'Diario',
                  ),
                  selected: _mode == m,
                  onSelected: (_) {
                    if (_mode != m) {
                      setState(() {
                        _mode = m;
                        _ensureLoaded();
                      });
                    }
                  },
                ),
            ],
          ),
          if (_mode == EnvironmentHistoryMode.daily) _monthNavigationHeader(),
          const SizedBox(height: 12),
          _legend(),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _monthNavigationHeader() {
    const labelStyle = TextStyle(fontSize: 12);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tooltip(
                message: _noMoreBefore
                    ? 'No hay períodos anteriores disponibles'
                    : 'Cargar mes anterior',
                child: TextButton.icon(
                  onPressed:
                      (_dailyLoadingPrevious ||
                          _noMoreBefore ||
                          _dailyMonths.isEmpty)
                      ? null
                      : _loadPreviousMonth,
                  icon: _dailyLoadingPrevious
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_left, size: 16),
                  label: const Text('Mes anterior', style: labelStyle),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _monthRangeLabel(),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          if (_dailyPreviousError != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Row(
                children: [
                  Text(
                    _dailyPreviousError!,
                    style: const TextStyle(
                      color: Color(0xFFF87171),
                      fontSize: 11,
                    ),
                  ),
                  TextButton(
                    onPressed: _loadPreviousMonth,
                    child: const Text(
                      'Reintentar',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _monthRangeLabel() {
    if (_dailyMonths.isEmpty) return '';
    final first = _dailyMonths.first.month;
    final last = _dailyMonths.last.month;
    String label(EnvironmentHistoryMonth m) => _monthAbbreviations[m.month - 1];
    if (first == last) return '${label(first)} ${first.year}';
    if (first.year == last.year) {
      return '${label(first)}–${label(last)} ${last.year}';
    }
    return '${label(first)} ${first.year}–${label(last)} ${last.year}';
  }

  Widget _buildBody() {
    if (_mode == EnvironmentHistoryMode.hourly) {
      return FutureBuilder<List<EnvironmentHistoryPoint>>(
        future: _hourlyFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            );
          }
          if (snap.hasError) {
            return _errorRetry('No se pudo cargar el histórico', _loadHourly);
          }
          return _renderChartArea(snap.data ?? [], scrollable: false);
        },
      );
    }
    if (_dailyLoadingInitial) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: CircularProgressIndicator(),
      );
    }
    if (_dailyInitialError != null) {
      return _errorRetry(_dailyInitialError!, _loadInitialMonth);
    }
    final points = <EnvironmentHistoryPoint>[
      for (final m in _dailyMonths) ...m.points,
    ];
    return _renderChartArea(points, scrollable: true);
  }

  Widget _errorRetry(String message, VoidCallback onRetry) => Column(
    children: [
      Text(message),
      TextButton(onPressed: onRetry, child: const Text('Reintentar')),
    ],
  );

  Widget _renderChartArea(
    List<EnvironmentHistoryPoint> points, {
    required bool scrollable,
  }) {
    final hasTemp = points.any((p) => p.temperature.value != null);
    final hasHum = points.any((p) => p.humidity.value != null);
    final hasAny = _metric == EnvironmentHistoryMetric.both
        ? hasTemp || hasHum
        : points.any((p) => p.stats(_metric).value != null);
    if (!hasAny) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Sin datos históricos'),
      );
    }
    final chart = _metric == EnvironmentHistoryMetric.both
        ? _buildDualChart(points, hasTemp: hasTemp, hasHum: hasHum)
        : _buildSingleChart(points, _metric);
    if (!scrollable) {
      return SizedBox(height: widget.chartHeight, child: chart);
    }
    // Etapa 2/2 §8-9: width grows with the loaded window instead of
    // compressing days — the SingleChildScrollView absorbs the growth, each
    // day keeps a legible fixed pixel width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          constraints.maxWidth,
          points.length * _dayWidth,
        );
        return SingleChildScrollView(
          controller: _dailyScrollController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: widget.chartHeight,
            child: chart,
          ),
        );
      },
    );
  }

  Widget _metricChip(EnvironmentHistoryMetric m, IconData icon, String label) {
    final selected = _metric == m;
    return Tooltip(
      message: label,
      child: ChoiceChip(
        label: Icon(
          icon,
          size: 16,
          color: selected ? Colors.black87 : Colors.white70,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        selected: selected,
        onSelected: (_) => setState(() => _metric = m),
      ),
    );
  }

  Widget _legendDot(Color color) => Container(
    width: 8,
    height: 8,
    margin: const EdgeInsets.only(right: 4),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _legend() {
    const style = TextStyle(color: Colors.white70, fontSize: 13);
    if (_metric == EnvironmentHistoryMetric.both) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _legendDot(Colors.orangeAccent),
            const Text('Temperatura interior', style: style),
            const SizedBox(width: 12),
            _legendDot(Colors.cyanAccent),
            const Text('Humedad interior', style: style),
          ],
        ),
      );
    }
    final humidity = _metric == EnvironmentHistoryMetric.humidity;
    return Text(
      humidity ? 'Humedad interior' : 'Temperatura interior',
      style: style,
    );
  }

  double _minX(int length) => length == 1 ? -0.5 : 0;
  double _maxX(int length) => length == 1 ? 0.5 : (length - 1).toDouble();

  List<FlSpot> _spotsFor(
    List<EnvironmentHistoryPoint> points,
    EnvironmentHistoryMetric metric,
  ) => [
    for (var i = 0; i < points.length; i++)
      if (points[i].stats(metric).value case final double value)
        FlSpot(i.toDouble(), value)
      else
        FlSpot.nullSpot,
  ];

  /// Shared by single- and dual-axis charts so Horario/Diario labeling never
  /// drifts between modes. Horario keeps its previous (unchanged) behaviour;
  /// Diario shows all days + month markers regardless of how many months
  /// are loaded (Etapa 1 §5/§6, extended in Etapa 2 to multi-month series).
  SideTitles _bottomTitles(List<EnvironmentHistoryPoint> points) {
    if (_mode == EnvironmentHistoryMode.daily) {
      return SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: 1,
        getTitlesWidget: (v, _) {
          final i = v.toInt();
          if (v != i || i < 0 || i >= points.length) {
            return const SizedBox.shrink();
          }
          final art = points[i].start.toUtc().subtract(const Duration(hours: 3));
          final DateTime? prevArt = i == 0
              ? null
              : points[i - 1].start.toUtc().subtract(const Duration(hours: 3));
          final monthChanged =
              prevArt == null ||
              prevArt.month != art.month ||
              prevArt.year != art.year;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 11,
                child: monthChanged
                    ? Text(
                        _monthAbbreviations[art.month - 1],
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      )
                    : null,
              ),
              Text(
                '${art.day}',
                style: const TextStyle(fontSize: 9, color: Colors.white70),
              ),
            ],
          );
        },
      );
    }
    return SideTitles(
      showTitles: true,
      reservedSize: 24,
      interval: points.length > 6 ? (points.length / 4).ceilToDouble() : 1,
      getTitlesWidget: (v, _) {
        final i = v.toInt();
        if (v != i || i < 0 || i >= points.length) {
          return const SizedBox.shrink();
        }
        final art = points[i].start.toUtc().subtract(const Duration(hours: 3));
        return Text(
          '${art.hour}:00',
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        );
      },
    );
  }

  LineTooltipItem _tooltipItem(
    EnvironmentHistoryPoint p,
    String suffix,
    EnvironmentHistoryMetric metric,
  ) {
    final s = p.stats(metric);
    final art = p.start.toUtc().subtract(const Duration(hours: 3));
    return LineTooltipItem(
      '${art.day}/${art.month} ${art.hour}:00 ART\n'
      'Prom: ${s.value?.toStringAsFixed(1)} $suffix\n'
      'Min: ${s.min ?? "—"} · Max: ${s.max ?? "—"}\nMuestras: ${s.sampleCount}',
      const TextStyle(color: Colors.white, fontSize: 11),
    );
  }

  Widget _buildSingleChart(
    List<EnvironmentHistoryPoint> points,
    EnvironmentHistoryMetric metric,
  ) {
    final humidity = metric == EnvironmentHistoryMetric.humidity;
    final suffix = humidity ? '%' : '°C';
    final values = points
        .map((p) => p.stats(metric).value)
        .whereType<double>()
        .toList()
      ..sort();
    return LineChart(
      LineChartData(
        minX: _minX(points.length),
        maxX: _maxX(points.length),
        minY: humidity ? 0 : values.first.floorToDouble() - 1,
        maxY: humidity ? 100 : values.last.ceilToDouble() + 1,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFF304156), strokeWidth: 0.5),
          drawVerticalLine: false,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: _spotsFor(points, metric),
            color: humidity ? Colors.cyanAccent : Colors.orangeAccent,
            isCurved: false,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: humidity ? 20 : 1,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)}$suffix',
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),
          ),
          bottomTitles: AxisTitles(sideTitles: _bottomTitles(points)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map(
                  (spot) =>
                      _tooltipItem(points[spot.x.toInt()], suffix, metric),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  /// True dual-axis: two independently-scaled [LineChart]s stacked in a
  /// [Stack], sharing the same X domain so points line up. fl_chart 0.69
  /// has no per-series Y scale on a single LineChartData (minY/maxY are
  /// chart-wide), so a single chart can't show °C and % on their own real
  /// scales — see the report's "limitación de dual-axis" section for why
  /// this shape was chosen instead of rescaling one series into the other's
  /// numeric range (which the prompt explicitly forbids).
  Widget _buildDualChart(
    List<EnvironmentHistoryPoint> points, {
    required bool hasTemp,
    required bool hasHum,
  }) {
    final tempValues = points
        .map((p) => p.temperature.value)
        .whereType<double>()
        .toList()
      ..sort();
    final minX = _minX(points.length);
    final maxX = _maxX(points.length);
    // Touch/tooltip lives on whichever chart actually has data to touch;
    // the other is IgnorePointer'd so taps always land on an interactive
    // series. Tooltip content always combines both metrics regardless.
    final touchOnTemp = hasTemp || !hasHum;

    Widget tempChart({required bool interactive}) => LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: hasTemp ? tempValues.first.floorToDouble() - 1 : 0,
        maxY: hasTemp ? tempValues.last.ceilToDouble() + 1 : 1,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFF304156), strokeWidth: 0.5),
          drawVerticalLine: false,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: _spotsFor(points, EnvironmentHistoryMetric.temperature),
            color: Colors.orangeAccent,
            isCurved: false,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 1,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 10, color: Colors.orangeAccent),
              ),
            ),
          ),
          bottomTitles: AxisTitles(sideTitles: _bottomTitles(points)),
        ),
        lineTouchData: interactive
            ? LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((spot) {
                    final p = points[spot.x.toInt()];
                    final art = p.start.toUtc().subtract(const Duration(hours: 3));
                    return LineTooltipItem(
                      '${art.day}/${art.month} ${art.hour}:00 ART\n'
                      'Temperatura: ${p.temperature.value?.toStringAsFixed(1) ?? "—"} °C\n'
                      'Humedad: ${p.humidity.value?.toStringAsFixed(1) ?? "—"} %',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    );
                  }).toList(),
                ),
              )
            : const LineTouchData(enabled: false),
      ),
    );

    Widget humChart({required bool interactive}) => LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: 0,
        maxY: 100,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _spotsFor(points, EnvironmentHistoryMetric.humidity),
            color: Colors.cyanAccent,
            isCurved: false,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 20,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 10, color: Colors.cyanAccent),
              ),
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: interactive
            ? LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((spot) {
                    final p = points[spot.x.toInt()];
                    final art = p.start.toUtc().subtract(const Duration(hours: 3));
                    return LineTooltipItem(
                      '${art.day}/${art.month} ${art.hour}:00 ART\n'
                      'Temperatura: ${p.temperature.value?.toStringAsFixed(1) ?? "—"} °C\n'
                      'Humedad: ${p.humidity.value?.toStringAsFixed(1) ?? "—"} %',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    );
                  }).toList(),
                ),
              )
            : const LineTouchData(enabled: false),
      ),
    );

    return Stack(
      children: [
        touchOnTemp
            ? tempChart(interactive: true)
            : IgnorePointer(child: tempChart(interactive: false)),
        if (hasHum || !hasTemp)
          touchOnTemp
              ? IgnorePointer(child: humChart(interactive: false))
              : humChart(interactive: true),
      ],
    );
  }
}
