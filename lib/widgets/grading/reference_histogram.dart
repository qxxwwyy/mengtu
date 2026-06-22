// reference_histogram.dart — 参照直方图叠放（v3.5 PR3 教学核心）
//
// 当前照片亮度直方图（强调色琥珀）+ 半透明灰背景的典型影调参照分布。
// 让用户直观看到「这张样片的直方图 vs 典型风格的直方图」差异 ——
// 例如高调样片会看到当前分布与「高调参照（右偏钟形）」重合度高。
//
// 参照分布用高斯/U型函数预生成 4 组 256 bins 常量（high/low/mid/full），
// 不依赖运行时计算，确保 O(1) 内存与零延迟。
//
// 规格对齐：HistogramPainter 的 barWidth = size.width / 256 约定。
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 参照直方图叠放：当前直方图 + 典型影调参照（半透明灰背景）
class ReferenceHistogram extends StatelessWidget {
  /// 当前照片的亮度直方图（256 bins）。null 时只画参照。
  final List<int>? current;

  /// 当前影调类型（high/mid/low/full），决定用哪组参照
  final String? currentToneKey;

  const ReferenceHistogram({
    super.key,
    this.current,
    this.currentToneKey,
  });

  @override
  Widget build(BuildContext context) {
    final reference = _getReferenceHistogram(currentToneKey);
    return SizedBox(
      height: 80,
      child: CustomPaint(
        painter: _ReferenceHistogramPainter(
          current: current,
          reference: reference,
        ),
      ),
    );
  }

  /// 取与当前影调最接近的参照直方图
  ///
  /// high → 右偏钟形（高调：主体在高光区）
  /// low → 左偏钟形（低调：主体在阴影区）
  /// full → U 型（全长调：两端高中间低，高反差）
  /// mid/default → 中央钟形（中间调：主体在中调区）
  List<int> _getReferenceHistogram(String? toneKey) {
    switch (toneKey) {
      case 'high':
        return _kHighKeyReference;
      case 'low':
        return _kLowKeyReference;
      case 'full':
        return _kFullRangeReference;
      default:
        return _kMidKeyReference;
    }
  }
}

class _ReferenceHistogramPainter extends CustomPainter {
  /// 当前直方图（256 bins）。null 时只画参照。
  final List<int>? current;

  /// 参照分布（256 bins）
  final List<int> reference;

  _ReferenceHistogramPainter({required this.current, required this.reference});

  // 性能优化：Paint 对象 static final
  static final _referencePaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.15)
    ..style = PaintingStyle.fill;

  static final _currentPaint = Paint()
    ..color = AppColors.darkAccent
    ..style = PaintingStyle.fill;

  static final _axisPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.1)
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final barWidth = width / 256;

    // 底部基线
    canvas.drawLine(Offset(0, height - 0.5), Offset(width, height - 0.5),
        _axisPaint);

    // 1) 参照分布（半透明灰背景）
    _drawHistogram(canvas, size, reference, _referencePaint, barWidth);

    // 2) 当前分布（强调色，叠在参照上）
    if (current != null && current!.isNotEmpty) {
      _drawHistogram(canvas, size, current!, _currentPaint, barWidth);
    }
  }

  void _drawHistogram(Canvas canvas, Size size, List<int> hist, Paint paint,
      double barWidth) {
    final maxVal = hist.reduce(math.max);
    if (maxVal <= 0) return;
    final height = size.height;
    final path = Path()..moveTo(0, height);
    for (var i = 0; i < 256; i++) {
      final h = (hist[i] / maxVal) * height;
      path.lineTo(i * barWidth, height - h);
    }
    path.lineTo(width(size), height);
    path.close();
    canvas.drawPath(path, paint);
  }

  double width(Size size) => size.width;

  @override
  bool shouldRepaint(covariant _ReferenceHistogramPainter old) =>
      old.current != current || old.reference != reference;
}

// ============ 预置典型分布（高斯生成，作为教学参照锚点）============
//
// 这些是「典型风格」的参考形态，不是精确标准。教学目的是让用户看到
// 自己照片的分布与典型形态的重合/偏离，建立直觉。

/// 高调参照：均值 180（偏右），标准差 40 —— 主体落在高光区
final _kHighKeyReference = _generateGaussian(mean: 180, std: 40);

/// 低调参照：均值 60（偏左），标准差 40 —— 主体落在阴影区
final _kLowKeyReference = _generateGaussian(mean: 60, std: 40);

/// 中间调参照：均值 128（中央），标准差 50 —— 主体落在中调区
final _kMidKeyReference = _generateGaussian(mean: 128, std: 50);

/// 全长调参照：U 型（两端高，中间低）—— 高反差，明暗两端都有内容
final _kFullRangeReference = _generateUShape();

/// 生成高斯钟形分布（256 bins）
///
/// [mean] 均值（峰值位置），[std] 标准差（峰宽）。
/// 用 exp(-((x-mean)²)/(2σ²)) 归一化到整数直方图，峰值约 1000。
List<int> _generateGaussian({required double mean, required double std}) {
  final result = List<int>.filled(256, 0);
  const peak = 1000.0;
  for (var i = 0; i < 256; i++) {
    final d = (i - mean) / std;
    result[i] = (peak * math.exp(-0.5 * d * d)).round();
  }
  return result;
}

/// 生成 U 型分布（全长调参照）
///
/// 两端（bin 0 和 255）高，中间低。用 |x-128| 的归一化形成 U 型。
List<int> _generateUShape() {
  final result = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    // 距离中心 128 的归一化距离（0~1），平方后 U 型更陡
    final dist = (i - 128).abs() / 128.0;
    result[i] = (1000 * (0.2 + 0.8 * dist * dist)).round();
  }
  return result;
}
