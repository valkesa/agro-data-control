import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dashboard_door_event.dart';
import '../models/door_openings_models.dart';
import '../services/door_openings_repository.dart';

class DoorOpeningsModule extends StatefulWidget {
  const DoorOpeningsModule({
    super.key,
    required this.tenantId,
    required this.siteId,
    required this.doorEvents,
    this.historyLimit = 20,
  });

  final String? tenantId;
  final String? siteId;
  final Map<String, DashboardDoorEvent> doorEvents;
  final int historyLimit;

  @override
  State<DoorOpeningsModule> createState() => _DoorOpeningsModuleState();
}

class _DoorOpeningsModuleState extends State<DoorOpeningsModule> {
  static const DoorOpeningsRepository _repository = DoorOpeningsRepository();

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? tenantId = widget.tenantId;
    final String? siteId = widget.siteId;
    if (tenantId == null ||
        tenantId.isEmpty ||
        siteId == null ||
        siteId.isEmpty) {
      return const _FooterMessage(
        text: 'Sin contexto Firestore para cargar aperturas.',
        color: Color(0xFF94A3B8),
      );
    }

    return _DoorOpeningsTable(
      tenantId: tenantId,
      siteId: siteId,
      historyLimit: widget.historyLimit,
      now: _now,
      repository: _repository,
      salaSnapshotEvent: widget.doorEvents['sala'],
      munterSnapshotEvent: widget.doorEvents['munter'],
    );
  }
}

class _DoorOpeningsTable extends StatefulWidget {
  const _DoorOpeningsTable({
    required this.tenantId,
    required this.siteId,
    required this.historyLimit,
    required this.now,
    required this.repository,
    required this.salaSnapshotEvent,
    required this.munterSnapshotEvent,
  });

  final String tenantId;
  final String siteId;
  final int historyLimit;
  final DateTime now;
  final DoorOpeningsRepository repository;
  final DashboardDoorEvent? salaSnapshotEvent;
  final DashboardDoorEvent? munterSnapshotEvent;

  @override
  State<_DoorOpeningsTable> createState() => _DoorOpeningsTableState();
}

class _DoorOpeningsTableState extends State<_DoorOpeningsTable> {
  late final Stream<DoorStateRecord?> _salaStateStream;
  late final Stream<List<DoorOpeningRecord>> _salaHistoryStream;
  late final Stream<List<DoorOpeningRecord>> _salaMonthHistoryStream;
  late final Stream<DoorStateRecord?> _munterStateStream;
  late final Stream<List<DoorOpeningRecord>> _munterHistoryStream;
  late final Stream<List<DoorOpeningRecord>> _munterMonthHistoryStream;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    final DateTime monthStart = DateTime(now.year, now.month);
    _salaStateStream = widget.repository.watchDoorState(
      tenantId: widget.tenantId,
      siteId: widget.siteId,
      doorId: 'sala',
    );
    _salaHistoryStream = widget.repository.watchDoorHistory(
      tenantId: widget.tenantId,
      siteId: widget.siteId,
      doorId: 'sala',
      limit: widget.historyLimit,
    );
    _salaMonthHistoryStream = widget.repository.watchDoorMonthHistory(
      tenantId: widget.tenantId,
      siteId: widget.siteId,
      doorId: 'sala',
      monthStart: monthStart,
    );
    _munterStateStream = widget.repository.watchDoorState(
      tenantId: widget.tenantId,
      siteId: widget.siteId,
      doorId: 'munter',
    );
    _munterHistoryStream = widget.repository.watchDoorHistory(
      tenantId: widget.tenantId,
      siteId: widget.siteId,
      doorId: 'munter',
      limit: widget.historyLimit,
    );
    _munterMonthHistoryStream = widget.repository.watchDoorMonthHistory(
      tenantId: widget.tenantId,
      siteId: widget.siteId,
      doorId: 'munter',
      monthStart: monthStart,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DoorStateRecord?>(
      stream: _salaStateStream,
      builder: (BuildContext context, AsyncSnapshot<DoorStateRecord?> salaStateSnapshot) {
        return StreamBuilder<List<DoorOpeningRecord>>(
          stream: _salaHistoryStream,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<DoorOpeningRecord>> salaHistorySnapshot,
              ) {
                return StreamBuilder<List<DoorOpeningRecord>>(
                  stream: _salaMonthHistoryStream,
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<List<DoorOpeningRecord>>
                        salaMonthSnapshot,
                      ) {
                        return StreamBuilder<DoorStateRecord?>(
                          stream: _munterStateStream,
                          builder:
                              (
                                BuildContext context,
                                AsyncSnapshot<DoorStateRecord?>
                                munterStateSnapshot,
                              ) {
                                return StreamBuilder<List<DoorOpeningRecord>>(
                                  stream: _munterHistoryStream,
                                  builder:
                                      (
                                        BuildContext context,
                                        AsyncSnapshot<List<DoorOpeningRecord>>
                                        munterHistorySnapshot,
                                      ) {
                                        return StreamBuilder<
                                          List<DoorOpeningRecord>
                                        >(
                                          stream: _munterMonthHistoryStream,
                                          builder:
                                              (
                                                BuildContext context,
                                                AsyncSnapshot<
                                                  List<DoorOpeningRecord>
                                                >
                                                munterMonthSnapshot,
                                              ) {
                                                final _DoorDisplayData sala =
                                                    _DoorDisplayData.fromSnapshots(
                                                      snapshotEvent: widget
                                                          .salaSnapshotEvent,
                                                      stateSnapshot:
                                                          salaStateSnapshot,
                                                      historySnapshot:
                                                          salaHistorySnapshot,
                                                      monthHistorySnapshot:
                                                          salaMonthSnapshot,
                                                      now: widget.now,
                                                    );
                                                final _DoorDisplayData munter =
                                                    _DoorDisplayData.fromSnapshots(
                                                      snapshotEvent: widget
                                                          .munterSnapshotEvent,
                                                      stateSnapshot:
                                                          munterStateSnapshot,
                                                      historySnapshot:
                                                          munterHistorySnapshot,
                                                      monthHistorySnapshot:
                                                          munterMonthSnapshot,
                                                      now: widget.now,
                                                    );

                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: <Widget>[
                                                    _DoorSection(
                                                      title: 'Puerta',
                                                      doorName: 'Sala',
                                                      data: sala,
                                                    ),
                                                    const SizedBox(height: 10),
                                                    _DoorSection(
                                                      title: 'Puerta',
                                                      doorName: 'Munter',
                                                      data: munter,
                                                    ),
                                                  ],
                                                );
                                              },
                                        );
                                      },
                                );
                              },
                        );
                      },
                );
              },
        );
      },
    );
  }
}

class _DoorDisplayData {
  const _DoorDisplayData({
    required this.isOpen,
    required this.statusLabel,
    required this.openSinceLabel,
    required this.lastChangedLabel,
    required this.lastOpeningTooltip,
    required this.totalOpeningsLabel,
    required this.monthOpeningsLabel,
    required this.lastClosedLabel,
    required this.recentHistoryItems,
    required this.loading,
    required this.errorMessage,
  });

  factory _DoorDisplayData.fromSnapshots({
    required DashboardDoorEvent? snapshotEvent,
    required AsyncSnapshot<DoorStateRecord?> stateSnapshot,
    required AsyncSnapshot<List<DoorOpeningRecord>> historySnapshot,
    required AsyncSnapshot<List<DoorOpeningRecord>> monthHistorySnapshot,
    required DateTime now,
  }) {
    final DoorStateRecord? state = stateSnapshot.data;
    final List<DoorOpeningRecord> history =
        historySnapshot.data ?? const <DoorOpeningRecord>[];
    final bool isOpen = snapshotEvent?.isOpen ?? state?.isOpen ?? false;
    final DateTime? currentOpenedAt =
        snapshotEvent?.currentOpenedAt ?? state?.currentOpenedAt;
    final DateTime? lastChangedAt =
        snapshotEvent?.lastChangedAt ?? state?.lastChangedAt;
    final String? lastOpeningId =
        snapshotEvent?.lastOpeningId ?? state?.lastOpeningId;
    final List<DoorOpeningRecord> closedHistory = history
        .where((DoorOpeningRecord record) => record.closedAt != null)
        .toList(growable: false);
    final DoorOpeningRecord? lastClosed = closedHistory.isEmpty
        ? null
        : closedHistory.first;
    final List<DoorOpeningRecord> recentHistory = closedHistory
        .take(20)
        .toList(growable: false);

    final bool stateLoading =
        stateSnapshot.connectionState == ConnectionState.waiting &&
        !stateSnapshot.hasData;
    final bool historyLoading =
        historySnapshot.connectionState == ConnectionState.waiting &&
        !historySnapshot.hasData;

    // Total openings: count + accumulated duration in parentheses
    final int? totalCount = state?.openCountTotal;
    final int? totalDurationS = state?.totalOpenDurationS;
    final String totalOpeningsLabel = totalCount == null
        ? '--'
        : totalDurationS == null
        ? '$totalCount'
        : '$totalCount (${_formatDuration(totalDurationS)})';

    // Month openings: count + accumulated duration in parentheses
    final List<DoorOpeningRecord> monthHistory =
        monthHistorySnapshot.data ?? const <DoorOpeningRecord>[];
    final int monthCount = monthHistory.length;
    int monthDurationS = 0;
    for (final DoorOpeningRecord record in monthHistory) {
      if (record.closedAt != null && record.durationS != null) {
        monthDurationS += record.durationS!;
      } else if (record.closedAt == null && record.openedAt != null) {
        monthDurationS += now.difference(record.openedAt!).inSeconds.abs();
      }
    }
    final bool monthLoading =
        monthHistorySnapshot.connectionState == ConnectionState.waiting &&
        !monthHistorySnapshot.hasData;
    final String monthOpeningsLabel = monthLoading
        ? '--'
        : '$monthCount (${_formatDuration(monthDurationS)})';

    return _DoorDisplayData(
      isOpen: isOpen,
      statusLabel: isOpen ? 'Abierta' : 'Cerrada',
      openSinceLabel: isOpen && currentOpenedAt != null
          ? '${_formatDateTime(currentOpenedAt)} (${_formatDuration(now.difference(currentOpenedAt).inSeconds)})'
          : null,
      lastChangedLabel: _formatDateTime(lastChangedAt),
      lastOpeningTooltip: lastOpeningId == null || lastOpeningId.isEmpty
          ? null
          : 'openingId: $lastOpeningId',
      totalOpeningsLabel: totalOpeningsLabel,
      monthOpeningsLabel: monthOpeningsLabel,
      lastClosedLabel: lastClosed == null
          ? null
          : '${_formatDateTime(lastClosed.openedAt)} (${_formatDuration(lastClosed.durationS)})',
      recentHistoryItems: recentHistory
          .map(
            (DoorOpeningRecord record) =>
                '${_formatDateTime(record.openedAt)} (${_formatDuration(record.durationS)})',
          )
          .toList(growable: false),
      loading: stateLoading || historyLoading,
      errorMessage: _errorMessage(stateSnapshot.error ?? historySnapshot.error),
    );
  }

  final bool isOpen;
  final String statusLabel;
  final String? openSinceLabel;
  final String lastChangedLabel;
  final String? lastOpeningTooltip;
  final String totalOpeningsLabel;
  final String monthOpeningsLabel;
  final String? lastClosedLabel;
  final List<String> recentHistoryItems;
  final bool loading;
  final String? errorMessage;
}

class _DoorDataRow extends StatelessWidget {
  const _DoorDataRow({
    required this.label,
    this.m1Child,
    this.m2Child,
    this.fullValueChild,
    this.labelBold = false,
    this.labelFontSize = 12,
    this.backgroundColor,
  }) : assert(
         fullValueChild != null || (m1Child != null && m2Child != null),
         'Provide fullValueChild or both m1Child and m2Child',
       );

  final String label;
  final Widget? m1Child;
  final Widget? m2Child;

  /// When set, spans both value columns (flex 8) instead of two separate ones.
  final Widget? fullValueChild;
  final bool labelBold;
  final double labelFontSize;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final List<Widget> valueColumns = fullValueChild != null
        ? <Widget>[Expanded(flex: 8, child: fullValueChild!)]
        : <Widget>[
            Expanded(flex: 4, child: m1Child!),
            Expanded(flex: 4, child: m2Child!),
          ];

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)
                  .copyWith(
                    fontSize: labelFontSize,
                    fontWeight: labelBold ? FontWeight.w700 : FontWeight.w400,
                  ),
            ),
          ),
          ...valueColumns,
        ],
      ),
    );
  }
}

class _DoorSection extends StatelessWidget {
  const _DoorSection({
    required this.title,
    required this.doorName,
    required this.data,
  });

  final String title;
  final String doorName;
  final _DoorDisplayData data;

  static const Color _rowEven = Color(0xFF0F172A);
  static const Color _rowOdd = Color(0xFF1E293B);

  static Color _rc(int i) => i.isEven ? _rowEven : _rowOdd;

  @override
  Widget build(BuildContext context) {
    int i = 0;
    final List<Widget> rows = <Widget>[
      // Título "Puerta" con el nombre (Sala / Munter) en la misma línea
      _DoorDataRow(
        label: title,
        labelBold: true,
        m1Child: Text(
          doorName,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        m2Child: const SizedBox.shrink(),
      ),
      _DoorDataRow(
        label: 'Estado actual',
        labelFontSize: data.isOpen ? 14 : 12,
        backgroundColor: _rc(i++),
        m1Child: _ValueText(
          data.statusLabel,
          color: data.isOpen
              ? const Color(0xFFEF4444)
              : const Color(0xFF22C55E),
          bold: true,
          fontSize: data.isOpen ? 14 : 12,
        ),
        m2Child: const _ValueText('-', color: Color(0xFF94A3B8)),
      ),
      if (data.openSinceLabel != null)
        _DoorDataRow(
          label: 'Abierta desde',
          labelFontSize: data.isOpen ? 14 : 12,
          backgroundColor: _rc(i++),
          m1Child: _ValueText(
            data.openSinceLabel!,
            color: const Color(0xFFEF4444),
            bold: true,
            fontSize: data.isOpen ? 14 : 12,
          ),
          m2Child: const _ValueText('-', color: Color(0xFF94A3B8)),
        ),
      _DoorDataRow(
        label: 'Último cambio',
        backgroundColor: _rc(i++),
        m1Child: _TooltipValueText(
          value: data.lastChangedLabel,
          tooltip: data.lastOpeningTooltip,
        ),
        m2Child: const _ValueText('-', color: Color(0xFF94A3B8)),
      ),
      _DoorDataRow(
        label: 'Aperturas totales',
        backgroundColor: _rc(i++),
        m1Child: _ValueText(data.totalOpeningsLabel, bold: true),
        m2Child: const _ValueText('-', color: Color(0xFF94A3B8)),
      ),
      _DoorDataRow(
        label: 'Aperturas mes',
        backgroundColor: _rc(i++),
        m1Child: _ValueText(data.monthOpeningsLabel, bold: true),
        m2Child: const _ValueText('-', color: Color(0xFF94A3B8)),
      ),
      _DoorDataRow(
        label: 'Última apertura completa',
        backgroundColor: _rc(i++),
        m1Child: _SingleLineValueText(data.lastClosedLabel ?? '--'),
        m2Child: const _ValueText('-', color: Color(0xFF94A3B8)),
      ),
      // Sin color de fila: la caja de historial tiene su propio estilo
      _DoorDataRow(
        label: 'Historial reciente',
        m1Child: _HistoryBoxValue(items: data.recentHistoryItems),
        m2Child: const _ValueText('-', color: Color(0xFF94A3B8)),
      ),
      if (data.loading)
        _DoorDataRow(
          label: '',
          m1Child: const _ValueText(
            'Cargando aperturas...',
            color: Color(0xFF94A3B8),
          ),
          m2Child: const SizedBox.shrink(),
        ),
      if (data.errorMessage != null)
        _DoorDataRow(
          label: '',
          m1Child: _ValueText(
            data.errorMessage!,
            color: const Color(0xFFFCA5A5),
          ),
          m2Child: const SizedBox.shrink(),
        ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText(
    this.value, {
    this.bold = false,
    this.color = const Color(0xFFE5E7EB),
    this.fontSize = 12,
  });

  final String value;
  final bool bold;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}

class _TooltipValueText extends StatelessWidget {
  const _TooltipValueText({required this.value, this.tooltip});

  final String value;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (tooltip == null) {
      return _ValueText(value);
    }
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 250),
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        child: Text(
          value,
          style: const TextStyle(
            color: Color(0xFFE5E7EB),
            fontSize: 12,
            fontWeight: FontWeight.w400,
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}

class _SingleLineValueText extends StatelessWidget {
  const _SingleLineValueText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(
        value,
        softWrap: false,
        style: const TextStyle(
          color: Color(0xFFE5E7EB),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _HistoryListValue extends StatelessWidget {
  const _HistoryListValue({required this.items});

  final List<String> items;

  static const double _rowHeight = 22;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _ValueText('--');
    }
    return ListView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      itemBuilder: (BuildContext context, int index) {
        return SizedBox(
          height: _rowHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              items[index],
              style: const TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HistoryBoxValue extends StatelessWidget {
  const _HistoryBoxValue({required this.items});

  final List<String> items;

  static const int _maxVisibleItems = 5;
  static const double _verticalPadding = 8;

  @override
  Widget build(BuildContext context) {
    final int visibleItems = items.isEmpty
        ? 1
        : (items.length < _maxVisibleItems ? items.length : _maxVisibleItems);
    final double contentHeight =
        (visibleItems * _HistoryListValue._rowHeight) + _verticalPadding;

    return Container(
      width: double.infinity,
      height: contentHeight,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF223046)),
      ),
      child: _HistoryListValue(items: items),
    );
  }
}

class _FooterMessage extends StatelessWidget {
  const _FooterMessage({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w400),
    );
  }
}

String? _errorMessage(Object? error) {
  if (error == null) {
    return null;
  }
  return 'No se pudo leer Firestore: $error';
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '--';
  }
  final DateTime local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${_two(local.year % 100)} ${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

String _formatDuration(int? seconds) {
  if (seconds == null) {
    return '--';
  }
  final int safe = seconds.abs();
  if (safe < 60) {
    return '${safe}s';
  }
  final int hours = safe ~/ 3600;
  final int minutes = (safe % 3600) ~/ 60;
  final int remainingSeconds = safe % 60;
  if (hours == 0) {
    return '${_two(minutes)}:${_two(remainingSeconds)}';
  }
  return '$hours:${_two(minutes)}:${_two(remainingSeconds)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
