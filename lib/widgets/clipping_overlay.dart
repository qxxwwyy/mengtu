// clipping_overlay.dart — Clipping 警告叠加层
//
// 在图片上高亮显示死黑（蓝色）和过曝（红色）区域
import 'package:flutter/material.dart';
import '../services/clipping_service.dart';

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
    ..color = Colors.blue.withValues(alpha: 0.4)
    ..style = PaintingStyle.fill;

  // 亮部 clipping 颜色（红色半透明）
  static final _brightPaint = Paint()
    ..color = Colors.red.withValues(alpha: 0.4)
    ..style = PaintingStyle.fill;

  _ClippingPainter({required this.result});

  @override
  void paint(Canvas canvas, Size size) {
    if (!result.hasAnyClipping) return;

    // 计算图片在容器中的实际位置和尺寸（BoxFit.contain）
    final imageAspect = result.width / result.height;
    final containerAspect = size.width / size.height;

    double drawWidth, drawHeight, offsetX, offsetY;

    if (imageAspect > containerAspect) {
      // 图片更宽，以宽度为准
      drawWidth = size.width;
      drawHeight = size.width / imageAspect;
      offsetX = 0;
      offsetY = (size.height - drawHeight) / 2;
    } else {
      // 图片更高，以高度为准
      drawHeight = size.height;
      drawWidth = size.height * imageAspect;
      offsetX = (size.width - drawWidth) / 2;
      offsetY = 0;
    }

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

/// Clipping 状态栏（显示暗部/亮部占比）
class ClippingStatusBar extends StatelessWidget {
  final ClippingResult result;

  const ClippingStatusBar({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    if (!result.hasAnyClipping) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result.hasDarkClipping) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '暗部 ${(result.darkRatio * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
          if (result.hasDarkClipping && result.hasBrightClipping)
            const SizedBox(width: 12),
          if (result.hasBrightClipping) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '亮部 ${(result.brightRatio * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
