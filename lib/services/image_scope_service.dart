// image_scope_service.dart — 全图像素色彩分布采样（v7.2 Cb/Cr 平面）
//
// 参考 darktable / 达芬奇 vectorscope 的数据采集策略：
//   - 从缩略图（低分辨率 preview）采样，不从全分辨率原图
//   - 2x2 像素块降采样（step=2）
//   - 全图所有像素计入（不滤肤色色相段）
//   - RGB→YCbCr(Rec.709) 后 bin 到 Cb/Cr 64×64 2D 直方图
//
// 性能：Isolate 内执行，缩略图 ~200×300=60K 像素，step=2 后 ~15K 次计算。
// 与 face_service 的 ROI 采样不同，这里看的是整张图的色彩分布。
//
// v7.2：旧的 sampleImageHueSat（HSV hue×sat 48×8）已删除，统一用 Cb/Cr 平面，
// 与示波器六色目标（BT.709 彩条）处于同一坐标系。
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/tone_result.dart';
import '../utils/color_utils.dart' show rgbToYCbCr;
import 'tone_service.dart' show convertP3ToSrgb;

/// 全图像素分布采样参数
class _ImageScopeArgs {
  final String imagePath;
  final bool isP3ColorSpace;
  const _ImageScopeArgs(this.imagePath, this.isP3ColorSpace);
}

// ============ v7.2：Cb/Cr 平面采样（达芬奇 broadcast vectorscope）============
//
// 把每个像素的 Cb/Cr（YCbCr Rec.709 full-range）bin 到 64×64 二维直方图。
// Cb/Cr 各覆盖 -128~127，每 bin ≈4。与示波器六色目标（BT.709 彩条标准 Cb/Cr）
// 处于同一坐标系。
//
// 过滤：chroma 幅度 sqrt(Cb²+Cr²) < 8 的无色像素跳过（减少灰云污染中心区）。
Future<List<int>> sampleImageChroma(
  String imagePath, {
  bool isP3ColorSpace = false,
}) {
  return compute(
    _sampleImageChromaIsolate,
    _ImageScopeArgs(imagePath, isP3ColorSpace),
  );
}

/// sampleImageChroma 的 Isolate 入口
Future<List<int>> _sampleImageChromaIsolate(_ImageScopeArgs args) async {
  final bytes = File(args.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  final cbBins = SkinAnalysis.cbBinCount;
  final crBins = SkinAnalysis.crBinCount;
  if (decoded == null) {
    return List<int>.filled(cbBins * crBins, 0);
  }

  final imgW = decoded.width;
  final imgH = decoded.height;

  final bins = List<int>.filled(cbBins * crBins, 0);

  // Cb/Cr 各 -128~127，共 256 个单位 → 每 bin 宽 256/cbBins
  final cbStep = 256.0 / cbBins;
  final crStep = 256.0 / crBins;

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
      final ycbcr = rgbToYCbCr(r, g, b);
      final cb = ycbcr.cb;
      final cr = ycbcr.cr;

      // 无色像素（接近原点）跳过，避免中心灰云过亮遮盖有色信号
      final chroma = math.sqrt(cb * cb + cr * cr);
      if (chroma < 8) continue;

      // Cb/Cr 从 [-128, 127] 映射到 [0, cbBins-1]
      final cbBin = ((cb + 128) / cbStep).floor().clamp(0, cbBins - 1);
      final crBin = ((cr + 128) / crStep).floor().clamp(0, crBins - 1);
      bins[cbBin * crBins + crBin]++;
    }
  }

  return bins;
}
