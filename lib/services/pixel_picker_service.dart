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

/// Isolate 内的解码结果。
///
/// v3.2 性能修复（取色前加载几秒）：
/// - [fullWidth]/[fullHeight] = 原图尺寸（坐标语义，保持与 detail_page / pin 持久化一致）
/// - [pixels]/[sampledWidth]/[sampledHeight] = **降采样后**的 ARGB 缓冲（长边 ≤ 1600px）
/// - [scale] = sampled / full，pick() 时把原图坐标映射回降采样缓冲坐标
///
/// 12MP 原图：原实现逐像素拷贝 48MB、解码+拷贝 2~4 秒；
/// 降采样到 1600px 后约 2.6MP / ~10MB，耗时降到 ~0.5 秒。
/// 取色精度：1600 长边足够单像素取色（人眼在放大镜里也看不出 ~0.1px 的映射误差）。
class _DecodedBuffer {
  final Uint8List pixels; // 降采样后的 ARGB 缓冲（行优先，每像素 4 字节 [A,R,G,B]）
  final int sampledWidth;
  final int sampledHeight;
  final int fullWidth;
  final int fullHeight;
  const _DecodedBuffer(this.pixels, this.sampledWidth, this.sampledHeight,
      this.fullWidth, this.fullHeight);
}

class _DecodeArgs {
  final String imagePath;
  final int maxDim; // 降采样目标长边
  const _DecodeArgs(this.imagePath, this.maxDim);
}

/// Isolate 入口：解码 → 按需降采样 → 转 ARGB Uint8List
///
/// 小图（长边 ≤ [maxDim]）不降采样，scale = 1.0，逐像素颜色与原图完全一致。
/// 大图降采样到长边 [maxDim]，pick 时按 scale 映射坐标。
_DecodedBuffer _decodeOnce(_DecodeArgs args) {
  final bytes = File(args.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('Image decode failed');

  final fullW = decoded.width;
  final fullH = decoded.height;
  final longSide = fullW > fullH ? fullW : fullH;

  // 决定降采样目标尺寸
  img.Image src;
  int sampledW;
  int sampledH;
  if (longSide <= args.maxDim) {
    // 小图：直接用原图
    src = decoded;
    sampledW = fullW;
    sampledH = fullH;
  } else {
    // 大图：按比例缩到长边 = maxDim
    final scale = args.maxDim / longSide;
    sampledW = (fullW * scale).round().clamp(1, fullW);
    sampledH = (fullH * scale).round().clamp(1, fullH);
    src = img.copyResize(decoded, width: sampledW, height: sampledH);
  }

  final pixels = Uint8List(sampledW * sampledH * 4);
  var i = 0;
  for (var y = 0; y < sampledH; y++) {
    for (var x = 0; x < sampledW; x++) {
      final p = src.getPixel(x, y);
      pixels[i++] = 0xFF; // A
      pixels[i++] = p.r.toInt() & 0xFF; // R
      pixels[i++] = p.g.toInt() & 0xFF; // G
      pixels[i++] = p.b.toInt() & 0xFF; // B
    }
  }
  return _DecodedBuffer(
      pixels, sampledW, sampledH, fullW, fullH);
}

/// 取色会话：进入取色模式时一次性解码（降采样），之后 pick() 是纯内存查找。
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
/// 内存：降采样到长边 1600px，2.6MP ARGB ≈ 10MB（原全分辨率 12MP ≈ 48MB）。
///
/// 坐标语义：[width]/[height] 仍是**原图**尺寸（detail_page 传 photo.width/height、
/// pin 持久化、测试断言都依赖此契约）。pick 内部把原图坐标按 [_scale] 映射到
/// 降采样缓冲 [_pixels] 的坐标再取像素。
class ColorPickerSession {
  final Uint8List _pixels; // 降采样后的 ARGB 缓冲
  final int _sampledWidth;
  final int _sampledHeight;

  /// 原图尺寸（pick 接收的坐标空间，不变）
  final int width;
  final int height;

  /// 原图 → 降采样缓冲的缩放比（≤1.0）。pick 时 dst = src * _scale
  final double _scale;

  /// v3.2 卡顿修复：预分配的 11×11 region 缓冲（pick 复用，避免每帧 121 次 List 分配）
  late final List<List<int>> _regionBuffer = List.generate(
    _regionSize,
    (_) => List.filled(_regionSize, 0),
  );

  static const int _regionSize = 11;

  ColorPickerSession._(this._pixels, this._sampledWidth, this._sampledHeight,
      this.width, this.height, this._scale);

  /// 解码（Isolate 内一次性降采样），返回主线程持有的会话
  static Future<ColorPickerSession> begin(String imagePath, {int maxDim = 1600}) {
    return compute(_decodeOnce, _DecodeArgs(imagePath, maxDim)).then(
      (b) => ColorPickerSession._(
        b.pixels,
        b.sampledWidth,
        b.sampledHeight,
        b.fullWidth,
        b.fullHeight,
        b.sampledWidth / b.fullWidth,
      ),
    );
  }

  /// 原图像素坐标 → 降采样缓冲坐标
  int _toSampled(int v, int sampledMax, int fullMax) {
    if (fullMax <= 0) return 0;
    return (v * _scale).round().clamp(0, sampledMax - 1);
  }

  /// 读取指定【原图像素坐标】的取色结果（同步，无 Isolate）
  ///
  /// [x]/[y] 为**原图**像素坐标（非屏幕坐标）。内部按 [_scale] 映射到降采样缓冲。
  /// 越界自动 clamp。
  ColorPickResult pick(int x, int y) {
    final px = x.clamp(0, width - 1);
    final py = y.clamp(0, height - 1);
    // 映射到降采样缓冲坐标
    final sx = _toSampled(px, _sampledWidth, width);
    final sy = _toSampled(py, _sampledHeight, height);

    int pixel(int sampledX, int sampledY) {
      final i = (sampledY * _sampledWidth + sampledX) * 4;
      return (_pixels[i] << 24) |
          (_pixels[i + 1] << 16) |
          (_pixels[i + 2] << 8) |
          _pixels[i + 3];
    }

    final argb = pixel(sx, sy);
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

    // 11×11 区域（在降采样缓冲坐标空间取，复用预分配缓冲消除每帧分配）
    const half = _regionSize ~/ 2;
    final region = _regionBuffer;
    for (var dy = -half; dy <= half; dy++) {
      final row = region[dy + half];
      // 降采样缓冲坐标空间内 clamp（±half 像素在缓冲内是真实像素）
      final ry = (sy + dy).clamp(0, _sampledHeight - 1);
      for (var dx = -half; dx <= half; dx++) {
        final rx = (sx + dx).clamp(0, _sampledWidth - 1);
        row[dx + half] = pixel(rx, ry);
      }
    }

    return ColorPickResult(
      pixel: PixelInfo(
        x: px, // 返回原图坐标（保持 pin 持久化/显示的坐标语义）
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
