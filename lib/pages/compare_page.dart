// compare_page.dart — 双图对比页面（v8.1 重做）
//
// 从详情页 ⋮ 菜单进入的调色对比场景：永远暗色（gotcha #26 精神），
// 全 token 化（清除 Colors.white12/24/54 残留），三图表入场动画
// （图表规范：无静态突现），色卡百分比按底色亮度自适应字色。
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/photo_provider.dart';
import '../providers/analysis_provider.dart';
import '../models/tone_result.dart';
import '../models/palette_result.dart';
import '../services/palette_service.dart';
import '../theme/app_theme.dart';
import '../widgets/charts/chart_animations.dart';
import '../widgets/common/async_views.dart';

class ComparePage extends ConsumerWidget {
  final String photoId1;
  final String photoId2;

  const ComparePage({
    super.key,
    required this.photoId1,
    required this.photoId2,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo1 = ref.watch(photoByIdProvider(photoId1));
    final photo2 = ref.watch(photoByIdProvider(photoId2));

    return Scaffold(
      backgroundColor: DetailColors.background,
      appBar: AppBar(
        title: const Text('照片对比'),
        backgroundColor: DetailColors.background,
        foregroundColor: DetailColors.textPrimary,
        iconTheme: const IconThemeData(color: DetailColors.textPrimary),
      ),
      body: photo1.when(
        loading: () => const AsyncLoadingView(height: 300),
        error: (e, _) => AsyncErrorView(
          message: '左侧照片加载失败',
          onRetry: () => ref.invalidate(photoByIdProvider(photoId1)),
        ),
        data: (p1) => photo2.when(
          loading: () => const AsyncLoadingView(height: 300),
          error: (e, _) => AsyncErrorView(
            message: '右侧照片加载失败',
            onRetry: () => ref.invalidate(photoByIdProvider(photoId2)),
          ),
          data: (p2) {
            if (p1 == null || p2 == null) {
              return const Center(
                child: Text('照片不存在',
                    style: AppTypography.bodySecondary),
              );
            }
            return Column(
              children: [
                // 左右分屏图片
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Expanded(child: _buildImage(p1.filePath)),
                      Container(
                          width: 1, color: DetailColors.divider),
                      Expanded(child: _buildImage(p2.filePath)),
                    ],
                  ),
                ),
                // 对比分析面板
                Expanded(
                  flex: 2,
                  child: _ComparePanel(
                    photoId1: photoId1,
                    photoId2: photoId2,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImage(String filePath) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.file(
          File(filePath),
          fit: BoxFit.contain,
          // 限制解码尺寸，避免双图全分辨率解码 OOM
          // （对比页两图并排，全分辨率大图内存翻倍）
          cacheWidth: 1000,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image,
            color: DetailColors.textMuted,
            size: 48,
          ),
        ),
      ),
    );
  }
}

/// 对比分析面板
class _ComparePanel extends ConsumerWidget {
  final String photoId1;
  final String photoId2;

  const _ComparePanel({required this.photoId1, required this.photoId2});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hist1 = ref.watch(histogramProvider(photoId1));
    final hist2 = ref.watch(histogramProvider(photoId2));

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '直方图'),
              Tab(text: '色卡'),
              Tab(text: '影调'),
            ],
            tabAlignment: TabAlignment.center,
          ),
          Expanded(
            child: TabBarView(
              children: [
                // 直方图对比
                hist1.when(
                  loading: () => const AsyncLoadingView(height: 120),
                  error: (_, __) => const AsyncErrorLine(message: '左图直方图加载失败'),
                  data: (h1) => hist2.when(
                    loading: () => const AsyncLoadingView(height: 120),
                    error: (_, __) => const AsyncErrorLine(message: '右图直方图加载失败'),
                    data: (h2) => _HistogramCompare(
                      data1: h1,
                      data2: h2,
                    ),
                  ),
                ),
                // 色卡对比
                _PaletteCompare(
                  photoId1: photoId1,
                  photoId2: photoId2,
                ),
                // 影调对比
                _ToneCompare(
                  photoId1: photoId1,
                  photoId2: photoId2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 直方图对比（亮度叠加 + 入场从底部生长）
class _HistogramCompare extends StatelessWidget {
  final HistogramData data1;
  final HistogramData data2;

  const _HistogramCompare({required this.data1, required this.data2});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: Spacing.all(Spacing.md),
      child: Column(
        children: [
          // 图例（左=琥珀 accent，右=青 accentCyan，不再挪用 RGB 通道色）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(AppColors.accent, '左图'),
              const SizedBox(width: 16),
              _legend(AppColors.accentCyan, '右图'),
            ],
          ),
          const SizedBox(height: 8),
          // 叠加直方图（入场动画：两条曲线从底部生长）
          Expanded(
            child: ChartEnterBuilder(
              builder: (context, progress) => CustomPaint(
                painter: _CompareHistogramPainter(
                  lum1: data1.lum,
                  lum2: data2.lum,
                  progress: progress,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.captionWith(DetailColors.textSecondary)),
      ],
    );
  }
}

class _CompareHistogramPainter extends CustomPainter {
  final List<int> lum1;
  final List<int> lum2;

  /// 入场动画进度（从底部生长）
  final double progress;

  _CompareHistogramPainter({
    required this.lum1,
    required this.lum2,
    this.progress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final barWidth = w / 256;
    final drawH =
        h * Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));

    final maxVal = [
      lum1.reduce((a, b) => a > b ? a : b),
      lum2.reduce((a, b) => a > b ? a : b),
    ].reduce((a, b) => a > b ? a : b);

    if (maxVal == 0) return;

    // 左图亮度（琥珀）
    _drawHist(canvas, lum1, barWidth, h, drawH, maxVal,
        AppColors.accent.withValues(alpha: 0.5));
    // 右图亮度（青）
    _drawHist(canvas, lum2, barWidth, h, drawH, maxVal,
        AppColors.accentCyan.withValues(alpha: 0.5));

    // 边框
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = ChartColors.gridLight
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawHist(Canvas canvas, List<int> data, double barWidth, double h,
      double drawH, int maxVal, Color color) {
    final path = Path();
    path.moveTo(0, h);
    for (var i = 0; i < 256; i++) {
      final x = i * barWidth;
      final y = h - (data[i] / maxVal) * drawH;
      path.lineTo(x, y);
    }
    path.lineTo(256 * barWidth, h);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _CompareHistogramPainter oldDelegate) {
    return oldDelegate.lum1 != lum1 ||
        oldDelegate.lum2 != lum2 ||
        oldDelegate.progress != progress;
  }
}

/// 色卡对比（stagger 逐块展开入场 + 百分比按底色亮度自适应字色）
class _PaletteCompare extends ConsumerWidget {
  final String photoId1;
  final String photoId2;

  const _PaletteCompare({required this.photoId1, required this.photoId2});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p1 = ref.watch(paletteProvider((
      photoId: photoId1,
      algorithm: PaletteAlgorithm.celebi,
      desired: 5,
    )));
    final p2 = ref.watch(paletteProvider((
      photoId: photoId2,
      algorithm: PaletteAlgorithm.celebi,
      desired: 5,
    )));

    return SingleChildScrollView(
      padding: Spacing.all(Spacing.md),
      child: Column(
        children: [
          _paletteRow(context, '左图', p1),
          const SizedBox(height: 12),
          _paletteRow(context, '右图', p2),
        ],
      ),
    );
  }

  Widget _paletteRow(BuildContext context, String label, AsyncValue<PaletteResult> async) {
    return async.when(
      loading: () => const AsyncLoadingView(height: 40),
      error: (_, __) => AsyncErrorLine(message: '$label 色卡加载失败'),
      data: (palette) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.captionWith(DetailColors.textSecondary)),
            const SizedBox(height: 4),
            Row(
              children: palette.colors
                  .asMap()
                  .entries
                  .map((entry) {
                return Expanded(
                  child: _AnimatedSwatch(
                    index: entry.key,
                    color: Color.fromARGB(0xFF, entry.value.r, entry.value.g, entry.value.b),
                    ratio: entry.value.ratio,
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

/// 色块（入场 stagger 展开 + 百分比文字按底色亮度选深/浅字）
class _AnimatedSwatch extends StatelessWidget {
  final int index;
  final Color color;
  final double ratio;

  const _AnimatedSwatch({
    required this.index,
    required this.color,
    required this.ratio,
  });

  /// Rec.709 亮度判断：亮底用深字、暗底用浅字（修复"白字浅色块不可读"）
  static bool _isLightBackground(Color c) {
    final r = (c.r * 255.0).round();
    final g = (c.g * 255.0).round();
    final b = (c.b * 255.0).round();
    return 0.2126 * r + 0.7152 * g + 0.0722 * b > 140;
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        _isLightBackground(color) ? AppColors.lightTextPrimary : DetailColors.textPrimary;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: AppAnimations.chartEnterDuration,
      // stagger：每块延迟 40ms，形成从左到右的展开节奏
      curve: Interval(
        (index * 0.08).clamp(0.0, 0.8),
        ((index * 0.08) + 0.2).clamp(0.0, 1.0),
        curve: Curves2.chartEnter,
      ),
      builder: (context, t, _) {
        return Opacity(
          opacity: t,
          child: Container(
            height: 40 * t,
            color: color,
            alignment: Alignment.bottomCenter,
            child: ratio > 0
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${ratio.toStringAsFixed(0)}%',
                      style: AppTypography.captionWith(labelColor)
                          .copyWith(fontSize: 9),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// 影调对比（五区条 stagger 生长入场）
class _ToneCompare extends ConsumerWidget {
  final String photoId1;
  final String photoId2;

  const _ToneCompare({required this.photoId1, required this.photoId2});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone1 = ref.watch(toneProvider(photoId1));
    final tone2 = ref.watch(toneProvider(photoId2));

    return SingleChildScrollView(
      padding: Spacing.all(Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _toneColumn(context, '左图', tone1)),
          const SizedBox(width: 8),
          Expanded(child: _toneColumn(context, '右图', tone2)),
        ],
      ),
    );
  }

  Widget _toneColumn(BuildContext context, String label, AsyncValue async) {
    return async.when(
      loading: () => const AsyncLoadingView(height: 60),
      error: (_, __) => AsyncErrorLine(message: '$label 影调加载失败'),
      data: (tone) {
        final t = tone as ToneResult;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.captionWith(DetailColors.textSecondary)),
            const SizedBox(height: 8),
            _zoneBar(context, 0, '黑色', t.blacks),
            const SizedBox(height: 3),
            _zoneBar(context, 1, '阴影', t.shadows),
            const SizedBox(height: 3),
            _zoneBar(context, 2, '中间调', t.midtones),
            const SizedBox(height: 3),
            _zoneBar(context, 3, '高光', t.highlights),
            const SizedBox(height: 3),
            _zoneBar(context, 4, '白色', t.whites),
            const SizedBox(height: 8),
            Text('均值 ${t.mean.toStringAsFixed(1)}', style: AppTypography.mono),
            Text('基调 ${t.toneKeyLabel}',
                style: AppTypography.labelWith(DetailColors.accent)),
          ],
        );
      },
    );
  }

  Widget _zoneBar(BuildContext context, int index, String label, double percent) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: percent / 100),
      duration: AppAnimations.chartEnterDuration,
      curve: Interval(
        (index * 0.1).clamp(0.0, 0.7),
        ((index * 0.1) + 0.3).clamp(0.0, 1.0),
        curve: Curves2.chartEnter,
      ),
      builder: (context, value, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: AppTypography.captionMuted),
                const Spacer(),
                Text('${percent.toStringAsFixed(1)}%',
                    style: AppTypography.mono.copyWith(fontSize: 10)),
              ],
            ),
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: Radii.xsBorder,
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: ChartColors.gridFaint,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
          ],
        );
      },
    );
  }
}
