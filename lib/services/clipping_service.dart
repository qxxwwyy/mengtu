// clipping_service.dart — Clipping 区域检测（死黑/过曝）
//
// 在 Isolate 中执行，检测图片中的纯黑和纯白像素区域
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Clipping 检测结果
class ClippingResult {
  /// 暗部 clipping 像素坐标集（归一化到 0-1）
  final List<Offset> darkPoints;

  /// 亮部 clipping 像素坐标集（归一化到 0-1）
  final List<Offset> brightPoints;

  /// 暗部 clipping 占比（0-1）
  final double darkRatio;

  /// 亮部 clipping 占比（0-1）
  final double brightRatio;

  /// 图片宽高
  final int width;
  final int height;

  const ClippingResult({
    required this.darkPoints,
    required this.brightPoints,
    required this.darkRatio,
    required this.brightRatio,
    required this.width,
    required this.height,
  });

  bool get hasDarkClipping => darkRatio > 0.005; // > 0.5%
  bool get hasBrightClipping => brightRatio > 0.005;
  bool get hasAnyClipping => hasDarkClipping || hasBrightClipping;
}

/// 检测 Clipping 区域（在 Isolate 中执行）
Future<ClippingResult> detectClipping(String imagePath) {
  return compute(_detectClipping, imagePath);
}

ClippingResult _detectClipping(String path) {
  final bytes = File(path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('Image decode failed: $path');
  }

  final w = decoded.width;
  final h = decoded.height;
  final darkPoints = <Offset>[];
  final brightPoints = <Offset>[];
  var darkCount = 0;
  var brightCount = 0;
  var totalSamples = 0;

  // 降采样 step=2（比直方图更密）
  const step = 2;
  // 坐标上限：超过后只继续计数，不再记录坐标（坐标仅用于可视化）
  const maxPoints = 2000;

  for (var y = 0; y < h; y += step) {
    for (var x = 0; x < w; x += step) {
      final pixel = decoded.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();

      totalSamples++;

      // 暗部 clipping：所有通道 < 5
      if (r < 5 && g < 5 && b < 5) {
        darkCount++;
        // 每 8 个采样点记录一个坐标（避免过多点导致性能问题）
        if (darkCount % 8 == 0 && darkPoints.length < maxPoints) {
          darkPoints.add(Offset(x / w, y / h));
        }
      }

      // 亮部 clipping：所有通道 > 250
      if (r > 250 && g > 250 && b > 250) {
        brightCount++;
        if (brightCount % 8 == 0 && brightPoints.length < maxPoints) {
          brightPoints.add(Offset(x / w, y / h));
        }
      }
    }
  }

  return ClippingResult(
    darkPoints: darkPoints,
    brightPoints: brightPoints,
    darkRatio: totalSamples > 0 ? darkCount / totalSamples : 0,
    brightRatio: totalSamples > 0 ? brightCount / totalSamples : 0,
    width: w,
    height: h,
  );
}
