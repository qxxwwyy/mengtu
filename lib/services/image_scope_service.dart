// image_scope_service.dart — 全图像素色彩分布采样（v7.1 新增）
//
// 参考 darktable 矢量示波器的数据采集策略：
//   - 从缩略图（低分辨率 preview）采样，不从全分辨率原图
//   - 2x2 像素块降采样（step=2）
//   - 全图所有像素计入（不滤肤色色相段）
//   - RGB→HSL 后 bin 到 hue×sat 2D 直方图
//
// 性能：Isolate 内执行，缩略图 ~200×300=60K 像素，step=2 后 ~15K 次计算。
// 与 face_service 的 ROI 采样不同，这里看的是整张图的色彩分布。
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/tone_result.dart';
import 'tone_service.dart' show convertP3ToSrgb;

/// 全图像素分布采样参数
class _ImageScopeArgs {
  final String imagePath;
  final bool isP3ColorSpace;
  const _ImageScopeArgs(this.imagePath, this.isP3ColorSpace);
}

/// 采样全图的 hue×sat 2D 直方图，用于全图矢量示波器渲染。
///
/// [imagePath] 通常是缩略图路径（低分辨率 preview）。
/// [isP3ColorSpace] 为 true 时对像素做 P3→sRGB 补偿。
///
/// 返回扁平化一维数组：[SkinAnalysis.hueBinCount] × [SkinAnalysis.satBinCount]。
Future<List<int>> sampleImageHueSat(
  String imagePath, {
  bool isP3ColorSpace = false,
}) {
  return compute(
    _sampleImageHueSatIsolate,
    _ImageScopeArgs(imagePath, isP3ColorSpace),
  );
}

/// Isolate 入口
Future<List<int>> _sampleImageHueSatIsolate(_ImageScopeArgs args) async {
  final bytes = File(args.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return List<int>.filled(
        SkinAnalysis.hueBinCount * SkinAnalysis.satBinCount, 0);
  }

  final imgW = decoded.width;
  final imgH = decoded.height;

  final bins = List<int>.filled(
      SkinAnalysis.hueBinCount * SkinAnalysis.satBinCount, 0);

  final hueStep = 360.0 / SkinAnalysis.hueBinCount;
  final satStep = 1.0 / SkinAnalysis.satBinCount;

  // step=2：2x2 降采样（参考 darktable 的 2x2 策略）
  const step = 2;
  for (var y = 0; y < imgH; y += step) {
    for (var x = 0; x < imgW; x += step) {
      final p = decoded.getPixel(x, y);
      var r = p.r.toInt();
      var g = p.g.toInt();
      var b = p.b.toInt();
      if (args.isP3ColorSpace) {
        final srgb = convertP3ToSrgb(r, g, b);
        r = srgb[0];
        g = srgb[1];
        b = srgb[2];
      }

      // 跳过低饱和度像素（接近灰色的不计入，减少噪点）
      final hsl = _rgbToHsl(r, g, b);
      final h = hsl[0];
      final s = hsl[1];
      if (s < 0.05) continue;

      final hb = (h / hueStep).floor().clamp(0, SkinAnalysis.hueBinCount - 1);
      final sb = (s / satStep).floor().clamp(0, SkinAnalysis.satBinCount - 1);
      bins[hb * SkinAnalysis.satBinCount + sb]++;
    }
  }

  return bins;
}

/// RGB → HSL（H: 0~360, S/L: 0~1）
List<double> _rgbToHsl(int r, int g, int b) {
  final rN = r / 255.0;
  final gN = g / 255.0;
  final bN = b / 255.0;
  final max = math.max(rN, math.max(gN, bN));
  final min = math.min(rN, math.min(gN, bN));
  double h = 0;
  double s = 0;
  final l = (max + min) / 2;
  if (max != min) {
    final d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max == rN) {
      h = (gN - bN) / d + (gN < bN ? 6 : 0);
    } else if (max == gN) {
      h = (bN - rN) / d + 2;
    } else {
      h = (rN - gN) / d + 4;
    }
    h /= 6;
  }
  return [h * 360, s, l];
}
