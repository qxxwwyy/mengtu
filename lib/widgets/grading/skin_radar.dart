// skin_radar.dart — 达芬奇式矢量示波器（v7.2 Cb/Cr 平面重构）
//
// 坐标系：Cb/Cr (YCbCr Rec.709 full-range) 直角平面，对齐达芬奇 Resolve /
// broadcast vectorscope 规范（参考 FFmpeg vf_vectorscope.c / Wikipedia Vectorscope）：
//   - 水平轴 = Cb（+Cb 朝右，3 点钟 = 0°）
//   - 垂直轴 = Cr（+Cr 朝上，12 点钟 = 90°）   ← 画布 y 向下，故 py = cy - cr_norm * radius
//   - 角度 θ = atan2(Cr, Cb)，从 +Cb 轴逆时针
//   - 半径   = chroma 幅度 sqrt(Cb² + Cr²)
//
// 像素云（修复 v7.1「画不出来」bug）：
//   - 数据源始终来自 imageScopeProvider（全图 Cb/Cr 64×64 bins），
//     任何照片（含无脸照片）都有数据，不再依赖 skinProvider 的 ROI 结果。
//   - skinRoi 模式额外叠加肤色光点（skinProvider 的 chromaCb/chromaCr）。
//   - fullImage 模式只看全图分布。
//
// 六色目标（BT.709 75% 彩条 SMPTE 100/0/75/0）：存 RGB 值，paint 时用 rgbToYCbCr
// 现算 Cb/Cr，与像素云共用同一转换函数。用 75% 彩条（每通道 191）而非 100%：
// 75% 目标的 Cb/Cr 恰好是 100% 的 0.75 倍（线性缩放），以 127.5 归一化后自然落在
// 半径 75% 处，无需额外 scale，也避免 G/Mg 的 clamp 扭曲。
//
// 肤色线：I-axis 标准 123°（从 +Cb 轴逆时针）。Cb/Cr 方向向量 =
// (cos123°, sin123°) = (-0.545, +0.839)，即左上 ~11 点钟方向。
// 由真实肤色 RGB(200,150,130) 经 rgbToYCbCr 校准（Cb≈-16, Cr≈+26）也落此线附近。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tone_result.dart';
import '../../theme/app_theme.dart';
import '../../utils/color_utils.dart' show rgbToYCbCr;
import '../../providers/analysis_provider.dart';
import '../charts/chart_animations.dart';
import 'interpretation_row.dart';

/// 矢量示波器（支持肤色 ROI / 全图双模式 + 交互）
///
/// 交互（v8.1）：
/// - 模式切换过渡：云层 crossfade + 肤色元素淡入淡出（modeProgress 0↔1）
/// - 入场动画：整体淡入 + 云从中心生长（enterProgress）
/// - 长按查询：按住示波器任意点位 → 十字游标 + Cb/Cr 读数浮层
class SkinRadar extends ConsumerStatefulWidget {
  /// 肤色分析（hueOffset / saturation / chromaCb / chromaCr），空时显示占位
  final SkinAnalysis skin;

  /// 照片 ID（用于全图模式拉取 imageScopeProvider）
  final String photoId;

  const SkinRadar({super.key, required this.skin, required this.photoId});

  @override
  ConsumerState<SkinRadar> createState() => _SkinRadarState();
}

class _SkinRadarState extends ConsumerState<SkinRadar> {
  /// 长按查询的画布位置（null = 未查询）
  Offset? _probe;

  void _probeAt(LongPressEndDetails _) => setState(() => _probe = null);

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(scopeModeProvider);
    final skin = widget.skin;
    final hasSkin = skin.hueOffset != null && skin.saturation != null;

    // 全图 Cb/Cr bins（修复 bug 核心：任何照片都有数据）
    final imageBinsAsync = ref.watch(imageScopeProvider(widget.photoId));
    final imageBins = imageBinsAsync.asData?.value;

    // skinRoi 模式下，如果 skin 自带 chromaBins（ROI 内云）优先用 skin 的，
    // 否则回退到全图 bins。这样 skinRoi 也能看到云（即使无脸，ROI 区域云）。
    // fullImage 模式始终用全图 bins。
    final skinBins = skin.chromaBins ?? imageBins;

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
              child: LayoutBuilder(builder: (context, constraints) {
                final size = constraints.biggest;
                return GestureDetector(
                  // 长按查询任意点位 Cb/Cr（移动跟手、抬起消失）
                  onLongPressStart: (d) =>
                      setState(() => _probe = d.localPosition),
                  onLongPressMoveUpdate: (d) =>
                      setState(() => _probe = d.localPosition),
                  onLongPressEnd: _probeAt,
                  onLongPressCancel: () => setState(() => _probe = null),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 入场动画（enterProgress：整体淡入 + 云从中心生长）
                      ChartEnterBuilder(
                        builder: (context, enter) =>
                            // 模式切换过渡（modeProgress：skinRoi=0 ↔ fullImage=1，
                            // 云层 crossfade + 肤色元素淡入淡出）
                            TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0.0,
                            end: mode == ScopeMode.fullImage ? 1.0 : 0.0,
                          ),
                          duration: AppAnimations.chartSwitchDuration,
                          curve: AppAnimations.chartSwitchCurve,
                          builder: (context, modeT, _) => Opacity(
                            opacity: 0.25 + 0.75 * enter,
                            child: CustomPaint(
                              painter: _VectorscopePainter(
                                binsImage: imageBins,
                                binsSkin: skinBins,
                                skinChromaCb: skin.chromaCb,
                                skinChromaCr: skin.chromaCr,
                                hueOffset: skin.hueOffset,
                                saturation: skin.saturation,
                                showSkinDot: mode == ScopeMode.skinRoi && hasSkin,
                                showSkinLine: mode == ScopeMode.skinRoi,
                                modeProgress: modeT,
                                enterProgress: enter,
                                probe: _probe,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 长按查询浮层（Cb/Cr 读数）
                      if (_probe != null)
                        Positioned(
                          top: 2,
                          left: 0,
                          right: 0,
                          child: _ProbeBadge(
                            probe: _probe!,
                            scopeSize: size,
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
                );
              }),
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
}

/// 画布坐标 → Cb/Cr 值（纯函数，painter 的 _chromaToCanvas 逆变换）
///
/// 与 painter 共用同一套几何参数（cx/cy/radius），保证读数与视觉点严格对齐。
/// 超出满量程圆的点位 clamp 到 ±128。
({double cb, double cr}) canvasToChroma(Offset local, Size size) {
  final cx = size.width / 2;
  final cy = size.height / 2;
  final radius = size.shortestSide / 2 - 16;
  final cb = ((local.dx - cx) / radius * 127.5).clamp(-128.0, 128.0);
  // y 翻转：Cr 正方向朝上（画布 y 向下）
  final cr = (-(local.dy - cy) / radius * 127.5).clamp(-128.0, 128.0);
  return (cb: cb, cr: cr);
}

/// Cb/Cr → 中文色相名（红/橙/黄/黄绿/绿/青/蓝/紫/品红，9 区）
///
/// 反算 RGB（Y 固定 135）→ HSV hue → 分区。用于长按查询的直观读数。
String chromaToHueName(double cb, double cr) {
  final rgb = ycbcrToRgbForCloud(135, cb, cr);
  final maxC = [rgb[0], rgb[1], rgb[2]].reduce((a, b) => a > b ? a : b);
  final minC = [rgb[0], rgb[1], rgb[2]].reduce((a, b) => a < b ? a : b);
  // 近无彩色（中心附近）：Cb/Cr 都小时直接按 Cb/Cr 方向给弱色名
  final chroma = math.sqrt(cb * cb + cr * cr);
  if (chroma < 8) return '无彩';
  if (maxC == minC) return '无彩';

  double r = rgb[0] / 255.0, g = rgb[1] / 255.0, b = rgb[2] / 255.0;
  final max = [r, g, b].reduce((a, c) => a > c ? a : c);
  final min = [r, g, b].reduce((a, c) => a < c ? a : c);
  final d = max - min;
  double hue;
  if (max == r) {
    hue = ((g - b) / d) % 6;
  } else if (max == g) {
    hue = (b - r) / d + 2;
  } else {
    hue = (r - g) / d + 4;
  }
  hue *= 60;
  if (hue < 0) hue += 360;

  if (hue < 15 || hue >= 345) return '红';
  if (hue < 40) return '橙';
  if (hue < 70) return '黄';
  if (hue < 100) return '黄绿';
  if (hue < 160) return '绿';
  if (hue < 200) return '青';
  if (hue < 260) return '蓝';
  if (hue < 300) return '紫';
  return '品红';
}

/// 长按查询浮层：色块 + Cb/Cr 数值 + 色相名
class _ProbeBadge extends StatelessWidget {
  final Offset probe;
  final Size scopeSize;

  const _ProbeBadge({required this.probe, required this.scopeSize});

  @override
  Widget build(BuildContext context) {
    final chroma = canvasToChroma(probe, scopeSize);
    final rgb = ycbcrToRgbForCloud(135, chroma.cb, chroma.cr);
    final swatch = Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);

    String fmt(double v) =>
        (v >= 0 ? '+' : '') + v.toStringAsFixed(0).replaceAll('-', '−');

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ChartColors.probeBadgeBg,
          borderRadius: Radii.smBorder,
          border: Border.all(color: ChartColors.gridLight, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(color: ChartColors.gridLight, width: 0.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Cb ${fmt(chroma.cb)}  Cr ${fmt(chroma.cr)}',
              style: AppTypography.mono.copyWith(fontSize: 10),
            ),
            const SizedBox(width: 6),
            Text(
              chromaToHueName(chroma.cb, chroma.cr),
              style: AppTypography.captionWith(DetailColors.accent)
                  .copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
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
            color: DetailColors.chipSurface,
            borderRadius: Radii.xsBorder,
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
                style: const TextStyle(
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

/// 达芬奇六色目标（BT.709 75% 彩条 SMPTE 100/0/75/0）
///
/// 存 RGB 而非 Cb/Cr：paint 时用 rgbToYCbCr 现算，与像素云共用同一转换函数，
/// 保证六色框与像素云完全对齐（自洽优先于「标准数值」）。
/// 用 75% 彩条（每通道 191）：Cb/Cr 恰为 100% 的 0.75 倍，以 127.5 归一化后
/// 自然落在 75% 圈，符合达芬奇目标电平，无需 scale hack。
class _ColorTarget {
  final int r, g, b;
  final String label;
  final Color color;
  const _ColorTarget(this.r, this.g, this.b, this.label, this.color);
}

const _targets = [
  _ColorTarget(191, 0, 0, 'R', ChartColors.labelR),
  _ColorTarget(191, 191, 0, 'Yl', ChartColors.labelY),
  _ColorTarget(0, 191, 0, 'G', ChartColors.labelG),
  _ColorTarget(0, 191, 191, 'Cy', ChartColors.labelC),
  _ColorTarget(0, 0, 191, 'B', ChartColors.labelB),
  _ColorTarget(191, 0, 191, 'Mg', ChartColors.labelM),
];

/// 示波器画笔
class _VectorscopePainter extends CustomPainter {
  /// 全图层 Cb/Cr 64×64 bins（fullImage 模式数据源）
  final List<int>? binsImage;

  /// 肤色 ROI 层 bins（skinRoi 模式数据源，无 ROI 数据时与全图相同）
  final List<int>? binsSkin;

  /// 肤色 ROI 平均 Cb/Cr（画肤色光点用，优先级高于 hueOffset 估算）
  final double? skinChromaCb;
  final double? skinChromaCr;

  /// HSV 旧字段（chromaCb/Cr 缺失时的回退估算）
  final double? hueOffset;
  final double? saturation;

  /// 是否画肤色光点 / 肤色线
  final bool showSkinDot;
  final bool showSkinLine;

  /// 模式过渡进度：0 = skinRoi，1 = fullImage。
  /// 云层 crossfade（skin 层 alpha=1−t，image 层 alpha=t）+ 肤色元素 alpha=1−t。
  final double modeProgress;

  /// 入场动画进度 0~1：云从中心生长（半径 ×(0.55+0.45·t)）
  final double enterProgress;

  /// 长按查询位置（画布坐标，null = 无查询）。画十字游标 + 圆环。
  final Offset? probe;

  _VectorscopePainter({
    this.binsImage,
    this.binsSkin,
    this.skinChromaCb,
    this.skinChromaCr,
    this.hueOffset,
    this.saturation,
    required this.showSkinDot,
    required this.showSkinLine,
    this.modeProgress = 0,
    this.enterProgress = 1.0,
    this.probe,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    // 半径归一到 Cb/Cr 的 ±128 满量程（chroma 幅度 0~181 对角线，但 75% 圈
    // 对应幅度 ~96，画布 radius 映射到 ±128 区间，让六色目标落在 75% 圈附近）
    final radius = size.shortestSide / 2 - 16;

    // ===== 1. 同心圆刻度（25/50/75/100% chroma 幅度）=====
    final gridPaint = Paint()
      ..color = ChartColors.gridLight
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // 25/50/100% 圈（75% 单独高亮画在下方，避免重复）
    for (final r in [0.25, 0.5, 1.0]) {
      canvas.drawCircle(Offset(cx, cy), radius * r, gridPaint);
    }
    // 75% 参考圆高亮（达芬奇彩条目标电平）
    final grid75Paint = Paint()
      ..color = ChartColors.grid75
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), radius * 0.75, grid75Paint);

    // ===== 2. 十字轴线（Cb 横轴 / Cr 纵轴）=====
    final axisPaint = Paint()
      ..color = ChartColors.gridFaint
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - radius, cy), Offset(cx + radius, cy), axisPaint);
    canvas.drawLine(Offset(cx, cy - radius), Offset(cx, cy + radius), axisPaint);

    // ===== 3. 像素云（双层 crossfade）=====
    // skinRoi 层（alpha = 1−t）：skin bins（无 ROI 数据回退 image bins）
    // fullImage 层（alpha = t）：image bins
    // 两层数据相同时只画一层（避免同数据双重叠加发白）。
    final t = modeProgress.clamp(0.0, 1.0);
    if (binsSkin != null && binsSkin!.isNotEmpty && t < 1.0) {
      _drawChromaCloud(canvas, cx, cy, radius, binsSkin!, 1.0 - t);
    }
    if (binsImage != null && binsImage!.isNotEmpty && t > 0.0) {
      final same = identical(binsSkin, binsImage) ||
          (binsSkin != null && _listEq(binsSkin!, binsImage!));
      // 同数据时由 skin 层负责绘制（t<1 期间），仅在切到纯 fullImage 时接管
      if (!same || t >= 1.0) {
        _drawChromaCloud(canvas, cx, cy, radius, binsImage!, t);
      }
    }

    // ===== 4. 六色目标方框（BT.709 75% 彩条）=====
    // 75% 彩条 Cb/Cr 已是 100% 的 0.75 倍，以 127.5 归一化后自然落在 75% 圈，
    // 故 scale=1.0（不再用 0.75 hack）。
    final targetPaint = Paint()
      ..color = ChartColors.vectorscopeTarget
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const targetSize = 5.0;
    for (final tg in _targets) {
      final ycbcr = rgbToYCbCr(tg.r, tg.g, tg.b);
      final (px, py) = _chromaToCanvas(ycbcr.cb, ycbcr.cr, cx, cy, radius, 1.0);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(px, py), width: targetSize * 2, height: targetSize * 2),
        targetPaint,
      );

      // 标签沿径向外移（scale 1.15）
      final (lx, ly) = _chromaToCanvas(ycbcr.cb, ycbcr.cr, cx, cy, radius, 1.15);
      _drawColorLabel(canvas, tg.label, Offset(lx, ly), tg.color,
          align: _labelAlign(ycbcr.cb));
    }

    // ===== 5. 肤色参考线（I-axis 123°，仅肤色模式显示，alpha=1−t）=====
    // 标准 I-axis 123°（从 +Cb 轴逆时针）：方向向量 (cos123°, sin123°) ≈
    // (-0.545, +0.839)，即左上 ~11 点钟。用幅度 75 画到 75% 圈处。
    if (showSkinLine && t < 1.0) {
      const skinAngle = 123.0 * math.pi / 180.0;
      const skinMag = 75.0; // 落在 75% 电平圈
      final skinCb = skinMag * math.cos(skinAngle); // ≈ -40.9
      final skinCr = skinMag * math.sin(skinAngle); // ≈ +62.9
      final skinLinePaint = Paint()
        ..color = ChartColors.skinToneLine.withValues(alpha: 1.0 - t)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      final (ex, ey) = _chromaToCanvas(skinCb, skinCr, cx, cy, radius, 1.0);
      canvas.drawLine(Offset(cx, cy), Offset(ex, ey), skinLinePaint);

      // 肤色线标签
      final (lx, ly) = _chromaToCanvas(skinCb, skinCr, cx, cy, radius, 1.2);
      _drawLabel(canvas, '肤色', Offset(lx, ly),
          color: ChartColors.skinToneLine.withValues(alpha: 1.0 - t),
          align: _labelAlign(skinCb));
    }

    // ===== 6. 肤色光点（仅肤色模式叠加，alpha=1−t）=====
    if (showSkinDot && t < 1.0) {
      double cb, cr;
      if (skinChromaCb != null && skinChromaCr != null) {
        // 精确路径：直接用 ROI 平均 Cb/Cr
        cb = skinChromaCb!;
        cr = skinChromaCr!;
      } else if (hueOffset != null) {
        // 回退路径：chromaCb/Cr 缺失（老缓存/手动校准单点）。
        // 不能把 HSV hueOffset 直接加到 Cb/Cr I-axis 角度上 —— HSV hue 和
        // Cb/Cr atan2(Cr,Cb) 是两个非线性相关的角空间（直接相加会系统性偏移，
        // 评审 B1）。改为同源转换：还原绝对 HSV hue=17+hueOffset → RGB → rgbToYCbCr，
        // 与像素云/六色目标共用同一转换函数，坐标系自洽。
        final absHue = (17.0 + hueOffset!) % 360.0;
        final sat = (saturation ?? 50) / 100.0;
        final rgb = _hsvToRgb(absHue, sat, 0.65);
        final ycbcr = rgbToYCbCr(rgb[0], rgb[1], rgb[2]);
        cb = ycbcr.cb;
        cr = ycbcr.cr;
      } else {
        // 最终兜底：标准 I-axis 123° 肤色点（RGB(200,150,130) 校准）
        final ycbcr = rgbToYCbCr(200, 150, 130);
        cb = ycbcr.cb;
        cr = ycbcr.cr;
      }
      final (px, py) = _chromaToCanvas(cb, cr, cx, cy, radius, 1.0);

      final glow = Paint()
        ..color = ChartColors.skinToneHalo.withValues(alpha: 0.25 * (1.0 - t))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 9, glow);

      final dot = Paint()
        ..color = ChartColors.skinTonePoint.withValues(alpha: 1.0 - t)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 4, dot);

      final ring = Paint()
        ..color = DetailColors.textPrimary.withValues(alpha: 1.0 - t)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(px, py), 4, ring);
    }

    // ===== 7. 中心点 =====
    final centerPaint = Paint()..color = ChartColors.gridLight;
    canvas.drawCircle(Offset(cx, cy), 1.5, centerPaint);

    // ===== 8. 长按查询游标（十字线 + 圆环）=====
    if (probe != null) {
      final probePaint = Paint()
        ..color = ChartColors.probeCursor.withValues(alpha: 0.7)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
          Offset(probe!.dx, cy - radius), Offset(probe!.dx, cy + radius), probePaint);
      canvas.drawLine(
          Offset(cx - radius, probe!.dy), Offset(cx + radius, probe!.dy), probePaint);
      canvas.drawCircle(probe!, 6, probePaint);
    }
  }

  bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Cb/Cr 值 → 画布坐标
  ///
  /// [scale] 缩放系数（标签外移用 >1.0，目标电平用 1.0）。
  /// 画布约定（broadcast 标准）：Cb→水平（+Cb 右）、Cr→垂直（+Cr 上，故 py 减）。
  /// Cb/Cr 满量程 ±128（以 127.5 归一化），映射到 [0, radius]。
  (double, double) _chromaToCanvas(
      double cb, double cr, double cx, double cy, double radius, double scale) {
    final cbNorm = (cb / 127.5).clamp(-1.0, 1.0);
    final crNorm = (cr / 127.5).clamp(-1.0, 1.0);
    final px = cx + cbNorm * radius * scale;
    final py = cy - crNorm * radius * scale; // y 翻转：Cr 正方向朝上
    return (px, py);
  }

  /// 像素云绘制（Cb/Cr 平面，参考 darktable）
  ///
  /// 把 64×64 bins 按 Cb/Cr 中心值映射到画布，每个 bin 画一个色块圆点：
  /// - 颜色 = 该 Cb/Cr 反算回 RGB 的真实颜色（让云团呈现真实色彩分布）
  /// - 透明度 = sqrt(count/maxCount)，热点更亮，稀疏处淡（darktable 风格）
  /// - BlendMode.screen：暗背景上叠加出发光感
  ///
  /// [alphaScale] 模式过渡系数（crossfade 用），[enterProgress] 入场进度
  /// （云从中心生长：映射半径 ×(0.55+0.45·t)）。
  void _drawChromaCloud(Canvas canvas, double cx, double cy, double radius,
      List<int> bins, double alphaScale) {
    final grow = 0.55 + 0.45 * enterProgress.clamp(0.0, 1.0);
    final points = computeCloudPoints(bins, cx, cy, radius * grow);
    if (points.isEmpty) return;

    // 色块半径：让相邻 bin 略有重叠（云团连续感），但不超过 bin 宽的一半
    final binW = radius * 2 / SkinAnalysis.cbBinCount;
    final cloudDotRadius = (binW * 0.7).clamp(2.0, 6.0);

    // 复用 Paint 对象，只改 color（性能：避免 4096 次 new Paint）
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.screen;

    for (final p in points) {
      paint.color = Color.fromARGB(
          (p.alphaByte * alphaScale).round().clamp(0, 255), p.r, p.g, p.b);
      canvas.drawCircle(Offset(p.px, p.py), cloudDotRadius, paint);
    }
  }

  /// 标签对齐方向（基于 Cb 横轴位置：Cb<0 在左侧用右对齐，Cb>0 在右侧用左对齐）
  TextAlign _labelAlign(double cb) {
    return cb < 0 ? TextAlign.right : TextAlign.left;
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
      old.binsImage != binsImage ||
      old.binsSkin != binsSkin ||
      old.skinChromaCb != skinChromaCb ||
      old.skinChromaCr != skinChromaCr ||
      old.hueOffset != hueOffset ||
      old.saturation != saturation ||
      old.showSkinDot != showSkinDot ||
      old.showSkinLine != showSkinLine ||
      old.modeProgress != modeProgress ||
      old.enterProgress != enterProgress ||
      old.probe != probe;
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
        Text('全图色彩分布（Cb/Cr）',
            style: TextStyle(
                color: InterpretationStatus.neutral,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text(
            '横轴=Cb，纵轴=Cr。\n'
            '每个色块 = 该色彩组合的\n'
            '像素密度。越亮=像素越多。',
            style: TextStyle(
                color: DetailColors.textMuted, fontSize: 9, height: 1.4)),
      ],
    );
  }

  Widget _skinRoiLegend() {
    if (!hasSkin) {
      // M2 半填充语义漏洞修复：chromaBins 有数据（ROI 内有色像素但无肤色色相匹配）
      // 时不能只写「未检出肤色」——示波器画了 ROI 云却没解读，图文割裂。
      // stage_color_card.summary 已对 chromaCb/Cr 做了「肤色色度已采样」区分，
      // 这里 legend 同步区分：有 chroma 数据显示色度落点，完全空才显示未检出。
      final hasChroma = skin.chromaBins != null || skin.chromaCb != null;
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
          Text(hasChroma ? '肤色色度已采样' : '未检出肤色',
              style: const TextStyle(
                  color: InterpretationStatus.low, fontSize: 11)),
          const SizedBox(height: 6),
          Text(
              hasChroma
                  ? 'ROI 像素已分布到 Cb/Cr 平面。\n'
                    '未匹配肤色色相区间（光点参考线）。\n'
                    '可长按图片皮肤区域手动校准。'
                  : '光点越靠近「肤色线」→ 肤色越正。\n'
                    '可长按图片皮肤区域手动校准。',
              style: const TextStyle(
                  color: DetailColors.textMuted, fontSize: 9, height: 1.4)),
        ],
      );
    }

    final dh = skin.hueOffset!.abs();
    final sat = skin.saturation!;
    final verdict = dh < 10
        ? '贴近肤色线'
        : (skin.hueOffset! > 0
            ? '偏黄气（黄金时段/港风常见）'
            : '偏粉气（日系/冷白皮方向）');
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
        // v8.1 调研词典：肤色明度 → "冷白皮/健康小麦"用户语言
        if (skin.skinLuminance != null) ...[
          const SizedBox(height: 3),
          _metric(
              '肤色明度',
              '${skin.skinLuminance!.toStringAsFixed(0)}%（'
              '${skin.skinLuminance! > 60 ? "冷白皮方向" : (skin.skinLuminance! < 40 ? "健康小麦" : "自然明度")}）',
              InterpretationStatus.neutral),
        ],
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
                fontFamily: AppTypography.monoFontFamily)),
      ],
    );
  }
}

// ============ 像素云计算纯函数（可独立 unit test）============
//
// 从 _drawChromaCloud 抽出，让 bin→点的映射逻辑可测，避免 CustomPaint
// 不产生 Element 导致 widget test 无法捕获 painter bug 的问题（评审 M3）。

/// 一个像素云色块的渲染数据
class CloudPoint {
  final double px, py;
  final int alphaByte; // 0~255
  final int r, g, b;

  const CloudPoint(this.px, this.py, this.alphaByte, this.r, this.g, this.b);
}

/// Cb/Cr → RGB 反算（用于像素云色块取真实颜色）
///
/// [yFixed] 固定 Y 值（示波器无法从 Cb/Cr 单独恢复 Y，取中灰让色彩接近视觉）。
/// Rec.709 逆变换：R = Y + 1.5748·Cr，G = Y − 0.1873·Cb − 0.4681·Cr，B = Y + 1.8556·Cb。
List<int> ycbcrToRgbForCloud(double yFixed, double cb, double cr) {
  final r = yFixed + 1.5748 * cr;
  final g = yFixed - 0.1873 * cb - 0.4681 * cr;
  final b = yFixed + 1.8556 * cb;
  return [
    r.round().clamp(0, 255),
    g.round().clamp(0, 255),
    b.round().clamp(0, 255),
  ];
}

/// HSV → RGB（用于肤色光点回退路径，从 HSV hue 还原 RGB 再走 rgbToYCbCr）
///
/// [h] 0~360°，[s]/[v] 0~1。标准 HSV→RGB 算法。
List<int> _hsvToRgb(double h, double s, double v) {
  final c = v * s;
  final hp = (h % 360) / 60.0;
  final x = c * (1 - (hp % 2 - 1).abs());
  double r, g, b;
  if (hp < 1) {
    r = c; g = x; b = 0;
  } else if (hp < 2) {
    r = x; g = c; b = 0;
  } else if (hp < 3) {
    r = 0; g = c; b = x;
  } else if (hp < 4) {
    r = 0; g = x; b = c;
  } else if (hp < 5) {
    r = x; g = 0; b = c;
  } else {
    r = c; g = 0; b = x;
  }
  final m = v - c;
  return [
    ((r + m) * 255).round().clamp(0, 255),
    ((g + m) * 255).round().clamp(0, 255),
    ((b + m) * 255).round().clamp(0, 255),
  ];
}

/// 把 Cb/Cr 64×64 bins 转成可绘制的像素云点列表。
///
/// 纯函数，无 canvas 依赖：
/// - 跳过 count==0 的 bin
/// - 每个非空 bin 算 Cb/Cr 中心值 → 画布坐标（Cb 横轴/Cr 纵轴）+ sqrt 密度压缩 alpha + 反算 RGB
/// - [radius] 为示波器半径（满量程 ±127.5 → radius）
///
/// 云色块的颜色用「反算 RGB 时 Y 固定 135」的近似值，与六色目标框（真实 Y）
/// 存在系统性偏差（饱和红/蓝端偏粉/淡紫，评审 M1）。当前作为像素密度可视化
/// 仍可接受；颜色判读以六色目标框为准。
List<CloudPoint> computeCloudPoints(
    List<int> bins, double cx, double cy, double radius) {
  final cbBins = SkinAnalysis.cbBinCount;
  final crBins = SkinAnalysis.crBinCount;
  if (bins.length < cbBins * crBins) return const [];

  int maxCount = 1;
  for (final c in bins) {
    if (c > maxCount) maxCount = c;
  }

  final cbStep = 256.0 / cbBins; // 每 bin 的 Cb 宽度
  final crStep = 256.0 / crBins;
  const yFixed = 135.0; // 略高于中灰，暗背景上云团更醒目（评审 n2）

  final result = <CloudPoint>[];
  for (var cbB = 0; cbB < cbBins; cbB++) {
    for (var crB = 0; crB < crBins; crB++) {
      final count = bins[cbB * crBins + crB];
      if (count == 0) continue;

      // bin 中心 → Cb/Cr 值（[-128,127] 空间）
      final cb = cbB * cbStep + cbStep / 2 - 128;
      final cr = crB * crStep + crStep / 2 - 128;

      // broadcast 标准坐标：Cb→横轴，Cr→纵轴（+Cr 上，canvas y 向下故减）
      final cbNorm = (cb / 127.5).clamp(-1.0, 1.0);
      final crNorm = (cr / 127.5).clamp(-1.0, 1.0);
      final px = cx + cbNorm * radius;
      final py = cy - crNorm * radius;

      // 密度 → alpha（sqrt 压缩，让热点突出，参考 darktable）
      final density = count / maxCount;
      final alpha = math.sqrt(density).clamp(0.08, 0.85);

      final rgb = ycbcrToRgbForCloud(yFixed, cb, cr);
      result.add(CloudPoint(px, py, (alpha * 255).round(), rgb[0], rgb[1], rgb[2]));
    }
  }
  return result;
}
