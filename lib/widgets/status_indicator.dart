import 'package:flutter/material.dart';

class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.active,
    this.isAlarm = false,
    this.size = 12,
  });

  final bool? active;
  final bool isAlarm;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool? value = active;
    final Color color = value == null
        ? const Color(0xFF64748B)
        : isAlarm
        ? (value ? const Color(0xFFEF4444) : const Color(0xFF94A3B8))
        : (value ? const Color(0xFF22C55E) : const Color(0xFF94A3B8));

    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Text(
          value == null ? '–' : (value ? '●' : '○'),
          style: TextStyle(
            color: color,
            fontSize: size,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.active,
    this.isAlarm = false,
    this.size = 12,
  });

  final bool? active;
  final bool isAlarm;
  final double size;

  @override
  Widget build(BuildContext context) {
    return StatusDot(active: active, isAlarm: isAlarm, size: size);
  }
}
