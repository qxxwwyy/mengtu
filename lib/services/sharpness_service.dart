// sharpness_service.dart — 锐度/合焦分析服务（v3.0 阶段二）
//
// 计算照片的拉普拉斯边缘响应，用于"峰值对焦 (Focus Peaking)"蒙层 ——
// 类似相机的合焦提示，在原图上叠加合焦边缘发光图层，直观展示焦点位置
// 与虚化过渡。
//
// 性能策略：
// - 降采样到 240×160（保持 3:2 比例），用 Laplacian 算子计算边缘强度
// - 整个计算在 Isolate 内执行（compute），不阻塞 UI
// - 返回 [SharpnessMap]：归一化的边缘强度矩阵（0~1）+ 原图宽高比
//   供 [SharpnessOverlay] 在 CustomPainter 内 GPU 一次性绘制
//
// 算法说明（参考 PyImageSearch 的 Variance of Laplacian）：
// - Laplacian 卷积核 [[0,1,0],[1,-4,1],[0,1,0]] 检测二阶导数（边缘）
// - 强响应点 = 合焦区域；弱响应点 = 虚化区域
// - 归一化到 0~1 便于 UI 渲染透明度
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 锐度分析结果（Isolate 间传递）
class SharpnessMap {
  /// 边缘强度矩阵（0~1，已归一化），行优先
  /// 长度 = rows * cols
  final List<double> response;

  /// 矩阵列数（宽）
  final int cols;

  /// 矩阵行数（高）
  final int rows;

  /// 原图宽高比（cols/rows），供 overlay 绘制时按比例缩放
  final double aspectRatio;

  /// 全图锐度评分（拉普拉斯方差），数值越大越清晰
  /// 低于阈值可提示"可能跑焦"
  final double overallScore;

  const SharpnessMap({
    required this.response,
    required this.cols,
    required this.rows,
    required this.aspectRatio,
    required this.overallScore,
  });

  /// 获取指定位置的强度（带边界检查）
  double at(int x, int y) {
    if (x < 0 || x >= cols || y < 0 || y >= rows) return 0;
    return response[y * cols + x];
  }
}

/// Isolate 入口参数
class _SharpnessArgs {
  final String imagePath;
  final int targetWidth; // 目标降采样宽度（默认 240）
  const _SharpnessArgs(this.imagePath, this.targetWidth);
}

/// 计算照片的锐度地图（Isolate 中执行）
///
/// [imagePath] 照片绝对路径
/// [targetWidth] 降采样目标宽度（默认 240，对应高度按比例 ~160）
Future<SharpnessMap> computeSharpness(
  String imagePath, {
  int targetWidth = 240,
}) {
  return compute(
    _computeSharpnessIsolate,
    _SharpnessArgs(imagePath, targetWidth),
  );
}

/// Isolate 入口：解码 → 降采样 → Laplacian 卷积 → 归一化
SharpnessMap _computeSharpnessIsolate(_SharpnessArgs args) {
  final bytes = File(args.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return const SharpnessMap(
        response: [], cols: 0, rows: 0, aspectRatio: 1, overallScore: 0);
  }

  // 按比例降采样到目标宽度
  final srcW = decoded.width;
  final srcH = decoded.height;
  final scale = args.targetWidth / srcW;
  final dstW = args.targetWidth;
  final dstH = math.max(1, (srcH * scale).round());
  final resized = img.copyResize(decoded, width: dstW, height: dstH);

  // 1) 计算灰度图（Rec.709 亮度）
  final gray = List<double>.filled(dstW * dstH, 0);
  for (var y = 0; y < dstH; y++) {
    for (var x = 0; x < dstW; x++) {
      final p = resized.getPixel(x, y);
      final lum = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      gray[y * dstW + x] = lum;
    }
  }

  // 2) Laplacian 卷积：[[0,1,0],[1,-4,1],[0,1,0]]
  // 边缘像素用 0 填充（不卷积）
  final response = List<double>.filled(dstW * dstH, 0);
  for (var y = 1; y < dstH - 1; y++) {
    for (var x = 1; x < dstW - 1; x++) {
      final center = gray[y * dstW + x];
      final top = gray[(y - 1) * dstW + x];
      final bottom = gray[(y + 1) * dstW + x];
      final left = gray[y * dstW + (x - 1)];
      final right = gray[y * dstW + (x + 1)];
      // Laplacian = top + bottom + left + right - 4*center
      response[y * dstW + x] =
          (top + bottom + left + right - 4 * center).abs();
    }
  }

  // 3) 全局锐度评分：拉普拉斯响应的方差（Variance of Laplacian）
  // 数值越大 = 越多边缘细节 = 越清晰
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < response.length; i++) {
    if (response[i] > 0) {
      sum += response[i];
      count++;
    }
  }
  final mean = count > 0 ? sum / count : 0.0;
  var varSum = 0.0;
  for (var i = 0; i < response.length; i++) {
    if (response[i] > 0) {
      final d = response[i] - mean;
      varSum += d * d;
    }
  }
  final variance = count > 0 ? varSum / count : 0.0;

  // 4) 归一化响应到 0~1（用 99 分位数防极端值拉伸）
  final sorted = List<double>.from(response.where((v) => v > 0))..sort();
  final p99 = sorted.isEmpty
      ? 1.0
      : sorted[(sorted.length * 0.99).floor().clamp(0, sorted.length - 1)];
  final norm = p99 > 0 ? p99 : 1.0;
  final normalized = response.map((v) => (v / norm).clamp(0.0, 1.0)).toList();

  return SharpnessMap(
    response: normalized,
    cols: dstW,
    rows: dstH,
    aspectRatio: srcW / srcH,
    overallScore: variance,
  );
}
