import 'dart:ui';

/// Normalized bounding box (0–1) relative to the camera image used for inference.
class ObstacleBounds {
  const ObstacleBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.frameWidth,
    this.frameHeight,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final int? frameWidth;
  final int? frameHeight;

  Map<String, dynamic> toMap() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
        if (frameWidth != null) 'frameWidth': frameWidth,
        if (frameHeight != null) 'frameHeight': frameHeight,
      };

  factory ObstacleBounds.fromMap(Map<String, dynamic> map) {
    return ObstacleBounds(
      left: (map['left'] as num?)?.toDouble() ?? 0,
      top: (map['top'] as num?)?.toDouble() ?? 0,
      width: (map['width'] as num?)?.toDouble() ?? 0,
      height: (map['height'] as num?)?.toDouble() ?? 0,
      frameWidth: map['frameWidth'] as int?,
      frameHeight: map['frameHeight'] as int?,
    );
  }

  /// Maps image-space bounds onto the camera preview widget.
  Rect toViewRect({
    required Size viewSize,
    required Size? previewSize,
    required bool rotateForPortrait,
  }) {
    var left = this.left;
    var top = this.top;
    var width = this.width;
    var height = this.height;

    if (rotateForPortrait) {
      final rotatedLeft = top;
      final rotatedTop = 1.0 - left - width;
      final rotatedWidth = height;
      final rotatedHeight = width;
      left = rotatedLeft;
      top = rotatedTop;
      width = rotatedWidth;
      height = rotatedHeight;
    }

    final imageW = frameWidth?.toDouble() ??
        (rotateForPortrait ? previewSize?.height : previewSize?.width) ??
        viewSize.width;
    final imageH = frameHeight?.toDouble() ??
        (rotateForPortrait ? previewSize?.width : previewSize?.height) ??
        viewSize.height;
    final imageAspect = imageW / imageH;
    final viewAspect = viewSize.width / viewSize.height;

    late final double displayedW;
    late final double displayedH;
    late final double offsetX;
    late final double offsetY;

    if (viewAspect > imageAspect) {
      displayedW = viewSize.width;
      displayedH = viewSize.width / imageAspect;
      offsetX = 0;
      offsetY = (viewSize.height - displayedH) / 2;
    } else {
      displayedH = viewSize.height;
      displayedW = viewSize.height * imageAspect;
      offsetX = (viewSize.width - displayedW) / 2;
      offsetY = 0;
    }

    return Rect.fromLTWH(
      offsetX + left * displayedW,
      offsetY + top * displayedH,
      width * displayedW,
      height * displayedH,
    );
  }
}
