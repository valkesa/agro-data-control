import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../services/plc_dashboard_service.dart';

class SnapshotValidationPage extends StatefulWidget {
  const SnapshotValidationPage({super.key});

  static const String routeName = '/validation';

  @override
  State<SnapshotValidationPage> createState() => _SnapshotValidationPageState();
}

class _SnapshotValidationPageState extends State<SnapshotValidationPage> {
  static const Duration _refreshInterval = Duration(seconds: 4);
  static const double _variableColumnWidth = 180;
  static const double _sourceColumnWidth = 165;
  static const double _valueColumnWidth = 170;
  static const double _statusColumnWidth = 52;
  static const double _tableWidth =
      _variableColumnWidth +
      _sourceColumnWidth +
      _sourceColumnWidth +
      _valueColumnWidth +
      _valueColumnWidth +
      _statusColumnWidth;

  final PlcDashboardService _currentService = const PlcDashboardService(
    endpoint: AppConfig.currentBackendSnapshotUrl,
  );
  final PlcDashboardService _candidateService = const PlcDashboardService(
    endpoint: AppConfig.candidateBackendSnapshotUrl,
  );

  Timer? _refreshTimer;
  _SnapshotSourceState _current = const _SnapshotSourceState.loading();
  _SnapshotSourceState _candidate = const _SnapshotSourceState.loading();

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    _refreshTimer?.cancel();
    final List<LiveSnapshotResult> results = await Future.wait([
      _currentService.fetchLiveSnapshot(),
      _candidateService.fetchLiveSnapshot(),
    ]);
    if (!mounted) {
      return;
    }

    setState(() {
      _current = _SnapshotSourceState.fromResult(results[0], fallbackName: 'current');
      _candidate = _SnapshotSourceState.fromResult(
        results[1],
        fallbackName: 'candidate',
      );
    });

    _refreshTimer = Timer(_refreshInterval, () {
      unawaited(_refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<_ComparisonRowData> rows = _buildComparisonRows(
      _current,
      _candidate,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Validacion Backends'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay datos comparables todavia.',
                        style: TextStyle(color: Color(0xFFCBD5E1)),
                      ),
                    )
                  : Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: _tableWidth + 40,
                          child: CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _SummaryCard(
                                        state: _current,
                                        title: 'Backend actual',
                                      ),
                                      _SummaryCard(
                                        state: _candidate,
                                        title: 'Backend nuevo',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: _PinnedHeaderDelegate(
                                  child: Container(
                                    color: const Color(0xFF0F172A),
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: const _TableHeaderRow(),
                                  ),
                                ),
                              ),
                              SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  return _TableDataRow(row: rows[index]);
                                }, childCount: rows.length),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state, required this.title});

  final _SnapshotSourceState state;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _SummaryLine(label: 'backendName', value: state.backendName),
          _SummaryLine(label: 'endpoint', value: state.endpoint),
          _SummaryLine(label: 'lastUpdatedAt', value: state.rootLastUpdatedAt),
          _SummaryLine(label: 'backendOnline', value: state.backendOnline),
          _SummaryLine(label: 'munters1.estado', value: state.munters1State),
          _SummaryLine(label: 'munters1.plcOnline', value: state.munters1Online),
          _SummaryLine(label: 'munters2.estado', value: state.munters2State),
          _SummaryLine(label: 'munters2.plcOnline', value: state.munters2Online),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              state.errorMessage!,
              style: const TextStyle(
                color: Color(0xFFFCA5A5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotSourceState {
  const _SnapshotSourceState({
    required this.endpoint,
    required this.backendName,
    required this.payload,
    required this.errorMessage,
  });

  const _SnapshotSourceState.loading()
      : endpoint = '',
        backendName = 'loading',
        payload = const <String, dynamic>{},
        errorMessage = null;

  factory _SnapshotSourceState.fromResult(
    LiveSnapshotResult result, {
    required String fallbackName,
  }) {
    final Map<String, dynamic> payload = result.rawPayload ?? const <String, dynamic>{};
    return _SnapshotSourceState(
      endpoint: result.endpoint ?? '-',
      backendName: (payload['backendName'] ?? fallbackName).toString(),
      payload: payload,
      errorMessage: result.isSuccess ? null : result.message,
    );
  }

  final String endpoint;
  final String backendName;
  final Map<String, dynamic> payload;
  final String? errorMessage;

  String get rootLastUpdatedAt => _stringify(
    payload['lastUpdatedAt'] ?? (payload['status'] as Map?)?['lastUpdatedAt'],
  );

  String get backendOnline => _stringify(
    payload['backendOnline'] ?? (payload['status'] as Map?)?['backendOnline'],
  );

  String get munters1State => _stringify(
    (payload['munters1'] as Map?)?['estadoEquipo'] ??
        (payload['munters1'] as Map?)?['estadoPLC'],
  );

  String get munters1Online =>
      _stringify((payload['munters1'] as Map?)?['plcOnline']);

  String get munters2State => _stringify(
    (payload['munters2'] as Map?)?['estadoEquipo'] ??
        (payload['munters2'] as Map?)?['estadoPLC'],
  );

  String get munters2Online =>
      _stringify((payload['munters2'] as Map?)?['plcOnline']);

  String get backendCommunication {
    if (errorMessage != null) {
      return errorMessage!;
    }

    final Object? statusObject = payload['status'];
    final Map<Object?, Object?>? statusMap =
        statusObject is Map ? statusObject : null;
    final Object? statusError = statusMap?['lastError'];
    if (statusError != null && statusError.toString().trim().isNotEmpty) {
      return statusError.toString();
    }

    final Map<Object?, Object?>? primaryUnit = _primaryUnitMap();
    final Object? unitError = primaryUnit?['lastError'];
    if (unitError != null && unitError.toString().trim().isNotEmpty) {
      return unitError.toString();
    }

    return 'ok';
  }

  String get pingPlc {
    final Map<Object?, Object?>? primaryUnit = _primaryUnitMap();
    final Object? reachable = primaryUnit?['plcReachable'];
    if (reachable == true) {
      return 'OK';
    }
    if (reachable == false) {
      return 'NOK';
    }
    return 'Sin datos';
  }

  String get heartbeatStatus {
    final Map<Object?, Object?>? primaryUnit = _primaryUnitMap();
    if (primaryUnit == null) {
      return 'Sin datos';
    }

    final Object? signalSources = primaryUnit['signalSources'];
    final bool hasHeartbeat =
        signalSources is Map && signalSources.containsKey('heartbeat');
    if (!hasHeartbeat) {
      return 'Sin heartbeat';
    }

    return primaryUnit['plcRunning'] == true
        ? 'Run (cambió)'
        : 'Stop (igual)';
  }

  Map<Object?, Object?>? _primaryUnitMap() {
    final Object? munters2 = payload['munters2'];
    if (munters2 is Map && munters2['configured'] != false) {
      return munters2;
    }
    final Object? munters1 = payload['munters1'];
    if (munters1 is Map) {
      return munters1;
    }
    return null;
  }
}

class _ComparisonRowData {
  const _ComparisonRowData({
    required this.path,
    required this.currentValue,
    required this.candidateValue,
    required this.currentSource,
    required this.candidateSource,
    required this.matches,
  });

  final String path;
  final String currentValue;
  final String candidateValue;
  final String? currentSource;
  final String? candidateSource;
  final bool matches;
}

List<_ComparisonRowData> _buildComparisonRows(
  _SnapshotSourceState currentState,
  _SnapshotSourceState candidateState,
) {
  final Map<String, dynamic> current = currentState.payload;
  final Map<String, dynamic> candidate = candidateState.payload;
  final Map<String, Object?> currentFlat = <String, Object?>{};
  final Map<String, Object?> candidateFlat = <String, Object?>{};
  _flattenMap('', current, currentFlat);
  _flattenMap('', candidate, candidateFlat);
  final Map<String, String> currentSources = _extractSignalSources(current);
  final Map<String, String> candidateSources = _extractSignalSources(candidate);

  final Set<String> keys = <String>{
    ...currentFlat.keys,
    ...candidateFlat.keys,
  }..removeWhere((key) => key.contains('.signalSources.'));
  final List<String> sortedKeys = keys.toList()..sort();

  final List<_ComparisonRowData> rows = <_ComparisonRowData>[
    _ComparisonRowData(
      path: 'Comunicacion backend',
      currentValue: currentState.backendCommunication,
      candidateValue: candidateState.backendCommunication,
      currentSource: null,
      candidateSource: null,
      matches:
          currentState.backendCommunication == candidateState.backendCommunication,
    ),
    _ComparisonRowData(
      path: 'Ping PLC',
      currentValue: currentState.pingPlc,
      candidateValue: candidateState.pingPlc,
      currentSource: null,
      candidateSource: null,
      matches: currentState.pingPlc == candidateState.pingPlc,
    ),
    _ComparisonRowData(
      path: 'Heartbeat',
      currentValue: currentState.heartbeatStatus,
      candidateValue: candidateState.heartbeatStatus,
      currentSource: null,
      candidateSource: null,
      matches: currentState.heartbeatStatus == candidateState.heartbeatStatus,
    ),
  ];

  rows.addAll(
    sortedKeys.map((key) {
      final Object? currentValue = currentFlat[key];
      final Object? candidateValue = candidateFlat[key];
      return _ComparisonRowData(
        path: key,
        currentValue: _stringify(currentValue),
        candidateValue: _stringify(candidateValue),
        currentSource: currentSources[key],
        candidateSource: candidateSources[key],
        matches: currentValue == candidateValue,
      );
    }),
  );

  return rows;
}

void _flattenMap(
  String prefix,
  Object? value,
  Map<String, Object?> output,
) {
  if (value is Map) {
    final List<String> keys = value.keys.map((key) => key.toString()).toList()
      ..sort();
    for (final String key in keys) {
      final String nextPrefix = prefix.isEmpty ? key : '$prefix.$key';
      _flattenMap(nextPrefix, value[key], output);
    }
    return;
  }

  if (value is List) {
    for (int index = 0; index < value.length; index += 1) {
      final String nextPrefix = '$prefix[$index]';
      _flattenMap(nextPrefix, value[index], output);
    }
    return;
  }

  if (prefix.isNotEmpty) {
    output[prefix] = value;
  }
}

String _stringify(Object? value) {
  if (value == null) {
    return 'null';
  }
  return value.toString();
}

Map<String, String> _extractSignalSources(Map<String, dynamic> payload) {
  final Map<String, String> sources = <String, String>{};
  for (final String unitKey in <String>['munters1', 'munters2']) {
    final Object? unitObject = payload[unitKey];
    if (unitObject is! Map) {
      continue;
    }
    final Object? sourceObject = unitObject['signalSources'];
    if (sourceObject is! Map) {
      continue;
    }
    sourceObject.forEach((key, value) {
      sources['$unitKey.$key'] = value?.toString() ?? '';
    });
  }
  return sources;
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(
    this.text, {
    required this.width,
    this.showDivider = true,
  });

  final String text;
  final double width;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                right: BorderSide(color: Color(0xFF334155), width: 1),
              )
            : null,
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell(
    this.text, {
    required this.width,
    this.monospace = false,
    this.color,
    this.weight,
    this.showDivider = true,
  });

  final String text;
  final double width;
  final bool monospace;
  final Color? color;
  final FontWeight? weight;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                right: BorderSide(color: Color(0xFF334155), width: 1),
              )
            : null,
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: weight,
          fontFamily: monospace ? 'monospace' : null,
        ),
      ),
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderCell('Variable', width: _SnapshotValidationPageState._variableColumnWidth),
        _HeaderCell(
          'Origen Modbus actual',
          width: _SnapshotValidationPageState._sourceColumnWidth,
        ),
        _HeaderCell(
          'Origen Modbus nuevo',
          width: _SnapshotValidationPageState._sourceColumnWidth,
        ),
        _HeaderCell(
          'Backend actual',
          width: _SnapshotValidationPageState._valueColumnWidth,
        ),
        _HeaderCell(
          'Backend nuevo',
          width: _SnapshotValidationPageState._valueColumnWidth,
        ),
        _HeaderCell(
          'Estado',
          width: _SnapshotValidationPageState._statusColumnWidth,
          showDivider: false,
        ),
      ],
    );
  }
}

class _TableDataRow extends StatelessWidget {
  const _TableDataRow({required this.row});

  final _ComparisonRowData row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BodyCell(
            row.path,
            width: _SnapshotValidationPageState._variableColumnWidth,
            monospace: true,
          ),
          _BodyCell(
            row.currentSource ?? 'null',
            width: _SnapshotValidationPageState._sourceColumnWidth,
          ),
          _BodyCell(
            row.candidateSource ?? 'null',
            width: _SnapshotValidationPageState._sourceColumnWidth,
          ),
          _BodyCell(
            row.currentValue,
            width: _SnapshotValidationPageState._valueColumnWidth,
          ),
          _BodyCell(
            row.candidateValue,
            width: _SnapshotValidationPageState._valueColumnWidth,
          ),
          _BodyCell(
            row.matches ? 'OK' : 'DIFF',
            width: _SnapshotValidationPageState._statusColumnWidth,
            color: row.matches
                ? const Color(0xFF22C55E)
                : const Color(0xFFEF4444),
            weight: FontWeight.w700,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 38;

  @override
  double get maxExtent => 38;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return false;
  }
}
