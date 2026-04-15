import 'package:flutter/material.dart';

import '../models/munters_model.dart';
import '../models/water_shortage_summary.dart';
import '../widgets/status_indicator.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.units,
    required this.selectedUnitName,
    this.waterShortageSummaries = const {},
  });

  final List<MuntersModel> units;
  final String selectedUnitName;
  final Map<String, WaterShortageSummary> waterShortageSummaries;

  @override
  Widget build(BuildContext context) {
    final MuntersModel unit = units.firstWhere(
      (item) => item.name == selectedUnitName,
      orElse: () => units.first,
    );
    final WaterShortageSummary? waterShortageSummary =
        waterShortageSummaries[unit.historyPlcId];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool narrow = constraints.maxWidth < 760;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: _panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PanelHeading(
                title: 'Tablero General',
                subtitle: 'Panel compacto de supervision',
              ),
              const SizedBox(height: 8),
              _CompactSection(
                title: 'AMBIENTE',
                child: _EnvironmentSection(unit: unit),
              ),
              const SizedBox(height: 8),
              _CompactSection(
                title: 'VENTILACION',
                child: _VentilationSection(unit: unit),
              ),
              const SizedBox(height: 8),
              if (narrow) ...[
                _CompactSection(
                  title: 'HUMIDIFICACION',
                  child: _HumidificationSection(
                    unit: unit,
                    waterShortageSummary: waterShortageSummary,
                  ),
                ),
                const SizedBox(height: 8),
                _CompactSection(
                  title: 'CALEFACCION',
                  child: _HeatingSection(unit: unit),
                ),
                const SizedBox(height: 8),
                _CompactSection(
                  title: 'ALARMAS',
                  child: _AlarmsSection(unit: unit),
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CompactSection(
                        title: 'HUMIDIFICACION',
                        child: _HumidificationSection(
                          unit: unit,
                          waterShortageSummary: waterShortageSummary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CompactSection(
                            title: 'CALEFACCION',
                            child: _HeatingSection(unit: unit),
                          ),
                          const SizedBox(height: 8),
                          _CompactSection(
                            title: 'ALARMAS',
                            child: _AlarmsSection(unit: unit),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EnvironmentSection extends StatelessWidget {
  const _EnvironmentSection({required this.unit});

  final MuntersModel unit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool singleColumn = constraints.maxWidth < 520;

        if (singleColumn) {
          return Column(
            children: [
              _ValueRow(
                label: 'Temp. Interior',
                value: _formatDecimal(unit.tempInterior, 1),
                unit: '°C',
              ),
              _ValueRow(
                label: 'Hum. Interior',
                value: _formatDecimal(unit.humInterior, 0),
                unit: '%',
              ),
              _ValueRow(
                label: 'Temp. Exterior',
                value: _formatDecimal(unit.tempExterior, 0),
                unit: '°C',
              ),
              _ValueRow(
                label: 'Hum. Exterior',
                value: _formatDecimal(unit.humExterior, 0),
                unit: '%',
              ),
              _ValueRow(
                label: 'Presion diferencial',
                value: _formatDecimal(unit.presionDiferencial, 0),
                unit: 'Pa',
              ),
              _ValueRow(
                label: 'NH3',
                value: _formatDecimal(unit.nh3, 0),
                unit: 'ppm',
              ),
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ValueRow(
                    label: 'Temp. Interior',
                    value: _formatDecimal(unit.tempInterior, 1),
                    unit: '°C',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ValueRow(
                    label: 'Hum. Interior',
                    value: _formatDecimal(unit.humInterior, 0),
                    unit: '%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _ValueRow(
                    label: 'Temp. Exterior',
                    value: _formatDecimal(unit.tempExterior, 0),
                    unit: '°C',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ValueRow(
                    label: 'Hum. Exterior',
                    value: _formatDecimal(unit.humExterior, 0),
                    unit: '%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'Presion diferencial',
              value: _formatDecimal(unit.presionDiferencial, 0),
              unit: 'Pa',
            ),
            const SizedBox(height: 4),
            _ValueRow(
              label: 'NH3',
              value: _formatDecimal(unit.nh3, 0),
              unit: 'ppm',
            ),
          ],
        );
      },
    );
  }
}

class _VentilationSection extends StatelessWidget {
  const _VentilationSection({required this.unit});

  final MuntersModel unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FanStatusRow(
          fans: [('Q5', unit.fanQ5), ('Q6', unit.fanQ6), ('Q7', unit.fanQ7)],
        ),
        const SizedBox(height: 6),
        _ProgressRow(
          label: 'Potencia',
          value: _normalizeVoltageToPercent(unit.tensionSalidaVentiladores),
        ),
        const SizedBox(height: 6),
        _FanStatusRow(
          fans: [('Q8', unit.fanQ8), ('Q9', unit.fanQ9), ('Q10', unit.fanQ10)],
        ),
      ],
    );
  }
}

class _HumidificationSection extends StatelessWidget {
  const _HumidificationSection({
    required this.unit,
    this.waterShortageSummary,
  });

  final MuntersModel unit;
  final WaterShortageSummary? waterShortageSummary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusTextRow(
          label: 'Bomba humidificador',
          active: unit.bombaHumidificador,
          activeLabel: 'ENCENDIDA',
          inactiveLabel: 'APAGADA',
        ),
        const SizedBox(height: 4),
        _StatusTextRow(
          label: 'Nivel de agua',
          active: unit.nivelAguaAlarma,
          activeLabel: 'FALLA',
          inactiveLabel: 'NORMAL',
          activeColor: const Color(0xFFEF4444),
          inactiveColor: const Color(0xFF22C55E),
        ),
        const SizedBox(height: 4),
        _StatusTextRow(
          label: 'Falla termica bomba',
          active: unit.fallaTermicaBomba,
          activeLabel: 'ALARMA',
          inactiveLabel: 'NORMAL',
          activeColor: const Color(0xFFEF4444),
          inactiveColor: const Color(0xFF22C55E),
        ),
        const SizedBox(height: 4),
        _ValueRow(
          label: 'Eventos sin agua Total',
          value: _formatInt(waterShortageSummary?.totalEvents),
        ),
        const SizedBox(height: 4),
        _ValueRow(
          label: 'Eventos sin agua Mes',
          value: _formatInt(waterShortageSummary?.monthEvents),
        ),
      ],
    );
  }
}

class _HeatingSection extends StatelessWidget {
  const _HeatingSection({required this.unit});

  final MuntersModel unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusTextRow(
          label: 'Resistencia etapa 1',
          active: unit.resistencia1,
          activeLabel: 'ENCENDIDA',
          inactiveLabel: 'APAGADA',
        ),
        const SizedBox(height: 4),
        _StatusTextRow(
          label: 'Resistencia etapa 2',
          active: unit.resistencia2,
          activeLabel: 'ENCENDIDA',
          inactiveLabel: 'APAGADA',
        ),
      ],
    );
  }
}

class _AlarmsSection extends StatelessWidget {
  const _AlarmsSection({required this.unit});

  final MuntersModel unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AlarmTextRow(
          label: 'Salida alarmas (Q12)',
          active: unit.alarmaGeneral,
        ),
        const SizedBox(height: 4),
        _AlarmTextRow(label: 'Falla red electrica', active: unit.fallaRed),
      ],
    );
  }
}

class _CompactSection extends StatelessWidget {
  const _CompactSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
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
          ),
        ),
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

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
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontSize: 16,
              fontWeight: FontWeight.w600,
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

class _StatusTextRow extends StatelessWidget {
  const _StatusTextRow({
    required this.label,
    required this.active,
    required this.activeLabel,
    required this.inactiveLabel,
    this.activeColor = const Color(0xFF22C55E),
    this.inactiveColor = const Color(0xFF94A3B8),
  });

  final String label;
  final bool? active;
  final String activeLabel;
  final String inactiveLabel;
  final Color activeColor;
  final Color inactiveColor;

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
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlarmTextRow extends StatelessWidget {
  const _AlarmTextRow({required this.label, required this.active});

  final String label;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final Color color = active == null
        ? const Color(0xFF94A3B8)
        : (active! ? const Color(0xFFEF4444) : const Color(0xFF22C55E));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: _rowDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: active == true ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          StatusDot(active: active, isAlarm: true),
          const SizedBox(width: 8),
          Text(
            active == null ? 'No disponible' : (active! ? 'ACTIVA' : 'NORMAL'),
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
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
            width: 88,
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percent! >= 70
                            ? const Color(0xFF38BDF8)
                            : const Color(0xFF22C55E),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 124,
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

class _FanStatusRow extends StatelessWidget {
  const _FanStatusRow({required this.fans});

  final List<(String, bool?)> fans;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: _rowDecoration(),
      child: Wrap(
        spacing: 18,
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
