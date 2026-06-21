import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class _CameraToModelJob {
  const _CameraToModelJob({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.yStride,
    required this.uBytes,
    required this.vBytes,
    required this.uvStride,
    required this.uvPixelStride,
    required this.inputSize,
    required this.inputLength,
    this.luminanceOnly = false,
  });

  final int width;
  final int height;
  final Uint8List yBytes;
  final int yStride;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int uvStride;
  final int uvPixelStride;
  final int inputSize;
  final int inputLength;
  final bool luminanceOnly;
}

/// Camera YUV → letterboxed float32 model input in one isolate (fewer allocations).
Float32List _cameraToModelInputIsolate(_CameraToModelJob job) {
  final packet = ObstacleFramePacket._fromRaw(
    width: job.width,
    height: job.height,
    yBytes: job.yBytes,
    yStride: job.yStride,
    uBytes: job.uBytes,
    vBytes: job.vBytes,
    uvStride: job.uvStride,
    uvPixelStride: job.uvPixelStride,
  );
  final buffer = Float32List(job.inputLength);
  ObstacleFramePacket.fillYoloInput(
    packet,
    buffer,
    job.inputSize,
    luminanceOnly: job.luminanceOnly,
  );
  return buffer;
}

/// Lightweight copy of a camera frame for background AI inference.
class ObstacleFramePacket {
  static const maxInferenceDimension = 320;

  static ({int width, int height}) inferenceFrameSize(int srcWidth, int srcHeight) {
    if (srcWidth <= 0 || srcHeight <= 0) {
      return (width: 0, height: 0);
    }
    final longest = math.max(srcWidth, srcHeight);
    if (longest <= maxInferenceDimension) {
      return (width: srcWidth, height: srcHeight);
    }
    final scale = maxInferenceDimension / longest;
    return (
      width: math.max(1, (srcWidth * scale).round()),
      height: math.max(1, (srcHeight * scale).round()),
    );
  }

  ObstacleFramePacket({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.yStride,
    required this.uBytes,
    required this.vBytes,
    required this.uvStride,
    required this.uvPixelStride,
  });

  final int width;
  final int height;
  final Uint8List yBytes;
  final int yStride;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int uvStride;
  final int uvPixelStride;

  factory ObstacleFramePacket.fromCamera(CameraImage image) {
    final y = image.planes[0];
    final u = image.planes.length > 1 ? image.planes[1] : null;
    final v = image.planes.length > 2 ? image.planes[2] : null;
    return _fromRaw(
      width: image.width,
      height: image.height,
      yBytes: y.bytes,
      yStride: y.bytesPerRow,
      uBytes: u?.bytes,
      vBytes: v?.bytes,
      uvStride: u?.bytesPerRow ?? 0,
      uvPixelStride: u?.bytesPerPixel ?? 1,
    );
  }

  static Future<ObstacleFramePacket> fromCameraAsync(CameraImage image) {
    if (image.planes.isEmpty) {
      return Future.value(_empty());
    }

    final y = image.planes[0];
    final u = image.planes.length > 1 ? image.planes[1] : null;
    final v = image.planes.length > 2 ? image.planes[2] : null;

    // Copy happens once when the message is sent to the isolate — avoid a second
    // Uint8List.fromList on the UI thread.
    return compute(
      _fromRawIsolate,
      <dynamic>[
        image.width,
        image.height,
        y.bytes,
        y.bytesPerRow,
        u?.bytes ?? Uint8List(0),
        v?.bytes ?? Uint8List(0),
        u?.bytesPerRow ?? 0,
        u?.bytesPerPixel ?? 1,
      ],
    );
  }

  /// Downsample, RGB convert, letterbox, and normalize in a single isolate pass.
  static Future<Float32List> toModelInputAsync(
    CameraImage image, {
    required int inputSize,
    required int inputLength,
  }) {
    if (image.planes.isEmpty) {
      return Future.value(Float32List(inputLength));
    }

    final y = image.planes[0];
    final u = image.planes.length > 1 ? image.planes[1] : null;
    final v = image.planes.length > 2 ? image.planes[2] : null;

    return compute(
      _cameraToModelInputIsolate,
      _CameraToModelJob(
        width: image.width,
        height: image.height,
        yBytes: y.bytes,
        yStride: y.bytesPerRow,
        uBytes: u?.bytes ?? Uint8List(0),
        vBytes: v?.bytes ?? Uint8List(0),
        uvStride: u?.bytesPerRow ?? 0,
        uvPixelStride: u?.bytesPerPixel ?? 1,
        inputSize: inputSize,
        inputLength: inputLength,
        luminanceOnly: true,
      ),
    );
  }

  static ObstacleFramePacket _empty() {
    return ObstacleFramePacket(
      width: 0,
      height: 0,
      yBytes: Uint8List(0),
      yStride: 0,
      uBytes: Uint8List(0),
      vBytes: Uint8List(0),
      uvStride: 0,
      uvPixelStride: 1,
    );
  }

  static ObstacleFramePacket _fromRawIsolate(List<dynamic> message) {
    return _fromRaw(
      width: message[0] as int,
      height: message[1] as int,
      yBytes: message[2] as Uint8List,
      yStride: message[3] as int,
      uBytes: message[4] as Uint8List,
      vBytes: message[5] as Uint8List,
      uvStride: message[6] as int,
      uvPixelStride: message[7] as int,
    );
  }

  static ObstacleFramePacket _fromRaw({
    required int width,
    required int height,
    required Uint8List yBytes,
    required int yStride,
    Uint8List? uBytes,
    Uint8List? vBytes,
    required int uvStride,
    required int uvPixelStride,
  }) {
    const maxDimension = maxInferenceDimension;
    if (width <= 0 || height <= 0) return _empty();

    final longest = math.max(width, height);
    if (longest <= maxDimension) {
      return ObstacleFramePacket(
        width: width,
        height: height,
        yBytes: yBytes,
        yStride: yStride,
        uBytes: uBytes ?? Uint8List(0),
        vBytes: vBytes ?? Uint8List(0),
        uvStride: uvStride,
        uvPixelStride: uvPixelStride,
      );
    }

    return _downsampleRaw(
      width: width,
      height: height,
      yBytes: yBytes,
      yStride: yStride,
      uBytes: uBytes ?? Uint8List(0),
      vBytes: vBytes ?? Uint8List(0),
      uvStride: uvStride,
      uvPixelStride: uvPixelStride,
      maxDimension: maxDimension,
    );
  }

  static ObstacleFramePacket _downsampleRaw({
    required int width,
    required int height,
    required Uint8List yBytes,
    required int yStride,
    required Uint8List uBytes,
    required Uint8List vBytes,
    required int uvStride,
    required int uvPixelStride,
    required int maxDimension,
  }) {
    final srcW = width;
    final srcH = height;
    final scale = maxDimension / math.max(srcW, srcH);
    final dstW = math.max(1, (srcW * scale).round());
    final dstH = math.max(1, (srcH * scale).round());
    final xStep = srcW / dstW;
    final yStep = srcH / dstH;

    final yOut = Uint8List(dstW * dstH);
    var dst = 0;
    for (var dy = 0; dy < dstH; dy++) {
      final sy = math.min(srcH - 1, (dy * yStep).floor());
      final row = sy * yStride;
      for (var dx = 0; dx < dstW; dx++) {
        final sx = math.min(srcW - 1, (dx * xStep).floor());
        yOut[dst++] = yBytes[row + sx];
      }
    }

    Uint8List uOut = Uint8List(0);
    Uint8List vOut = Uint8List(0);
    var outUvStride = 0;
    const outUvPixelStride = 1;

    if (uBytes.isNotEmpty && vBytes.isNotEmpty) {
      final uvDstW = math.max(1, (dstW / 2).ceil());
      final uvDstH = math.max(1, (dstH / 2).ceil());
      uOut = Uint8List(uvDstW * uvDstH);
      vOut = Uint8List(uvDstW * uvDstH);
      outUvStride = uvDstW;

      var uvDst = 0;
      for (var dy = 0; dy < uvDstH; dy++) {
        final sy = math.min(math.max(0, srcH ~/ 2 - 1), (dy * yStep / 2).floor());
        final uRow = sy * uvStride;
        final vRow = sy * uvStride;
        for (var dx = 0; dx < uvDstW; dx++) {
          final sx = math.min(math.max(0, srcW ~/ 2 - 1), (dx * xStep / 2).floor());
          final uIndex = uRow + sx * uvPixelStride;
          final vIndex = vRow + sx * uvPixelStride;
          uOut[uvDst] =
              uIndex >= 0 && uIndex < uBytes.length ? uBytes[uIndex] : 128;
          vOut[uvDst] =
              vIndex >= 0 && vIndex < vBytes.length ? vBytes[vIndex] : 128;
          uvDst++;
        }
      }
    }

    return ObstacleFramePacket(
      width: dstW,
      height: dstH,
      yBytes: yOut,
      yStride: dstW,
      uBytes: uOut,
      vBytes: vOut,
      uvStride: outUvStride,
      uvPixelStride: outUvPixelStride,
    );
  }

  List<dynamic> toIsolateMessage() {
    return <dynamic>[
      width,
      height,
      yBytes,
      yStride,
      uBytes,
      vBytes,
      uvStride,
      uvPixelStride,
    ];
  }

  factory ObstacleFramePacket.fromIsolateMessage(List<dynamic> message) {
    return ObstacleFramePacket(
      width: message[0] as int,
      height: message[1] as int,
      yBytes: message[2] as Uint8List,
      yStride: message[3] as int,
      uBytes: message[4] as Uint8List,
      vBytes: message[5] as Uint8List,
      uvStride: message[6] as int,
      uvPixelStride: message[7] as int,
    );
  }

  /// YOLO letterbox: preserve aspect ratio, pad with gray 114 (training default).
  static void fillYoloInput(
    ObstacleFramePacket packet,
    Float32List buffer,
    int size, {
    bool luminanceOnly = false,
  }) {
    const padValue = 114 / 255.0;
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = padValue;
    }

    final width = packet.width;
    final height = packet.height;
    final yBytes = packet.yBytes;
    final yStride = packet.yStride;
    final uBytes = packet.uBytes;
    final vBytes = packet.vBytes;
    final uvStride = packet.uvStride;
    final uvPixelStride = packet.uvPixelStride;

    final scale = math.min(size / width, size / height);
    final scaledW = math.max(1, (width * scale).round());
    final scaledH = math.max(1, (height * scale).round());
    final padX = (size - scaledW) ~/ 2;
    final padY = (size - scaledH) ~/ 2;

    for (var dy = 0; dy < scaledH; dy++) {
      final srcY = math.min(height - 1, (dy / scale).floor());
      final yRow = srcY * yStride;
      final dstRow = padY + dy;

      for (var dx = 0; dx < scaledW; dx++) {
        final srcX = math.min(width - 1, (dx / scale).floor());
        final yIndex = yRow + srcX;
        final yVal =
            yIndex >= 0 && yIndex < yBytes.length ? yBytes[yIndex] : 0;

        late final double r;
        late final double g;
        late final double b;

        if (!luminanceOnly &&
            uBytes.isNotEmpty &&
            vBytes.isNotEmpty &&
            uvStride > 0) {
          final uvIndex =
              (srcY ~/ 2) * uvStride + (srcX ~/ 2) * uvPixelStride;
          final uVal = uvIndex < uBytes.length ? uBytes[uvIndex] : 128;
          final vVal = uvIndex < vBytes.length ? vBytes[uvIndex] : 128;
          r = (yVal + 1.402 * (vVal - 128)).clamp(0, 255) / 255.0;
          g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
                  .clamp(0, 255) /
              255.0;
          b = (yVal + 1.772 * (uVal - 128)).clamp(0, 255) / 255.0;
        } else {
          r = g = b = yVal / 255.0;
        }

        final base = (dstRow * size + padX + dx) * 3;
        buffer[base] = r;
        buffer[base + 1] = g;
        buffer[base + 2] = b;
      }
    }
  }
}
