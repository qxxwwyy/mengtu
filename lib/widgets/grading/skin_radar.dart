// skin_radar.dart — 达芬奇式矢量示波器（v7.1 双模式重写）
//
// 参考达芬奇 Resolve / darktable 的矢量示波器：
//   - 极坐标：角度 = 色相，半径 = 饱和度
//   - 像素云：每个采样像素按 hue+sat 铺成有密度梯度的云团
//   - 六色目标方框（R/Yl/G/Cy/B/Mg）位于 75% 电平
//   - 白色肤色线（17°）作为参考
//
// 双模式：
//   1. 肤色 ROI 模式：只看人脸 bbox 内的肤色像素分布
//   2. 全图模式：看整张图的色彩分布（darktable 风格）
//
// 用户通过右上角切换按钮在两种模式间切换。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tone_result.dart';
import '../../theme/app_theme.dart';
import '../../providers/analysis_provider.dart';
import 'interpretation_row.dart';

double _cos(double x) => math.cos(x);
double _sin(double x) => math.sin(x);

/// 矢量示波器（支持肤色 ROI / 全图双模式）
class SkinRadar extends ConsumerWidget {
  /// 肤色分析（hueOffset / saturation），空时显示占位
  final SkinAnalysis skin;

  /// 照片 ID（用于全图模式拉取 imageScopeProvider）
  final String photoId;

  const SkinRadar({super.key, required this.skin, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(scopeModeProvider);
    final hasSkin = skin.hueOffset != null && skin.saturation != null;

    // 全图模式：watch imageScopeProvider 拿到 bins
    final imageBinsAsync = ref.watch(imageScopeProvider(photoId));

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 示波器（正方形）
          Expanded(
            flex: 3,
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  CustomPaint(
                    painter: _VectorscopePainter(
                      hueDeg: hasSkin ? _normalizeHue(17 + skin.hueOffset!) : null,
                      satPercent: hasSkin ? skin.saturation! : null,
                      hueSatBins: mode == ScopeMode.skinRoi
                          ? skin.hueSatBins
                          : imageBinsAsync.asData?.value,
                      mode: mode,
                    ),
                  ),
                  // 右上角模式切换按钮
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _ModeToggle(mode: mode),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 右侧解读
          Expanded(
            flex: 2,
            child: _Legend(skin: skin, hasSkin: hasSkin, mode: mode),
          ),
        ],
      ),
    );
  }

  double _normalizeHue(double h) {
    final m = h % 360;
    return m < 0 ? m + 360 : m;
  }
}

/// 模式切换按钮
class _ModeToggle extends StatelessWidget {
  final ScopeMode mode;
  const _ModeToggle({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      return GestureDetector(
        onTap: () =>
            ref.read(scopeModeProvider.notifier).toggle(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: ChartColors.gridLight, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                mode == ScopeMode.skinRoi ? Icons.face : Icons.image,
                size: 10,
                color: ChartColors.skinToneLine,
              ),
              const SizedBox(width: 3),
              Text(
                mode == ScopeMode.skinRoi ? '肤色' : '全图',
                style: TextStyle(
                  color: ChartColors.skinToneLine,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// 达芬奇六色方位
class _ColorTarget {
  final double hueDeg;
  final String label;
  final Color color;
  const _ColorTarget(this.hueDeg, this.label, this.color);
}

const _targets = [
  _ColorTarget(0, 'R', ChartColors.labelR),
  _ColorTarget(60, 'Yl', ChartColors.labelY),
  _ColorTarget(120, 'G', ChartColors.labelG),
  _ColorTarget(180, 'Cy', ChartColors.labelC),
  _ColorTarget(240, 'B', ChartColors.labelB),
  _ColorTarget(300, 'Mg', ChartColors.labelM),
];

/// 示波器画笔
class _VectorscopePainter extends CustomPainter {
  final double? hueDeg;
  final double? satPercent;
  final List<int>? hueSatBins;
  final ScopeMode mode;

  _VectorscopePainter({
    this.hueDeg,
    this.satPercent,
    this.hueSatBins,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.shortestSide / 2 - 16;

    // ===== 1. 同心圆刻度（25/50/75/100%）=====
    final gridPaint = Paint()
      ..color = ChartColors.gridLight
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (final r in [0.25, 0.5, 1.0]) {
      canvas.drawCircle(Offset(cx, cy), radius * r, gridPaint);
    }
    // 75% 参考圆高亮
    final grid75Paint = Paint()
      ..color = ChartColors.grid75
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), radius * 0.75, grid75Paint);

    // ===== 2. 十字轴线 =====
    final axisPaint = Paint()
      ..color = ChartColors.gridFaint
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - radius, cy), Offset(cx + radius, cy), axisPaint);
    canvas.drawLine(Offset(cx, cy - radius), Offset(cx, cy + radius), axisPaint);

    // ===== 3. 像素云 =====
    if (hueSatBins != null && hueSatBins!.isNotEmpty) {
      _drawPixelCloud(canvas, cx, cy, radius);
    }

    // ===== 4. 六色目标方框 =====
    final targetPaint = Paint()
      ..color = ChartColors.vectorscopeTarget
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const targetSize = 5.0;
    for (final t in _targets) {
      final angle = _hueToCanvasAngle(t.hueDeg);
      final tx = cx + radius * 0.75 * _cos(angle);
      final ty = cy + radius * 0.75 * _sin(angle);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(tx, ty), width: targetSize * 2, height: targetSize * 2),
        targetPaint,
      );

      final labelDist = radius * 0.75 + 12;
      final lx = cx + labelDist * _cos(angle);
      final ly = cy + labelDist * _sin(angle);
      _drawColorLabel(canvas, t.label, Offset(lx, ly), t.color,
          align: _labelAlign(angle));
    }

    // ===== 5. 肤色参考线（只在肤色模式显示）=====
    if (mode == ScopeMode.skinRoi) {
      const skinHueRef = 17.0;
      final skinLinePaint = Paint()
        ..color = ChartColors.skinToneLine
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      final refAngle = _hueToCanvasAngle(skinHueRef);
      final refEndR = radius * 0.75;
      final refEx = cx + refEndR * _cos(refAngle);
      final refEy = cy + refEndR * _sin(refAngle);
      canvas.drawLine(Offset(cx, cy), Offset(refEx, refEy), skinLinePaint);

      // 肤色线标签
      final refLabelDist = refEndR + 12;
      final refLx = cx + refLabelDist * _cos(refAngle);
      final refLy = cy + refLabelDist * _sin(refAngle);
      _drawLabel(canvas, '肤色', Offset(refLx, refLy),
          color: ChartColors.skinToneLine, align: _labelAlign(refAngle));
    }

    // ===== 6. 肤色光点（只在肤色模式叠加）=====
    if (mode == ScopeMode.skinRoi && hueDeg != null && satPercent != null) {
      final angle = _hueToCanvasAngle(hueDeg!);
      final r = (satPercent! / 100).clamp(0.0, 1.0) * radius;
      final px = cx + r * _cos(angle);
      final py = cy + r * _sin(angle);

      final glow = Paint()
        ..color = ChartColors.skinToneHalo.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 9, glow);

      final dot = Paint()
        ..color = ChartColors.skinTonePoint
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 4, dot);

      final ring = Paint()
        ..color = DetailColors.textPrimary
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(px, py), 4, ring);
    }

    // ===== 7. 中心点 =====
    final centerPaint = Paint()..color = ChartColors.gridLight;
    canvas.drawCircle(Offset(cx, cy), 1.5, centerPaint);
  }

  /// 像素云绘制（参考 darktable：bin→色块，透明度=密度）
  void _drawPixelCloud(Canvas canvas, double cx, double cy, double radius) {
    final bins = hueSatBins!;
    final hueBins = SkinAnalysis.hueBinCount;
    final satBins = SkinAnalysis.satBinCount;

    int maxCount = 1;
    for (final c in bins) {
      if (c > maxCount) maxCount = c;
    }

    final hueStep = 360.0 / hueBins;
    final satStep = 1.0 / satBins;
    final cloudDotRadius = (radius * satStep * 0.7).clamp(2.0, 6.0);

    for (var hb = 0; hb < hueBins; hb++) {
      for (var sb = 0; sb < satBins; sb++) {
        final count = bins[hb * satBins + sb];
        if (count == 0) continue;

        final hue = hb * hueStep + hueStep / 2;
        final sat = sb * satStep + satStep / 2;

        final angle = _hueToCanvasAngle(hue);
        final r = sat.clamp(0.0, 1.0) * radius;
        final px = cx + r * _cos(angle);
        final py = cy + r * _sin(angle);

        final density = count / maxCount;
        final alpha = (0.15 + density * 0.6).clamp(0.1, 0.75);

        // 色块颜色 = 该色相真实颜色
        final color = HSLColor.fromAHSL(1.0, hue, sat, 0.55).toColor()
            .withValues(alpha: alpha);

        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(px, py), cloudDotRadius, paint);
      }
    }
  }

  double _hueToCanvasAngle(double hueDeg) => hueDeg * math.pi / 180;

  TextAlign _labelAlign(double angle) {
    final a = angle % (2 * math.pi);
    if (a > math.pi / 2 && a < 3 * math.pi / 2) return TextAlign.right;
    return TextAlign.left;
  }

  void _drawColorLabel(Canvas canvas, String text, Offset pos, Color color,
      {required TextAlign align}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = pos.dx;
    if (align == TextAlign.right) {
      dx -= tp.width;
    } else if (align == TextAlign.left) {
      dx += 2;
    }
    tp.paint(canvas, Offset(dx, pos.dy - tp.height / 2));
  }

  void _drawLabel(Canvas canvas, String text, Offset pos,
      {required Color color, required TextAlign align}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = pos.dx;
    if (align == TextAlign.right) {
      dx -= tp.width;
    } else if (align == TextAlign.left) {
      dx += 4;
    }
    tp.paint(canvas, Offset(dx, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _VectorscopePainter old) =>
      old.hueDeg != hueDeg ||
      old.satPercent != satPercent ||
      old.hueSatBins != hueSatBins ||
      old.mode != mode;
}

/// 右侧解读面板（双模式）
class _Legend extends StatelessWidget {
  final SkinAnalysis skin;
  final bool hasSkin;
  final ScopeMode mode;

  const _Legend({required this.skin, required this.hasSkin, required this.mode});

  @override
  Widget build(BuildContext context) {
    if (mode == ScopeMode.fullImage) {
      return _fullImageLegend();
    }
    return _skinRoiLegend();
  }

  Widget _fullImageLegend() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('矢量示波器',
            style: TextStyle(
                color: DetailColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('全图色彩分布',
            style: TextStyle(
                color: InterpretationStatus.neutral,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text(
            '每个色块 = 该色相+饱和度\n'
            '组合的像素密度。\n'
            '色块越亮 = 像素越多。',
            style: TextStyle(
                color: DetailColors.textMuted, fontSize: 9, height: 1.4)),
      ],
    );
  }

  Widget _skinRoiLegend() {
    if (!hasSkin) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('肤色示波器',
              style: TextStyle(
                  color: DetailColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('未检出肤色',
              style: TextStyle(color: InterpretationStatus.low, fontSize: 11)),
          SizedBox(height: 6),
          Text(
              '光点越靠近白色「肤色线」→ 肤色越正。\n'
              '可长按图片皮肤区域手动校准。',
              style: TextStyle(
                  color: DetailColors.textMuted, fontSize: 9, height: 1.4)),
        ],
      );
    }

    final dh = skin.hueOffset!.abs();
    final sat = skin.saturation!;
    final verdict = dh < 10
        ? '贴近肤色线'
        : (skin.hueOffset! > 0
            ? '暖偏移（黄金时段/港风常见）'
            : '冷偏移（日系/阴影环境常见）');
    final color = InterpretationStatus.neutral;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('肤色示波器',
            style: TextStyle(
                color: DetailColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(verdict,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _metric('色相偏差', '${skin.hueOffset!.toStringAsFixed(0)}°', color),
        const SizedBox(height: 3),
        _metric('饱和度', '${sat.toStringAsFixed(0)}%', InterpretationStatus.neutral),
      ],
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  color: DetailColors.textSecondary, fontSize: 9)),
        ),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace')),
      ],
    );
  }
}
