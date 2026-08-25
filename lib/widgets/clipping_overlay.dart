// clipping_overlay.dart — Clipping 警告叠加层
//
// 在图片上高亮显示死黑（蓝色）和过曝（红色）区域
import 'package:flutter/material.dart';
import '../services/clipping_service.dart';
import '../utils/letterbox.dart';
import '../theme/app_theme.dart';

/// Clipping 警告叠加层
class ClippingOverlay extends StatelessWidget {
  final ClippingResult result;
  final BoxFit fit;

  const ClippingOverlay({
    super.key,
    required this.result,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ClippingPainter(result: result),
      size: Size.infinite,
    );
  }
}

class _ClippingPainter extends CustomPainter {
  final ClippingResult result;

  // 暗部 clipping 颜色（蓝色半透明）
  static final _darkPaint = Paint()
    ..color = DetailColors.accent.withValues(alpha: 0.4)
    ..style = PaintingStyle.fill;

  // 亮部 clipping 颜色（红色半透明）
  static final _brightPaint = Paint()
    ..color = DetailColors.warning.withValues(alpha: 0.4)
    ..style = PaintingStyle.fill;

  _ClippingPainter({required this.result});

  @override
  void paint(Canvas canvas, Size size) {
    if (!result.hasAnyClipping) return;

    // 图片实际显示矩形（letterbox 统一计算，utils/letterbox.dart）
    final rect = imageRectInContainer(size, result.width / result.height);
    final drawWidth = rect.width;
    final drawHeight = rect.height;
    final offsetX = rect.left;
    final offsetY = rect.top;

    // 绘制暗部 clipping 点
    if (result.hasDarkClipping) {
      for (final point in result.darkPoints) {
        final x = offsetX + point.dx * drawWidth;
        final y = offsetY + point.dy * drawHeight;
        // 绘制小方块（3x3 像素）
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, y), width: 3, height: 3),
          _darkPaint,
        );
      }
    }

    // 绘制亮部 clipping 点
    if (result.hasBrightClipping) {
      for (final point in result.brightPoints) {
        final x = offsetX + point.dx * drawWidth;
        final y = offsetY + point.dy * drawHeight;
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, y), width: 3, height: 3),
          _brightPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ClippingPainter oldDelegate) {
    return oldDelegate.result != result;
  }
}
