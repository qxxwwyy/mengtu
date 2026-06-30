// skin_radar.dart — 肤色雷达图（v6.0 问题8）
//
// 心心念念的「肤色雷达」：把肤色的 5 个关键维度（ΔH色相 / 饱和度 / 明度 /
// 通透STI / 隔离SLS）画成雷达多边形，中心 = 理想肤色（达芬奇肤色线 H=17°、
// S=25%、Y=65%、STI≈1、SLS>15%），越接近中心多边形越「健康圆」。
//
// 设计：每个维度的「理想值」归一化到外圈，当前值偏离理想值则该轴缩进，形成
// 不规则多边形 —— 一眼看出肤色哪个维度偏了。配合状态色描边（绿=好/橙=注意）。
//
// 数据来源：skinProvider（ΔH/饱和/明度/SLS）+ advancedMetricsProvider（STI）。
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/advanced_portrait_metrics.dart';
import '../../models/tone_result.dart';
import '../../theme/app_theme.dart';
import 'interpretation_row.dart';

const _pi = math.pi;
double _cos(double x) => math.cos(x);
double _sin(double x) => math.sin(x);

/// 肤色雷达图（5 维）
///
/// 5 轴：ΔH色相偏差 / 饱和度 / 明度 / 通透STI / 隔离SLS。
/// 中心 = 理想肤色，越接近中心（即越接近理想）→ 多边形越饱满、越接近外圈。
class SkinRadar extends StatelessWidget {
  /// 肤色分析（ΔH/饱和/明度/SLS），空时显示占位
  final SkinAnalysis skin;

  /// 高级指标（含 STI，可空）
  final AdvancedPortraitMetrics? advanced;

  const SkinRadar({super.key, required this.skin, this.advanced});

  @override
  Widget build(BuildContext context) {
    // 5 维归一化分数 [0,1]：1 = 理想，0 = 严重偏离
    final scores = _computeScores();
    final avg = scores.reduce((a, b) => a + b) / scores.length;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 雷达图（正方形，紧凑）
          Expanded(
            flex: 3,
            child: AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: _SkinRadarPainter(
                  scores: scores,
                  overallColor: _overallColor(avg),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 右侧总分 + 维度图例
          Expanded(
            flex: 2,
            child: _Legend(avg: avg, scores: scores),
          ),
        ],
      ),
    );
  }

  /// 计算 5 维归一化分数 [0,1]（1=理想）
  ///
  /// 各维度的「理想区间」与 [ToneGuideCard]/[stage_color_card] 解读阈值对齐：
  /// - ΔH：|ΔH|<2° → 1；|ΔH|>30° → 0（线性插值）
  /// - 饱和度：30~50% 理想 → 1；<10% 或 >70% → 0
  /// - 明度（Y）：55~75% 理想（达芬奇线 Y≈65）→ 1；<30% 或 >90% → 0
  /// - STI：>0.85 理想 → 1；<0.3 → 0
  /// - SLS：>15% 理想（主体提亮）→ 1；<0（暗脸）→ 0
  List<double> _computeScores() {
    double clampScore(double v, double ideal, double halfWidth) {
      final d = (v - ideal).abs();
      return (1 - d / halfWidth).clamp(0.0, 1.0);
    }

    // ΔH 色相偏差（skin.hueOffset 已是相对 17° 的偏差角，直接用绝对值）
    final dh = skin.hueOffset?.abs() ?? 15;
    final dhScore = (1 - dh / 30).clamp(0.0, 1.0);

    // 饱和度：理想 40%（30~50 区间中心），半宽 30
    final sat = skin.saturation ?? 0;
    final satScore = clampScore(sat, 40, 30);

    // 明度：理想 65%（达芬奇肤色线 Y=0.65），半宽 25
    final lum = skin.skinLuminance ?? 0;
    final lumScore = clampScore(lum, 65, 25);

    // STI：理想 0.85+，半宽 0.6
    final sti = advanced?.skinSti ?? -1;
    final stiScore = sti < 0 ? 0.0 : clampScore(sti, 0.85, 0.6);

    // SLS：理想 20（>15% 主体提亮），半宽 40（覆盖 -20~60）
    final sls = skin.luminanceSeparation ?? -50;
    final slsScore = clampScore(sls, 20, 40);

    return [dhScore, satScore, lumScore, stiScore, slsScore];
  }

  Color _overallColor(double avg) {
    if (avg > 0.7) return InterpretationStatus.good;
    if (avg > 0.4) return InterpretationStatus.warn;
    return InterpretationStatus.low;
  }
}

class _SkinRadarPainter extends CustomPainter {
  final List<double> scores; // 5 维 [0,1]
  final Color overallColor;

  static const _axes = [
    '色相 ΔH',
    '饱和度',
    '明度 Y',
    '通透 STI',
    '隔离 SLS',
  ];

  _SkinRadarPainter({required this.scores, required this.overallColor});

  static final _gridPaint = Paint()
    ..color = const Color(0x33FFFFFF)
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  static final _idealPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.1)
    ..style = PaintingStyle.fill;

  static final _idealStroke = Paint()
    ..color = Colors.white.withValues(alpha: 0.4)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  final _currentFill = Paint()..style = PaintingStyle.fill;

  final _currentStroke = Paint()
    ..strokeWidth = 1.8
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.shortestSide / 2 - 22;
    final n = _axes.length;

    // 中心标「理想肤色」（小圆点）
    final centerPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
    canvas.drawCircle(Offset(cx, cy), 2, centerPaint);

    // 3 层网格五边形（33%/66%/100%）
    for (final r in [0.33, 0.66, 1.0]) {
      _drawGridPolygon(canvas, cx, cy, radius * r, n, _gridPaint);
    }

    // 理想轮廓（外圈五边形，半透明白，提示「理想区域」）
    _drawGridPolygon(canvas, cx, cy, radius, n, _idealPaint);
    _drawGridPolygon(canvas, cx, cy, radius, n, _idealStroke);

    // 当前肤色多边形（状态色填充+描边）
    _currentFill.color = overallColor.withValues(alpha: 0.35);
    _currentStroke.color = overallColor;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final v = scores[i].clamp(0.0, 1.0);
      final angle = -_pi / 2 + (2 * _pi * i / n);
      final x = cx + radius * v * _cos(angle);
      final y = cy + radius * v * _sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, _currentFill);
    canvas.drawPath(path, _currentStroke);

    // 各轴顶点小圆点（强调数据点位置）
    final dotPaint = Paint()
      ..color = overallColor
      ..style = PaintingStyle.fill;
    for (var i = 0; i < n; i++) {
      final v = scores[i].clamp(0.0, 1.0);
      final angle = -_pi / 2 + (2 * _pi * i / n);
      final x = cx + radius * v * _cos(angle);
      final y = cy + radius * v * _sin(angle);
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
  }

  void _drawGridPolygon(
      Canvas canvas, double cx, double cy, double radius, int n, Paint paint) {
    final path = Path();
    for (var i = 0; i < n; i++) {
      final angle = -_pi / 2 + (2 * _pi * i / n);
      final x = cx + radius * _cos(angle);
      final y = cy + radius * _sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SkinRadarPainter old) =>
      old.scores != scores || old.overallColor != overallColor;
}

/// 右侧图例：总分 + 5 维分数
class _Legend extends StatelessWidget {
  final double avg; // 平均分 [0,1]
  final List<double> scores;

  const _Legend({required this.avg, required this.scores});

  static const _labels = [
    '色相 ΔH',
    '饱和度',
    '明度 Y',
    '通透 STI',
    '隔离 SLS',
  ];

  @override
  Widget build(BuildContext context) {
    final overallColor = avg > 0.7
        ? InterpretationStatus.good
        : (avg > 0.4 ? InterpretationStatus.warn : InterpretationStatus.low);
    final verdict = avg > 0.7
        ? '肤色健康自然'
        : (avg > 0.4 ? '肤色基本合理' : '肤色需校准');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${(avg * 100).round()}',
                style: TextStyle(
                  color: overallColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                )),
            const Text('分',
                style: TextStyle(color: DetailColors.textMuted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 2),
        Text(verdict,
            style: TextStyle(
                color: overallColor,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ...List.generate(_labels.length, (i) {
          final s = scores[i];
          final color = s > 0.7
              ? InterpretationStatus.good
              : (s > 0.4 ? InterpretationStatus.warn : InterpretationStatus.low);
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_labels[i],
                      style: const TextStyle(
                          color: DetailColors.textSecondary, fontSize: 9)),
                ),
                Text('${(s * 100).round()}',
                    style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace')),
              ],
            ),
          );
        }),
      ],
    );
  }
}
