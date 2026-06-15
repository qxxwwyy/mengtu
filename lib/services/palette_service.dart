// palette_service.dart — 色卡提取（Isolate 中执行）
//
// 支持三种算法：
// 1. QuantizerCelebi (默认) — material_color_utilities，Google 的 WSMD 量化
// 2. MMCQ — Modified Median Cut Quantization，经典中位数切分
// 3. K-Means++ — 迭代聚类，感知均匀
//
// 工作流：image 包解码 → 降采样构建 ARGB int 列表 → 算法量化 → 占比计算
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';
import '../models/palette_result.dart';
import '../algorithms/mmcq.dart';
import '../algorithms/kmeans.dart';

/// 色卡提取算法
enum PaletteAlgorithm {
  /// Google QuantizerCelebi + Score（默认）
  celebi,
  /// Modified Median Cut Quantization
  mmcq,
  /// K-Means++ 迭代聚类
  kmeans,
}

/// Isolate 入口参数（需可序列化）
class _PaletteArgs {
  final String path;
  final int desired;
  final int algorithmIndex; // PaletteAlgorithm.index

  const _PaletteArgs(this.path, this.desired, this.algorithmIndex);
}

/// 计算色卡（Isolate 中执行）
Future<PaletteResult> extractPalette(
  String imagePath, {
  int desired = 5,
  PaletteAlgorithm algorithm = PaletteAlgorithm.celebi,
}) {
  return compute(
    _extractPaletteIsolate,
    _PaletteArgs(imagePath, desired, algorithm.index),
  );
}

/// Isolate 入口：解码 → 降采样 → 按算法量化 → 占比计算
Future<PaletteResult> _extractPaletteIsolate(_PaletteArgs args) async {
  final bytes = File(args.path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('Image decode failed: ${args.path}');
  }

  // 降采样构建 ARGB int 列表（0xFFRRGGBB）
  const step = 4;
  final pixels = <int>[];
  for (var y = 0; y < decoded.height; y += step) {
    for (var x = 0; x < decoded.width; x += step) {
      final p = decoded.getPixel(x, y);
      final r = p.r.toInt().clamp(0, 255);
      final g = p.g.toInt().clamp(0, 255);
      final b = p.b.toInt().clamp(0, 255);
      pixels.add(0xFF000000 | (r << 16) | (g << 8) | b);
    }
  }

  final algorithm = PaletteAlgorithm.values[args.algorithmIndex];

  switch (algorithm) {
    case PaletteAlgorithm.celebi:
      return _extractWithCelebi(pixels, args.desired);
    case PaletteAlgorithm.mmcq:
      return _extractWithMmcq(pixels, args.desired);
    case PaletteAlgorithm.kmeans:
      return _extractWithKmeans(pixels, args.desired);
  }
}

/// QuantizerCelebi + Score 提取（原 v0.2.0 逻辑）
Future<PaletteResult> _extractWithCelebi(List<int> pixels, int desired) async {
  final quantizer = QuantizerCelebi();
  final result = await quantizer.quantize(pixels, desired * 3);
  final colorToCount = result.colorToCount;
  final totalPixels = colorToCount.values.fold<int>(0, (a, b) => a + b);

  final scoredColors = Score.score(
    Map<int, int>.from(colorToCount),
    desired: desired,
    filter: false,
  );

  final colors = <PaletteColor>[];
  for (final argb in scoredColors) {
    final count = colorToCount[argb] ?? 0;
    final ratio = totalPixels > 0 ? (count / totalPixels) * 100 : 0.0;
    colors.add(PaletteColor(argb: argb, ratio: ratio));
  }

  // 补齐
  if (colors.length < desired) {
    final existing = scoredColors.toSet();
    final remaining = colorToCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in remaining) {
      if (colors.length >= desired) break;
      if (existing.contains(entry.key)) continue;
      final ratio = totalPixels > 0 ? (entry.value / totalPixels) * 100 : 0.0;
      colors.add(PaletteColor(argb: entry.key, ratio: ratio));
    }
  }

  return _normalize(colors);
}

/// MMCQ 提取
PaletteResult _extractWithMmcq(List<int> pixels, int desired) {
  final result = mmcq(pixels, colorCount: desired);
  final totalPixels = result.counts.fold<int>(0, (a, b) => a + b);

  final colors = <PaletteColor>[];
  for (var i = 0; i < result.colors.length; i++) {
    final ratio = totalPixels > 0 ? (result.counts[i] / totalPixels) * 100 : 0.0;
    colors.add(PaletteColor(argb: result.colors[i], ratio: ratio));
  }

  return _normalize(colors);
}

/// K-Means++ 提取
PaletteResult _extractWithKmeans(List<int> pixels, int desired) {
  final result = kmeansPlusPlus(pixels, k: desired);
  final totalPixels = result.counts.fold<int>(0, (a, b) => a + b);

  final colors = <PaletteColor>[];
  for (var i = 0; i < result.colors.length; i++) {
    final ratio = totalPixels > 0 ? (result.counts[i] / totalPixels) * 100 : 0.0;
    colors.add(PaletteColor(argb: result.colors[i], ratio: ratio));
  }

  // K-Means 按像素数排序（大块在前）
  final sortedColors = List<PaletteColor>.from(colors)
    ..sort((a, b) => b.ratio.compareTo(a.ratio));
  colors.clear();
  colors.addAll(sortedColors);

  return _normalize(colors);
}

/// 归一化占比到 100%
PaletteResult _normalize(List<PaletteColor> colors) {
  if (colors.isEmpty) return PaletteResult(colors: colors);
  final selectedTotal = colors.fold<double>(0, (a, c) => a + c.ratio);
  if (selectedTotal <= 0) return PaletteResult(colors: colors);
  final scale = 100.0 / selectedTotal;
  return PaletteResult(
    colors: colors
        .map((c) => PaletteColor(argb: c.argb, ratio: c.ratio * scale))
        .toList(),
  );
}
