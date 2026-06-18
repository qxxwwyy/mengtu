// sharpness_overlay.dart — 峰值对焦蒙层（v3.0 阶段二）
//
// 在原图上叠加合焦边缘发光图层，类似相机的 Focus Peaking：
// - 拉普拉斯响应强的像素（合焦区域）→ 亮色高亮（默认青绿色）
// - 响应弱的像素（虚化区域）→ 透明，不遮挡原图
//
// 渲染策略：
// - 用 CustomPainter + Paint(PaintingStyle.fill) 把降采样矩阵（240×160）
//   拉伸到画布尺寸，由 GPU 一次性完成纹理绘制，保证 60fps/120fps 缩放流畅
// - 高响应区做发光叠加（多层 alpha 渐变），模拟峰值对焦的霓虹感
//
// 颜色方案：经典峰值对焦配色
// - 强响应（>0.6）→ 红色（焦点）
// - 中响应（0.3~0.6）→ 绿色（清晰边缘）
// - 弱响应（<0.3）→ 不绘制
import 'package:flutter/material.dart';
import '../services/sharpness_service.dart';

/// 峰值对焦蒙层组件
class SharpnessOverlay extends StatelessWidget {
  final SharpnessMap map;

  /// 强响应阈值（>该值绘制红色焦点）
  final double strongThreshold;

  /// 中响应阈值（>该值绘制绿色边缘）
  final double midThreshold;

  const SharpnessOverlay({
    super.key,
    required this.map,
    this.strongThreshold = 0.6,
    this.midThreshold = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 蒙层不拦截手势，让 InteractiveViewer 的缩放/平移正常工作
      child: CustomPaint(
        painter: _SharpnessPainter(
          map: map,
          strongThreshold: strongThreshold,
          midThreshold: midThreshold,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SharpnessPainter extends CustomPainter {
  final SharpnessMap map;
  final double strongThreshold;
  final double midThreshold;

  _SharpnessPainter({
    required this.map,
    required this.strongThreshold,
    required this.midThreshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (map.cols == 0 || map.rows == 0) return;

    final cellW = size.width / map.cols;
    final cellH = size.height / map.rows;

    // 用 Path 批量绘制同色单元格，减少 draw call
    // 强响应（红色）和中响应（绿色）分别一个 Paint + Path
    final strongPath = Path();
    final midPath = Path();

    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        final v = map.at(x, y);
        if (v < midThreshold) continue;
        final rect = Rect.fromLTWH(
          x * cellW,
          y * cellH,
          cellW + 0.5, // +0.5 防缝隙
          cellH + 0.5,
        );
        if (v >= strongThreshold) {
          strongPath.addRect(rect);
        } else {
          midPath.addRect(rect);
        }
      }
    }

    // 中响应：绿色半透明（清晰边缘）
    if (midPath.getBounds().width > 0) {
      canvas.drawPath(
        midPath,
        Paint()
          ..color = const Color(0xFF00FF66).withValues(alpha: 0.45)
          ..style = PaintingStyle.fill
          ..blendMode = BlendMode.screen, // 叠加发光感
      );
    }

    // 强响应：亮红色不透明（核心焦点）
    if (strongPath.getBounds().width > 0) {
      canvas.drawPath(
        strongPath,
        Paint()
          ..color = const Color(0xFFFF3030).withValues(alpha: 0.75)
          ..style = PaintingStyle.fill
          ..blendMode = BlendMode.screen,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SharpnessPainter oldDelegate) {
    return oldDelegate.map != map ||
        oldDelegate.strongThreshold != strongThreshold ||
        oldDelegate.midThreshold != midThreshold;
  }
}
