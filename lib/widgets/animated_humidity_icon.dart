import 'package:flutter/material.dart';

class AnimatedHumidityIcon extends StatefulWidget {
  const AnimatedHumidityIcon({
    super.key,
    this.baseFill = 0.5,
    this.amplitude = 0.42,
    this.size = 22,
    this.color,
    this.duration = const Duration(milliseconds: 1800),
  });

  final double baseFill;
  final double amplitude;
  final double size;
  final Color? color;
  final Duration duration;

  @override
  State<AnimatedHumidityIcon> createState() => _AnimatedHumidityIconState();
}

class _AnimatedHumidityIconState extends State<AnimatedHumidityIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant AnimatedHumidityIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _colorForFill(double fill) {
    if (widget.color != null) {
      return widget.color!;
    }
    if (fill >= 0.66) {
      return const Color(0xFF38BDF8);
    }
    if (fill >= 0.33) {
      return const Color(0xFF7DD3FC);
    }
    return const Color(0xFFD6C3A1);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double fill =
            widget.baseFill + ((_controller.value * 2 - 1) * widget.amplitude);
        final double clampedFill = fill.clamp(0.0, 1.0);
        final Color color = _colorForFill(clampedFill);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _HumidityDropPainter(fill: clampedFill, color: color),
          ),
        );
      },
    );
  }
}

class _HumidityDropPainter extends CustomPainter {
  const _HumidityDropPainter({required this.fill, required this.color});

  final double fill;
  final Color color;

  Path _dropPath(Size size) {
    final double w = size.width;
    final double h = size.height;
    return Path()
      ..moveTo(w * 0.5, h * 0.05)
      ..cubicTo(w * 0.82, h * 0.34, w * 0.94, h * 0.52, w * 0.94, h * 0.68)
      ..cubicTo(w * 0.94, h * 0.9, w * 0.75, h * 0.98, w * 0.5, h * 0.98)
      ..cubicTo(w * 0.25, h * 0.98, w * 0.06, h * 0.9, w * 0.06, h * 0.68)
      ..cubicTo(w * 0.06, h * 0.52, w * 0.18, h * 0.34, w * 0.5, h * 0.05)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Path drop = _dropPath(size);
    final Paint outlinePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.shortestSide * 0.08).clamp(1.1, 2.2)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint backgroundPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    final Paint fillPaint = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;

    canvas.drawPath(drop, backgroundPaint);

    canvas.save();
    canvas.clipPath(drop);
    final double fillTop = size.height * (1 - fill);
    canvas.drawRect(
      Rect.fromLTRB(0, fillTop, size.width, size.height),
      fillPaint,
    );
    canvas.restore();

    canvas.drawPath(drop, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _HumidityDropPainter oldDelegate) {
    return oldDelegate.fill != fill || oldDelegate.color != color;
  }
}
