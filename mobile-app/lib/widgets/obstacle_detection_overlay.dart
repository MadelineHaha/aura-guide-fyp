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

        final labelTop = rect.top > 30 ? rect.top - 26 : rect.bottom + 6;

        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: rect,
                child: CustomPaint(
                  painter: _HollowBoxPainter(
                    color: _accent,
                    strokeWidth: 3,
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                top: labelTop.clamp(0, viewSize.height - 48),
                child: Text(
                  labelText,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  softWrap: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 6),
                      Shadow(color: Colors.black, offset: Offset(0, 1)),
                    ],
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
