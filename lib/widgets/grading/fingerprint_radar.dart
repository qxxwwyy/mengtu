// fingerprint_radar.dart — 指纹雷达图（9 维标量特征对比）
//
// 在阶④档案比对卡片展示：当前照片指纹 vs 目标档案指纹的 9 维多边形对比。
//
// v6.0 修复（问题7）：
// - 用 AspectRatio 强制正方形 + Center 居中，修复原「雷达飘出框外/圆心偏左」
//   （SizedBox height 固定但 width 未约束，半径按短边算导致绘制溢出卡片）
// - 补全 PR4 漏接的 _drawPolygon（原被注释，雷达只有空网格毫无意义）
// - 标量按 RAW 单位归一化（与 photo_fingerprint.dart 标注一致）
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/photo_fingerprint.dart';
import '../../theme/app_theme.dart';

const _pi = math.pi;
double _cos(double x) => math.cos(x);
double _sin(double x) => math.sin(x);

/// 指纹雷达图（9 维标量特征对比）
///
/// 9 个轴对应 [PhotoFingerprint.scalarLabels]：
/// RMS对比度 / 冷暖比 / 黑点 / 白点 / 信息熵 / SCS / SLS / STI / FLC
///
/// PR4 用法：
/// ```dart
/// FingerprintRadar(
///   current: matchList.first.currentFingerprint,
///   target: matchList.first.archiveFingerprint,
/// )
/// ```
class FingerprintRadar extends StatelessWidget {
  /// 当前照片指纹（9 维标量）
  final PhotoFingerprint? current;

  /// 目标档案指纹（9 维标量均值）
  final PhotoFingerprint? target;

  const FingerprintRadar({
    super.key,
    this.current,
    this.target,
  });

  @override
  Widget build(BuildContext context) {
    // v6.0 修复（问题7）：用 AspectRatio 强制正方形 + Center 居中，
    // 避免 StageCard 的 Column 宽度未约束导致圆心偏左、雷达飘出框外。
    final hasData = current != null || target != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: SizedBox(
            width: double.maxFinite,
            child: CustomPaint(
              painter: _FingerprintRadarPainter(
                current: current,
                target: target,
                showHint: !hasData,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FingerprintRadarPainter extends CustomPainter {
  final PhotoFingerprint? current;
  final PhotoFingerprint? target;
  final bool showHint;

  _FingerprintRadarPainter({
    this.current,
    this.target,
    this.showHint = false,
  });

  static const _axes = PhotoFingerprint.scalarLabels; // 9 维标签

  /// 9 维标量的归一化范围（[min, max]），用于把 RAW 单位映射到雷达 [0,1]
  ///
  /// 与 photo_fingerprint.dart 标注的 RAW 单位一致（v3.5 二轮复核修复）。
  /// 缺失值（-1）按 0.05 渲染（贴近中心，提示「无数据」）。
  static const _normalizeRanges = <double>[
    0, 128, // rms_contrast
    0.5, 2.0, // warm_cold_ratio
    0, 255, // black_point
    0, 255, // white_point
    0, 8, // entropy
    0, 180, // scs
    -100, 100, // sls
    0, 1, // sti
    0, 1, // flc
  ];

  static final _gridPaint = Paint()
    ..color = const Color(0x33FFFFFF)
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  static final _currentPaint = Paint()
    ..color = AppColors.darkAccent.withValues(alpha: 0.35)
    ..style = PaintingStyle.fill;

  static final _currentStroke = Paint()
    ..color = AppColors.darkAccent
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  static final _targetPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.12)
    ..style = PaintingStyle.fill;

  static final _targetStroke = Paint()
    ..color = Colors.white.withValues(alpha: 0.6)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  static final _labelPaint = Paint()
    ..color = const Color(0x88FFFFFF)
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    // v6.0：半径裕度 -32（原 -20），给轴标签留空间，确保不溢出 AspectRatio 边界
    final radius = size.shortestSide / 2 - 32;
    final n = _axes.length; // 9

    // 3 层网格圆（33%/66%/100%）
    for (final r in [0.33, 0.66, 1.0]) {
      canvas.drawCircle(Offset(cx, cy), radius * r, _gridPaint);
    }

    // 9 条轴线
    for (var i = 0; i < n; i++) {
      final angle = -_pi / 2 + (2 * _pi * i / n);
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + radius * _cos(angle), cy + radius * _sin(angle)),
        _gridPaint,
      );
    }

    // v6.0：实际渲染 current / target 多边形（PR3 留空、PR4 漏接，现补全）
    _drawPolygon(canvas, cx, cy, radius, target?.scalarFeatures, _targetPaint,
        _targetStroke, n);
    _drawPolygon(canvas, cx, cy, radius, current?.scalarFeatures, _currentPaint,
        _currentStroke, n);

    // 图例（左上角）
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = const TextSpan(
        text: '● 当前',
        style: TextStyle(color: AppColors.darkAccent, fontSize: 9),
      );
    tp.layout();
    tp.paint(canvas, Offset(4, 4));
    final tp2 = TextPainter(textDirection: TextDirection.ltr)
      ..text = const TextSpan(
        text: '○ 档案',
        style: TextStyle(color: Color(0x99FFFFFF), fontSize: 9),
      );
    tp2.layout();
    tp2.paint(canvas, Offset(4, 16));

    if (showHint) {
      final hintTp = TextPainter(textDirection: TextDirection.ltr)
        ..text = const TextSpan(
          text: '暂无指纹数据',
          style: TextStyle(color: Color(0x55FFFFFF), fontSize: 10),
        )
        ..textAlign = TextAlign.center;
      hintTp.layout(maxWidth: size.width);
      hintTp.paint(
          canvas, Offset(0, cy + radius + 6));
    }
    // 触发 _labelPaint 使用（预留：未来可在轴线末端画标签）
    // ignore: unused_local_variable
    final _ = _labelPaint;
  }

  void _drawPolygon(Canvas canvas, double cx, double cy, double radius,
      List<double>? features, Paint fill, Paint stroke, int n) {
    if (features == null || features.length < n) return;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final raw = features[i];
      final norm = _normalize(i, raw);
      final angle = -_pi / 2 + (2 * _pi * i / n);
      final x = cx + radius * norm * _cos(angle);
      final y = cy + radius * norm * _sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  /// 把第 i 维的 RAW 值归一化到 [0,1]（雷达半径比例）
  /// 缺失值（<0）按 0.05 渲染（贴中心，提示无数据）
  double _normalize(int i, double raw) {
    if (raw < 0) return 0.05;
    final min = _normalizeRanges[i * 2];
    final max = _normalizeRanges[i * 2 + 1];
    final span = max - min;
    if (span <= 0) return 0.5;
    return ((raw - min) / span).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _FingerprintRadarPainter old) =>
      old.current != current ||
      old.target != target ||
      old.showHint != showHint;
}

