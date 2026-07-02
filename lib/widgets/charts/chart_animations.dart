// chart_animations.dart — 图表共享动画 helper
//
// 核心原则：图表必须有入场动画。静止的图表是死的，动画的图表是活的。
// 所有图表 Widget 通过 TweenAnimationBuilder + [ChartEnterMixin] 实现统一的入场效果。
import 'package:flutter/material.dart' hide Durations;
import '../../theme/app_animations.dart';

/// 图表入场动画进度 Widget
///
/// 用法：
/// ```dart
/// ChartEnterBuilder(
///   builder: (context, progress) => CustomPaint(
///     painter: MyPainter(progress: progress),
///   ),
/// )
/// ```
///
/// [progress] 从 0.0 → 1.0，曲线 [Curves2.chartEnter]（easeOutCubic），
/// duration [Durations.chartEnter]（500ms）。
/// 首次挂载即自动播放，无需手动管理 AnimationController。
class ChartEnterBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, double progress) builder;

  const ChartEnterBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: AppAnimations.chartEnterDuration,
      curve: AppAnimations.chartEnterCurve,
      builder: (context, progress, _) => builder(context, progress),
    );
  }
}

/// 将 progress (0.0~1.0) 映射到图表的有效高度比例
///
/// 入场动画的视觉效果是「从底部生长」：
/// - progress=0.0 → 柱子高度 = 0
/// - progress=1.0 → 柱子高度 = 原始值
/// 中间用 easeOutCubic，让前期增长快、后期减速到目标位置。
double chartEnterScale(double progress) {
  return Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
}

/// 脉动动画 helper（用于肤色光点呼吸效果）
///
/// 返回当前帧的 opacity (0.7~1.0)，需要 AnimationController 驱动。
/// 用法：
/// ```dart
/// final opacity = pulseOpacity(_controller.value);
/// ```
double pulseOpacity(double t) {
  // 正弦波：t=0→0.85, t=0.5→1.0, t=1→0.85
  return 0.85 + 0.15 * (0.5 + 0.5 * (t * 2 * 3.14159265).sin());
}

/// 扩展：给 num 加 sin/cos 便捷方法
extension NumTrig on num {
  double sin() => _dartSin(toDouble());
  double cos() => _dartCos(toDouble());
}

// 纯 Dart sin/cos 实现（避免 import dart:math 到每个文件）
double _dartSin(double x) {
  // 归一化到 [0, 2π)
  x = x % (2 * 3.141592653589793);
  if (x < 0) x += 2 * 3.141592653589793;
  // 泰勒展开（精度足够 UI 动画用）
  final x2 = x * x;
  final x3 = x2 * x;
  final x5 = x3 * x2;
  final x7 = x5 * x2;
  if (x <= 3.141592653589793 / 2) {
    return x - x3 / 6 + x5 / 120 - x7 / 5040;
  } else if (x <= 3.141592653589793) {
    final y = 3.141592653589793 - x;
    final y3 = y * y * y;
    final y5 = y3 * y * y;
    return y - y3 / 6 + y5 / 120;
  } else if (x <= 3 * 3.141592653589793 / 2) {
    final y = x - 3.141592653589793;
    final y3 = y * y * y;
    final y5 = y3 * y * y;
    return -(y - y3 / 6 + y5 / 120);
  } else {
    final y = 2 * 3.141592653589793 - x;
    final y3 = y * y * y;
    final y5 = y3 * y * y;
    return -(y - y3 / 6 + y5 / 120);
  }
}

double _dartCos(double x) {
  return _dartSin(x + 3.141592653589793 / 2);
}
