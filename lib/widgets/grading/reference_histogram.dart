// reference_histogram.dart — 参照直方图叠放（v3.5 PR3 教学核心；v8.1 风格参照库）
//
// 当前照片亮度直方图（强调色琥珀）+ 半透明灰背景的典型分布参照。
// 让用户直观看到「这张样片的直方图 vs 典型风格的直方图」差异 ——
// 例如高调样片会看到当前分布与「高调参照（右偏钟形）」重合度高。
//
// v8.1（小红书调研驱动）：参照从 4 组影调扩展为 8 组 —— 影调参照
// （高调/低调/中间调/全长调）+ 风格参照（日系清透/电影感/胶片感/港风）。
// 风格分布参数由调研的风格特征表推导（色调倾向/影调特征 → 高斯参数）。
//
// 参照分布用高斯/U型函数预生成常量，不依赖运行时计算，O(1) 内存零延迟。
//
// 规格对齐：HistogramPainter 的 barWidth = size.width / 256 约定。
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../charts/chart_animations.dart';

/// 可选的参照分布（key → 显示名），UI 用它渲染切换 chips
const kReferenceChoices = [
  ('auto', '自动'),
  ('japanese', '日系清透'),
  ('cinema', '电影感'),
  ('film', '胶片感'),
  ('hongkong', '港风'),
  ('high', '高调'),
  ('low', '低调'),
  ('full', '全长调'),
];

/// 参照直方图叠放：当前直方图 + 典型分布参照（半透明灰背景）
class ReferenceHistogram extends StatelessWidget {
  /// 当前照片的亮度直方图（256 bins）。null 时只画参照。
  final List<int>? current;

  /// 当前影调类型（high/mid/low/full），决定用哪组参照
  final String? currentToneKey;

  /// 参照选择 key（kReferenceChoices 之一）；'auto' 按影调自动选
  final String referenceKey;

  const ReferenceHistogram({
    super.key,
    this.current,
    this.currentToneKey,
    this.referenceKey = 'auto',
  });

  @override
  Widget build(BuildContext context) {
    final reference = getReferenceHistogram(referenceKey, currentToneKey);
    // width: double.infinity 强制撑满父级宽度。
    // 根因（gotcha #64）：CustomPaint 无 child 时 intrinsic 宽度 = 0，
    // 若父级是 Column(crossAxisAlignment: start)（如 stage_card 展开内容）
    // 不给交叉轴紧约束，整条链会把 SizedBox 压成 0 宽度 → painter 拿到
    // size.width=0 → barWidth=0 → 所有点塌缩到 x=0 → 视觉上 0 像素（黑框）。
    // 显式 width: double.infinity 让 SizedBox 在水平方向请求父级最大宽度。
    //
    // 入场动画（图表规范）：参照分布先浮现（progress 前半段），
    // 当前分布从底部生长（后半段）—— 教学语义：先看"典型"再看"你的"。
    return SizedBox(
      width: double.infinity,
      height: 80,
      child: ChartEnterBuilder(
        builder: (context, progress) => CustomPaint(
          painter: _ReferenceHistogramPainter(
            current: current,
            reference: reference,
            progress: progress,
          ),
        ),
      ),
    );
  }
}

/// 取参照分布（纯函数，供切换参照时复用）
///
/// 'auto' → 按当前影调选（high/low/mid/full 四组经典形态）；
/// 风格 key → 风格参照库（v8.1 调研驱动）。
List<int> getReferenceHistogram(String key, String? toneKey) {
  switch (key) {
    case 'japanese':
      return _kJapaneseReference;
    case 'cinema':
      return _kCinemaReference;
    case 'film':
      return _kFilmReference;
    case 'hongkong':
      return _kHongkongReference;
    case 'high':
      return _kHighKeyReference;
    case 'low':
      return _kLowKeyReference;
    case 'full':
      return _kFullRangeReference;
    case 'auto':
    default:
      switch (toneKey) {
        case 'high':
          return _kHighKeyReference;
        case 'low':
          return _kLowKeyReference;
        case 'full':
          return _kFullRangeReference;
        default:
          return _kMidKeyReference;
      }
  }
}

class _ReferenceHistogramPainter extends CustomPainter {
  /// 当前直方图（256 bins）。null 时只画参照。
  final List<int>? current;

  /// 参照分布（256 bins）
  final List<int> reference;

  /// 入场动画进度 0~1：0~0.5 参照浮现，0.5~1 当前分布从底部生长
  final double progress;

  _ReferenceHistogramPainter({
    required this.current,
    required this.reference,
    this.progress = 1.0,
  });

  // 性能优化：Paint 对象 static final（参照色 token 化，ChartColors.referenceFill）
  static final _referencePaint = Paint()
    ..color = ChartColors.referenceFill
    ..style = PaintingStyle.fill;

  static final _currentPaint = Paint()
    ..color = AppColors.accent
    ..style = PaintingStyle.fill;

  static final _axisPaint = Paint()
    ..color = ChartColors.gridFaint
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // 防御性守卫：尺寸非正时跳过绘制（gotcha #64：父级无宽度约束时 size 可能退化）
    if (size.width <= 0 || size.height <= 0) return;
    final width = size.width;
    final height = size.height;
    final barWidth = width / 256;

    // 底部基线
    canvas.drawLine(
        Offset(0, height - 0.5), Offset(width, height - 0.5), _axisPaint);

    final p = progress.clamp(0.0, 1.0);

    // 1) 参照分布（半透明灰背景，前半段浮现）
    final refH = Curves.easeOutCubic.transform((p / 0.5).clamp(0.0, 1.0));
    if (refH > 0) {
      _drawHistogram(canvas, size, reference, _referencePaint, barWidth, refH);
    }

    // 2) 当前分布（强调色，后半段从底部生长，叠在参照上）
    final curH = Curves.easeOutCubic.transform(((p - 0.5) / 0.5).clamp(0.0, 1.0));
    if (current != null && current!.isNotEmpty && curH > 0) {
      _drawHistogram(canvas, size, current!, _currentPaint, barWidth, curH);
    }
  }

  void _drawHistogram(Canvas canvas, Size size, List<int> hist, Paint paint,
      double barWidth, double grow) {
    final maxVal = hist.reduce(math.max);
    if (maxVal <= 0) return;
    final height = size.height;
    final drawH = height * grow;
    final path = Path()..moveTo(0, height);
    for (var i = 0; i < 256; i++) {
      final h = (hist[i] / maxVal) * drawH;
      path.lineTo(i * barWidth, height - h);
    }
    path.lineTo(size.width, height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ReferenceHistogramPainter old) =>
      old.current != current ||
      old.reference != reference ||
      old.progress != progress;
}

// ============ 预置典型分布（高斯生成，作为教学参照锚点）============
//
// 这些是「典型风格」的参考形态，不是精确标准。教学目的是让用户看到
// 自己照片的分布与典型形态的重合/偏离，建立直觉。

/// 高调参照：均值 180（偏右），标准差 40 —— 主体落在高光区
final _kHighKeyReference = _generateGaussian(mean: 180, std: 40);

/// 低调参照：均值 60（偏左），标准差 40 —— 主体落在阴影区
final _kLowKeyReference = _generateGaussian(mean: 60, std: 40);

/// 中间调参照：均值 128（中央），标准差 50 —— 主体在中调区
final _kMidKeyReference = _generateGaussian(mean: 128, std: 50);

/// 全长调参照：U 型（两端高，中间低）—— 高反差，明暗两端都有内容
final _kFullRangeReference = _generateUShape();

// ── v8.1 风格参照库（小红书调研 2026-08 驱动，参数由风格特征表推导）──

/// 日系清透：高调（mean 165）+ 中低对比（std 45）+ 黑位上提（低 bin 削减）
/// 调研依据：「中高调、低-中对比、通透感并不来自于低对比」
final _kJapaneseReference = _generateGaussian(mean: 165, std: 45, blackLift: 6);

/// 电影感：低长调（mean 95）+ 高对比（std 55）+ 黑位抬起 + 高光压制
/// 调研依据：「低长调 + 黑场提升（空气感）+ 高光压制（避免死白）」
final _kCinemaReference = _generateGaussian(
    mean: 95, std: 55, blackLift: 10, whiteCeiling: 240);

/// 胶片感：中间偏暗（mean 120）+ 低对比窄分布（std 32）+ 黑位上提
/// 调研依据：「低对比、黑位抬起、故意发灰是核心手法」
final _kFilmReference = _generateGaussian(mean: 120, std: 32, blackLift: 12);

/// 港风：宽分布高对比（mean 105 + std 65 的宽钟形 + 两端翘起）
/// 调研依据：「高饱和高对比 + 暗调 + 颗粒」
final _kHongkongReference = _blendWide(
    _generateGaussian(mean: 105, std: 65), _generateUShape(), 0.7, 0.3);

/// 生成高斯钟形分布（256 bins）
///
/// [mean] 均值（峰值位置），[std] 标准差（峰宽）。
/// 用 exp(-((x-mean)²)/(2σ²)) 归一化到整数直方图，峰值约 1000。
/// [blackLift] 黑位上提量：低于它的 bin 削减（模拟"空气感"曲线黑点抬升）。
/// [whiteCeiling] 白点压制：高于它的 bin 削减（模拟高光保护）。
List<int> _generateGaussian({
  required double mean,
  required double std,
  double blackLift = 0,
  double whiteCeiling = 255,
}) {
  final result = List<int>.filled(256, 0);
  const peak = 1000.0;
  for (var i = 0; i < 256; i++) {
    final d = (i - mean) / std;
    var v = peak * math.exp(-0.5 * d * d);
    if (blackLift > 0 && i < blackLift + 20) {
      // 黑位上提：低 bin 按 (i/blackLift+20) 渐进削减
      v *= (i / (blackLift + 20)).clamp(0.0, 1.0);
    }
    if (whiteCeiling < 255 && i > whiteCeiling - 20) {
      // 白点压制：高 bin 渐进削减到 0
      v *= ((whiteCeiling - i) / 20).clamp(0.0, 1.0);
    }
    result[i] = v.round();
  }
  return result;
}

/// 两个分布线性混合（港风 = 宽钟形 + U 型高反差）
List<int> _blendWide(List<int> a, List<int> b, double wa, double wb) {
  return [
    for (var i = 0; i < 256; i++) (a[i] * wa + b[i] * wb).round(),
  ];
}

/// 生成 U 型分布（全长调参照）
///
/// 两端（bin 0 和 255）高，中间低。用 |x-128| 的归一化形成 U 型。
List<int> _generateUShape() {
  final result = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    // 距离中心 128 的归一化距离（0~1），平方后 U 型更陡
    final dist = (i - 128).abs() / 128.0;
    result[i] = (1000 * (0.2 + 0.8 * dist * dist)).round();
  }
  return result;
}
