import 'package:flutter/material.dart';

import 'status_indicator.dart';

class AlarmCard extends StatelessWidget {
  const AlarmCard({super.key, required this.title, required this.isAlarm});

  final String title;
  final bool isAlarm;

  @override
  Widget build(BuildContext context) {
    final Color accent = isAlarm
        ? const Color(0xFFEF4444)
        : const Color(0xFF22C55E);

    return Container(
      decoration: BoxDecoration(
        color: isAlarm ? Colors.red.shade700 : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (isAlarm ? Colors.red.shade900 : Colors.black).withValues(
              alpha: 0.24,
            ),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: isAlarm ? Colors.red.shade400 : const Color(0xFF334155),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusIndicator(active: isAlarm, isAlarm: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              isAlarm ? 'ALARMA' : 'NORMAL',
              style: TextStyle(
                color: isAlarm ? Colors.white : accent,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isAlarm ? 'Requiere revision' : 'Sin eventos activos',
              style: TextStyle(
                color: isAlarm ? Colors.white70 : const Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
