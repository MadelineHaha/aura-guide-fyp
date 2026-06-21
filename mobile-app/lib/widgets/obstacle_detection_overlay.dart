import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/obstacle_scanner_service.dart';

/// Draws a hollow labeled border around the detected obstacle on the camera preview.
class ObstacleDetectionOverlay extends StatelessWidget {
  const ObstacleDetectionOverlay({
    super.key,
    required this.alert,
    required this.controller,
    required this.labelText,
  });

  final ObstacleAlert alert;
  final CameraController controller;
  final String labelText;

  static const Color _accent = Color(0xFF63F7F2);

  @override
  Widget build(BuildContext context) {
    final bounds = alert.bounds;
    if (bounds == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final previewSize = controller.value.previewSize;
        final rotateForPortrait = _shouldRotateForPortrait(
          previewSize: previewSize,
          viewSize: viewSize,
          frameWidth: bounds.frameWidth,
          frameHeight: bounds.frameHeight,
        );
        final rect = bounds.toViewRect(
          viewSize: viewSize,
          previewSize: previewSize,
          rotateForPortrait: rotateForPortrait,
        );

        if (rect.width < 8 || rect.height < 8) {
          return const SizedBox.shrink();
        }

        final labelTop = rect.top > 34 ? rect.top - 22 : rect.bottom + 4;
        final labelWidth = math.min(
          math.max(rect.width + 12, 96.0),
          viewSize.width * 0.72,
        ).toDouble();
        final labelLeft = (rect.center.dx - labelWidth / 2)
            .clamp(8.0, viewSize.width - labelWidth - 8);

        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: rect,
                child: CustomPaint(
                  painter: _HollowBoxPainter(
                    color: _accent,
                    strokeWidth: 2,
                  ),
                ),
              ),
              Positioned(
                left: labelLeft,
                width: labelWidth,
                top: labelTop.clamp(0, viewSize.height - 36),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Text(
                      labelText,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                        height: 1.2,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _shouldRotateForPortrait({
    required Size? previewSize,
    required Size viewSize,
    int? frameWidth,
    int? frameHeight,
  }) {
    final imageW = frameWidth?.toDouble() ?? previewSize?.width;
    final imageH = frameHeight?.toDouble() ?? previewSize?.height;
    if (imageW == null || imageH == null) return false;
    final imageLandscape = imageW > imageH;
    final viewPortrait = viewSize.height >= viewSize.width;
    return imageLandscape && viewPortrait;
  }
}

class _HollowBoxPainter extends CustomPainter {
  const _HollowBoxPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HollowBoxPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
