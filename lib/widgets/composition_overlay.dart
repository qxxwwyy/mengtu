// composition_overlay.dart — 构图参考线叠加层
//
// 九宫格、黄金螺旋、对角线三种构图辅助模式
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 构图模式
enum CompositionMode {
  none, // 关闭
  thirds, // 九宫格（三分法）
  golden, // 黄金螺旋
  diagonals, // 对角线
}

/// 构图参考线叠加层
class CompositionOverlay extends StatelessWidget {
  final CompositionMode mode;

  const CompositionOverlay({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    if (mode == CompositionMode.none) return const SizedBox.shrink();

    return IgnorePointer(
      child: CustomPaint(
        painter: _CompositionPainter(mode: mode),
        size: Size.infinite,
      ),
    );
  }
}

class _CompositionPainter extends CustomPainter {
  final CompositionMode mode;

  static final _linePaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.3)
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  static final _pointPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;

  static final _spiralPaint = Paint()
    ..color = Colors.amber.withValues(alpha: 0.3)
    ..strokeWidth = 0.8
    ..style = PaintingStyle.stroke;

  _CompositionPainter({required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    switch (mode) {
      case CompositionMode.thirds:
        _drawThirds(canvas, size);
        break;
      case CompositionMode.golden:
        _drawGoldenSpiral(canvas, size);
        break;
      case CompositionMode.diagonals:
        _drawDiagonals(canvas, size);
        break;
      case CompositionMode.none:
        break;
    }
  }

  /// 绘制九宫格（三分法）
  void _drawThirds(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 竖线（1/3 和 2/3）
    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), _linePaint);
    canvas.drawLine(Offset(2 * w / 3, 0), Offset(2 * w / 3, h), _linePaint);

    // 横线（1/3 和 2/3）
    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), _linePaint);
    canvas.drawLine(Offset(0, 2 * h / 3), Offset(w, 2 * h / 3), _linePaint);

    // 交叉点圆点
    final points = [
      Offset(w / 3, h / 3),
      Offset(2 * w / 3, h / 3),
      Offset(w / 3, 2 * h / 3),
      Offset(2 * w / 3, 2 * h / 3),
    ];
    for (final p in points) {
      canvas.drawCircle(p, 3, _pointPaint);
    }
  }

  /// 绘制黄金螺旋
  void _drawGoldenSpiral(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const phi = 1.618033988749895; // 黄金比例

    // 黄金分割线
    final gx1 = w / phi;
    final gx2 = w - gx1;
    final gy1 = h / phi;
    final gy2 = h - gy1;

    // 竖线
    canvas.drawLine(Offset(gx1, 0), Offset(gx1, h), _linePaint);
    canvas.drawLine(Offset(gx2, 0), Offset(gx2, h), _linePaint);

    // 横线
    canvas.drawLine(Offset(0, gy1), Offset(w, gy1), _linePaint);
    canvas.drawLine(Offset(0, gy2), Offset(w, gy2), _linePaint);

    // 黄金螺旋曲线（简化版：用贝塞尔曲线近似）
    final path = Path();
    path.moveTo(w, 0);

    // 绘制斐波那契矩形内的螺旋
    _drawSpiralSegment(canvas, path, w, h, 0, 0, w, h, 8);

    canvas.drawPath(path, _spiralPaint);
  }

  /// 递归绘制螺旋线段
  void _drawSpiralSegment(Canvas canvas, Path path, double w, double h,
      double x, double y, double rectW, double rectH, int depth) {
    if (depth <= 0 || rectW < 2 || rectH < 2) return;

    const phi = 1.618033988749895;

    // 根据矩形方向决定分割方式
    if (rectW >= rectH) {
      // 水平矩形，竖向分割
      final splitW = rectW / phi;
      // 绘制弧线
      path.arcTo(
        Rect.fromLTWH(x + splitW - rectH, y, rectH, rectH),
        -math.pi / 2,
        math.pi / 2,
        false,
      );
      _drawSpiralSegment(
          canvas, path, w, h, x, y, splitW, rectH, depth - 1);
    } else {
      // 垂直矩形，横向分割
      final splitH = rectH / phi;
      path.arcTo(
        Rect.fromLTWH(x, y + splitH - rectW, rectW, rectW),
        0,
        math.pi / 2,
        false,
      );
      _drawSpiralSegment(
          canvas, path, w, h, x, y, rectW, splitH, depth - 1);
    }
  }

  /// 绘制对角线
  void _drawDiagonals(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 主对角线
    canvas.drawLine(Offset(0, 0), Offset(w, h), _linePaint);
    canvas.drawLine(Offset(w, 0), Offset(0, h), _linePaint);

    // 垂直对角线（从边中点到对角）
    canvas.drawLine(Offset(w / 2, 0), Offset(0, h), _linePaint);
    canvas.drawLine(Offset(w / 2, 0), Offset(w, h), _linePaint);
    canvas.drawLine(Offset(0, h / 2), Offset(w, 0), _linePaint);
    canvas.drawLine(Offset(0, h / 2), Offset(w, h), _linePaint);
    canvas.drawLine(Offset(w, h / 2), Offset(0, 0), _linePaint);
    canvas.drawLine(Offset(w, h / 2), Offset(w, 0), _linePaint);
  }

  @override
  bool shouldRepaint(covariant _CompositionPainter oldDelegate) {
    return oldDelegate.mode != mode;
  }
}
