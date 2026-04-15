import 'package:flutter/material.dart';

class FanSpeedCard extends StatelessWidget {
  const FanSpeedCard({
    super.key,
    required this.title,
    required this.value,
    this.compact = false,
  });

  final String title;
  final double value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final int percentage = (value * 100).round();
    final Color accent = percentage >= 75
        ? const Color(0xFF0EA5E9)
        : const Color(0xFFFACC15);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: compact ? 18 : 24),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: compact ? 10 : 12,
                      value: value,
                      backgroundColor: const Color(0xFF334155),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$percentage%',
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              compact
                  ? 'Velocidad instantanea'
                  : 'Control proporcional de ventilacion',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
