// compare_page.dart — 双图对比页面
//
// 左右分屏显示两张照片，底部对比分析面板
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/photo_provider.dart';
import '../providers/analysis_provider.dart';
import '../models/tone_result.dart';
import '../models/palette_result.dart';
import '../services/palette_service.dart';

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
      appBar: AppBar(title: const Text('对比')),
      body: photo1.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('错误: $e')),
        data: (p1) => photo2.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('错误: $e')),
          data: (p2) {
            if (p1 == null || p2 == null) {
              return const Center(child: Text('照片不存在'));
            }
            return Column(
              children: [
                // 左右分屏图片
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Expanded(child: _buildImage(p1.filePath)),
                      Container(width: 1, color: Colors.white12),
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
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image,
            color: Colors.white54,
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
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const Center(child: Text('加载失败')),
                  data: (h1) => hist2.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const Center(child: Text('加载失败')),
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

/// 直方图对比（亮度叠加）
class _HistogramCompare extends StatelessWidget {
  final HistogramData data1;
  final HistogramData data2;

  const _HistogramCompare({required this.data1, required this.data2});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 图例
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(context, Colors.red.withValues(alpha: 0.6), '左图'),
              const SizedBox(width: 16),
              _legend(context, Colors.blue.withValues(alpha: 0.6), '右图'),
            ],
          ),
          const SizedBox(height: 8),
          // 叠加直方图
          Expanded(
            child: CustomPaint(
              painter: _CompareHistogramPainter(
                lum1: data1.lum,
                lum2: data2.lum,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _CompareHistogramPainter extends CustomPainter {
  final List<int> lum1;
  final List<int> lum2;

  _CompareHistogramPainter({required this.lum1, required this.lum2});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final barWidth = w / 256;

    final maxVal = [
      lum1.reduce((a, b) => a > b ? a : b),
      lum2.reduce((a, b) => a > b ? a : b),
    ].reduce((a, b) => a > b ? a : b);

    if (maxVal == 0) return;

    // 左图亮度（红色）
    _drawHist(canvas, lum1, barWidth, h, maxVal,
        Colors.red.withValues(alpha: 0.5));
    // 右图亮度（蓝色）
    _drawHist(canvas, lum2, barWidth, h, maxVal,
        Colors.blue.withValues(alpha: 0.5));

    // 边框
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawHist(Canvas canvas, List<int> data, double barWidth, double h,
      int maxVal, Color color) {
    final path = Path();
    path.moveTo(0, h);
    for (var i = 0; i < 256; i++) {
      final x = i * barWidth;
      final y = h - (data[i] / maxVal) * h;
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
    return oldDelegate.lum1 != lum1 || oldDelegate.lum2 != lum2;
  }
}

/// 色卡对比
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
      padding: const EdgeInsets.all(12),
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
      loading: () => const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Text('$label: 加载失败'),
      data: (palette) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            Row(
              children: palette.colors.map((c) {
                return Expanded(
                  child: Container(
                    height: 40,
                    color: Color.fromARGB(0xFF, c.r, c.g, c.b),
                    child: c.ratio > 0
                        ? Align(
                            alignment: Alignment.bottomCenter,
                            child: Text(
                              '${c.ratio.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          )
                        : null,
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

/// 影调对比
class _ToneCompare extends ConsumerWidget {
  final String photoId1;
  final String photoId2;

  const _ToneCompare({required this.photoId1, required this.photoId2});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone1 = ref.watch(toneProvider(photoId1));
    final tone2 = ref.watch(toneProvider(photoId2));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
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
    final colorScheme = Theme.of(context).colorScheme;

    return async.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Text('$label: 加载失败'),
      data: (tone) {
        final t = tone as ToneResult;
        // 判断差异
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                )),
            const SizedBox(height: 8),
            _zoneBar(context, '黑色', t.blacks),
            const SizedBox(height: 3),
            _zoneBar(context, '阴影', t.shadows),
            const SizedBox(height: 3),
            _zoneBar(context, '中间调', t.midtones),
            const SizedBox(height: 3),
            _zoneBar(context, '高光', t.highlights),
            const SizedBox(height: 3),
            _zoneBar(context, '白色', t.whites),
            const SizedBox(height: 8),
            Text('均值 ${t.mean.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 10)),
            Text('基调 ${t.toneKeyLabel}',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.primary,
                )),
          ],
        );
      },
    );
  }

  Widget _zoneBar(BuildContext context, String label, double percent) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 10)),
            const Spacer(),
            Text('${percent.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 10)),
          ],
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 6,
            backgroundColor:
                colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        ),
      ],
    );
  }
}
