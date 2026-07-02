// skin_radar.dart — 达芬奇式肤色示波器（v6.2 重写）
//
// 旧版是 5 维雷达图（ΔH/饱和/明度/STI/SLS），用户反馈「看不懂是什么意思」。
// v6.2 改为业界标准的**肤色矢量示波器（skin tone vectorscope）**，参考
// DaVinci Resolve / darktable 的实现原理：
//
//   - 极坐标：角度 = 色相（hue），半径 = 饱和度（saturation）
//   - 肤色线（skin tone line）：所有肤色不论种族都落在同一条色相线上
//     （「血透过皮肤」原理 —— 黑色素/血红蛋白决定色相，种族只改明度/饱和）
//   - 标准肤色色相 ≈ 20°（达芬奇线 H=17° 附近，HSV 暖橙区间），示波器上
//     固定画一条径向参考线（11 点钟方向）
//   - 当前照片的肤色画成一个光点，离参考线越近 = 肤色越「正」
//
// 数据来源：skinProvider（hueOffset 相对 17° 的偏差 + saturation%）。
// advanced（STI）不再进示波器，但仍在下方文字解读行展示（见 stage_color_card）。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/tone_result.dart';
import '../../theme/app_theme.dart';
import 'interpretation_row.dart';

double _cos(double x) => math.cos(x);
double _sin(double x) => math.sin(x);

/// 肤色矢量示波器（达芬奇式）
///
/// 把肤色画在极坐标上：角度=色相，半径=饱和度，固定一条 11 点钟方向的
/// 肤色参考线。当前照片肤色光点越靠近参考线 → 肤色越正。
class SkinRadar extends StatelessWidget {
  /// 肤色分析（hueOffset / saturation），空时显示占位
  final SkinAnalysis skin;

  const SkinRadar({super.key, required this.skin});

  @override
  Widget build(BuildContext context) {
    final hasSkin = skin.hueOffset != null && skin.saturation != null;

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
              child: CustomPaint(
                painter: _VectorscopePainter(
                  // hueOffset 相对 17° 的偏差；还原绝对色相
                  hueDeg: hasSkin ? _normalizeHue(17 + skin.hueOffset!) : null,
                  satPercent: hasSkin ? skin.saturation! : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 右侧解读
          Expanded(
            flex: 2,
            child: _Legend(skin: skin, hasSkin: hasSkin),
          ),
        ],
      ),
    );
  }

  /// 色相归一化到 [0, 360)
  double _normalizeHue(double h) {
    final m = h % 360;
    return m < 0 ? m + 360 : m;
  }
}

/// 示波器画笔
class _VectorscopePainter extends CustomPainter {
  /// 肤色色相（度，0~360），null = 无肤色（只画空示波器）
  final double? hueDeg;

  /// 肤色饱和度（百分比 0~100），null = 无肤色
  final double? satPercent;

  _VectorscopePainter({this.hueDeg, this.satPercent});

  // 示波器色相环刻度颜色（按色相环的色块标识）
  // 与达芬奇示波器一致：在圆周上标注主要色相方位
  static final _gridPaint = Paint()
    ..color = ChartColors.gridLight
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  static final _axisPaint = Paint()
    ..color = ChartColors.gridFaint
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  // 肤色参考线（达芬奇肤色线，11 点钟方向）
  static final _skinLinePaint = Paint()
    ..color = ChartColors.skinToneLine // 暖黄，区别于数据光点
    ..strokeWidth = 1.2
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.shortestSide / 2 - 14;

    // ===== 1. 同心圆（饱和度刻度：25/50/75/100%）=====
    for (final r in [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawCircle(Offset(cx, cy), radius * r, _gridPaint);
    }

    // ===== 2. 十字轴线（水平/垂直 + 对角）=====
    canvas.drawLine(Offset(cx - radius, cy), Offset(cx + radius, cy), _axisPaint);
    canvas.drawLine(Offset(cx, cy - radius), Offset(cx, cy + radius), _axisPaint);

    // ===== 3. 肤色参考线（达芬奇线）=====
    // 标准肤色色相 = 17°（达芬奇肤色线，HSV 暖橙）。skinProvider 的 hueOffset
    // 即相对此 17° 的偏差，所以 hueOffset=0 时光点正好落在线上。
    // 示波器坐标系：0° 指向右（3 点钟，红），90° 下（黄绿），180° 左（青），
    // 270° 上（品红）—— 与达芬奇 R/Yl/G/Cy/B/Mg 六色方位一致。
    const skinHueRef = 17.0; // 达芬奇肤色线标准色相（度）
    final refAngle = _hueToCanvasAngle(skinHueRef);
    final refEx = cx + radius * _cos(refAngle);
    final refEy = cy + radius * _sin(refAngle);
    final refSx = cx - radius * _cos(refAngle);
    final refSy = cy - radius * _sin(refAngle);
    canvas.drawLine(Offset(refSx, refSy), Offset(refEx, refEy), _skinLinePaint);

    // ===== 4. 肤色光点（当前照片）=====
    if (hueDeg != null && satPercent != null) {
      final angle = _hueToCanvasAngle(hueDeg!);
      // 半径按饱和度（0~100 → 0~radius）
      final r = (satPercent! / 100).clamp(0.0, 1.0) * radius;
      final px = cx + r * _cos(angle);
      final py = cy + r * _sin(angle);

      // 外层光晕（柔和）
      final glow = Paint()
        ..color = ChartColors.skinToneHalo.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 9, glow);

      // 内层光点
      final dot = Paint()
        ..color = ChartColors.skinTonePoint // 暖橙肤色点
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 4, dot);

      // 白色描边让光点在任何背景上可见
      final ring = Paint()
        ..color = DetailColors.textPrimary
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(px, py), 4, ring);
    }

    // ===== 5. 中心点 =====
    final centerPaint = Paint()..color = ChartColors.gridLight;
    canvas.drawCircle(Offset(cx, cy), 1.5, centerPaint);

    // ===== 6. 肤色参考线标签（11 点方向标「肤色」）=====
    _drawLabel(canvas, '肤色线', Offset(refEx, refEy),
        align: _labelAlign(refAngle));
  }

  /// HSV 色相（0~360，红=0 在 3 点钟数学角度方向）→ 画布角度
  /// 示波器约定：0° 指向正上方（12 点），顺时针递增。
  /// 即画布角度 = -90° + hue（数学坐标系，y 向下）。
  /// 输入弧度，使 0 色相（红）在 3 点，90（黄绿）在 6 点，180（青）在 9 点，
  /// 270（品红）在 12 点 —— 与达芬奇示波器 R/Yl/G/Cy/B/Mg 六色方位一致。
  double _hueToCanvasAngle(double hueDeg) {
    // 数学坐标系（y 向下）：0°→右(红), 90°→下(黄绿), 180°→左(青), 270°→上(品红)
    // Flutter 的 sin/cos 与屏幕坐标系一致（y 向下），所以直接用弧度即可
    return hueDeg * math.pi / 180;
  }

  /// 标签对齐方向（根据光点所在象限决定文字 anchor）
  TextAlign _labelAlign(double angle) {
    final a = angle % (2 * math.pi);
    // 左半圆 → 右对齐（文字在点左侧）；右半圆 → 左对齐
    if (a > math.pi / 2 && a < 3 * math.pi / 2) return TextAlign.right;
    return TextAlign.left;
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, {required TextAlign align}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: ChartColors.skinToneLine,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
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
      old.hueDeg != hueDeg || old.satPercent != satPercent;
}

/// 右侧解读：色相偏差 + 饱和度 + 判定
class _Legend extends StatelessWidget {
  final SkinAnalysis skin;
  final bool hasSkin;

  const _Legend({required this.skin, required this.hasSkin});

  @override
  Widget build(BuildContext context) {
    if (!hasSkin) {
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
          const Text('未检出肤色',
              style: TextStyle(color: InterpretationStatus.low, fontSize: 11)),
          const SizedBox(height: 6),
          const Text(
              '光点越靠近黄色「肤色线」→ 肤色越正。\n'
              '可长按图片皮肤区域手动校准。',
              style: TextStyle(
                  color: DetailColors.textMuted, fontSize: 9, height: 1.4)),
        ],
      );
    }

    final dh = skin.hueOffset!.abs();
    final sat = skin.saturation!;
    // 描述性标签（非诊断）：贴近肤色线 / 偏暖 / 偏冷
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
