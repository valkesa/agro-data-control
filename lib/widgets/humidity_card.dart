import 'package:flutter/material.dart';

class HumidityCard extends StatelessWidget {
  const HumidityCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
  });

  final String title;
  final double value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final Color accent = value >= 65
        ? const Color(0xFFFACC15)
        : const Color(0xFF38BDF8);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_drop_outlined, color: accent),
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
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(bottom: 5),
                  child: Text(
                    '%',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle ?? 'Humedad relativa simulada',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
