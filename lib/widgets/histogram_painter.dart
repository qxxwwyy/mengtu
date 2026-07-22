// histogram_painter.dart — 直方图 CustomPainter（暗房专业美学 v2）
//
// v1.0.0: 色相直方图模式（360 bins，彩虹色条）
// v1.1.0: ACR 风格标注（五段分界 + 溢出三角 + RGB+亮度叠加）
// v2.0.0: 渐变填充 + cubicTo 平滑曲线 + 网格线 + 入场动画
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/tone_result.dart';
import '../theme/app_theme.dart';

/// 直方图显示模式
enum HistogramMode { rgb, luminance, r, g, b, hue, rgbLum }

/// 直方图 CustomPainter（暗房专业美学 v2）
///
/// v2 改进：
/// - 填充改为渐变（通道色 → 透明），不是纯色块
/// - 曲线用 Path + quadraticCurveTo 平滑（逐点连线改为平滑曲线）
/// - 底部加细网格线（5 档：0/25/50/75/100%）
/// - 入场动画支持（progress 参数，从底部生长）
class HistogramPainter extends CustomPainter {
  final HistogramData data;
  final HistogramMode mode;
  final List<int>? colorPinHues;
  /// 入场动画进度 0.0~1.0（1.0 = 动画完成）。默认 1.0 向后兼容。
  final double progress;

  HistogramPainter({
    required this.data,
    this.mode = HistogramMode.rgb,
    this.colorPinHues,
    this.progress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    // 入场动画缩放系数（从底部生长）
    final grow = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final drawH = h * grow;

    if (mode == HistogramMode.hue) {
      _drawHueHistogram(canvas, size, drawH);
      _drawColorPinMarkers(canvas, size);
      _drawGridLines(canvas, size);
      _drawBorder(canvas, size);
      return;
    }

    final w = size.width;
    final barWidth = w / 256;

    // 绘制网格线（背景层）
    _drawGridLines(canvas, size);

    // 绘制直方图内容
    switch (mode) {
      case HistogramMode.rgb:
        _drawChannelGradient(canvas, size, drawH, data.r, ChartColors.channelR, barWidth);
        _drawChannelGradient(canvas, size, drawH, data.g, ChartColors.channelG, barWidth);
        _drawChannelGradient(canvas, size, drawH, data.b, ChartColors.channelB, barWidth);
        break;
      case HistogramMode.rgbLum:
        _drawChannelGradient(canvas, size, drawH, data.r, ChartColors.channelR, barWidth);
        _drawChannelGradient(canvas, size, drawH, data.g, ChartColors.channelG, barWidth);
        _drawChannelGradient(canvas, size, drawH, data.b, ChartColors.channelB, barWidth);
        _drawLuminanceOverlay(canvas, size, drawH, barWidth);
        break;
      case HistogramMode.luminance:
        _drawChannelGradient(canvas, size, drawH, data.lum, ChartColors.channelLum, barWidth);
        break;
      case HistogramMode.r:
        _drawChannelGradient(canvas, size, drawH, data.r, ChartColors.channelR, barWidth, solid: true);
        break;
      case HistogramMode.g:
        _drawChannelGradient(canvas, size, drawH, data.g, ChartColors.channelG, barWidth, solid: true);
        break;
      case HistogramMode.b:
        _drawChannelGradient(canvas, size, drawH, data.b, ChartColors.channelB, barWidth, solid: true);
        break;
      case HistogramMode.hue:
        break; // handled above
    }

    // 绘制五段分界线
    _drawZoneDividers(canvas, size);

    // 绘制溢出三角
    _drawOverflowTriangles(canvas, size);

    _drawBorder(canvas, size);
  }

  /// 绘制背景网格线（5 档垂直线：0/25/50/75/100%）
  void _drawGridLines(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = ChartColors.gridFaint
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (var i = 1; i < 4; i++) {
      final x = w * (i / 4);
      canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
    }
  }

  /// 绘制单通道（渐变填充 + 平滑曲线）
  ///
  /// [color] 通道色，[solid] 为 true 时不透明（单通道模式）
  void _drawChannelGradient(
    Canvas canvas,
    Size size,
    double drawH,
    List<int> channel,
    Color color,
    double barWidth, {
    bool solid = false,
  }) {
    // m3 修复：空 list 上 reduce 会抛 StateError: No element。守卫先判空。
    if (channel.isEmpty) return;
    final maxVal = channel.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final w = size.width;
    final baseY = size.height; // 始终从画布底部开始（入场动画用 drawH 控制柱高）

    // 构建平滑路径
    final path = Path();
    path.moveTo(0, baseY);

    final points = <Offset>[];
    for (var i = 0; i < 256; i++) {
      final x = i * barWidth;
      final y = baseY - (channel[i] / maxVal) * drawH;
      points.add(Offset(x, y));
    }

    // 用 quadraticCurveTo 平滑连接（每两个点之间用中点做控制点）
    if (points.length >= 2) {
      path.lineTo(points[0].dx, points[0].dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final curr = points[i];
        final midX = (prev.dx + curr.dx) / 2;
        final midY = (prev.dy + curr.dy) / 2;
        path.quadraticBezierTo(prev.dx, prev.dy, midX, midY);
      }
      path.lineTo(points.last.dx, points.last.dy);
    }

    path.lineTo(w, baseY);
    path.close();

    // 渐变填充（通道色 → 透明，从上到下）
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withValues(alpha: solid ? 0.9 : 0.55),
        color.withValues(alpha: solid ? 0.4 : 0.15),
      ],
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);

    // 顶部描边（线条色，增加清晰度）
    final strokePath = Path();
    if (points.isNotEmpty) {
      strokePath.moveTo(points[0].dx, points[0].dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final curr = points[i];
        final midX = (prev.dx + curr.dx) / 2;
        final midY = (prev.dy + curr.dy) / 2;
        strokePath.quadraticBezierTo(prev.dx, prev.dy, midX, midY);
      }
      strokePath.lineTo(points.last.dx, points.last.dy);
    }
    final strokePaint = Paint()
      ..color = color.withValues(alpha: solid ? 1.0 : 0.8)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(strokePath, strokePaint);
  }

  /// 绘制色相直方图（彩虹色填充）
  void _drawHueHistogram(Canvas canvas, Size size, double drawH) {
    final hue = data.hue;
    if (hue == null || hue.isEmpty) return;

    final maxVal = hue.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final w = size.width;
    final baseY = size.height;
    final barWidth = w / 360;

    for (var i = 0; i < 360; i++) {
      if (hue[i] == 0) continue;
      final x = i * barWidth;
      final barHeight = (hue[i] / maxVal) * drawH;
      canvas.drawRect(
        Rect.fromLTWH(x, baseY - barHeight, barWidth + 0.5, barHeight),
        _huePaints[i],
      );
    }
  }

  /// 绘制亮度叠加曲线（半透明白色描边）
  void _drawLuminanceOverlay(
      Canvas canvas, Size size, double drawH, double barWidth) {
    final lum = data.lum;
    // m3 修复：守卫空 list（与 _drawChannelGradient 同源防 reduce 崩溃）
    if (lum.isEmpty) return;
    final maxVal = lum.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final baseY = size.height;
    final path = Path();
    path.moveTo(0, baseY);

    for (var i = 0; i < 256; i++) {
      final x = i * barWidth;
      final y = baseY - (lum[i] / maxVal) * drawH;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, baseY);
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = ChartColors.gridLight
        ..style = PaintingStyle.fill,
    );
  }

  /// 绘制五段分界线（黑色/阴影/中间调/高光/白色）
  void _drawZoneDividers(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    const dividers = [51, 102, 153, 204];
    for (final d in dividers) {
      final x = w * (d / 256);
      _drawDashedLine(
        canvas,
        Offset(x, 0),
        Offset(x, h),
        Paint()
          ..color = ChartColors.gridLight
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke,
      );
    }

    // 底部标签（五段居中）
    // m4 修复：原用 text.length * 8.0 魔数估算宽度，中文每字 ≈ fontSize
    // 而非 8px，导致五段标签居中偏移。改用 TextPainter 拿真实宽度。
    const labels = ['黑色', '阴影', '中间调', '高光', '白色'];
    const centers = [25, 76, 128, 179, 230];
    for (var i = 0; i < labels.length; i++) {
      final cx = w * (centers[i] / 256);
      final text = labels[i];
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 8)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, h - 10));
    }
  }

  /// 绘制溢出三角（左上角=纯黑，右上角=纯白）
  void _drawOverflowTriangles(Canvas canvas, Size size) {
    final w = size.width;
    // m3 修复：守卫空 list（data.lum 异常为空时防 reduce 崩溃）
    if (data.lum.isEmpty) return;
    final totalPixels = data.lum.reduce((a, b) => a + b);
    if (totalPixels == 0) return;

    final blackRatio = data.lum[0] / totalPixels;
    final whiteRatio = data.lum[255] / totalPixels;

    const triSize = 10.0;
    const threshold = 0.01;

    final blackPaint = Paint()
      ..color = blackRatio > threshold
          ? StatusColors.error.withValues(alpha: 0.8)
          : ChartColors.gridLight
      ..style = PaintingStyle.fill;
    final blackPath = Path()
      ..moveTo(0, 0)
      ..lineTo(triSize, 0)
      ..lineTo(0, triSize)
      ..close();
    canvas.drawPath(blackPath, blackPaint);

    final whitePaint = Paint()
      ..color = whiteRatio > threshold
          ? StatusColors.error.withValues(alpha: 0.8)
          : ChartColors.gridLight
      ..style = PaintingStyle.fill;
    final whitePath = Path()
      ..moveTo(w, 0)
      ..lineTo(w - triSize, 0)
      ..lineTo(w, triSize)
      ..close();
    canvas.drawPath(whitePath, whitePaint);
  }

  /// 绘制取色点色相标记（色相模式下）
  void _drawColorPinMarkers(Canvas canvas, Size size) {
    if (colorPinHues == null || colorPinHues!.isEmpty) return;

    final w = size.width;
    final h = size.height;
    final barWidth = w / 360;

    for (final hue in colorPinHues!) {
      final x = (hue + 0.5) * barWidth;
      final markerPaint = Paint()
        ..color = HSLColor.fromAHSL(1.0, hue.toDouble(), 0.8, 0.6).toColor()
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(x, 0), Offset(x, h), markerPaint);

      final triPath = Path()
        ..moveTo(x - 3, 0)
        ..lineTo(x + 3, 0)
        ..lineTo(x, 5)
        ..close();
      canvas.drawPath(
        triPath,
        Paint()
          ..color = markerPaint.color
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawBorder(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = ChartColors.gridFaint
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke,
    );
  }

  /// 绘制虚线
  void _drawDashedLine(
      Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 3.0;
    const dashSpace = 2.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = dx * dx + dy * dy;
    final len = length > 0 ? math.sqrt(length) : 0.0;
    if (len == 0) return;

    final unitDx = dx / len;
    final unitDy = dy / len;
    var distance = 0.0;

    while (distance < len) {
      final x1 = start.dx + unitDx * distance;
      final y1 = start.dy + unitDy * distance;
      distance += dashWidth;
      final x2 = start.dx + unitDx * distance.clamp(0, len);
      final y2 = start.dy + unitDy * distance.clamp(0, len);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
      distance += dashSpace;
    }
  }

  // v3.2 性能优化：色相直方图 360 个 bin 的颜色 Paint 预生成。
  static final List<Paint> _huePaints = List.generate(
    360,
    (i) => Paint()
      ..color = HSLColor.fromAHSL(1.0, i.toDouble(), 0.7, 0.5).toColor()
      ..style = PaintingStyle.fill,
  );

  @override
  bool shouldRepaint(covariant HistogramPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.mode != mode ||
        oldDelegate.colorPinHues != colorPinHues ||
        oldDelegate.progress != progress;
  }
}
