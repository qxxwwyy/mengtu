// sharpness_overlay.dart — 峰值对焦（Focus Peaking）发光蒙层（v6.0 恢复）
//
// 把拉普拉斯边缘响应（SharpnessMap.response）按发光叠加（BlendMode.screen）
// 渲染到图片上：合焦区域边缘「发光」、虚化区域不亮 —— 与专业相机的
// Focus Peaking / Focus Assist 同款视觉，让用户一眼看出焦点落在哪。
//
// 颜色策略：弱响应（背景虚化）→ 不画；中响应 → 暖橙；强响应（合焦）→ 青绿，
// 形成与背景的冷暖对比，避免单一绿色在全画面发亮时刺眼。
//
// 关键约束（gotcha #45）：本蒙层表达的是【照片像素属性】（合焦/虚化），
// 必须挂在 InteractiveViewer 内部，与 Image 共享缩放/平移变换，否则放大检查
// 时发光斑点会错位。letterbox 计算与 ClippingOverlay 一致。
import 'package:flutter/material.dart';
import '../services/sharpness_service.dart';

/// 峰值对焦发光蒙层
class SharpnessOverlay extends StatelessWidget {
  final SharpnessMap map;

  /// 响应阈值：低于此值的边缘不绘制（默认 0.18，过滤虚化区的弱噪声）
  final double threshold;

  const SharpnessOverlay({
    super.key,
    required this.map,
    this.threshold = 0.18,
  });

  @override
  Widget build(BuildContext context) {
    if (map.cols == 0 || map.rows == 0) return const SizedBox.shrink();
    return CustomPaint(
      painter: _SharpnessPainter(map: map, threshold: threshold),
      size: Size.infinite,
    );
  }
}

class _SharpnessPainter extends CustomPainter {
  final SharpnessMap map;
  final double threshold;

  _SharpnessPainter({required this.map, required this.threshold});

  @override
  void paint(Canvas canvas, Size size) {
    final imageAspect = map.aspectRatio;
    final containerAspect = size.width / size.height;

    // BoxFit.contain letterbox（与 ClippingOverlay 同款）
    double drawWidth, drawHeight, offsetX, offsetY;
    if (imageAspect > containerAspect) {
      drawWidth = size.width;
      drawHeight = size.width / imageAspect;
      offsetX = 0;
      offsetY = (size.height - drawHeight) / 2;
    } else {
      drawHeight = size.height;
      drawWidth = size.height * imageAspect;
      offsetX = (size.width - drawWidth) / 2;
      offsetY = 0;
    }

    // 平移到图片矩形，按图片区域画格子（与 Image 像素对齐）
    canvas.save();
    canvas.translate(offsetX, offsetY);

    final cellW = drawWidth / map.cols;
    final cellH = drawHeight / map.rows;

    // 复用单个 Paint（热路径：480×320 ≈ 15 万格子）
    final paint = Paint()..style = PaintingStyle.fill;
    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        final v = map.at(x, y);
        if (v < threshold) continue;
        // 响应越强越亮：t∈[0,1] 把阈值以上的部分线性映射到 [0,1]
        final t = ((v - threshold) / (1 - threshold)).clamp(0.0, 1.0);
        // 颜色：弱→暖橙（accent），强→青绿，中→黄绿过渡
        // 用 alpha 表达强度，BlendMode.screen 叠加发光
        paint.color = _colorForResponse(t);
        canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }
    canvas.restore();
  }

  /// 按归一化响应强度 t∈[0,1] 取色（带 alpha，配合 BlendMode.screen 发光）
  Color _colorForResponse(double t) {
    // 低于阈值的部分已被过滤；t∈[0,1] 线性映射亮度与不透明度
    // 暖橙(255,177,66) → 青绿(0,230,118)
    final r = (255 * (1 - t) + 0 * t).round();
    final g = (177 * (1 - t) + 230 * t).round();
    final b = (66 * (1 - t) + 118 * t).round();
    // alpha：t=0 → 60，t=1 → 200（强响应更醒目，弱响应不刺眼）
    final alpha = (60 + 140 * t).round();
    return Color.fromARGB(alpha, r, g, b);
  }

  @override
  bool shouldRepaint(covariant _SharpnessPainter oldDelegate) =>
      oldDelegate.map != map || oldDelegate.threshold != threshold;
}
