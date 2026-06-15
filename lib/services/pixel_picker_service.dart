// pixel_picker_service.dart — 像素取色服务
//
// 读取图片指定坐标的像素颜色
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../utils/color_utils.dart';

/// 像素颜色信息
class PixelInfo {
  final int x;
  final int y;
  final int r;
  final int g;
  final int b;
  final int luminance;
  final int hue;
  final double saturation;
  final double value;

  const PixelInfo({
    required this.x,
    required this.y,
    required this.r,
    required this.g,
    required this.b,
    required this.luminance,
    required this.hue,
    required this.saturation,
    required this.value,
  });

  String get hex => argbToHex(0xFF000000 | (r << 16) | (g << 8) | b);
  String get rgbString => 'rgb($r, $g, $b)';
  String get hsvString =>
      'hsv($hue°, ${(saturation * 100).round()}%, ${(value * 100).round()}%)';
}

/// 取色结果（包含像素信息和局部像素数据用于放大镜）
class ColorPickResult {
  final PixelInfo pixel;
  final List<List<int>> regionRgb; // 11x11 区域的 RGB 值

  const ColorPickResult({required this.pixel, required this.regionRgb});
}

/// 读取指定坐标的像素颜色（在 Isolate 中执行）
Future<ColorPickResult> pickColor(
    String imagePath, int x, int y, int imageWidth, int imageHeight) {
  return compute(
    _pickColor,
    _PickColorParams(imagePath, x, y, imageWidth, imageHeight),
  );
}

class _PickColorParams {
  final String imagePath;
  final int x;
  final int y;
  final int imageWidth;
  final int imageHeight;

  const _PickColorParams(
      this.imagePath, this.x, this.y, this.imageWidth, this.imageHeight);
}

ColorPickResult _pickColor(_PickColorParams params) {
  final bytes = File(params.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('Image decode failed');

  final px = params.x.clamp(0, decoded.width - 1);
  final py = params.y.clamp(0, decoded.height - 1);

  final pixel = decoded.getPixel(px, py);
  final r = pixel.r.toInt();
  final g = pixel.g.toInt();
  final b = pixel.b.toInt();
  final lum = luminance(r, g, b);
  final hue = rgbToHue(r, g, b);

  // 计算 HSV
  final rf = r / 255, gf = g / 255, bf = b / 255;
  final maxVal = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
  final minVal = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
  final delta = maxVal - minVal;
  final saturation = maxVal == 0 ? 0.0 : delta / maxVal;

  // 读取 11x11 区域像素（用于放大镜）
  const regionSize = 11;
  const half = regionSize ~/ 2;
  final region = <List<int>>[];
  for (var dy = -half; dy <= half; dy++) {
    final row = <int>[];
    for (var dx = -half; dx <= half; dx++) {
      final sx = (px + dx).clamp(0, decoded.width - 1);
      final sy = (py + dy).clamp(0, decoded.height - 1);
      final p = decoded.getPixel(sx, sy);
      // ARGB int
      row.add(0xFF000000 |
          ((p.r.toInt() & 0xFF) << 16) |
          ((p.g.toInt() & 0xFF) << 8) |
          (p.b.toInt() & 0xFF));
    }
    region.add(row);
  }

  return ColorPickResult(
    pixel: PixelInfo(
      x: px,
      y: py,
      r: r,
      g: g,
      b: b,
      luminance: lum,
      hue: hue < 0 ? 0 : hue,
      saturation: saturation,
      value: maxVal,
    ),
    regionRgb: region,
  );
}
