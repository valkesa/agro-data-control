import 'package:flutter/material.dart';

import '../models/munters_model.dart';
import 'status_indicator.dart';

class MuntersPanel extends StatelessWidget {
  const MuntersPanel({super.key, required this.unit});

  final MuntersModel unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unit.name,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Vista experimental comparativa',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
          const SizedBox(height: 8),
          _CompactSection(
            title: 'AMBIENTE',
            child: Column(
              children: [
                _MetricRow(
                  label: 'Temp. interior',
                  value: _formatDecimal(unit.tempInterior, 1),
                  unit: '°C',
                ),
                const SizedBox(height: 4),
                _MetricRow(
                  label: 'Humedad interior',
                  value: _formatDecimal(unit.humInterior, 0),
                  unit: '%',
                ),
                const SizedBox(height: 4),
                _MetricRow(
                  label: 'Temp. exterior',
                  value: _formatDecimal(unit.tempExterior, 0),
                  unit: '°C',
                ),
                const SizedBox(height: 4),
                _MetricRow(
                  label: 'Humedad exterior',
                  value: _formatDecimal(unit.humExterior, 0),
                  unit: '%',
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _CompactSection(
            title: 'VENTILACION',
            child: Column(
              children: [
                _FanLine(
                  label: 'Fans',
                  value: null,
                  fans: [
                    ('Q5', unit.fanQ5),
                    ('Q6', unit.fanQ6),
                    ('Q7', unit.fanQ7),
                    ('Q8', unit.fanQ8),
                    ('Q9', unit.fanQ9),
                    ('Q10', unit.fanQ10),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _CompactSection(
            title: 'HUMIDIFICACION',
            child: Column(
              children: [
                _StatusRow(
                  label: 'Bomba humidificador',
                  active: unit.bombaHumidificador,
                  activeLabel: 'ENCENDIDA',
                  inactiveLabel: 'APAGADA',
                ),
                const SizedBox(height: 4),
                _MetricRow(
                  label: 'Contador sin agua',
                  value: _formatInt(unit.contadorSinAgua),
                ),
                const SizedBox(height: 4),
                _AlarmRow(label: 'Nivel de agua', active: unit.nivelAguaAlarma),
                const SizedBox(height: 4),
                _AlarmRow(
                  label: 'Falla termica bomba',
                  active: unit.fallaTermicaBomba,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _CompactSection(
            title: 'CALEFACCION',
            child: Column(
              children: [
                _StatusRow(
                  label: 'Resistencia etapa 1',
                  active: unit.resistencia1,
                  activeLabel: 'ENCENDIDA',
                  inactiveLabel: 'APAGADA',
                ),
                const SizedBox(height: 4),
                _StatusRow(
                  label: 'Resistencia etapa 2',
                  active: unit.resistencia2,
                  activeLabel: 'ENCENDIDA',
                  inactiveLabel: 'APAGADA',
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _CompactSection(
            title: 'ALARMAS',
            child: Column(
              children: [
                _AlarmRow(
                  label: 'Salida alarmas (Q12)',
                  active: unit.alarmaGeneral,
                ),
                const SizedBox(height: 4),
                _AlarmRow(label: 'Falla red electrica', active: unit.fallaRed),
              ],
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF162133),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final bool missingValue = value == 'Sin datos';
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: missingValue
                ? const Color(0xFF94A3B8)
                : const Color(0xFFE5E7EB),
            fontSize: 13,
            fontWeight: missingValue ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: 3),
          Text(
            unit!,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
          ),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.active,
    required this.activeLabel,
    required this.inactiveLabel,
  });

  final String label;
  final bool? active;
  final String activeLabel;
  final String inactiveLabel;

  @override
  Widget build(BuildContext context) {
    final bool missingValue = active == null;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
          ),
        ),
        StatusDot(active: active, size: 10),
        const SizedBox(width: 6),
        Text(
          missingValue ? 'Sin datos' : (active! ? activeLabel : inactiveLabel),
          style: TextStyle(
            color: missingValue
                ? const Color(0xFF94A3B8)
                : (active! ? const Color(0xFF22C55E) : const Color(0xFF94A3B8)),
            fontSize: 12,
            fontWeight: missingValue ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AlarmRow extends StatelessWidget {
  const _AlarmRow({required this.label, required this.active});

  final String label;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: active == null
                  ? const Color(0xFF94A3B8)
                  : (active!
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF22C55E)),
              fontSize: 11,
              fontWeight: active == true ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        StatusDot(active: active, isAlarm: true, size: 10),
      ],
    );
  }
}

class _FanLine extends StatelessWidget {
  const _FanLine({
    required this.label,
    required this.value,
    required this.fans,
  });

  final String label;
  final double? value;
  final List<(String, bool?)> fans;

  @override
  Widget build(BuildContext context) {
    final double? currentValue = value;
    final int? percent = currentValue == null
        ? null
        : (currentValue * 100).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool compact = constraints.maxWidth < 320;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(child: _Bar(value: currentValue)),
                  const SizedBox(width: 6),
                  Text(
                    percent == null ? '--' : '$percent%',
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: fans
                    .map((fan) => _FanDot(label: fan.$1, active: fan.$2))
                    .toList(),
              ),
            ],
          );
        }

        return Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
              ),
            ),
            Expanded(child: _Bar(value: currentValue)),
            const SizedBox(width: 6),
            SizedBox(
              width: 36,
              child: Text(
                percent == null ? '--' : '$percent%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: fans
                    .map((fan) => _FanDot(label: fan.$1, active: fan.$2))
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FanDot extends StatelessWidget {
  const _FanDot({required this.label, required this.active});

  final String label;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
        ),
        const SizedBox(width: 3),
        StatusDot(active: active, size: 10),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const Text(
        'Sin datos',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 7,
        backgroundColor: const Color(0xFF334155),
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF22C55E)),
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
