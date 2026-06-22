// fingerprint_radar.dart — 指纹雷达图骨架（v3.5 PR3，PR4 接入）
//
// PR3 只建骨架：定义 widget 接口 + CustomPainter 画 9 维雷达网格。
// PR4 接入真实数据后，渲染 current vs archive 两条多边形对比。
//
// 不依赖 PR4 的 provider —— PR3 内不实例化本组件（只在 stage_archive_match_card
// 的 children 注释里声明，PR4 取消注释接入）。避免前向依赖。
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
    return SizedBox(
      height: 180,
      child: CustomPaint(
        painter: _FingerprintRadarPainter(
          current: current,
          target: target,
        ),
      ),
    );
  }
}

class _FingerprintRadarPainter extends CustomPainter {
  final PhotoFingerprint? current;
  final PhotoFingerprint? target;

  _FingerprintRadarPainter({this.current, this.target});

  static const _axes = PhotoFingerprint.scalarLabels; // 9 维标签

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
    ..color = Colors.white.withValues(alpha: 0.15)
    ..style = PaintingStyle.fill;

  static final _targetStroke = Paint()
    ..color = Colors.white.withValues(alpha: 0.6)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.shortestSide / 2 - 20;
    final n = _axes.length; // 9

    // 3 层网格圆（25%/50%/100%）
    for (final r in [0.25, 0.5, 1.0]) {
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

    // PR4：渲染 current / target 多边形。PR3 留空（仅网格）。
    // ignore: unused_local_variable
    final _ = (_currentPaint, _currentStroke, _targetPaint, _targetStroke);
    // _drawPolygon(canvas, cx, cy, radius, target?.scalarFeatures, _targetPaint, _targetStroke, n);
    // _drawPolygon(canvas, cx, cy, radius, current?.scalarFeatures, _currentPaint, _currentStroke, n);
  }

  // PR4 接入时取消注释此方法
  // void _drawPolygon(Canvas canvas, double cx, double cy, double radius,
  //     List<double>? features, Paint fill, Paint stroke, int n) {
  //   if (features == null || features.length < n) return;
  //   final path = Path();
  //   for (var i = 0; i < n; i++) {
  //     // 缺失维度（-1）按 0 处理；各维度需归一化到 [0,1]（PR4 的标准化欧氏距离副产品）
  //     final v = features[i] < 0 ? 0.0 : features[i].clamp(0.0, 1.0);
  //     final angle = -_pi / 2 + (2 * _pi * i / n);
  //     final x = cx + radius * v * _cos(angle);
  //     final y = cy + radius * v * _sin(angle);
  //     if (i == 0) {
  //       path.moveTo(x, y);
  //     } else {
  //       path.lineTo(x, y);
  //     }
  //   }
  //   path.close();
  //   canvas.drawPath(path, fill);
  //   canvas.drawPath(path, stroke);
  // }

  @override
  bool shouldRepaint(covariant _FingerprintRadarPainter old) =>
      old.current != current || old.target != target;
}

