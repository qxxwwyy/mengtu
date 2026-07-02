// animated_number.dart — 数字滚动动画组件
//
// 数字变化时平滑过渡（TweenAnimationBuilder + int 插值）。
// 用于统计数字、计数器等场景。
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 数字滚动动画 Widget
///
/// 当 [value] 变化时，数字从旧值平滑滚动到新值。
///
/// 用法：
/// ```dart
/// AnimatedNumber(value: photoCount, style: AppTypography.dataXl)
/// ```
class AnimatedNumber extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;

  const AnimatedNumber({
    super.key,
    required this.value,
    this.style,
    this.duration = AppAnimations.chartEnterDuration,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: AppAnimations.chartEnterCurve,
      builder: (context, val, _) {
        return Text(
          '$val',
          style: style ?? AppTypography.dataXl,
        );
      },
    );
  }
}
