import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
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

/// Selected-state color for every ChoiceChip in this card — relying on color
/// alone (no checkmark icon) to signal selection, per the user's request.
const _selectedGreen = Color(0xFF22C55E);

/// One ART calendar month already fetched for Diario, with its points.
class _MonthState {
  const _MonthState(this.month, this.points);
  final EnvironmentHistoryMonth month;
  final List<EnvironmentHistoryPoint> points;
}

/// One ART calendar day already fetched for Horario, with its points.
class _DayState {
  const _DayState(this.day, this.points);
  final EnvironmentHistoryDay day;
  final List<EnvironmentHistoryPoint> points;
}

/// Allows click-and-drag horizontal scrolling with a mouse (not just
/// touch/trackpad/stylus) — Flutter's default `ScrollBehavior` omits mouse
/// from `dragDevices` since a mouse drag usually means "select text", but
/// there's no selectable text inside these charts.
class _DragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
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
    this.chartHeight = 440,
  });
  final DeviceEnvironmentHistoryRepository repository;
  final String? tenantId, unitId;
  final bool visible;
  final EnvironmentHistoryMetric initialMetric;
  final EnvironmentHistoryMode initialMode;

  /// Default is the card's own "ampliado" size — there is no separate
  /// expand button/dialog any more, the card always renders at full detail.
  /// Callers embedding it inside their own compact popup (see
  /// `comparison_page.dart`) pass a smaller explicit value.
  final double chartHeight;

  @override
  State<DeviceEnvironmentHistoryCard> createState() => _HistoryState();
}

class _HistoryState extends State<DeviceEnvironmentHistoryCard> {
  static const double _dayWidth = 26;
  static const double _hourWidth = 22;

  late EnvironmentHistoryMetric _metric = widget.initialMetric;
  late EnvironmentHistoryMode _mode = widget.initialMode;

  DeviceDisplayNames? _displayNames;
  bool _loadingDisplayNames = false;

  // Horario: day pagination, mirroring Diario's month pagination below.
  // Ascending by day; concatenating each day's already-ascending points
  // yields one ascending series. Opens with just today's ART day — loading
  // more history is always an explicit "Día anterior" tap, never automatic.
  List<_DayState> _hourlyDays = [];
  bool _hourlyLoadingInitial = false;
  bool _hourlyLoadingPrevious = false;
  String? _hourlyInitialError;
  String? _hourlyPreviousError;
  bool _hourlyNoMoreBefore = false;
  final ScrollController _hourlyScrollController = ScrollController();

  // Diario: month pagination. Ascending by month; concatenating each
  // month's already-ascending points yields one ascending series.
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
    if (widget.visible) _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant DeviceEnvironmentHistoryCard old) {
    super.didUpdateWidget(old);
    if (old.tenantId != widget.tenantId ||
        old.unitId != widget.unitId ||
        old.repository != widget.repository) {
      _hourlyDays = [];
      _hourlyNoMoreBefore = false;
      _hourlyInitialError = null;
      _hourlyPreviousError = null;
      _dailyMonths = [];
      _noMoreBefore = false;
      _dailyInitialError = null;
      _dailyPreviousError = null;
      _displayNames = null;
      _loadingDisplayNames = false;
    }
    if (widget.visible) _ensureLoaded();
  }

  @override
  void dispose() {
    _hourlyScrollController.dispose();
    _dailyScrollController.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (_displayNames == null && !_loadingDisplayNames) _loadDisplayNames();
    if (_mode == EnvironmentHistoryMode.hourly) {
      if (_hourlyDays.isEmpty && !_hourlyLoadingInitial) _loadInitialHourly();
    } else if (_dailyMonths.isEmpty && !_dailyLoadingInitial) {
      _loadInitialMonth();
    }
  }

  void _loadDisplayNames() {
    final tenant = widget.tenantId;
    final unit = widget.unitId;
    if (tenant == null || unit == null) return;
    final repo = widget.repository;
    _loadingDisplayNames = true;
    repo
        .resolve(tenant, unit)
        .then((scope) => repo.resolveDisplayNames(tenant, scope, unit))
        .then((names) {
          if (!mounted) return;
          setState(() {
            _displayNames = names;
            _loadingDisplayNames = false;
          });
        })
        .catchError((Object _) {
          _loadingDisplayNames = false;
        });
  }

  EnvironmentHistoryDay _currentArtDay() {
    final art = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return EnvironmentHistoryDay(art.year, art.month, art.day);
  }

  void _loadInitialHourly() {
    final tenant = widget.tenantId;
    final unit = widget.unitId;
    if (tenant == null || unit == null) {
      setState(() => _hourlyInitialError = 'No se pudo cargar el histórico');
      return;
    }
    final repo = widget.repository;
    final day = _currentArtDay();
    setState(() {
      _hourlyLoadingInitial = true;
      _hourlyInitialError = null;
    });
    repo
        .resolve(tenant, unit)
        .then((scope) => repo.fetchDay(scope, day))
        .then((points) {
          if (!mounted) return;
          setState(() {
            _hourlyDays = [_DayState(day, points)];
            _hourlyLoadingInitial = false;
          });
          _jumpScrollToEnd(_hourlyScrollController);
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            _hourlyLoadingInitial = false;
            _hourlyInitialError = 'No se pudo cargar el histórico';
          });
        });
  }

  void _loadPreviousHourly() {
    if (_hourlyLoadingPrevious || _hourlyNoMoreBefore || _hourlyDays.isEmpty) {
      return;
    }
    final tenant = widget.tenantId;
    final unit = widget.unitId;
    if (tenant == null || unit == null) return;
    final repo = widget.repository;
    final target = _hourlyDays.first.day.previous;
    setState(() {
      _hourlyLoadingPrevious = true;
      _hourlyPreviousError = null;
    });
    repo
        .resolve(tenant, unit)
        .then((scope) => repo.fetchDay(scope, target))
        .then((points) {
          if (!mounted) return;
          setState(() {
            _hourlyLoadingPrevious = false;
            if (points.isEmpty) {
              _hourlyNoMoreBefore = true;
            } else {
              _hourlyDays = [_DayState(target, points), ..._hourlyDays];
            }
          });
          if (points.isNotEmpty) {
            _preserveScrollAfterPrepend(
              _hourlyScrollController,
              points.length * _hourWidth,
            );
          }
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            _hourlyLoadingPrevious = false;
            _hourlyPreviousError = 'No se pudo cargar el período anterior';
          });
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
          _jumpScrollToEnd(_dailyScrollController);
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
          if (points.isNotEmpty) {
            _preserveScrollAfterPrepend(
              _dailyScrollController,
              points.length * _dayWidth,
            );
          }
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            _dailyLoadingPrevious = false;
            _dailyPreviousError = 'No se pudo cargar el mes anterior';
          });
        });
  }

  void _jumpScrollToEnd(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.jumpTo(controller.position.maxScrollExtent);
    });
  }

  void _preserveScrollAfterPrepend(ScrollController controller, double addedWidth) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final target = (controller.offset + addedWidth).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(target);
    });
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
          if (_displayNames case final names?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  names.roomName != null
                      ? '${names.deviceName} · ${names.roomName}'
                      : names.deviceName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Wrap(
                spacing: 6,
                children: [
                  _metricChip(
                    EnvironmentHistoryMetric.temperature,
                    Icons.thermostat,
                    'Temperatura',
                    suffixLabel: 'in',
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
                  showCheckmark: false,
                  selectedColor: _selectedGreen,
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
          if (_mode == EnvironmentHistoryMode.daily)
            _periodNavigationHeader(
              loading: _dailyLoadingPrevious,
              noMoreBefore: _noMoreBefore,
              hasData: _dailyMonths.isNotEmpty,
              error: _dailyPreviousError,
              onLoadPrevious: _loadPreviousMonth,
              rangeLabel: _monthRangeLabel(),
              buttonLabel: 'Mes anterior',
            )
          else
            _periodNavigationHeader(
              loading: _hourlyLoadingPrevious,
              noMoreBefore: _hourlyNoMoreBefore,
              hasData: _hourlyDays.isNotEmpty,
              error: _hourlyPreviousError,
              onLoadPrevious: _loadPreviousHourly,
              rangeLabel: _hourlyRangeLabel(),
              buttonLabel: 'Día anterior',
            ),
          const SizedBox(height: 12),
          _legend(),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _periodNavigationHeader({
    required bool loading,
    required bool noMoreBefore,
    required bool hasData,
    required String? error,
    required VoidCallback onLoadPrevious,
    required String rangeLabel,
    required String buttonLabel,
  }) {
    const labelStyle = TextStyle(fontSize: 12);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tooltip(
                message: noMoreBefore
                    ? 'No hay períodos anteriores disponibles'
                    : 'Cargar período anterior',
                child: TextButton.icon(
                  onPressed: (loading || noMoreBefore || !hasData)
                      ? null
                      : onLoadPrevious,
                  icon: loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_left, size: 16),
                  label: Text(buttonLabel, style: labelStyle),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                rangeLabel,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Row(
                children: [
                  Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFFF87171),
                      fontSize: 11,
                    ),
                  ),
                  TextButton(
                    onPressed: onLoadPrevious,
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

  String _hourlyRangeLabel() {
    if (_hourlyDays.isEmpty) return '';
    final first = _hourlyDays.first.day;
    final last = _hourlyDays.last.day;
    String d(EnvironmentHistoryDay a) =>
        '${a.day.toString().padLeft(2, '0')}/${a.month.toString().padLeft(2, '0')}';
    return first == last ? d(first) : '${d(first)}–${d(last)}';
  }

  Widget _buildBody() {
    if (_mode == EnvironmentHistoryMode.hourly) {
      if (_hourlyLoadingInitial) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        );
      }
      if (_hourlyInitialError != null) {
        return _errorRetry(_hourlyInitialError!, _loadInitialHourly);
      }
      final points = <EnvironmentHistoryPoint>[
        for (final d in _hourlyDays) ...d.points,
      ];
      return _renderChartArea(points, _hourWidth);
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
    return _renderChartArea(points, _dayWidth);
  }

  Widget _errorRetry(String message, VoidCallback onRetry) => Column(
    children: [
      Text(message),
      TextButton(onPressed: onRetry, child: const Text('Reintentar')),
    ],
  );

  Widget _renderChartArea(List<EnvironmentHistoryPoint> points, double unitWidth) {
    final hasTemp = points.any((p) => p.temperature.value != null);
    final hasHum = points.any((p) => p.humidity.value != null);
    final isDual = _metric == EnvironmentHistoryMetric.both;
    final hasAny = isDual
        ? hasTemp || hasHum
        : points.any((p) => p.stats(_metric).value != null);
    if (!hasAny) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Sin datos históricos'),
      );
    }
    final chart = isDual
        ? _buildDualChart(points, hasTemp: hasTemp, hasHum: hasHum)
        : _buildSingleChart(points, _metric);
    final isDaily = _mode == EnvironmentHistoryMode.daily;
    final controller = isDaily ? _dailyScrollController : _hourlyScrollController;

    // Pinned Y axis/axes (Etapa "eje fijo"): built as separate, non-scrolled
    // LineCharts sharing the exact same minY/maxY/bottom-reserved-size as
    // the real (scrolled) chart, so their tick labels land at identical
    // pixel rows — the standard fl_chart trick for a sticky axis, since a
    // single LineChartData has no way to keep just its axis fixed while its
    // plot area scrolls. Only vertical geometry (height, top/bottom
    // reservedSize) needs to match between the two widgets; left/right
    // reservedSize never affects the Y mapping.
    final leftSpec = isDual
        ? _dualLeftAxisSpec(points, hasTemp: hasTemp)
        : _singleAxisSpec(points, _metric);
    final rightSpec = isDual && (hasHum || !hasTemp) ? _dualRightAxisSpec() : null;

    // Each point keeps a minimum fixed pixel width so it never gets
    // unreadably cramped, but when the container is wider than the loaded
    // data needs, the chart takes the FULL available width instead (fl_chart
    // then spaces the points out evenly to fill it) — only a narrower
    // container falls back to the data-driven width, wrapped in horizontal
    // scroll. Loading more history is never automatic; only "Día
    // anterior"/"Mes anterior" does that.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: leftSpec.reservedSize,
          height: widget.chartHeight,
          child: _pinnedAxis(leftSpec, bottomReservedSize: _bottomReservedSize),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(constraints.maxWidth, points.length * unitWidth);
              return ScrollConfiguration(
                behavior: _DragScrollBehavior(),
                child: SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    height: widget.chartHeight,
                    child: chart,
                  ),
                ),
              );
            },
          ),
        ),
        if (rightSpec != null)
          SizedBox(
            width: rightSpec.reservedSize,
            height: widget.chartHeight,
            child: _pinnedAxis(
              rightSpec,
              bottomReservedSize: _bottomReservedSize,
              onRight: true,
            ),
          ),
      ],
    );
  }

  Widget _metricChip(
    EnvironmentHistoryMetric m,
    IconData icon,
    String label, {
    String? suffixLabel,
  }) {
    final selected = _metric == m;
    final iconColor = selected ? Colors.black87 : Colors.white70;
    return Tooltip(
      message: label,
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            if (suffixLabel != null) ...[
              const SizedBox(width: 2),
              Text(
                suffixLabel,
                style: TextStyle(fontSize: 9, color: iconColor),
              ),
            ],
          ],
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        selected: selected,
        showCheckmark: false,
        selectedColor: _selectedGreen,
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
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendDot(Colors.orangeAccent),
                const Text('Temperatura interior', style: style),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendDot(Colors.cyanAccent),
                const Text('Humedad interior', style: style),
              ],
            ),
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

  List<FlSpot> _boundSpotsFor(
    List<EnvironmentHistoryPoint> points,
    EnvironmentHistoryMetric metric, {
    required bool useMax,
  }) => [
    for (var i = 0; i < points.length; i++)
      if ((useMax ? points[i].stats(metric).max : points[i].stats(metric).min)
          case final double value)
        FlSpot(i.toDouble(), value)
      else
        FlSpot.nullSpot,
  ];

  /// Diario-only: an avg line plus two invisible min/max lines whose area is
  /// shaded via `betweenBarsData`, showing the day's thermal range. Horario
  /// keeps a single visible line, unchanged.
  ({List<LineChartBarData> bars, List<BetweenBarsData> betweenBars}) _seriesFor(
    List<EnvironmentHistoryPoint> points,
    EnvironmentHistoryMetric metric,
    Color color,
  ) {
    final avgBar = LineChartBarData(
      spots: _spotsFor(points, metric),
      color: color,
      isCurved: false,
      barWidth: 2,
      dotData: const FlDotData(show: true),
    );
    if (_mode != EnvironmentHistoryMode.daily) {
      return (bars: [avgBar], betweenBars: const []);
    }
    final minBar = LineChartBarData(
      spots: _boundSpotsFor(points, metric, useMax: false),
      color: color,
      show: false,
      dotData: const FlDotData(show: false),
    );
    final maxBar = LineChartBarData(
      spots: _boundSpotsFor(points, metric, useMax: true),
      color: color,
      show: false,
      dotData: const FlDotData(show: false),
    );
    return (
      bars: [avgBar, minBar, maxBar],
      betweenBars: [
        BetweenBarsData(fromIndex: 1, toIndex: 2, color: color.withValues(alpha: 0.15)),
      ],
    );
  }

  /// Y bounds wide enough for both the average line and (in Diario) the
  /// min/max band, so the shaded area never gets clipped by the chart.
  ({double minY, double maxY}) _yRangeFor(
    List<EnvironmentHistoryPoint> points,
    EnvironmentHistoryMetric metric, {
    required double fallbackMin,
    required double fallbackMax,
  }) {
    final avgValues = points
        .map((p) => p.stats(metric).value)
        .whereType<double>()
        .toList();
    if (avgValues.isEmpty) return (minY: fallbackMin, maxY: fallbackMax);
    final extremes = _mode == EnvironmentHistoryMode.daily
        ? points
              .expand((p) => [p.stats(metric).min, p.stats(metric).max])
              .whereType<double>()
              .toList()
        : const <double>[];
    final all = [...avgValues, ...extremes]..sort();
    return (minY: all.first.floorToDouble() - 1, maxY: all.last.ceilToDouble() + 1);
  }

  /// Bottom-axis reserved height — shared between the real (scrolled) chart
  /// and every pinned axis column, since they must match for the Y-value
  /// pixel mapping to line up (see `_pinnedAxis`'s doc comment).
  double get _bottomReservedSize => _mode == EnvironmentHistoryMode.daily ? 28 : 30;

  /// One pinned Y axis's definition — everything `_pinnedAxis` needs to
  /// render tick labels that land on the same pixel rows as the real
  /// (scrolled) chart's gridlines.
  ({
    double minY,
    double maxY,
    double interval,
    double reservedSize,
    Widget Function(double, TitleMeta) titleBuilder,
  })
  _singleAxisSpec(
    List<EnvironmentHistoryPoint> points,
    EnvironmentHistoryMetric metric,
  ) {
    final humidity = metric == EnvironmentHistoryMetric.humidity;
    final suffix = humidity ? '%' : '°C';
    final yRange = humidity
        ? (minY: 0.0, maxY: 100.0)
        : _yRangeFor(points, metric, fallbackMin: 0, fallbackMax: 1);
    return (
      minY: yRange.minY,
      maxY: yRange.maxY,
      interval: humidity ? 20 : 1,
      reservedSize: 48,
      titleBuilder: (v, _) => Text(
        '${v.toStringAsFixed(0)}$suffix',
        style: const TextStyle(fontSize: 10, color: Colors.white70),
      ),
    );
  }

  ({
    double minY,
    double maxY,
    double interval,
    double reservedSize,
    Widget Function(double, TitleMeta) titleBuilder,
  })
  _dualLeftAxisSpec(List<EnvironmentHistoryPoint> points, {required bool hasTemp}) {
    final yRange = hasTemp
        ? _yRangeFor(
            points,
            EnvironmentHistoryMetric.temperature,
            fallbackMin: 0,
            fallbackMax: 1,
          )
        : (minY: 0.0, maxY: 1.0);
    return (
      minY: yRange.minY,
      maxY: yRange.maxY,
      interval: 1,
      reservedSize: 40,
      titleBuilder: (v, _) => Text(
        '${v.toStringAsFixed(0)}°',
        style: const TextStyle(fontSize: 10, color: Colors.orangeAccent),
      ),
    );
  }

  ({
    double minY,
    double maxY,
    double interval,
    double reservedSize,
    Widget Function(double, TitleMeta) titleBuilder,
  })
  _dualRightAxisSpec() => (
    minY: 0.0,
    maxY: 100.0,
    interval: 20.0,
    reservedSize: 34,
    titleBuilder: (v, _) => Text(
      '${v.toStringAsFixed(0)}%',
      style: const TextStyle(fontSize: 10, color: Colors.cyanAccent),
    ),
  );

  /// A non-interactive, dataless [LineChart] that renders ONLY axis tick
  /// labels — pinned outside the horizontal [SingleChildScrollView] so the
  /// Y axis stays visible while the plot scrolls. Must share [minY]/[maxY],
  /// overall height (`widget.chartHeight`, applied by the caller) and
  /// [bottomReservedSize] with the real chart: those are exactly the
  /// parameters that determine where a Y value lands vertically: horizontal
  /// (left/right) reservedSize never affects that mapping, so it's the only
  /// thing safe to let differ between this narrow pinned column and the
  /// wide scrolled chart.
  Widget _pinnedAxis(
    ({
      double minY,
      double maxY,
      double interval,
      double reservedSize,
      Widget Function(double, TitleMeta) titleBuilder,
    })
    spec, {
    required double bottomReservedSize,
    bool onRight = false,
  }) {
    final sideTitles = SideTitles(
      showTitles: true,
      reservedSize: spec.reservedSize,
      interval: spec.interval,
      getTitlesWidget: spec.titleBuilder,
    );
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 1,
        minY: spec.minY,
        maxY: spec.maxY,
        lineBarsData: const [],
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false, reservedSize: bottomReservedSize),
          ),
          leftTitles: onRight
              ? const AxisTitles(sideTitles: SideTitles(showTitles: false))
              : AxisTitles(sideTitles: sideTitles),
          rightTitles: onRight
              ? AxisTitles(sideTitles: sideTitles)
              : const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      ),
    );
  }

  /// Shared by single- and dual-axis charts so Horario/Diario labeling never
  /// drifts between modes. Diario shows all days + month markers regardless
  /// of how many months are loaded. Horario shows 2-digit, colon-free hours
  /// (`05`, `13`) plus a day marker once it spans more than one ART day —
  /// every point gets its own label since the fixed per-point pixel width
  /// (`_hourWidth`/`_dayWidth`) already guarantees adequate spacing.
  SideTitles _bottomTitles(List<EnvironmentHistoryPoint> points) {
    if (_mode == EnvironmentHistoryMode.daily) {
      return SideTitles(
        showTitles: true,
        reservedSize: _bottomReservedSize,
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
      reservedSize: _bottomReservedSize,
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
        final dayChanged =
            prevArt == null ||
            prevArt.day != art.day ||
            prevArt.month != art.month ||
            prevArt.year != art.year;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 11,
              child: dayChanged
                  ? Text(
                      '${art.day.toString().padLeft(2, '0')}/${art.month.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    )
                  : null,
            ),
            Text(
              art.hour.toString().padLeft(2, '0'),
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ],
        );
      },
    );
  }

  /// Horario: just the hour and the average value, nothing else.
  LineTooltipItem _tooltipItem(
    EnvironmentHistoryPoint p,
    String suffix,
    EnvironmentHistoryMetric metric,
  ) {
    final s = p.stats(metric);
    final art = p.start.toUtc().subtract(const Duration(hours: 3));
    return LineTooltipItem(
      '${art.hour.toString().padLeft(2, '0')}: ${s.value?.toStringAsFixed(1) ?? "—"} $suffix',
      const TextStyle(color: Colors.white, fontSize: 11),
    );
  }

  /// Diario: just the date, no values.
  LineTooltipItem _dateTooltipItem(EnvironmentHistoryPoint p) {
    final art = p.start.toUtc().subtract(const Duration(hours: 3));
    return LineTooltipItem(
      '${art.day.toString().padLeft(2, '0')}/${art.month.toString().padLeft(2, '0')}/${art.year}',
      const TextStyle(color: Colors.white, fontSize: 11),
    );
  }

  Widget _buildSingleChart(
    List<EnvironmentHistoryPoint> points,
    EnvironmentHistoryMetric metric,
  ) {
    final humidity = metric == EnvironmentHistoryMetric.humidity;
    final suffix = humidity ? '%' : '°C';
    final isDaily = _mode == EnvironmentHistoryMode.daily;
    final color = humidity ? Colors.cyanAccent : Colors.orangeAccent;
    final series = _seriesFor(points, metric, color);
    final yRange = humidity
        ? (minY: 0.0, maxY: 100.0)
        : _yRangeFor(points, metric, fallbackMin: 0, fallbackMax: 1);
    return LineChart(
      LineChartData(
        minX: _minX(points.length),
        maxX: _maxX(points.length),
        minY: yRange.minY,
        maxY: yRange.maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFF304156), strokeWidth: 0.5),
          drawVerticalLine: false,
        ),
        lineBarsData: series.bars,
        betweenBarsData: series.betweenBars,
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          // Shown separately in a pinned column outside the horizontal
          // scroll (see `_renderChartArea`/`_pinnedAxis`) so it stays
          // visible while the plot scrolls — not rendered here any more.
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: _bottomTitles(points)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                // Diario adds 2 extra (invisible) bars per _seriesFor for the
                // min/max band; only the average bar (index 0) should ever
                // produce a tooltip line.
                .where((spot) => spot.barIndex == 0)
                .map(
                  (spot) => isDaily
                      ? _dateTooltipItem(points[spot.x.toInt()])
                      : _tooltipItem(points[spot.x.toInt()], suffix, metric),
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
    final minX = _minX(points.length);
    final maxX = _maxX(points.length);
    final isDaily = _mode == EnvironmentHistoryMode.daily;
    // Touch/tooltip lives on whichever chart actually has data to touch;
    // the other is IgnorePointer'd so taps always land on an interactive
    // series. Tooltip content combines both metrics in Horario; Diario
    // shows only the date (see _dateTooltipItem).
    final touchOnTemp = hasTemp || !hasHum;

    LineTooltipItem dualTooltip(EnvironmentHistoryPoint p) {
      final art = p.start.toUtc().subtract(const Duration(hours: 3));
      return LineTooltipItem(
        '${art.hour.toString().padLeft(2, '0')}\n'
        'Temp: ${p.temperature.value?.toStringAsFixed(1) ?? "—"} °C\n'
        'Hum: ${p.humidity.value?.toStringAsFixed(1) ?? "—"} %',
        const TextStyle(color: Colors.white, fontSize: 11),
      );
    }

    LineTouchTooltipData tooltipData() => LineTouchTooltipData(
      getTooltipItems: (spots) => spots
          .where((spot) => spot.barIndex == 0)
          .map(
            (spot) => isDaily
                ? _dateTooltipItem(points[spot.x.toInt()])
                : dualTooltip(points[spot.x.toInt()]),
          )
          .toList(),
    );

    Widget tempChart({required bool interactive}) {
      final series = _seriesFor(points, EnvironmentHistoryMetric.temperature, Colors.orangeAccent);
      final yRange = hasTemp
          ? _yRangeFor(
              points,
              EnvironmentHistoryMetric.temperature,
              fallbackMin: 0,
              fallbackMax: 1,
            )
          : (minY: 0.0, maxY: 1.0);
      return LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: yRange.minY,
          maxY: yRange.maxY,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF304156), strokeWidth: 0.5),
            drawVerticalLine: false,
          ),
          lineBarsData: series.bars,
          betweenBarsData: series.betweenBars,
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            // Pinned separately outside the scroll — see _renderChartArea.
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: _bottomTitles(points)),
          ),
          lineTouchData: interactive
              ? LineTouchData(touchTooltipData: tooltipData())
              : const LineTouchData(enabled: false),
        ),
      );
    }

    Widget humChart({required bool interactive}) {
      final series = _seriesFor(points, EnvironmentHistoryMetric.humidity, Colors.cyanAccent);
      return LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: 0,
          maxY: 100,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          lineBarsData: series.bars,
          betweenBarsData: series.betweenBars,
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            // Pinned separately outside the scroll — see _renderChartArea.
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: interactive
              ? LineTouchData(touchTooltipData: tooltipData())
              : const LineTouchData(enabled: false),
        ),
      );
    }

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
