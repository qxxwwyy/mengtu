// histogram_painter.dart — 直方图 CustomPainter
//
// v1.0.0: 色相直方图模式（360 bins，彩虹色条）
// v1.1.0: ACR 风格标注（五段分界 + 溢出三角 + RGB+亮度叠加）
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/tone_result.dart';

/// 直方图显示模式
enum HistogramMode { rgb, luminance, r, g, b, hue, rgbLum }

/// 直方图 CustomPainter
class HistogramPainter extends CustomPainter {
  final HistogramData data;
  final HistogramMode mode;
  final List<int>? colorPinHues; // 取色点的色相值（用于联动标注）

  // 性能优化：Paint 对象声明为 static final
  static final _redPaint = Paint()
    ..color = Colors.red.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;
  static final _greenPaint = Paint()
    ..color = Colors.green.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;
  static final _bluePaint = Paint()
    ..color = Colors.blue.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;
  static final _lumPaint = Paint()
    ..color = Color(0xFF3A3A3A)
    ..style = PaintingStyle.fill;
  static final _solidRedPaint = Paint()
    ..color = Colors.red
    ..style = PaintingStyle.fill;
  static final _solidGreenPaint = Paint()
    ..color = Colors.green
    ..style = PaintingStyle.fill;
  static final _solidBluePaint = Paint()
    ..color = Colors.blue
    ..style = PaintingStyle.fill;
  static final _borderPaint = Paint()
    ..color = Colors.white24
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  // 五段分界线 Paint
  static final _dividerPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.2)
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  // 溢出三角 Paint
  static final _overflowNormalPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.3)
    ..style = PaintingStyle.fill;
  static final _overflowWarningPaint = Paint()
    ..color = Colors.red.withValues(alpha: 0.8)
    ..style = PaintingStyle.fill;

  // 标签文字样式
  static const _labelStyle = TextStyle(
    color: Colors.white54,
    fontSize: 8,
  );

  HistogramPainter({
    required this.data,
    this.mode = HistogramMode.rgb,
    this.colorPinHues,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == HistogramMode.hue) {
      _drawHueHistogram(canvas, size);
      _drawColorPinMarkers(canvas, size);
      canvas.drawRect(Offset.zero & size, _borderPaint);
      return;
    }

    final w = size.width;
    final barWidth = w / 256;

    // 绘制直方图内容
    switch (mode) {
      case HistogramMode.rgb:
        _drawChannel(canvas, size, data.r, _redPaint, barWidth);
        _drawChannel(canvas, size, data.g, _greenPaint, barWidth);
        _drawChannel(canvas, size, data.b, _bluePaint, barWidth);
        break;
      case HistogramMode.rgbLum:
        // RGB 三通道叠加 + 亮度曲线叠加
        _drawChannel(canvas, size, data.r, _redPaint, barWidth);
        _drawChannel(canvas, size, data.g, _greenPaint, barWidth);
        _drawChannel(canvas, size, data.b, _bluePaint, barWidth);
        _drawLuminanceOverlay(canvas, size, barWidth);
        break;
      case HistogramMode.luminance:
        _drawChannel(canvas, size, data.lum, _lumPaint, barWidth);
        break;
      case HistogramMode.r:
        _drawChannel(canvas, size, data.r, _solidRedPaint, barWidth);
        break;
      case HistogramMode.g:
        _drawChannel(canvas, size, data.g, _solidGreenPaint, barWidth);
        break;
      case HistogramMode.b:
        _drawChannel(canvas, size, data.b, _solidBluePaint, barWidth);
        break;
      case HistogramMode.hue:
        break; // handled above
    }

    // 绘制五段分界线（非色相模式）
    _drawZoneDividers(canvas, size);

    // 绘制溢出三角
    _drawOverflowTriangles(canvas, size);

    // 边框
    canvas.drawRect(Offset.zero & size, _borderPaint);
  }

  /// 绘制色相直方图（彩虹色填充）
  void _drawHueHistogram(Canvas canvas, Size size) {
    final hue = data.hue;
    if (hue == null || hue.isEmpty) return;

    final maxVal = hue.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final w = size.width;
    final h = size.height;
    final barWidth = w / 360;

    // 逐 bin 绘制，每个 bin 用对应色相的颜色
    for (var i = 0; i < 360; i++) {
      if (hue[i] == 0) continue;
      final x = i * barWidth;
      final barHeight = (hue[i] / maxVal) * h;
      // HSL(hue, 0.7, 0.5) → 可读又不刺眼
      final color = HSLColor.fromAHSL(1.0, i.toDouble(), 0.7, 0.5).toColor();
      canvas.drawRect(
        Rect.fromLTWH(x, h - barHeight, barWidth + 0.5, barHeight),
        Paint()..color = color,
      );
    }
  }

  /// 绘制亮度叠加曲线（半透明白色）
  void _drawLuminanceOverlay(Canvas canvas, Size size, double barWidth) {
    final lum = data.lum;
    final maxVal = lum.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final h = size.height;
    final path = Path();
    path.moveTo(0, h);

    for (var i = 0; i < 256; i++) {
      final x = i * barWidth;
      final y = h - (lum[i] / maxVal) * h;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, h);
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawChannel(
      Canvas canvas, Size size, List<int> channel, Paint paint, double barWidth) {
    final maxVal = channel.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;
    final h = size.height;

    final path = Path();
    path.moveTo(0, h);
    for (var i = 0; i < 256; i++) {
      final x = i * barWidth;
      final y = h - (channel[i] / maxVal) * h;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, h);
    path.close();
    canvas.drawPath(path, paint);
  }

  /// 绘制五段分界线（黑色/阴影/中间调/高光/白色）
  void _drawZoneDividers(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 五段分界点：51, 102, 153, 204（均分 0~255 为五段）
    const dividers = [51, 102, 153, 204];
    for (final d in dividers) {
      final x = w * (d / 256);
      _drawDashedLine(canvas, Offset(x, 0), Offset(x, h), _dividerPaint);
    }

    // 底部标签（五段居中）
    const labels = ['黑色', '阴影', '中间调', '高光', '白色'];
    const centers = [25, 76, 128, 179, 230]; // 各段中点 (0-255)
    for (var i = 0; i < labels.length; i++) {
      final cx = w * (centers[i] / 256);
      final text = labels[i];
      // 估算文字宽度（8px 字体，每个汉字约 8px）
      final tw = text.length * 8.0;
      _drawText(canvas, text, Offset(cx - tw / 2, h - 10), _labelStyle);
    }
  }

  /// 绘制溢出三角（左上角=纯黑，右上角=纯白）
  void _drawOverflowTriangles(Canvas canvas, Size size) {
    final w = size.width;
    final totalPixels = data.lum.reduce((a, b) => a + b);
    if (totalPixels == 0) return;

    // 纯黑像素占比（bin 0）
    final blackRatio = data.lum[0] / totalPixels;
    // 纯白像素占比（bin 255）
    final whiteRatio = data.lum[255] / totalPixels;

    const triSize = 10.0;
    const threshold = 0.01; // 1%

    // 左上角三角（纯黑溢出）
    final blackPaint =
        blackRatio > threshold ? _overflowWarningPaint : _overflowNormalPaint;
    final blackPath = Path()
      ..moveTo(0, 0)
      ..lineTo(triSize, 0)
      ..lineTo(0, triSize)
      ..close();
    canvas.drawPath(blackPath, blackPaint);

    // 右上角三角（纯白溢出）
    final whitePaint =
        whiteRatio > threshold ? _overflowWarningPaint : _overflowNormalPaint;
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
      final x = (hue + 0.5) * barWidth; // bin 中心
      final markerPaint = Paint()
        ..color = HSLColor.fromAHSL(1.0, hue.toDouble(), 0.8, 0.6).toColor()
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      // 竖线标记
      canvas.drawLine(Offset(x, 0), Offset(x, h), markerPaint);

      // 顶部小三角
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

  /// 绘制文字
  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant HistogramPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.mode != mode ||
        oldDelegate.colorPinHues != colorPinHues;
  }
}
