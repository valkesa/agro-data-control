import 'dart:async';

import 'package:flutter/material.dart';

import '../models/munters_model.dart';
import '../models/plc_unit_diagnostics.dart';
import '../models/water_shortage_summary.dart';
import '../widgets/status_indicator.dart';

class MuntersPage extends StatefulWidget {
  const MuntersPage({
    super.key,
    required this.data,
    required this.snapshotStale,
    required this.showSnapshotPulse,
    this.waterShortageSummary,
  });

  final MuntersModel data;
  final bool snapshotStale;
  final bool showSnapshotPulse;
  final WaterShortageSummary? waterShortageSummary;

  @override
  State<MuntersPage> createState() => _MuntersPageState();
}

class _MuntersPageState extends State<MuntersPage> {
  static const Duration _technicalDataAutoCollapseDelay = Duration(minutes: 5);

  Timer? _technicalDataAutoCollapseTimer;
  bool _technicalDataExpanded = false;

  @override
  void dispose() {
    _technicalDataAutoCollapseTimer?.cancel();
    super.dispose();
  }

  void _setTechnicalDataExpanded(bool expanded) {
    _technicalDataAutoCollapseTimer?.cancel();
    if (expanded) {
      _technicalDataAutoCollapseTimer = Timer(
        _technicalDataAutoCollapseDelay,
        () {
          if (!mounted) {
            return;
          }
          setState(() {
            _technicalDataExpanded = false;
          });
        },
      );
    }

    setState(() {
      _technicalDataExpanded = expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> sections = _buildSections();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool singleColumn = constraints.maxWidth < 720;
          final bool boundedHeight = constraints.maxHeight.isFinite;
          final Widget content = _SectionsLayout(
            sections: sections,
            singleColumn: singleColumn,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: boundedHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              _Header(
                title: widget.data.name,
                subtitle: 'Detalle operacional compacto',
              ),
              const SizedBox(height: 8),
              if (boundedHeight)
                Expanded(child: SingleChildScrollView(child: content))
              else
                content,
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildSections() {
    final MuntersModel data = widget.data;

    return [
      _Section(
        title: 'AMBIENTE',
        child: Column(
          children: [
            _ValueRow(
              label: 'T. Salida Sala',
              value: _formatDecimal(data.tempInterior, 1),
              unit: '°C',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'T. Ingreso Sala',
              value: _formatDecimal(data.tempIngresoSala, 1),
              unit: '°C',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Humedad interior',
              value: _formatDecimal(data.humInterior, 0),
              unit: '%',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'T. Exterior',
              value: _formatDecimal(data.tempExterior, 0),
              unit: '°C',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Humedad exterior',
              value: _formatDecimal(data.humExterior, 0),
              unit: '%',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Presion diferencial',
              value: _formatDecimal(data.presionDiferencial, 0),
              unit: 'Pa',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'NH3',
              value: _formatDecimal(data.nh3, 0),
              unit: 'ppm',
            ),
          ],
        ),
      ),
      _Section(
        title: 'VENTILACION',
        child: Column(
          children: [
            _ProgressRow(
              label: 'Potencia',
              value: _normalizeVoltageToPercent(data.tensionSalidaVentiladores),
            ),
            const SizedBox(height: 4),
            _CompactFanRow(
              fans: [
                ('Q5', data.fanQ5),
                ('Q6', data.fanQ6),
                ('Q7', data.fanQ7),
                ('Q8', data.fanQ8),
                ('Q9', data.fanQ9),
                ('Q10', data.fanQ10),
              ],
            ),
          ],
        ),
      ),
      _Section(
        title: 'HUMIDIFICACION',
        child: Column(
          children: [
            _StatusRow(
              label: 'Bomba humidificador',
              active: data.bombaHumidificador,
              activeLabel: 'ENCENDIDA',
              inactiveLabel: 'APAGADA',
            ),
            const SizedBox(height: 4),
            _StatusRow(
              label: 'Nivel de agua',
              active: data.nivelAguaAlarma,
              activeLabel: 'FALLA',
              inactiveLabel: 'NORMAL',
              activeColor: const Color(0xFFEF4444),
              inactiveColor: const Color(0xFF22C55E),
            ),
            const SizedBox(height: 4),
            _StatusRow(
              label: 'Falla termica bomba',
              active: data.fallaTermicaBomba,
              activeLabel: 'ALARMA',
              inactiveLabel: 'NORMAL',
              activeColor: const Color(0xFFEF4444),
              inactiveColor: const Color(0xFF22C55E),
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Eventos sin agua Total',
              value: _formatInt(widget.waterShortageSummary?.totalEvents),
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Eventos sin agua Mes',
              value: _formatInt(widget.waterShortageSummary?.monthEvents),
            ),
          ],
        ),
      ),
      _Section(
        title: 'CALEFACCION',
        child: Column(
          children: [
            _StatusRow(
              label: 'Resistencia etapa 1',
              active: data.resistencia1,
              activeLabel: 'ENCENDIDA',
              inactiveLabel: 'APAGADA',
            ),
            const SizedBox(height: 4),
            _StatusRow(
              label: 'Resistencia etapa 2',
              active: data.resistencia2,
              activeLabel: 'ENCENDIDA',
              inactiveLabel: 'APAGADA',
            ),
          ],
        ),
      ),
      _Section(
        title: 'ESTADOS MECANICOS',
        child: Column(
          children: [
            _StatusRow(
              label: 'Puerta sala',
              active: data.salaAbierta,
              activeLabel: 'Abierta',
              inactiveLabel: 'Cerrada',
              activeColor: const Color(0xFFEF4444),
              inactiveColor: const Color(0xFF22C55E),
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Aperturas sala',
              value: _formatInt(data.contadorAperturasSala),
            ),
            const SizedBox(height: 4),
            _StatusRow(
              label: 'Puerta Munter',
              active: data.munterAbierto,
              activeLabel: 'Abierto',
              inactiveLabel: 'Cerrado',
              activeColor: const Color(0xFFEF4444),
              inactiveColor: const Color(0xFF22C55E),
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Aperturas munter',
              value: _formatInt(data.contadorAperturasMunter),
            ),
          ],
        ),
      ),
      _Section(
        title: 'FUNCIONAMIENTO',
        showSnapshotPulse: widget.showSnapshotPulse,
        child: Column(
          children: [
            _StateRow(label: 'Estado equipo', diagnostics: data.diagnostics),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Cantidad apagadas',
              value: _formatInt(data.cantidadApagadasMunter),
            ),
            const SizedBox(height: 8),
            _TechnicalDataGroup(
              expanded: _technicalDataExpanded,
              onToggle: () =>
                  _setTechnicalDataExpanded(!_technicalDataExpanded),
              child: Column(
                children: [
                  _ValueRow(
                    label: 'Latency PLC',
                    value: _formatInt(data.plcLatencyMs),
                    unit: 'ms',
                    valueFontWeight: FontWeight.w400,
                  ),
                  const SizedBox(height: 4),
                  _ValueRow(
                    label: 'Latency ER605',
                    value: _formatInt(data.routerLatencyMs),
                    unit: 'ms',
                    valueFontWeight: FontWeight.w400,
                  ),
                  const SizedBox(height: 4),
                  _ValueRow(
                    label: 'Heart Beat',
                    value: _formatRawValue(data.lastHeartbeatValue),
                    valueFontWeight: FontWeight.w400,
                  ),
                  const SizedBox(height: 4),
                  _StatusRow(
                    label: 'Backend',
                    active: data.backendOnline,
                    activeLabel: 'on-line',
                    inactiveLabel: 'off-line',
                    activeColor: const Color(0xFF22C55E),
                    inactiveColor: const Color(0xFFEF4444),
                    valueFontWeight: FontWeight.w400,
                  ),
                  const SizedBox(height: 4),
                  _ValueRow(
                    label: 'Uptime',
                    value: _formatUptime(data.backendStartedAt),
                    valueFontWeight: FontWeight.w400,
                  ),
                  const SizedBox(height: 4),
                  _ValueRow(
                    label: 'Last update -1',
                    value: _formatPreviousLastUpdated(
                      data.previousLastUpdatedAt,
                    ),
                    valueFontWeight: FontWeight.w400,
                  ),
                  const SizedBox(height: 4),
                  _ValueRow(
                    label: 'Last update',
                    value: _formatLastUpdated(
                      data.lastUpdatedAt,
                      data.previousLastUpdatedAt,
                    ),
                    valueFontWeight: FontWeight.w400,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _Section(
        title: 'HORIMETROS',
        child: Column(
          children: [
            _ValueRow(
              label: 'Horas munter',
              value: _formatInt(data.horasMunter),
              unit: 'h',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Horas filtro F9',
              value: _formatInt(data.horasFiltroF9),
              unit: 'h',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Horas filtro G4',
              value: _formatInt(data.horasFiltroG4),
              unit: 'h',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Horas polifosfato',
              value: _formatInt(data.horasPolifosfato),
              unit: 'h',
            ),
          ],
        ),
      ),
    ];
  }
}

class _SectionsLayout extends StatelessWidget {
  const _SectionsLayout({required this.sections, required this.singleColumn});

  final List<Widget> sections;
  final bool singleColumn;

  @override
  Widget build(BuildContext context) {
    if (singleColumn) {
      return Column(children: _withSpacing(sections, 8));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(children: _withSpacing(sections.take(4).toList(), 8)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(children: _withSpacing(sections.skip(4).toList(), 8)),
        ),
      ],
    );
  }
}

List<Widget> _withSpacing(List<Widget> children, double spacing) {
  if (children.isEmpty) {
    return const [];
  }

  final List<Widget> spaced = <Widget>[];
  for (var index = 0; index < children.length; index++) {
    if (index > 0) {
      spaced.add(SizedBox(height: spacing));
    }
    spaced.add(children[index]);
  }
  return spaced;
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFE5E7EB),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.showSnapshotPulse = false,
  });

  final String title;
  final Widget child;
  final bool showSnapshotPulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (showSnapshotPulse) ...[
                const SizedBox(width: 8),
                const _SectionPulseDot(),
              ],
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _SectionPulseDot extends StatelessWidget {
  const _SectionPulseDot();

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 180),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF22C55E),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x9922C55E), blurRadius: 8, spreadRadius: 1),
          ],
        ),
      ),
    );
  }
}

class _TechnicalDataGroup extends StatelessWidget {
  const _TechnicalDataGroup({
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF162133),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF223046)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Technical data',
                      style: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.expand_more,
                      color: Color(0xFF94A3B8),
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              heightFactor: expanded ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.unit,
    this.valueFontWeight = FontWeight.w600,
  });

  final String label;
  final String value;
  final String? unit;
  final FontWeight valueFontWeight;

  @override
  Widget build(BuildContext context) {
    final bool missingValue = value == 'Sin datos';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: _rowDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: missingValue
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFFE5E7EB),
              fontSize: 16,
              fontWeight: missingValue ? FontWeight.w400 : valueFontWeight,
            ),
          ),
          if (unit != null) ...[
            const SizedBox(width: 4),
            Text(
              unit!,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.active,
    required this.activeLabel,
    required this.inactiveLabel,
    this.activeColor = const Color(0xFF22C55E),
    this.inactiveColor = const Color(0xFF94A3B8),
    this.valueFontWeight = FontWeight.w600,
  });

  final String label;
  final bool? active;
  final String activeLabel;
  final String inactiveLabel;
  final Color activeColor;
  final Color inactiveColor;
  final FontWeight valueFontWeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: _rowDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
          ),
          StatusDot(active: active),
          const SizedBox(width: 8),
          Text(
            active == null
                ? 'No disponible'
                : (active! ? activeLabel : inactiveLabel),
            style: TextStyle(
              color: active == null
                  ? const Color(0xFF94A3B8)
                  : (active! ? activeColor : inactiveColor),
              fontSize: 16,
              fontWeight: valueFontWeight,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.label, required this.diagnostics});

  final String label;
  final PlcUnitDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    final PlcUnitDiagnostics? currentDiagnostics = diagnostics;
    final String resolvedState = currentDiagnostics?.stateLabel ?? 'Sin datos';
    final String? resolvedReason = currentDiagnostics?.stateReason;
    final Color color = switch (currentDiagnostics?.stateCode) {
      PlcUnitDiagnostics.plcNotConfigured => const Color(0xFFFACC15),
      PlcUnitDiagnostics.plcUnreachable => const Color(0xFFEF4444),
      PlcUnitDiagnostics.plcReachableNoValidData => const Color(0xFFF59E0B),
      PlcUnitDiagnostics.plcHealthy => const Color(0xFF22C55E),
      PlcUnitDiagnostics.backendDown => const Color(0xFFCBD5E1),
      _ => const Color(0xFF94A3B8),
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: _rowDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                resolvedState,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (resolvedReason != null && resolvedReason.isNotEmpty)
                Text(
                  resolvedReason,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final double? currentValue = value;
    final int? percent = currentValue == null
        ? null
        : (currentValue * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: _rowDecoration(),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
          ),
          Expanded(
            child: currentValue == null
                ? const Text(
                    'Sin datos',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: currentValue,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF334155),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF38BDF8),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: Text(
              percent == null ? 'Sin datos' : '$percent%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: percent == null
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFFE5E7EB),
                fontSize: 14,
                fontWeight: percent == null ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactFanRow extends StatelessWidget {
  const _CompactFanRow({required this.fans});

  final List<(String, bool?)> fans;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: _rowDecoration(),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: fans
            .map(
              (fan) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fan.$1,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusDot(active: fan.$2, size: 10),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

String _formatDecimal(double? value, int fractionDigits) {
  if (value == null) {
    return 'Sin datos';
  }

  return value.toStringAsFixed(fractionDigits);
}

String _formatInt(int? value) {
  if (value == null) {
    return 'Sin datos';
  }

  return value.toString();
}

String _formatRawValue(Object? value) {
  if (value == null) {
    return 'Sin datos';
  }
  return value.toString();
}

String _formatLastUpdated(DateTime? value, DateTime? previousValue) {
  if (value == null) {
    return 'Sin datos';
  }

  final DateTime local = value.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  final String ss = local.second.toString().padLeft(2, '0');
  final String base = '$hh:$mm:$ss';
  if (previousValue == null) {
    return base;
  }

  final int deltaSeconds = value.difference(previousValue).inSeconds.abs();
  return '$base (${deltaSeconds}s)';
}

String _formatPreviousLastUpdated(DateTime? value) {
  if (value == null) {
    return '0';
  }

  final DateTime local = value.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  final String ss = local.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

String _formatUptime(DateTime? startedAt) {
  if (startedAt == null) {
    return '00:00:00';
  }

  final int totalSeconds = DateTime.now()
      .difference(startedAt.toLocal())
      .inSeconds;
  if (totalSeconds < 0) {
    return '00:00:00';
  }

  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String hh = hours.toString().padLeft(2, '0');
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = seconds.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

double? _normalizeVoltageToPercent(double? voltage) {
  if (voltage == null) {
    return null;
  }
  // Backend exposes the raw analog output scaled by 100.
  // Example: 450 => 4.50 V, so 100% = 10.00 V.
  return (voltage / 1000).clamp(0.0, 1.0);
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: const Color(0xFF1E293B),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: const Color(0xFF334155)),
  );
}

BoxDecoration _rowDecoration() {
  return BoxDecoration(
    color: const Color(0xFF162133),
    borderRadius: BorderRadius.circular(6),
  );
}
