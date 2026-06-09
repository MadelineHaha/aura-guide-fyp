import 'dart:math' as math;

import 'package:flutter/material.dart';

/// AR-style floor path arrows that rotate toward the navigation bearing.
class ArPathOverlay extends StatelessWidget {
  const ArPathOverlay({
    super.key,
    required this.turnDeltaDegrees,
    required this.guidanceHint,
    this.pulse = 0,
  });

  final double turnDeltaDegrees;
  final String guidanceHint;
  final double pulse;

  static const Color _arrowColor = Color(0xFF63F7F2);
  static const Color _glowColor = Color(0xAA63F7F2);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _ArPathPainter(
              turnDeltaDegrees: turnDeltaDegrees,
              pulse: pulse,
              arrowColor: _arrowColor,
              glowColor: _glowColor,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 120,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _arrowColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  guidanceHint,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArPathPainter extends CustomPainter {
  _ArPathPainter({
    required this.turnDeltaDegrees,
    required this.pulse,
    required this.arrowColor,
    required this.glowColor,
  });

  final double turnDeltaDegrees;
  final double pulse;
  final Color arrowColor;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width * 0.5;
    final baseY = size.height * 0.82;
    final rotation = turnDeltaDegrees * math.pi / 180;
    final sway = math.sin(pulse * math.pi * 2) * 6;

    canvas.save();
    canvas.translate(centerX + sway, baseY);
    canvas.rotate(rotation);

    for (var i = 0; i < 5; i++) {
      final depth = i / 4;
      final scale = 1.15 - depth * 0.55;
      final y = -depth * size.height * 0.16;
      final opacity = (0.95 - depth * 0.45).clamp(0.35, 1.0);

      _drawChevron(
        canvas,
        Offset(0, y),
        scale,
        opacity,
      );
    }

    _drawFeatureDots(canvas, size);
    canvas.restore();
  }

  void _drawChevron(
    Canvas canvas,
    Offset center,
    double scale,
    double opacity,
  ) {
    final width = 92 * scale;
    final height = 54 * scale;

    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: opacity * 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    final fillPaint = Paint()
      ..color = arrowColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(center.dx, center.dy - height * 0.5)
      ..lineTo(center.dx + width * 0.5, center.dy + height * 0.15)
      ..lineTo(center.dx + width * 0.18, center.dy + height * 0.15)
      ..lineTo(center.dx + width * 0.18, center.dy + height * 0.5)
      ..lineTo(center.dx - width * 0.18, center.dy + height * 0.5)
      ..lineTo(center.dx - width * 0.18, center.dy + height * 0.15)
      ..lineTo(center.dx - width * 0.5, center.dy + height * 0.15)
      ..close();

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, fillPaint);
  }

  void _drawFeatureDots(Canvas canvas, Size size) {
    final random = math.Random(7);
    final paint = Paint()..color = const Color(0xFFFFD54F).withValues(alpha: 0.85);
    for (var i = 0; i < 28; i++) {
      final x = (random.nextDouble() - 0.5) * size.width * 0.9;
      final y = -random.nextDouble() * size.height * 0.55;
      final radius = 1.2 + random.nextDouble() * 2.2;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArPathPainter oldDelegate) {
    return oldDelegate.turnDeltaDegrees != turnDeltaDegrees ||
        oldDelegate.pulse != pulse;
  }
}
