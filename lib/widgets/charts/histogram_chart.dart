// histogram_chart.dart — 带入场动画的直方图 Widget
//
// 封装 [HistogramPainter] + [ChartEnterBuilder]，提供从底部生长的入场动画。
// 替代直接用 CustomPaint + HistogramPainter 的旧用法。
import 'package:flutter/material.dart';
import '../histogram_painter.dart';
import '../../models/tone_result.dart';
import 'chart_animations.dart';

/// 带入场动画的直方图 Widget
///
/// 用法（替代旧写法）：
/// ```dart
/// // 旧：CustomPaint(painter: HistogramPainter(data: hist, mode: mode))
/// // 新：HistogramChart(data: hist, mode: mode)
/// ```
class HistogramChart extends StatelessWidget {
  final HistogramData data;
  final HistogramMode mode;
  final List<int>? colorPinHues;

  const HistogramChart({
    super.key,
    required this.data,
    this.mode = HistogramMode.rgb,
    this.colorPinHues,
  });

  @override
  Widget build(BuildContext context) {
    return ChartEnterBuilder(
      builder: (context, progress) => CustomPaint(
        painter: HistogramPainter(
          data: data,
          mode: mode,
          colorPinHues: colorPinHues,
          progress: progress,
        ),
      ),
    );
  }
}
