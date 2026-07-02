// color_wheel.dart — HSL 色轮 + 主色标注（暗房专业美学 v2）
//
// v2.0.0: SweepGradient 替代扇形拼接（零锯齿）+ 径向渐变 + 发光主色点 + 刻度标注
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/harmony_service.dart';
import '../theme/app_theme.dart';
import 'charts/chart_animations.dart';

/// 色轮 + 主色标注组件
class ColorWheel extends StatelessWidget {
  final HarmonyResult result;

  const ColorWheel({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return ChartEnterBuilder(
      builder: (context, progress) => CustomPaint(
        painter: _ColorWheelPainter(hues: result.hues, progress: progress),
        size: const Size.square(180),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final List<int> hues;
  final double progress;

  _ColorWheelPainter({
    required this.hues,
    this.progress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final p = (progress).clamp(0.0, 1.0);

    // 1. 色轮圆盘 — SweepGradient（零锯齿）
    _drawWheel(canvas, center, radius * p);

    // 2. 径向亮度渐变叠加（外圈饱和 → 中心灰）
    _drawRadialFade(canvas, center, radius * p);

    // 3. 中心暗圆（让色轮变成环形 + 放置标签）
    final innerR = radius * 0.32 * p;
    canvas.drawCircle(
      center,
      innerR,
      Paint()..color = AppColors.bgBase,
    );
    // 中心圆描边
    canvas.drawCircle(
      center,
      innerR,
      Paint()
        ..color = ChartColors.gridLight
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke,
    );

    // 4. 外圈刻度（6 个色相方位）
    if (p > 0.8) {
      _drawTickMarks(canvas, center, radius);
    }

    // 5. 主色点
    if (hues.isEmpty || p < 0.5) return;

    final dotRadius = radius * 0.72 * p;
    final points = <_HuePoint>[];

    for (final hue in hues) {
      final angle = (hue / 360) * 2 * math.pi - math.pi / 2;
      final dx = center.dx + math.cos(angle) * dotRadius;
      final dy = center.dy + math.sin(angle) * dotRadius;
      points.add(_HuePoint(Offset(dx, dy), hue));
    }

    // 5a. 配色关系连线（多边形）
    if (points.length >= 2) {
      final linePath = Path();
      linePath.moveTo(points[0].pos.dx, points[0].pos.dy);
      for (var i = 1; i < points.length; i++) {
        linePath.lineTo(points[i].pos.dx, points[i].pos.dy);
      }
      if (points.length >= 3) linePath.close();
      canvas.drawPath(
        linePath,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.3)
          ..strokeWidth = 1.5
          ..style = points.length >= 3
              ? PaintingStyle.fill
              : PaintingStyle.stroke,
      );
      // 描边
      canvas.drawPath(
        linePath,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.8)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    // 5b. 发光主色点
    for (final hp in points) {
      final color =
          HSLColor.fromAHSL(1.0, hp.hue.toDouble(), 0.8, 0.6).toColor();
      // 外晕
      canvas.drawCircle(
        hp.pos,
        10,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
      // 主色点
      canvas.drawCircle(
        hp.pos,
        6,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      // 白色描边
      canvas.drawCircle(
        hp.pos,
        6,
        Paint()
          ..color = DetailColors.textPrimary
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  /// 用 SweepGradient 绘制零锯齿色轮
  void _drawWheel(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = SweepGradient(
      colors: List.generate(
        13,
        (i) => HSLColor.fromAHSL(1.0, (i * 30).toDouble(), 1.0, 0.5).toColor(),
      ),
    );
    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..shader = sweep.createShader(rect)
        ..style = PaintingStyle.fill,
    );
  }

  /// 径向渐变叠加（外圈饱和 → 中心灰）
  void _drawRadialFade(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final radial = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.4),
      ],
      stops: const [0.0, 0.3, 1.0],
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = radial.createShader(rect)
        ..style = PaintingStyle.fill,
      // 用 BlendMode 让中心变灰
    );
  }

  /// 外圈刻度（R/Yl/G/Cy/B/Mg 六色方位）
  void _drawTickMarks(Canvas canvas, Offset center, double radius) {
    const labels = ['R', 'Y', 'G', 'Cy', 'B', 'Mg'];
    for (var i = 0; i < 6; i++) {
      final angle = (i * 60 - 90) * math.pi / 180;
      final dx = center.dx + math.cos(angle) * (radius + 8);
      final dy = center.dy + math.sin(angle) * (radius + 8);

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(dx - tp.width / 2, dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.hues != hues || oldDelegate.progress != progress;
  }
}

/// 主色点位置 + 色相值
class _HuePoint {
  final Offset pos;
  final int hue;
  _HuePoint(this.pos, this.hue);
}
