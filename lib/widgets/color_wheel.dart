// color_wheel.dart — HSL 色轮 + 主色标注
//
// CustomPainter 绘制色轮圆盘，主色以圆点标注，连线显示色彩关系
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/harmony_service.dart';

/// 色轮 + 主色标注组件
class ColorWheel extends StatelessWidget {
  final HarmonyResult result;

  const ColorWheel({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ColorWheelPainter(hues: result.hues),
      size: const Size.square(180),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final List<int> hues;

  _ColorWheelPainter({required this.hues});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 绘制色轮（360 扇形）
    const segments = 120;
    final sweep = 2 * math.pi / segments;

    for (var i = 0; i < segments; i++) {
      final hue = (i / segments) * 360;
      final color = HSLColor.fromAHSL(1.0, hue, 0.7, 0.5).toColor();

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          i * sweep - math.pi / 2,
          sweep + 0.01, // 微重叠避免缝隙
          false,
        )
        ..close();

      canvas.drawPath(path, paint);
    }

    // 中心白圆（让色轮变成环形）
    canvas.drawCircle(
      center,
      radius * 0.35,
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..style = PaintingStyle.fill,
    );

    // 绘制主色点
    if (hues.isEmpty) return;

    final dotRadius = radius * 0.72;
    final points = <Offset>[];

    for (final hue in hues) {
      final angle = (hue / 360) * 2 * math.pi - math.pi / 2;
      final dx = center.dx + math.cos(angle) * dotRadius;
      final dy = center.dy + math.sin(angle) * dotRadius;
      final point = Offset(dx, dy);
      points.add(point);

      // 主色点
      final color = HSLColor.fromAHSL(1.0, hue.toDouble(), 0.8, 0.6).toColor();
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      // 白色描边
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    // 连线（显示色彩关系）
    if (points.length >= 2) {
      for (var i = 0; i < points.length - 1; i++) {
        canvas.drawLine(
          points[i],
          points[i + 1],
          Paint()
            ..color = Colors.white.withValues(alpha: 0.4)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.hues != hues;
  }
}
