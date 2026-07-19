// face_service.dart — 肤色 ROI 提取服务（v7.0 SCRFD 重构）
//
// v7.0 重构：移除 BlazeFace / Face Mesh / STI/FLC（依赖 468 点网格，SCRFD 只给 5 点）。
// 现在只保留 bbox-ROI 肤色统计：人脸 bbox 由 [scrfd_service] 的 SCRFD 检测器产出，
// 本服务在 bbox 内缩 20% 后采样像素统计 ΔH/饱和/SLS/SCS/skinLuminance/bgLuminance。
//
// 检测链（外部调用方负责）：
//   scrfd_service.detectPrimaryFace(imagePath) → DetectedFace?（归一化 bbox）
//   → analyzeSkinTone(imagePath, primaryFace: face) → SkinAnalysis
//
// 性能：ROI 遍历在 Isolate 内执行（compute），不阻塞 UI。
// 降级：无脸 → 空 SkinAnalysis；手动校准 → _computeManualSkinStats 跳过检测。
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/tone_result.dart';
import 'tone_service.dart' show convertP3ToSrgb, skinHueOffset;

/// 检测到的人脸（归一化坐标 0~1）
///
/// bbox 由 [scrfd_service] 的 SCRFD 检测器产出并归一化到 0~1。
/// 被 [FaceBBoxOverlay] 可视化、[analyzeSkinTone] ROI 采样、providers 传递。
class DetectedFace {
  /// 边界框（归一化 0~1，相对原图）
  final double left, top, right, bottom;

  /// 置信度（0~1）
  final double confidence;

  const DetectedFace({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
  });

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;
}

/// 肤色分析参数（Isolate 间传递，需可序列化）
class _FaceAnalysisArgs {
  final String imagePath;
  final bool isP3ColorSpace;
  final List<double>? manualSkinRgb; // 手动覆盖：取色点 RGB [r,g,b] 0-255
  final DetectedFace? primaryFace; // SCRFD 预检测的主脸 bbox（归一化 0~1）

  const _FaceAnalysisArgs(
    this.imagePath,
    this.isP3ColorSpace,
    this.manualSkinRgb,
    this.primaryFace,
  );
}

/// 检测照片中的主脸 bbox 内肤色 ROI 统计指标（v7.0：bbox-only，无 STI/FLC）。
///
/// [imagePath] 照片绝对路径；[primaryFace] 为 SCRFD 预检测的 bbox（归一化 0~1）。
/// [isP3ColorSpace] 为 true 时对像素做 P3→sRGB 补偿。
///
/// **手动覆盖模式**：当 [manualSkinRgb] 非空时，跳过人脸检测，直接用该 RGB
/// （取色点）计算色相偏差和饱和度，作为检测失败时的备用通路。
Future<SkinAnalysis> analyzeSkinTone(
  String imagePath, {
  bool isP3ColorSpace = false,
  List<double>? manualSkinRgb,
  DetectedFace? primaryFace,
}) {
  return compute(
    _analyzeSkinIsolate,
    _FaceAnalysisArgs(
      imagePath,
      isP3ColorSpace,
      manualSkinRgb,
      primaryFace,
    ),
  );
}

/// Isolate 入口（v7.0：bbox-ROI only）
Future<SkinAnalysis> _analyzeSkinIsolate(_FaceAnalysisArgs args) async {
  final bytes = File(args.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return const SkinAnalysis();
  }

  // 手动覆盖模式：跳过人脸检测，直接从给定 RGB 算色相/饱和度
  if (args.manualSkinRgb != null && args.manualSkinRgb!.length >= 3) {
    final r = args.manualSkinRgb![0].round().clamp(0, 255);
    final g = args.manualSkinRgb![1].round().clamp(0, 255);
    final b = args.manualSkinRgb![2].round().clamp(0, 255);
    return _computeManualSkinStats(decoded, r, g, b, args.isP3ColorSpace);
  }

  final face = args.primaryFace;
  if (face == null) {
    return const SkinAnalysis(); // 无脸 → 空结果，UI 提示手动校准
  }

  // bbox-ROI 肤色统计（ΔH/饱和/SLS/SCS/skinLuminance/bgLuminance）
  return _analyzeRoiSkin(decoded, face, args.isP3ColorSpace);
}

/// 在主脸 ROI 内统计肤色 HSL 指标 + 计算 SLS / SCS 隔离度
///
/// v3.2 性能优化：单次全图遍历，命中 ROI 累加肤色统计，否则累加背景统计。
/// 同时把 `getPixel(x,y)` 的 3 次调用（取 r/g/b）合并为 1 次，省 2/3 的
/// Pixel 对象分配。整体提速约 2x。
SkinAnalysis _analyzeRoiSkin(img.Image image, DetectedFace face, bool isP3) {
  final imgW = image.width;
  final imgH = image.height;

  // 归一化 → 像素坐标
  var xMin = (face.left * imgW).round().clamp(0, imgW - 1);
  var yMin = (face.top * imgH).round().clamp(0, imgH - 1);
  var xMax = (face.right * imgW).round().clamp(0, imgW - 1);
  var yMax = (face.bottom * imgH).round().clamp(0, imgH - 1);

  // ROI 内缩 20%（避开发际线、耳朵、下巴背景边缘）
  final padX = ((xMax - xMin) * 0.1).round();
  final padY = ((yMax - yMin) * 0.1).round();
  final roiXMin = xMin + padX;
  final roiXMax = xMax - padX;
  final roiYMin = yMin + padY;
  final roiYMax = yMax - padY;

  // 肤色 ROI 累加器
  double sumHue = 0;
  double sumSat = 0;
  double sumLum = 0;
  int skinCount = 0;

  // 肤色像素 hue×sat 2D 直方图（48×8=384 bins），用于矢量示波器像素云渲染。
  // 在同一遍历循环内累加，几乎零额外成本（只有一次数组自增）。
  final hueSatBins = List<int>.filled(SkinAnalysis.hueBinCount * SkinAnalysis.satBinCount, 0);

  // 背景累加器（全图排除 ROI）
  double bgSumLum = 0;
  int bgLumCount = 0;
  // 背景色相直方图（24 bins，每 15°），用于找主导色相
  final bgHueBins = List.filled(24, 0);
  int bgHueCount = 0;

  const step = 2;
  // 单次遍历：肤色 ROI（内缩后）内 → 肤色统计；
  // 原始 ROI bbox（未内缩）外 → 背景统计；内缩环（两者之间）→ 跳过。
  // 这样与原双遍历实现完全等价（内缩环既不进肤色也不进背景）。
  for (var y = 0; y < imgH; y += step) {
    final inBboxY = y >= yMin && y <= yMax;
    for (var x = 0; x < imgW; x += step) {
      final inBbox = inBboxY && x >= xMin && x <= xMax;
      if (!inBbox) {
        // 背景：累计 L + 色相直方图
        final p = image.getPixel(x, y);
        var r = p.r.toInt();
        var g = p.g.toInt();
        var b = p.b.toInt();
        if (isP3) {
          final srgb = convertP3ToSrgb(r, g, b);
          r = srgb[0];
          g = srgb[1];
          b = srgb[2];
        }
        final hsl = _rgbToHsl(r, g, b);
        bgSumLum += hsl[2];
        bgLumCount++;
        if (hsl[1] > 0.1) {
          bgHueBins[(hsl[0] / 15).floor().clamp(0, 23)]++;
          bgHueCount++;
        }
        continue;
      }
      // 在 bbox 内但不在内缩 ROI 内 → 跳过（与原实现等价）
      final inRoi = inBboxY &&
          x >= roiXMin &&
          x <= roiXMax &&
          y >= roiYMin &&
          y <= roiYMax;
      if (!inRoi) continue;

      // 肤色 ROI 内：一次 getPixel 取 r/g/b（原实现调用 3 次，省 2/3 Pixel 分配）
      final p = image.getPixel(x, y);
      var r = p.r.toInt();
      var g = p.g.toInt();
      var b = p.b.toInt();
      if (isP3) {
        final srgb = convertP3ToSrgb(r, g, b);
        r = srgb[0];
        g = srgb[1];
        b = srgb[2];
      }
      final hsl = _rgbToHsl(r, g, b);
      final h = hsl[0];
      final s = hsl[1];
      final l = hsl[2];
      // 肤色色相段：0~45° 或 320~360°（暖橙到红）
      if ((h <= 45 || h >= 320) && s >= 0.1 && s <= 0.8) {
        sumHue += (h >= 320) ? (h - 360) : h;
        sumSat += s;
        sumLum += l;
        skinCount++;
        // hue×sat 2D bin 累加（hue 已归一到 0~360，sat 0~1）
        final hb = (h / (360.0 / SkinAnalysis.hueBinCount)).floor().clamp(0, SkinAnalysis.hueBinCount - 1);
        final sb = (s / (1.0 / SkinAnalysis.satBinCount)).floor().clamp(0, SkinAnalysis.satBinCount - 1);
        hueSatBins[hb * SkinAnalysis.satBinCount + sb]++;
      }
    }
  }

  if (skinCount == 0) return const SkinAnalysis();

  double avgHue = sumHue / skinCount;
  if (avgHue < 0) avgHue += 360;
  final avgSat = sumSat / skinCount * 100;
  final avgLum = sumLum / skinCount * 100;

  // 背景平均 L
  final bgAvgLum = bgLumCount > 0 ? bgSumLum / bgLumCount * 100 : 0.0;
  // 背景主导色相 = bin 数最多的区段中心
  var maxBin = 0;
  var maxCount = 0;
  for (var i = 0; i < 24; i++) {
    if (bgHueBins[i] > maxCount) {
      maxCount = bgHueBins[i];
      maxBin = i;
    }
  }
  final bgDominantHue = bgHueCount > 0 ? (maxBin * 15 + 7.5) : 0.0;

  // SLS = 肤色 L − 背景 L（百分比）
  final sls = avgLum - bgAvgLum;
  // SCS = 肤色色相与背景主导色相的环形最短距离
  final scs = _hueRingDistance(avgHue, bgDominantHue);

  return SkinAnalysis(
    hueOffset: skinHueOffset(avgHue),
    saturation: avgSat,
    luminanceSeparation: sls,
    colorSeparation: scs,
    skinLuminance: avgLum,
    bgLuminance: bgAvgLum,
    hueSatBins: hueSatBins,
  );
}

/// 手动覆盖模式：仅计算色相偏差和饱和度（无背景统计，SLS/SCS 置 null）
SkinAnalysis _computeManualSkinStats(
    img.Image image, int r, int g, int b, bool isP3) {
  if (isP3) {
    final srgb = convertP3ToSrgb(r, g, b);
    r = srgb[0];
    g = srgb[1];
    b = srgb[2];
  }
  final hsl = _rgbToHsl(r, g, b);
  final h = hsl[0];
  final s = hsl[1];
  final l = hsl[2];
  return SkinAnalysis(
    hueOffset: skinHueOffset(h),
    saturation: s * 100,
    luminanceSeparation: null,
    colorSeparation: null,
    skinLuminance: l * 100,
    bgLuminance: null,
  );
}

/// 两个色相在 360° 环上的最短距离
double _hueRingDistance(double h1, double h2) {
  var d = (h1 - h2).abs();
  if (d > 180) d = 360 - d;
  return d;
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
