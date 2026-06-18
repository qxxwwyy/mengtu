// pixel_picker_service.dart — 像素取色服务
//
// 读取图片指定坐标的像素颜色。
//
// 性能策略（v3.1 修复"取色工具极其卡顿"）：
// 原实现每次拖动都重新 decodeImage 全图 + 新建 Isolate，4MP 图每帧几十 ms，
// 拖动手指无法达到 60fps → 卡顿不可用。
// 现拆为两条路径：
//   - ColorPickerSession：进入取色模式时【一次性】compute 解码全图，主线程持有
//     像素缓冲；之后 session.pick() 是纯内存查找（<1ms，无 Isolate）。
//   - pickColor（旧 API）：保留用于一次性取色场景（兼容现有调用方）。
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
///
/// 单次取色场景使用。**拖动场景请用 [ColorPickerSession]**，
/// 避免每次调用都重新解码全图导致卡顿。
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

  return _pickFromDecoded(decoded, params.x, params.y);
}

/// 从已解码的 img.Image 取色（Isolate 与 Session 共用逻辑）
ColorPickResult _pickFromDecoded(img.Image decoded, int x, int y) {
  final px = x.clamp(0, decoded.width - 1);
  final py = y.clamp(0, decoded.height - 1);

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

// ============ ColorPickerSession：会话级取色（拖动场景性能优化） ============

/// Isolate 内的解码结果：裸像素缓冲 + 宽高。
/// 传递 Uint8List（每个像素 4 字节 ARGB）回主线程。
class _DecodedBuffer {
  final Uint8List pixels; // 行优先，每像素 4 字节 [A,R,G,B]
  final int width;
  final int height;
  const _DecodedBuffer(this.pixels, this.width, this.height);
}

class _DecodeArgs {
  final String imagePath;
  const _DecodeArgs(this.imagePath);
}

/// Isolate 入口：解码全图 → 转 ARGB Uint8List
_DecodedBuffer _decodeOnce(_DecodeArgs args) {
  final bytes = File(args.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('Image decode failed');

  final w = decoded.width;
  final h = decoded.height;
  final pixels = Uint8List(w * h * 4);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = decoded.getPixel(x, y);
      pixels[i++] = 0xFF; // A
      pixels[i++] = p.r.toInt() & 0xFF; // R
      pixels[i++] = p.g.toInt() & 0xFF; // G
      pixels[i++] = p.b.toInt() & 0xFF; // B
    }
  }
  return _DecodedBuffer(pixels, w, h);
}

/// 取色会话：进入取色模式时一次性解码，之后 pick() 是纯内存查找。
///
/// 用法：
/// ```dart
/// final session = await ColorPickerSession.begin(path);
/// // 拖动期间反复调用（<1ms，无 Isolate）：
/// final result = session.pick(x, y);
/// // 退出取色模式：
/// session.dispose();
/// ```
///
/// 内存：4MP 图 ARGB ≈ 16MB，进入/退出取色时及时 dispose。
class ColorPickerSession {
  final Uint8List _pixels;
  final int width;
  final int height;

  ColorPickerSession._(this._pixels, this.width, this.height);

  /// 解码全图（Isolate 内一次性），返回主线程持有的会话
  static Future<ColorPickerSession> begin(String imagePath) {
    return compute(_decodeOnce, _DecodeArgs(imagePath)).then(
      (b) => ColorPickerSession._(b.pixels, b.width, b.height),
    );
  }

  /// 读取指定【像素坐标】的取色结果（同步，无 Isolate）
  ///
  /// [x]/[y] 为原图像素坐标（非屏幕坐标）。越界自动 clamp。
  ColorPickResult pick(int x, int y) {
    final px = x.clamp(0, width - 1);
    final py = y.clamp(0, height - 1);

    int pixel(int x, int y) {
      final i = (y * width + x) * 4;
      return (_pixels[i] << 24) |
          (_pixels[i + 1] << 16) |
          (_pixels[i + 2] << 8) |
          _pixels[i + 3];
    }

    final argb = pixel(px, py);
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final lum = luminance(r, g, b);
    final hue = rgbToHue(r, g, b);

    final rf = r / 255, gf = g / 255, bf = b / 255;
    final maxVal = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
    final minVal = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
    final delta = maxVal - minVal;
    final saturation = maxVal == 0 ? 0.0 : delta / maxVal;

    // 11×11 区域
    const regionSize = 11;
    const half = regionSize ~/ 2;
    final region = <List<int>>[];
    for (var dy = -half; dy <= half; dy++) {
      final row = <int>[];
      for (var dx = -half; dx <= half; dx++) {
        final sx = (px + dx).clamp(0, width - 1);
        final sy = (py + dy).clamp(0, height - 1);
        row.add(pixel(sx, sy));
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

  /// 释放像素缓冲（Dart 无显式 free，置 null 便于 GC；保持 API 显式以便将来扩展）
  void dispose() {
    // Uint8List 无需显式释放，离开作用域即 GC。保留方法以匹配 begin/dispose 对称语义。
  }
}
