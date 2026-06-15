// histogram_service.dart — 直方图计算（Isolate 中执行）
//
// v1.0.0 新增：色相直方图（360 bins，HSV H 通道）
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../utils/color_utils.dart';
import '../models/tone_result.dart';

/// 计算直方图（在 Isolate 中执行）
/// 返回 RGB(256×3) + Lum(256) + Hue(360)
Future<HistogramData> computeHistogram(String imagePath) {
  return compute(_computeHistogram, imagePath);
}

HistogramData _computeHistogram(String path) {
  final bytes = File(path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('Image decode failed: $path');
  }

  final rHist = List.filled(256, 0);
  final gHist = List.filled(256, 0);
  final bHist = List.filled(256, 0);
  final lumHist = List.filled(256, 0);
  final hueHist = List.filled(360, 0);

  // 降采样 step=4
  const step = 4;
  for (var y = 0; y < decoded.height; y += step) {
    for (var x = 0; x < decoded.width; x += step) {
      final pixel = decoded.getPixel(x, y);
      final r = pixel.r.toInt().clamp(0, 255);
      final g = pixel.g.toInt().clamp(0, 255);
      final b = pixel.b.toInt().clamp(0, 255);
      rHist[r]++;
      gHist[g]++;
      bHist[b]++;
      final l = luminance(r, g, b);
      lumHist[l]++;
      // 色相直方图（灰度像素不计入色相）
      final h = rgbToHue(r, g, b);
      if (h >= 0) hueHist[h]++;
    }
  }

  return HistogramData(
    r: rHist,
    g: gHist,
    b: bHist,
    lum: lumHist,
    hue: hueHist,
  );
}
