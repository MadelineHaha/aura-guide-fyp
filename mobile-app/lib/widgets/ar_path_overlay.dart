import 'dart:math' as math;

import 'package:flutter/material.dart';

/// AR-style direction arrow anchored at the bottom of the screen, rotated toward navigation bearing.
class ArPathOverlay extends StatelessWidget {
  const ArPathOverlay({
    super.key,
    required this.turnDeltaDegrees,
    required this.guidanceHint,
    this.pulse = 0,
    this.bottomInset = 112,
  });

  final double turnDeltaDegrees;
  final String guidanceHint;
  final double pulse;

  /// Space reserved at the bottom for the scanning bar and safe area.
  final double bottomInset;

  static const Color _arrowColor = Color(0xFF63F7F2);
  static const Color _glowColor = Color(0xAA63F7F2);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final reservedBottom = safeBottom + bottomInset;
    final baseScale = math.min(size.width, size.height) / 300;
    final chevronHeight = 100 * 1.55 * baseScale;
    final hintBottom = reservedBottom + chevronHeight * 0.92 + 16;

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
              bottomInset: reservedBottom,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: hintBottom),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: _arrowColor.withValues(alpha: 0.55)),
                ),
                child: Text(
                  guidanceHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
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
    required this.bottomInset,
  });

  final double turnDeltaDegrees;
  final double pulse;
  final Color arrowColor;
  final Color glowColor;
  final double bottomInset;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width * 0.5;
    final baseScale = math.min(size.width, size.height) / 300;
    final primaryScale = 1.55 * baseScale;
    final chevronHeight = 100 * primaryScale;
    final centerY = size.height - bottomInset - chevronHeight * 0.42;
    final rotation = turnDeltaDegrees * math.pi / 180;
    final sway = math.sin(pulse * math.pi * 2) * 3;

    canvas.save();
    canvas.translate(centerX + sway, centerY);
    canvas.rotate(rotation);

    for (var i = 0; i < 3; i++) {
      final depth = i / 2;
      final scale = (1.55 - depth * 0.30) * baseScale;
      final y = -depth * size.height * 0.055;
      final opacity = (1.0 - depth * 0.28).clamp(0.45, 1.0);

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
    final width = 165 * scale;
    final height = 100 * scale;

    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: opacity * 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
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
    for (var i = 0; i < 18; i++) {
      final x = (random.nextDouble() - 0.5) * size.width * 0.7;
      final y = (random.nextDouble() - 0.65) * size.height * 0.22;
      final radius = 1.4 + random.nextDouble() * 2.4;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArPathPainter oldDelegate) {
    return oldDelegate.turnDeltaDegrees != turnDeltaDegrees ||
        oldDelegate.pulse != pulse;
  }
}
