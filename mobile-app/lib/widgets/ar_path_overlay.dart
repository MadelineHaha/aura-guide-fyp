import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// AR-style direction arrows anchored on the floor plane, rotated toward navigation bearing.
class ArPathOverlay extends StatelessWidget {
  const ArPathOverlay({
    super.key,
    required this.turnDeltaDegrees,
    this.pulse = 0,
    this.bottomInset = 112,
  });

  final double turnDeltaDegrees;
  final double pulse;

  /// Space reserved at the bottom for the scanning bar and safe area.
  final double bottomInset;

  static const Color _arrowColor = Color(0xFF63F7F2);
  static const Color _glowColor = Color(0xAA63F7F2);

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final reservedBottom = safeBottom + bottomInset;

    return IgnorePointer(
      child: CustomPaint(
        painter: _ArPathPainter(
          turnDeltaDegrees: turnDeltaDegrees,
          pulse: pulse,
          arrowColor: _arrowColor,
          glowColor: _glowColor,
          bottomInset: reservedBottom,
        ),
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
    final baseScale = math.min(size.width, size.height) / 360;
    final anchorX = size.width * 0.5;
    final anchorY = size.height - bottomInset + 6 * baseScale;
    final rotation = turnDeltaDegrees * math.pi / 180;
    final sway = math.sin(pulse * math.pi * 2) * 2 * baseScale;

    _drawFloorAnchor(canvas, Offset(anchorX, anchorY), baseScale);

    canvas.save();
    canvas.translate(anchorX + sway, anchorY);
    canvas.rotate(rotation);

    const chevronCount = 4;
    for (var i = 0; i < chevronCount; i++) {
      final depth = i / (chevronCount - 1);
      final scale = (1.0 - depth * 0.62) * baseScale;
      final y = -depth * size.height * 0.24;
      final opacity = (1.0 - depth * 0.45).clamp(0.35, 1.0);
      _drawFloorChevron(canvas, Offset(0, y), scale, opacity);
    }

    canvas.restore();
  }

  void _drawFloorAnchor(Canvas canvas, Offset center, double baseScale) {
    final rect = Rect.fromCenter(
      center: center,
      width: 220 * baseScale,
      height: 36 * baseScale,
    );

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        rect.width * 0.5,
        [
          arrowColor.withValues(alpha: 0.22),
          arrowColor.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        [0.0, 0.55, 1.0],
      );

    canvas.drawOval(rect, paint);

    final ringPaint = Paint()
      ..color = arrowColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * baseScale;
    canvas.drawOval(rect, ringPaint);
  }

  void _drawFloorChevron(
    Canvas canvas,
    Offset center,
    double scale,
    double opacity,
  ) {
    final width = 210 * scale;
    final height = 72 * scale;
    final frontNarrow = 0.68;

    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: opacity * 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * scale);

    final fillPaint = Paint()
      ..color = arrowColor.withValues(alpha: opacity * 0.92)
      ..style = PaintingStyle.fill;

    final edgePaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale;

    final path = Path()
      ..moveTo(center.dx, center.dy - height * 0.52)
      ..lineTo(center.dx + width * 0.5 * frontNarrow, center.dy + height * 0.18)
      ..lineTo(center.dx + width * 0.2, center.dy + height * 0.18)
      ..lineTo(center.dx + width * 0.2, center.dy + height * 0.5)
      ..lineTo(center.dx - width * 0.2, center.dy + height * 0.5)
      ..lineTo(center.dx - width * 0.2, center.dy + height * 0.18)
      ..lineTo(center.dx - width * 0.5 * frontNarrow, center.dy + height * 0.18)
      ..close();

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, edgePaint);
  }

  @override
  bool shouldRepaint(covariant _ArPathPainter oldDelegate) {
    return oldDelegate.turnDeltaDegrees != turnDeltaDegrees ||
        oldDelegate.pulse != pulse ||
        oldDelegate.bottomInset != bottomInset;
  }
}
