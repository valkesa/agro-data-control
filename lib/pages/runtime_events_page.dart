import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/electric_consumption_settings.dart';
import '../models/runtime_event_record.dart';
import '../services/electric_consumption_settings_service.dart';
import '../services/electrical_cost_service.dart';
import '../services/runtime_events_service.dart';

enum _FanPeriod { today, week, month }

const Map<String, String> _deviceLabels = <String, String>{
  'humidifierPump': 'Bomba Humidificadora',
  'heater1': 'Resistencia 1',
  'heater2': 'Resistencia 2',
  'fans': 'Ventiladores',
};

const Map<String, Color> _deviceColors = <String, Color>{
  'humidifierPump': Color(0xFF3B82F6),
  'heater1': Color(0xFFF97316),
  'heater2': Color(0xFFEF4444),
  'fans': Color(0xFF22C55E),
};

String _plcLabel(String plcId) {
  switch (plcId) {
    case 'munters1':
      return 'Munters 1';
    case 'munters2':
      return 'Munters 2';
    default:
      return plcId;
  }
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final int minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}min';
  final int hours = minutes ~/ 60;
  final int rem = minutes % 60;
  return rem > 0 ? '${hours}h ${rem}min' : '${hours}h';
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String _fmtNum(double value, int decimals) =>
    value.toStringAsFixed(decimals).replaceAll('.', ',');

String _fmtInt(int value) {
  final String raw = value.abs().toString();
  final StringBuffer buf = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buf.write('.');
    buf.write(raw[i]);
  }
  return '${value < 0 ? '-' : ''}${buf.toString()}';
}

String _formatCost(double value) {
  final int rounded = value.round();
  final String raw = rounded.abs().toString();
  final StringBuffer buf = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buf.write('.');
    buf.write(raw[i]);
  }
  return '\$${rounded < 0 ? '-' : ''}${buf.toString()}';
}

String _formatShortDate(DateTime dt) {
  final DateTime now = DateTime.now();
  final DateTime local = dt.toLocal();
  final bool sameDay =
      local.day == now.day &&
      local.month == now.month &&
      local.year == now.year;
  if (sameDay) {
    return 'Hoy ${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  }
  return '${_twoDigits(local.day)}/${_twoDigits(local.month)} ${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

// ─────────────────────────────────────────────
//  Page
// ─────────────────────────────────────────────

class RuntimeEventsPage extends StatefulWidget {
  const RuntimeEventsPage({
    super.key,
    required this.tenantId,
    required this.siteId,
    required this.plcIds,
    required this.onBack,
  });

  final String tenantId;
  final String siteId;
  final List<String> plcIds;
  final VoidCallback onBack;

  @override
  State<RuntimeEventsPage> createState() => _RuntimeEventsPageState();
}

class _RuntimeEventsPageState extends State<RuntimeEventsPage>
    with SingleTickerProviderStateMixin {
  final RuntimeEventsService _service = const RuntimeEventsService();
  late final TabController _tabController;

  List<RuntimeEventRecord> _records = <RuntimeEventRecord>[];
  bool _loading = true;
  String? _error;

  String _selectedPlcId = 'all';
  _FanPeriod _selectedPeriod = _FanPeriod.week;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Future<List<RuntimeEventRecord>>> futures = widget.plcIds
          .map(
            (String plcId) => _service.fetchRecent(
              tenantId: widget.tenantId,
              siteId: widget.siteId,
              plcId: plcId,
            ),
          )
          .toList();
      final List<List<RuntimeEventRecord>> results = await Future.wait(futures);
      final List<RuntimeEventRecord> all =
          results.expand((List<RuntimeEventRecord> r) => r).toList();
      all.sort(
        (RuntimeEventRecord a, RuntimeEventRecord b) =>
            b.startedAt.compareTo(a.startedAt),
      );
      if (mounted) {
        setState(() {
          _records = all;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<RuntimeEventRecord> get _filtered {
    if (_selectedPlcId == 'all') return _records;
    return _records
        .where((RuntimeEventRecord r) => r.plcId == _selectedPlcId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildHeader(),
        _buildFilterBar(),
        Container(
          color: const Color(0xFF0F172A),
          child: TabBar(
            controller: _tabController,
            tabs: const <Tab>[Tab(text: 'Datos'), Tab(text: 'Gráficos')],
            labelColor: const Color(0xFF38BDF8),
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorColor: const Color(0xFF38BDF8),
            dividerColor: const Color(0xFF1E293B),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF38BDF8),
                  ),
                )
              : _error != null
              ? _ErrorView(error: _error!, onRetry: _loadData)
              : TabBarView(
                  controller: _tabController,
                  children: <Widget>[
                    _DataTab(records: _filtered, allRecords: _records),
                    _ChartsTab(
                      records: _filtered,
                      allRecords: _records,
                      tenantId: widget.tenantId,
                      siteId: widget.siteId,
                      plcIds: widget.plcIds,
                      selectedPlcId: _selectedPlcId,
                      selectedPeriod: _selectedPeriod,
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xCC0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, color: Color(0xFFE5E7EB)),
            tooltip: 'Volver',
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Registros para consumos',
              style: TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${_records.length} registros',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
            tooltip: 'Actualizar',
          ),
        ],
      ),
    );
  }

  String _periodLabel(_FanPeriod p) {
    switch (p) {
      case _FanPeriod.today:
        return 'Hoy';
      case _FanPeriod.week:
        return 'Semana';
      case _FanPeriod.month:
        return 'Mes';
    }
  }

  Widget _buildSelectorChip(
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1D4ED8) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selected ? const Color(0xFF3B82F6) : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? const Color(0xFFBFDBFE) : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            _buildSelectorChip(
              'Todos',
              _selectedPlcId == 'all',
              () => setState(() => _selectedPlcId = 'all'),
            ),
            const SizedBox(width: 6),
            ...widget.plcIds.map(
              (String id) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildSelectorChip(
                  _plcLabel(id),
                  _selectedPlcId == id,
                  () => setState(() => _selectedPlcId = id),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 20,
              color: const Color(0xFF334155),
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            ..._FanPeriod.values.map(
              (_FanPeriod p) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildSelectorChip(
                  _periodLabel(p),
                  _selectedPeriod == p,
                  () => setState(() => _selectedPeriod = p),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Data tab
// ─────────────────────────────────────────────

class _DataTab extends StatefulWidget {
  const _DataTab({required this.records, required this.allRecords});

  final List<RuntimeEventRecord> records;
  final List<RuntimeEventRecord> allRecords;

  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  String? _filterDeviceType;
  bool? _filterIsHeartbeat;

  List<RuntimeEventRecord> get _displayed {
    return widget.records.where((RuntimeEventRecord r) {
      if (_filterDeviceType != null && r.deviceType != _filterDeviceType) {
        return false;
      }
      if (_filterIsHeartbeat != null && r.isHeartbeat != _filterIsHeartbeat) {
        return false;
      }
      return true;
    }).toList();
  }

  void _showDeviceFilter() {
    _showStringDialog(
      title: 'Filtrar por dispositivo',
      options: <_StrOpt>[
        const _StrOpt(value: null, label: 'Todos'),
        ..._deviceLabels.entries.map(
          (MapEntry<String, String> e) => _StrOpt(value: e.key, label: e.value),
        ),
      ],
      current: _filterDeviceType,
      onSelected: (String? v) => setState(() => _filterDeviceType = v),
    );
  }

  void _showTypeFilter() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => _SimpleDialog(
        title: 'Filtrar por tipo',
        children: <Widget>[
          _DialogTile(
            label: 'Todos',
            selected: _filterIsHeartbeat == null,
            onTap: () {
              setState(() => _filterIsHeartbeat = null);
              Navigator.of(ctx).pop();
            },
          ),
          _DialogTile(
            label: 'Solo cerrados',
            selected: _filterIsHeartbeat == false,
            onTap: () {
              setState(() => _filterIsHeartbeat = false);
              Navigator.of(ctx).pop();
            },
          ),
          _DialogTile(
            label: 'Solo heartbeat (HB)',
            selected: _filterIsHeartbeat == true,
            onTap: () {
              setState(() => _filterIsHeartbeat = true);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  void _showStringDialog({
    required String title,
    required List<_StrOpt> options,
    required String? current,
    required void Function(String?) onSelected,
  }) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => _SimpleDialog(
        title: title,
        children: options
            .map(
              (_StrOpt opt) => _DialogTile(
                label: opt.label,
                selected: opt.value == current,
                onTap: () {
                  onSelected(opt.value);
                  Navigator.of(ctx).pop();
                },
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<RuntimeEventRecord> displayed = _displayed;
    final bool hasFilter = _filterDeviceType != null || _filterIsHeartbeat != null;
    return Column(
      children: <Widget>[
        _CurrentStateSummary(allRecords: widget.allRecords),
        Container(
          color: const Color(0xFF0F172A),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _Chip(
                  label: _filterDeviceType == null
                      ? 'Todos los dispositivos'
                      : (_deviceLabels[_filterDeviceType] ?? _filterDeviceType!),
                  active: _filterDeviceType != null,
                  onTap: _showDeviceFilter,
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: _filterIsHeartbeat == null
                      ? 'Todos los tipos'
                      : (_filterIsHeartbeat! ? 'Solo HB' : 'Solo cerrados'),
                  active: _filterIsHeartbeat != null,
                  onTap: _showTypeFilter,
                ),
                if (hasFilter) ...<Widget>[
                  const SizedBox(width: 8),
                  _Chip(
                    label: 'Limpiar',
                    active: false,
                    isReset: true,
                    onTap: () => setState(() {
                      _filterDeviceType = null;
                      _filterIsHeartbeat = null;
                    }),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: displayed.isEmpty
              ? const Center(
                  child: Text(
                    'No hay registros',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: displayed.length,
                  itemBuilder: (BuildContext ctx, int i) =>
                      _EventCard(record: displayed[i]),
                ),
        ),
      ],
    );
  }
}

class _CurrentStateSummary extends StatelessWidget {
  const _CurrentStateSummary({required this.allRecords});

  final List<RuntimeEventRecord> allRecords;

  @override
  Widget build(BuildContext context) {
    if (allRecords.isEmpty) return const SizedBox.shrink();

    // For each (plcId, deviceType) find the most recent record.
    final Map<String, RuntimeEventRecord> latest = <String, RuntimeEventRecord>{};
    for (final RuntimeEventRecord r in allRecords) {
      final String key = '${r.plcId}::${r.deviceType}';
      final RuntimeEventRecord? prev = latest[key];
      if (prev == null || r.eventTime.isAfter(prev.eventTime)) {
        latest[key] = r;
      }
    }

    if (latest.isEmpty) return const SizedBox.shrink();

    final List<_DeviceState> states = latest.entries.map((MapEntry<String, RuntimeEventRecord> e) {
      final RuntimeEventRecord r = e.value;
      // Use explicit deviceIsOn if available; fall back to isHeartbeat for old docs.
      final bool isOn = r.deviceIsOn ?? r.isHeartbeat;
      return _DeviceState(
        plcId: r.plcId,
        deviceType: r.deviceType,
        isOn: isOn,
        since: isOn ? r.startedAt : null,
        powerPercent: r.powerPercent,
      );
    }).toList()
      ..sort((a, b) {
        final int plcCmp = a.plcId.compareTo(b.plcId);
        if (plcCmp != 0) return plcCmp;
        return (_deviceLabels[a.deviceType] ?? a.deviceType)
            .compareTo(_deviceLabels[b.deviceType] ?? b.deviceType);
      });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Estado actual (según último registro)',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: () {
              final Map<String, List<_DeviceState>> byPlc = <String, List<_DeviceState>>{};
              for (final _DeviceState s in states) {
                byPlc.putIfAbsent(s.plcId, () => <_DeviceState>[]).add(s);
              }
              final List<String> plcIds = byPlc.keys.toList()..sort();
              return plcIds.map((String plcId) {
                final List<_DeviceState> plcStates = byPlc[plcId]!;
                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: plcStates
                        .map((_DeviceState s) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _StateChip(state: s),
                            ))
                        .toList(),
                  ),
                );
              }).toList();
            }(),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _DeviceState {
  const _DeviceState({
    required this.plcId,
    required this.deviceType,
    required this.isOn,
    this.since,
    this.powerPercent,
  });
  final String plcId;
  final String deviceType;
  final bool isOn;
  final DateTime? since;
  final int? powerPercent;
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});
  final _DeviceState state;

  @override
  Widget build(BuildContext context) {
    final Color deviceColor =
        _deviceColors[state.deviceType] ?? const Color(0xFF94A3B8);
    final String deviceLabel =
        _deviceLabels[state.deviceType] ?? state.deviceType;
    final Color onColor = const Color(0xFF22C55E);
    final Color offColor = const Color(0xFF475569);

    final bool isFans = state.deviceType == 'fans';
    final String stateText;
    final Color stateColor;
    if (isFans) {
      final int pct = state.powerPercent ?? 0;
      stateColor = pct > 0 ? onColor : offColor;
      stateText = pct > 0 ? '$pct%' : 'OFF';
    } else {
      stateColor = state.isOn ? onColor : offColor;
      stateText = state.isOn ? 'ON' : 'OFF';
    }

    String sinceText = '';
    if (state.isOn && state.since != null) {
      sinceText = ' · desde ${_formatShortDate(state.since!)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: state.isOn
              ? onColor.withValues(alpha: 0.4)
              : const Color(0xFF334155),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: stateColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            deviceLabel,
            style: TextStyle(
              color: deviceColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _plcLabel(state.plcId),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
          ),
          const SizedBox(width: 4),
          Text(
            stateText,
            style: TextStyle(
              color: stateColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (sinceText.isNotEmpty)
            Text(
              sinceText,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
            ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.record});

  final RuntimeEventRecord record;

  @override
  Widget build(BuildContext context) {
    final Color color =
        _deviceColors[record.deviceType] ?? const Color(0xFF94A3B8);
    final String label =
        _deviceLabels[record.deviceType] ?? record.deviceType;

    final DateTime? endTime = record.endedAt ?? record.observedAt;
    final String dateRange = endTime != null
        ? '${_formatShortDate(record.startedAt)} → ${_formatShortDate(endTime)}'
        : _formatShortDate(record.startedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 80,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _plcLabel(record.plcId),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      if (record.isHeartbeat)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Text(
                            'HB',
                            style: TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      if (record.isHeartbeat)
                        _buildHbStateWidget(record, color)
                      else
                        Text(
                          _formatDuration(record.durationSec),
                          style: const TextStyle(
                            color: Color(0xFFE5E7EB),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        dateRange,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                  if (record.powerPercent != null ||
                      record.energyKwh != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        if (record.powerPercent != null)
                          Text(
                            '${record.powerPercent}% potencia',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                            ),
                          ),
                        if (record.powerPercent != null &&
                            record.energyKwh != null)
                          const Text(
                            '  ·  ',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                            ),
                          ),
                        if (record.energyKwh != null)
                          Text(
                            '${record.energyKwh!.toStringAsFixed(3)} kWh',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHbStateWidget(RuntimeEventRecord record, Color deviceColor) {
    final bool isFans = record.deviceType == 'fans';
    if (isFans) {
      final int pct = record.powerPercent ?? 0;
      return Text(
        '$pct%',
        style: TextStyle(
          color: pct > 0 ? deviceColor : const Color(0xFF475569),
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    final bool isOn = record.deviceIsOn ?? false;
    return Text(
      isOn ? 'ON' : 'OFF',
      style: TextStyle(
        color: isOn ? const Color(0xFF22C55E) : const Color(0xFF475569),
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Charts tab
// ─────────────────────────────────────────────

class _ChartsTab extends StatelessWidget {
  const _ChartsTab({
    required this.records,
    required this.allRecords,
    required this.tenantId,
    required this.siteId,
    required this.plcIds,
    required this.selectedPlcId,
    required this.selectedPeriod,
  });

  final List<RuntimeEventRecord> records;
  final List<RuntimeEventRecord> allRecords;
  final String tenantId;
  final String siteId;
  final List<String> plcIds;
  final String selectedPlcId;
  final _FanPeriod selectedPeriod;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── Cost summary + Ventiladores card ──
          _DeviceBreakdownSection(
            allRecords: allRecords,
            tenantId: tenantId,
            siteId: siteId,
            plcIds: plcIds,
            selectedPlcId: selectedPlcId,
            selectedPeriod: selectedPeriod,
            showCostSummary: true,
            deviceTypes: const <String>['fans'],
          ),
          // ── Power line charts ──
          const Text(
            'Potencia — Ventiladores',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (selectedPlcId == 'all' || selectedPlcId == 'munters1')
            _PowerLineChart(
              records: records,
              plcId: 'munters1',
              plcLabel: 'Munters 1',
              selectedPeriod: selectedPeriod,
            ),
          if (selectedPlcId == 'all') const SizedBox(height: 16),
          if (selectedPlcId == 'all' || selectedPlcId == 'munters2')
            _PowerLineChart(
              records: records,
              plcId: 'munters2',
              plcLabel: 'Munters 2',
              selectedPeriod: selectedPeriod,
            ),
          const SizedBox(height: 20),
          // ── Otros dispositivos ──
          _DeviceBreakdownSection(
            allRecords: allRecords,
            tenantId: tenantId,
            siteId: siteId,
            plcIds: plcIds,
            selectedPlcId: selectedPlcId,
            selectedPeriod: selectedPeriod,
            deviceTypes: const <String>[
              'humidifierPump',
              'heater1',
              'heater2',
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Device breakdown with shared PLC/period selectors and cost
// ─────────────────────────────────────────────

class _DeviceBreakdownSection extends StatefulWidget {
  const _DeviceBreakdownSection({
    required this.allRecords,
    required this.tenantId,
    required this.siteId,
    required this.plcIds,
    required this.selectedPlcId,
    required this.selectedPeriod,
    this.showCostSummary = false,
    this.deviceTypes,
  });

  final List<RuntimeEventRecord> allRecords;
  final String tenantId;
  final String siteId;
  final List<String> plcIds;
  final String selectedPlcId;
  final _FanPeriod selectedPeriod;
  final bool showCostSummary;
  final List<String>? deviceTypes;

  @override
  State<_DeviceBreakdownSection> createState() =>
      _DeviceBreakdownSectionState();
}

class _DeviceBreakdownSectionState extends State<_DeviceBreakdownSection> {
  double? _costPerKw;
  Map<String, ElectricConsumptionSettings> _consumptionByPlc =
      <String, ElectricConsumptionSettings>{};
  bool _costLoading = true;

  final ElectricalCostService _costService = const ElectricalCostService();
  final ElectricConsumptionSettingsService _consumptionService =
      const ElectricConsumptionSettingsService();

  @override
  void initState() {
    super.initState();
    _loadCostData();
  }

  Future<void> _loadCostData() async {
    try {
      final double? cost = await _costService.readCost(
        tenantId: widget.tenantId,
        siteId: widget.siteId,
      );
      final Map<String, ElectricConsumptionSettings> byPlc =
          <String, ElectricConsumptionSettings>{};
      for (final String plcId in widget.plcIds) {
        byPlc[plcId] = await _consumptionService.readSettings(
          tenantId: widget.tenantId,
          siteId: widget.siteId,
          plcId: plcId,
        );
      }
      if (mounted) {
        setState(() {
          _costPerKw = cost;
          _consumptionByPlc = byPlc;
          _costLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _costLoading = false);
    }
  }

  List<String> get _activePlcIds =>
      widget.selectedPlcId == 'all'
          ? widget.plcIds
          : <String>[widget.selectedPlcId];

  DateTime _periodStart() {
    final DateTime now = DateTime.now();
    switch (widget.selectedPeriod) {
      case _FanPeriod.today:
        return DateTime(now.year, now.month, now.day);
      case _FanPeriod.week:
        return DateTime(now.year, now.month, now.day - (now.weekday - 1));
      case _FanPeriod.month:
        return DateTime(now.year, now.month, 1);
    }
  }

  double? _kwForFanLevel(String plcId, int pct) {
    final ElectricConsumptionSettings? s = _consumptionByPlc[plcId];
    if (s == null) return null;
    for (final FanConsumptionLevel l in s.fanLevels) {
      if (l.percent.round() == pct) return l.kw;
    }
    return null;
  }

  double? _kwForSimpleDevice(String plcId, String deviceType) {
    final ElectricConsumptionSettings? s = _consumptionByPlc[plcId];
    if (s == null) return null;
    switch (deviceType) {
      case 'humidifierPump':
        return s.humidifierPumpKw;
      case 'heater1':
        return s.heaterStage1Kw;
      case 'heater2':
        return s.heaterStage2Kw;
      default:
        return null;
    }
  }

  // For each unique event instance (plcId + deviceType + startedAt),
  // keep the closed record if available, otherwise the HB with the
  // largest durationSec (most recent snapshot). This avoids double-counting
  // when both HBs and a closed record exist for the same event.
  // Returns the portion of a record's duration that falls within the period.
  // Cross-boundary events (started before periodStart but observed/ended after)
  // are clamped so we don't count pre-period time.
  int _effectiveDurationSec(RuntimeEventRecord r, DateTime periodStart) {
    if (!r.startedAt.isBefore(periodStart)) return r.durationSec;
    if (r.isHeartbeat &&
        r.observedAt != null &&
        r.observedAt!.isAfter(periodStart)) {
      return r.observedAt!.difference(periodStart).inSeconds;
    }
    if (!r.isHeartbeat &&
        r.endedAt != null &&
        r.endedAt!.isAfter(periodStart)) {
      return r.endedAt!.difference(periodStart).inSeconds;
    }
    return 0;
  }

  Map<String, RuntimeEventRecord> _groupByEvent(
    Iterable<RuntimeEventRecord> records,
  ) {
    final Map<String, RuntimeEventRecord> best =
        <String, RuntimeEventRecord>{};
    for (final RuntimeEventRecord r in records) {
      final String key =
          '${r.plcId}:${r.deviceType}:${r.startedAt.millisecondsSinceEpoch}';
      final RuntimeEventRecord? existing = best[key];
      if (existing == null) {
        best[key] = r;
      } else if (!r.isHeartbeat && existing.isHeartbeat) {
        best[key] = r; // closed supersedes HB
      } else if (r.isHeartbeat &&
          existing.isHeartbeat &&
          r.durationSec > existing.durationSec) {
        best[key] = r; // latest (longest) HB wins
      }
    }
    return best;
  }

  Widget _buildGroupTitleRow(String title, double? kwh, double? cost) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF22C55E),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (kwh != null && kwh > 0) ...<Widget>[
            Text(
              '${_fmtNum(kwh, 1)} kWh',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            cost != null ? _formatCost(cost) : '—',
            style: const TextStyle(
              color: Color(0xFF4ADE80),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextCostSummary() {
    if (_costLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: 14,
          width: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF38BDF8),
          ),
        ),
      );
    }
    if (_costPerKw == null) return const SizedBox.shrink();

    final DateTime periodStart = _periodStart();
    final double cpk = _costPerKw!;
    final String cpkStr = _fmtInt(cpk.round());

    // ── Fans: accumulate per power-percent level ──
    final Map<int, int> fanSec = <int, int>{};
    final Map<int, double> fanKwHrs = <int, double>{};
    final Map<int, double> fanCostMap = <int, double>{};
    final Set<int> fanMissingPcts = <int>{};

    final Iterable<RuntimeEventRecord> fanCandidates = widget.allRecords.where(
      (RuntimeEventRecord r) =>
          r.deviceType == 'fans' &&
          _activePlcIds.contains(r.plcId) &&
          r.powerPercent != null &&
          _effectiveDurationSec(r, periodStart) > 0,
    );
    for (final RuntimeEventRecord r in _groupByEvent(fanCandidates).values) {
      final int pct = r.powerPercent!;
      final int effSec = _effectiveDurationSec(r, periodStart);
      fanSec[pct] = (fanSec[pct] ?? 0) + effSec;
      final double? kw = _kwForFanLevel(r.plcId, pct);
      if (kw != null) {
        final double hrs = effSec / 3600.0;
        fanKwHrs[pct] = (fanKwHrs[pct] ?? 0) + hrs * kw;
        fanCostMap[pct] = (fanCostMap[pct] ?? 0) + hrs * kw * cpk;
      } else {
        fanMissingPcts.add(pct);
      }
    }

    // ── Simple devices ──
    const List<String> simpleDevices = <String>[
      'humidifierPump',
      'heater1',
      'heater2',
    ];
    final Map<String, int> devSec = <String, int>{};
    final Map<String, double> devKwHrs = <String, double>{};
    final Map<String, double> devCostMap = <String, double>{};
    final Set<String> devMissing = <String>{};

    for (final String deviceType in simpleDevices) {
      final Iterable<RuntimeEventRecord> candidates = widget.allRecords.where(
        (RuntimeEventRecord r) =>
            r.deviceType == deviceType &&
            _activePlcIds.contains(r.plcId) &&
            _effectiveDurationSec(r, periodStart) > 0,
      );
      for (final RuntimeEventRecord r in _groupByEvent(candidates).values) {
        final int effSec = _effectiveDurationSec(r, periodStart);
        devSec[deviceType] = (devSec[deviceType] ?? 0) + effSec;
        final double? kw = _kwForSimpleDevice(r.plcId, deviceType);
        if (kw != null) {
          final double hrs = effSec / 3600.0;
          devKwHrs[deviceType] = (devKwHrs[deviceType] ?? 0) + hrs * kw;
          devCostMap[deviceType] = (devCostMap[deviceType] ?? 0) + hrs * kw * cpk;
        } else {
          devMissing.add(deviceType);
        }
      }
    }

    // ── Grand total ──
    double grandTotal =
        fanCostMap.values.fold(0.0, (double a, double b) => a + b);
    for (final String d in simpleDevices) {
      grandTotal += devCostMap[d] ?? 0;
    }

    // ── Group totals ──────────────────────────────────────────────────────────
    final double fansTotalKwh =
        fanKwHrs.values.fold(0.0, (double a, double b) => a + b);
    final double fansTotalCost =
        fanCostMap.values.fold(0.0, (double a, double b) => a + b);
    final bool fansMissingAny = fanMissingPcts.isNotEmpty;

    final double coolKwh = devKwHrs['humidifierPump'] ?? 0;
    final double coolCost = devCostMap['humidifierPump'] ?? 0;
    final bool coolMissing = devMissing.contains('humidifierPump');

    final double heatKwh =
        (devKwHrs['heater1'] ?? 0) + (devKwHrs['heater2'] ?? 0);
    final double heatCost =
        (devCostMap['heater1'] ?? 0) + (devCostMap['heater2'] ?? 0);
    final bool heatMissing =
        devMissing.contains('heater1') || devMissing.contains('heater2');

    final List<Widget> lines = <Widget>[];

    // ── Forzadores ────────────────────────────────────────────────────────────
    final List<int> sortedPcts = fanSec.keys.toList()..sort();
    if (sortedPcts.isNotEmpty) {
      lines.add(
        _buildGroupTitleRow(
          'Forzadores',
          fansMissingAny ? null : fansTotalKwh,
          fansMissingAny ? null : fansTotalCost,
        ),
      );
      for (final int pct in sortedPcts) {
        final int sec = fanSec[pct]!;
        final double hrs = sec / 3600.0;
        final bool missing =
            fanMissingPcts.contains(pct) || !fanKwHrs.containsKey(pct);
        final String line;
        if (missing) {
          line = '  $pct%: ${_fmtNum(hrs, 2)}h — sin config kW';
        } else {
          final double effectiveKw = hrs > 0 ? fanKwHrs[pct]! / hrs : 0;
          final double cost = fanCostMap[pct]!;
          line =
              '  $pct%: ${_fmtNum(hrs, 2)}h × ${_fmtNum(effectiveKw, 2)}kW'
              ' × $cpkStr \$/kWh = ${_formatCost(cost)}';
        }
        lines.add(Text(
          line,
          style: TextStyle(
            color: missing
                ? const Color(0xFF64748B)
                : const Color(0xFFCBD5E1),
            fontSize: 11,
          ),
        ));
      }
    }

    // ── Refrigeración ─────────────────────────────────────────────────────────
    if (sortedPcts.isNotEmpty) lines.add(const SizedBox(height: 4));
    lines.add(
      _buildGroupTitleRow(
        'Refrigeración',
        coolMissing ? null : coolKwh,
        coolMissing ? null : coolCost,
      ),
    );
    {
      const String deviceType = 'humidifierPump';
      final String label = _deviceLabels[deviceType] ?? deviceType;
      final int sec = devSec[deviceType] ?? 0;
      if (sec == 0) {
        lines.add(const Text(
          '  Bomba Humidificadora: \$0',
          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
        ));
      } else {
        final double hrs = sec / 3600.0;
        final bool missing = coolMissing || !devKwHrs.containsKey(deviceType);
        final String line;
        if (missing) {
          line = '  $label: ${_fmtNum(hrs, 2)}h — sin config kW';
        } else {
          final double effectiveKw = hrs > 0 ? devKwHrs[deviceType]! / hrs : 0;
          final double cost = devCostMap[deviceType]!;
          line = '  $label: ${_fmtNum(hrs, 2)}h × ${_fmtNum(effectiveKw, 2)}kW'
              ' × $cpkStr \$/kWh = ${_formatCost(cost)}';
        }
        lines.add(Text(
          line,
          style: TextStyle(
            color: missing
                ? const Color(0xFF64748B)
                : const Color(0xFFCBD5E1),
            fontSize: 11,
          ),
        ));
      }
    }

    // ── Calefacción ───────────────────────────────────────────────────────────
    const List<String> heaterDevices = <String>['heater1', 'heater2'];
    final bool hasHeaters =
        heaterDevices.any((String d) => (devSec[d] ?? 0) > 0);
    if (hasHeaters) {
      lines.add(const SizedBox(height: 4));
      lines.add(
        _buildGroupTitleRow(
          'Calefacción',
          heatMissing ? null : heatKwh,
          heatMissing ? null : heatCost,
        ),
      );
      for (final String deviceType in heaterDevices) {
        final int sec = devSec[deviceType] ?? 0;
        if (sec == 0) continue;
        final String label = _deviceLabels[deviceType] ?? deviceType;
        final double hrs = sec / 3600.0;
        final bool missing =
            devMissing.contains(deviceType) || !devKwHrs.containsKey(deviceType);
        final String line;
        if (missing) {
          line = '  $label: ${_fmtNum(hrs, 2)}h — sin config kW';
        } else {
          final double effectiveKw = hrs > 0 ? devKwHrs[deviceType]! / hrs : 0;
          final double cost = devCostMap[deviceType]!;
          line =
              '  $label: ${_fmtNum(hrs, 2)}h × ${_fmtNum(effectiveKw, 2)}kW'
              ' × $cpkStr \$/kWh = ${_formatCost(cost)}';
        }
        lines.add(Text(
          line,
          style: TextStyle(
            color: missing
                ? const Color(0xFF64748B)
                : const Color(0xFFCBD5E1),
            fontSize: 11,
          ),
        ));
      }
    }

    if (lines.isEmpty) return const SizedBox.shrink();

    lines.add(const Divider(color: Color(0xFF334155), height: 16));
    lines.add(Text(
      'Total: ${_formatCost(grandTotal)}',
      style: const TextStyle(
        color: Color(0xFF4ADE80),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  Widget _buildPowerRow({
    required String label,
    required Color color,
    required double frac,
    required String duration,
    required bool showCost,
    String? costText,
    String? tooltipText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: <Widget>[
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: frac.clamp(0.0, 1.0),
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              duration,
              style: const TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          if (showCost) ...<Widget>[
            const SizedBox(width: 8),
            SizedBox(
              width: 58,
              child: costText != null
                  ? Tooltip(
                      message: tooltipText ?? '',
                      child: Text(
                        costText,
                        style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    )
                  : const Text(
                      '—',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.right,
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFanContent(Color color) {
    final DateTime periodStart = _periodStart();
    final bool showCost = !_costLoading && _costPerKw != null;
    final Map<int, int> secByPower = <int, int>{};
    final Map<int, double> costByPower = <int, double>{};
    final Set<int> missingKwPcts = <int>{};

    final Iterable<RuntimeEventRecord> candidates = widget.allRecords.where(
      (RuntimeEventRecord r) =>
          r.deviceType == 'fans' &&
          _activePlcIds.contains(r.plcId) &&
          r.powerPercent != null &&
          _effectiveDurationSec(r, periodStart) > 0,
    );
    for (final RuntimeEventRecord r in _groupByEvent(candidates).values) {
      final int pct = r.powerPercent!;
      final int effSec = _effectiveDurationSec(r, periodStart);
      secByPower[pct] = (secByPower[pct] ?? 0) + effSec;
      if (showCost) {
        final double? kw = _kwForFanLevel(r.plcId, pct);
        if (kw != null) {
          costByPower[pct] = (costByPower[pct] ?? 0) +
              (effSec / 3600.0) * kw * _costPerKw!;
        } else {
          missingKwPcts.add(pct);
        }
      }
    }

    if (secByPower.isEmpty) {
      return const Text(
        'Sin datos para el período seleccionado',
        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
      );
    }

    final List<int> sortedPcts = secByPower.keys.toList()..sort();
    final int totalSec = secByPower.values.fold(0, (int a, int b) => a + b);
    final double? grandTotal = showCost && costByPower.isNotEmpty
        ? costByPower.values.fold<double>(0.0, (double a, double b) => a + b)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Tiempo por nivel de potencia',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
        ),
        const SizedBox(height: 6),
        ...sortedPcts.map((int pct) {
          final int sec = secByPower[pct]!;
          final double frac = totalSec > 0 ? sec / totalSec : 0;
          String? costText;
          String? tooltipText;
          if (showCost && costByPower.containsKey(pct)) {
            final double cost = costByPower[pct]!;
            final bool partial = missingKwPcts.contains(pct);
            costText = '${partial ? '~' : ''}${_formatCost(cost)}';
            if (!partial) {
              final double hours = sec / 3600.0;
              final double kw = hours > 0 ? cost / (hours * _costPerKw!) : 0;
              tooltipText =
                  '${hours.toStringAsFixed(1)}h'
                  ' × ${kw.toStringAsFixed(2)}kW'
                  ' × ${_formatCost(_costPerKw!)}/kWh'
                  ' = ${_formatCost(cost)}';
            } else {
              tooltipText =
                  'Costo parcial — falta configurar kW para algún PLC';
            }
          }
          return _buildPowerRow(
            label: '$pct%',
            color: color,
            frac: frac,
            duration: _formatDuration(sec),
            showCost: showCost,
            costText: showCost ? (costText ?? '—') : null,
            tooltipText: tooltipText,
          );
        }),
        if (showCost) ...<Widget>[
          const Divider(color: Color(0xFF334155), height: 16),
          Row(
            children: <Widget>[
              const Spacer(),
              const Text(
                'Total',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: Text(
                  _formatDuration(totalSec),
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 58,
                child: grandTotal != null
                    ? Text(
                        _formatCost(grandTotal),
                        style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.right,
                      )
                    : const Text(
                        '—',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.right,
                      ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSimpleDeviceContent(String deviceType, Color color) {
    if (_costLoading || _costPerKw == null) return const SizedBox.shrink();
    final DateTime periodStart = _periodStart();
    double totalCost = 0;
    int totalSec = 0;
    bool hasMissing = false;

    final Iterable<RuntimeEventRecord> candidates = widget.allRecords.where(
      (RuntimeEventRecord r) =>
          r.deviceType == deviceType &&
          _activePlcIds.contains(r.plcId) &&
          _effectiveDurationSec(r, periodStart) > 0,
    );
    for (final RuntimeEventRecord r in _groupByEvent(candidates).values) {
      final int effSec = _effectiveDurationSec(r, periodStart);
      totalSec += effSec;
      final double? kw = _kwForSimpleDevice(r.plcId, deviceType);
      if (kw != null) {
        totalCost += (effSec / 3600.0) * kw * _costPerKw!;
      } else {
        hasMissing = true;
      }
    }

    if (totalSec == 0) return const SizedBox.shrink();

    final String costText = totalCost > 0
        ? '${hasMissing ? '~' : ''}${_formatCost(totalCost)}'
        : '—';
    final double hours = totalSec / 3600.0;
    final double kw =
        hours > 0 && _costPerKw! > 0 ? totalCost / (hours * _costPerKw!) : 0;
    final String tooltip = hasMissing
        ? 'Costo parcial — falta configurar kW'
        : '${hours.toStringAsFixed(1)}h'
            ' × ${kw.toStringAsFixed(2)}kW'
            ' × ${_formatCost(_costPerKw!)}/kWh'
            ' = ${_formatCost(totalCost)}';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          const Spacer(),
          Tooltip(
            message: tooltip,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF4ADE80).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _formatDuration(totalSec),
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                  const Text(
                    ' = ',
                    style: TextStyle(color: Color(0xFF475569), fontSize: 11),
                  ),
                  Text(
                    costText,
                    style: TextStyle(
                      color: totalCost > 0
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFF475569),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime periodStart = _periodStart();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.showCostSummary) _buildTextCostSummary(),
        // ── Device cards ──
        ..._deviceLabels.entries.map((MapEntry<String, String> entry) {
          final String deviceType = entry.key;
          if (widget.deviceTypes != null &&
              !widget.deviceTypes!.contains(deviceType)) {
            return const SizedBox.shrink();
          }
          final Color color =
              _deviceColors[deviceType] ?? const Color(0xFF94A3B8);

          final List<RuntimeEventRecord> recs = widget.allRecords
              .where(
                (RuntimeEventRecord r) =>
                    r.deviceType == deviceType &&
                    _activePlcIds.contains(r.plcId) &&
                    !r.eventTime.isBefore(periodStart),
              )
              .toList();

          if (recs.isEmpty) return const SizedBox.shrink();

          final List<RuntimeEventRecord> closed =
              recs.where((RuntimeEventRecord r) => !r.isHeartbeat).toList();
          final List<RuntimeEventRecord> hbs =
              recs.where((RuntimeEventRecord r) => r.isHeartbeat).toList();
          final int totalSec = recs.fold(
            0,
            (int s, RuntimeEventRecord r) =>
                s + _effectiveDurationSec(r, periodStart),
          );
          final int closedSec = closed.fold(
            0,
            (int s, RuntimeEventRecord r) =>
                s + _effectiveDurationSec(r, periodStart),
          );

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.value,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    _StatPill(
                      label: 'Total activo',
                      value: _formatDuration(totalSec),
                    ),
                    const SizedBox(width: 8),
                    _StatPill(
                      label: 'Eventos cerrados',
                      value:
                          '${closed.length}  (${_formatDuration(closedSec)})',
                    ),
                    const SizedBox(width: 8),
                    _StatPill(
                      label: 'Heartbeats',
                      value: hbs.length.toString(),
                    ),
                  ],
                ),
                if (deviceType == 'fans') ...<Widget>[
                  const SizedBox(height: 12),
                  _buildFanContent(color),
                ] else ...<Widget>[
                  _buildSimpleDeviceContent(deviceType, color),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Power line chart with pan / zoom
// ─────────────────────────────────────────────

class _PowerLineChart extends StatefulWidget {
  const _PowerLineChart({
    required this.records,
    required this.plcId,
    required this.plcLabel,
    required this.selectedPeriod,
  });

  final List<RuntimeEventRecord> records;
  final String plcId;
  final String plcLabel;
  final _FanPeriod selectedPeriod;

  @override
  State<_PowerLineChart> createState() => _PowerLineChartState();
}

class _PowerLineChartState extends State<_PowerLineChart> {
  List<FlSpot> _spots = const <FlSpot>[];
  double _startMs = 0;
  double _endMs = 0;

  // Pan gesture tracking (chart body)
  double _panStartMs = 0;
  double _panEndMs = 0;
  double _panStartX = 0;

  // X-axis strip gesture tracking: horizontal = pan, vertical = zoom
  String? _xGestureMode; // 'pan' or 'zoom'
  double _xGestureStartMs = 0;
  double _xGestureEndMs = 0;
  double _xGestureStartX = 0;
  double _xGestureStartY = 0;

  static const double _minWindowMs = 15 * 60 * 1000; // 15 min
  static const double _maxWindowMs = 30 * 24 * 3600 * 1000; // 30 days

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(_PowerLineChart old) {
    super.didUpdateWidget(old);
    if (old.plcId != widget.plcId || old.selectedPeriod != widget.selectedPeriod) {
      _rebuild();
    } else if (old.records != widget.records) {
      _rebuildSpots();
    }
  }

  DateTime _periodStart() {
    final DateTime now = DateTime.now();
    switch (widget.selectedPeriod) {
      case _FanPeriod.today:
        return DateTime(now.year, now.month, now.day);
      case _FanPeriod.week:
        return DateTime(now.year, now.month, now.day - (now.weekday - 1));
      case _FanPeriod.month:
        return DateTime(now.year, now.month, 1);
    }
  }

  void _rebuild() {
    _rebuildSpots();
    final double periodMs = _periodStart().millisecondsSinceEpoch.toDouble();
    final double nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    _startMs = periodMs;
    _endMs = nowMs + 30 * 60 * 1000;
  }

  void _rebuildSpots() {
    final double periodMs = _periodStart().millisecondsSinceEpoch.toDouble();
    _spots = _buildStepSpots(afterMs: periodMs);
  }

  // Build step-line spots from fan records for this PLC, filtered by period.
  List<FlSpot> _buildStepSpots({required double afterMs}) {
    final List<RuntimeEventRecord> recs = widget.records
        .where(
          (RuntimeEventRecord r) =>
              r.plcId == widget.plcId &&
              r.deviceType == 'fans' &&
              r.startedAt.millisecondsSinceEpoch >= afterMs,
        )
        .toList()
      ..sort(
        (RuntimeEventRecord a, RuntimeEventRecord b) =>
            a.startedAt.compareTo(b.startedAt),
      );

    if (recs.isEmpty) return const <FlSpot>[];

    final List<FlSpot> spots = <FlSpot>[];

    for (final RuntimeEventRecord r in recs) {
      final double sx = r.startedAt.millisecondsSinceEpoch.toDouble();
      final double ex =
          (r.endedAt ?? r.observedAt ?? r.startedAt)
              .millisecondsSinceEpoch
              .toDouble();
      final double pw = (r.powerPercent ?? 0).toDouble();

      if (spots.isEmpty) {
        spots.add(FlSpot(sx, pw));
      } else {
        final double prevY = spots.last.y;
        if (prevY != pw) {
          spots.add(FlSpot(sx, prevY));
          spots.add(FlSpot(sx, pw));
        } else if (sx > spots.last.x + 500) {
          spots.add(FlSpot(sx, pw));
        }
      }

      if (ex > sx + 500) {
        spots.add(FlSpot(ex, pw));
      }
    }

    return spots;
  }

  // ── Pan (drag on chart body) ──────────────────
  void _onPanStart(DragStartDetails d, double chartWidth) {
    _panStartMs = _startMs;
    _panEndMs = _endMs;
    _panStartX = d.localPosition.dx;
  }

  void _onPanUpdate(DragUpdateDetails d, double chartWidth) {
    final double duration = _panEndMs - _panStartMs;
    final double dx = d.localPosition.dx - _panStartX;
    final double panMs = -(dx / chartWidth) * duration;
    setState(() {
      _startMs = _panStartMs + panMs;
      _endMs = _panEndMs + panMs;
    });
  }

  // ── X-axis strip: horizontal = pan, vertical = zoom ──
  void _onXAxisPanStart(DragStartDetails d, double chartWidth) {
    _xGestureMode = null;
    _xGestureStartMs = _startMs;
    _xGestureEndMs = _endMs;
    _xGestureStartX = d.localPosition.dx;
    _xGestureStartY = d.localPosition.dy;
  }

  void _onXAxisPanUpdate(DragUpdateDetails d, double chartWidth) {
    final double dx = d.localPosition.dx - _xGestureStartX;
    final double dy = d.localPosition.dy - _xGestureStartY;

    if (_xGestureMode == null && (dx.abs() > 5 || dy.abs() > 5)) {
      _xGestureMode = dx.abs() >= dy.abs() ? 'pan' : 'zoom';
    }

    if (_xGestureMode == 'pan') {
      final double duration = _xGestureEndMs - _xGestureStartMs;
      final double panMs = -(dx / chartWidth) * duration;
      setState(() {
        _startMs = _xGestureStartMs + panMs;
        _endMs = _xGestureEndMs + panMs;
      });
    } else if (_xGestureMode == 'zoom') {
      final double origDuration = _xGestureEndMs - _xGestureStartMs;
      // drag up (negative dy) = zoom in; drag down = zoom out
      final double factor = math.pow(2.0, dy / 150.0).toDouble();
      final double newDuration =
          (origDuration * factor).clamp(_minWindowMs, _maxWindowMs);
      final double center = (_xGestureStartMs + _xGestureEndMs) / 2;
      setState(() {
        _startMs = center - newDuration / 2;
        _endMs = center + newDuration / 2;
      });
    }
  }

  double _axisInterval(double windowMs) {
    const double m = 60000;
    const double h = 3600000;
    if (windowMs <= 30 * m) return 5 * m;
    if (windowMs <= 2 * h) return 15 * m;
    if (windowMs <= 6 * h) return h;
    if (windowMs <= 24 * h) return 3 * h;
    if (windowMs <= 7 * 24 * h) return 12 * h;
    return 24 * h;
  }

  String _formatAxisLabel(double ms, double windowMs) {
    final DateTime dt =
        DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal();
    final String hhmm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (windowMs < 24 * 3600000) return hhmm;
    return '${dt.day}/${dt.month}\n$hhmm';
  }

  @override
  Widget build(BuildContext context) {
    final Color fanColor =
        _deviceColors['fans'] ?? const Color(0xFF22C55E);

    final double windowMs = _endMs - _startMs;
    final double interval = _axisInterval(windowMs);

    // Clip spots to a slightly wider window to avoid edge artifacts
    final double buf = windowMs * 0.15;
    final List<FlSpot> visible = _spots
        .where((FlSpot s) => s.x >= _startMs - buf && s.x <= _endMs + buf)
        .toList();
    final List<FlSpot> chartSpots = visible.isEmpty
        ? <FlSpot>[FlSpot(_startMs, 0), FlSpot(_endMs, 0)]
        : visible;

    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints bc) {
        final double chartWidth = bc.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                widget.plcLabel,
                style: TextStyle(
                  color: fanColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              height: 190,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: <Widget>[
                    // ── Chart body: pan by horizontal drag ──
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (DragStartDetails d) =>
                          _onPanStart(d, chartWidth),
                      onHorizontalDragUpdate: (DragUpdateDetails d) =>
                          _onPanUpdate(d, chartWidth),
                      child: LineChart(
                      duration: Duration.zero,
                      LineChartData(
                        minX: _startMs,
                        maxX: _endMs,
                        minY: 0,
                        maxY: 105,
                        clipData: const FlClipData.all(),
                        gridData: FlGridData(
                          show: true,
                          horizontalInterval: 25,
                          verticalInterval: interval,
                          getDrawingHorizontalLine: (_) => const FlLine(
                            color: Color(0xFF1E293B),
                            strokeWidth: 1,
                          ),
                          getDrawingVerticalLine: (_) => const FlLine(
                            color: Color(0xFF1E293B),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              interval: 25,
                              getTitlesWidget: (double v, TitleMeta _) {
                                if (v != 0 &&
                                    v != 25 &&
                                    v != 50 &&
                                    v != 75 &&
                                    v != 100) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '${v.toInt()}%',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 9,
                                  ),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: interval,
                              getTitlesWidget: (double v, TitleMeta meta) {
                                if (v < _startMs || v > _endMs) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _formatAxisLabel(v, windowMs),
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 9,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => const Color(0xFF1E293B),
                            getTooltipItems: (List<LineBarSpot> spots) =>
                                spots.map((LineBarSpot s) {
                              final DateTime dt =
                                  DateTime.fromMillisecondsSinceEpoch(
                                s.x.toInt(),
                              ).toLocal();
                              final String time =
                                  '${dt.day}/${dt.month} '
                                  '${dt.hour.toString().padLeft(2, '0')}:'
                                  '${dt.minute.toString().padLeft(2, '0')}';
                              return LineTooltipItem(
                                '$time\n${s.y.toInt()}%',
                                const TextStyle(
                                  color: Color(0xFFE5E7EB),
                                  fontSize: 11,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        lineBarsData: <LineChartBarData>[
                          LineChartBarData(
                            spots: chartSpots,
                            isCurved: false,
                            color: fanColor,
                            barWidth: 2,
                            isStrokeCapRound: false,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: fanColor.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                    // ── X axis strip: horizontal = pan, vertical = zoom ──
                    Positioned(
                      left: 34,
                      right: 0,
                      bottom: 0,
                      height: 32,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (DragStartDetails d) =>
                              _onXAxisPanStart(d, chartWidth),
                          onPanUpdate: (DragUpdateDetails d) =>
                              _onXAxisPanUpdate(d, chartWidth),
                          onPanEnd: (_) => _xGestureMode = null,
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 9),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFE5E7EB),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Shared small widgets
// ─────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.isReset = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool isReset;

  @override
  Widget build(BuildContext context) {
    final Color border = isReset
        ? const Color(0xFF475569)
        : (active ? const Color(0xFF38BDF8) : const Color(0xFF334155));
    final Color bg = isReset
        ? const Color(0xFF1E293B)
        : (active
              ? const Color(0xFF0EA5E9).withValues(alpha: 0.12)
              : const Color(0xFF1E293B));
    final Color text = isReset
        ? const Color(0xFF94A3B8)
        : (active ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: text,
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _SimpleDialog extends StatelessWidget {
  const _SimpleDialog({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFE5E7EB),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      content: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _DialogTile extends StatelessWidget {
  const _DialogTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFF38BDF8) : const Color(0xFFE5E7EB),
          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          fontSize: 13,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: Color(0xFF38BDF8), size: 18)
          : null,
      onTap: onTap,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline,
              color: Color(0xFFEF4444),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              error,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

// Internal data helpers
class _StrOpt {
  const _StrOpt({required this.value, required this.label});
  final String? value;
  final String label;
}
