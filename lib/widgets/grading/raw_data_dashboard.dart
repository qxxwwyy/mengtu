// raw_data_dashboard.dart — 数据仪表盘全屏页（v3.5 PR3）
//
// 从 DetailBottomPanel 工具行「数据」入口进入。替代原 6 Tab 的信息/直方图/
// 色卡/影调/和谐/取色内容，重排为物理分类（spec §3.10）：
//   ▼ 影调读数 / ▼ 色彩读数 / ▼ 隔离读数 / ▼ 拍摄参数（EXIF）
// 大字号数值 + 迷你可视化，像 CT 报告。
//
// 复用现有组件不重写算法：HistogramPainter / ColorCard / HarmonyCard /
// ToneInfoCard。只读展示（EXIF 重读功能仍在详情页信息流保留）。
//
// gotcha #26：本页作为详情页的子页，继承暗色（DetailColors token）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/analysis_provider.dart';
import '../../providers/exif_provider.dart';
import '../../services/palette_service.dart';
import '../../theme/app_theme.dart';
import '../color_card.dart';
import '../harmony_card.dart';
import '../histogram_painter.dart';
import '../tone_info_card.dart';

/// 数据仪表盘：分类展示所有原始读数
class RawDataDashboard extends ConsumerWidget {
  final String photoId;

  const RawDataDashboard({super.key, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: DetailColors.background,
      appBar: AppBar(
        title: const Text('数据读数'),
        backgroundColor: DetailColors.panelSurface,
        foregroundColor: DetailColors.textPrimary,
        iconTheme: const IconThemeData(color: DetailColors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          _SectionHeader(title: '影调读数', icon: Icons.tonality),
          _TonalReadingsSection(photoId: photoId),
          const SizedBox(height: 16),
          _SectionHeader(title: '色彩读数', icon: Icons.palette_outlined),
          _ColorReadingsSection(photoId: photoId),
          const SizedBox(height: 16),
          _SectionHeader(title: '隔离读数', icon: Icons.center_focus_strong_outlined),
          _IsolationReadingsSection(photoId: photoId),
          const SizedBox(height: 16),
          _SectionHeader(title: '拍摄参数', icon: Icons.camera_outlined),
          _ExifReadingsSection(photoId: photoId),
        ],
      ),
    );
  }
}

/// Section 标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.darkAccent),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                color: AppColors.darkAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              )),
        ],
      ),
    );
  }
}

/// 数值卡片（大字号数值 + 标签）
class _ReadingTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;

  const _ReadingTile({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DetailColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: DetailColors.textMuted, fontSize: 10)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: const TextStyle(
                    color: DetailColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  )),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(unit!,
                    style: const TextStyle(
                        color: DetailColors.textSecondary, fontSize: 11)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============ 影调读数 ============

class _TonalReadingsSection extends ConsumerWidget {
  final String photoId;
  const _TonalReadingsSection({required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final histAsync = ref.watch(histogramProvider(photoId));
    final toneAsync = ref.watch(toneProvider(photoId));
    final advancedAsync = ref.watch(advancedMetricsProvider(photoId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 直方图
        histAsync.when(
          loading: () => const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('直方图加载失败: $e',
              style: const TextStyle(color: DetailColors.warning, fontSize: 11)),
          data: (hist) => Container(
            height: 100,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DetailColors.cardSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomPaint(
              painter: HistogramPainter(data: hist, mode: HistogramMode.rgbLum),
              child: Container(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 数值网格
        toneAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (tone) => GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.2,
            children: [
              _ReadingTile(label: '均值', value: tone.mean.toStringAsFixed(0)),
              _ReadingTile(label: '中位数', value: tone.median.toStringAsFixed(0)),
              _ReadingTile(
                  label: 'RMS 对比度', value: tone.rmsContrast.toStringAsFixed(1)),
              _ReadingTile(label: '信息熵', value: tone.entropy.toStringAsFixed(2)),
              _ReadingTile(
                  label: '最暗', value: '${tone.minVal}', unit: '/255'),
              _ReadingTile(
                  label: '最亮', value: '${tone.maxVal}', unit: '/255'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 黑点/白点/十大影调（advanced）
        advancedAsync.maybeWhen(
          data: (a) => a == null
              ? const SizedBox.shrink()
              : GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 2.2,
                  children: [
                    _ReadingTile(
                        label: '黑点偏移',
                        value: a.blackPointOffset.toStringAsFixed(1)),
                    _ReadingTile(
                        label: '白点压缩',
                        value: a.whitePointCompression.toStringAsFixed(1)),
                    _ReadingTile(
                        label: '十大影调',
                        value: a.tenTonalType,
                        unit: ''),
                  ],
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        // ToneInfoCard（5 区域占比条）
        toneAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (tone) => ToneInfoCard(tone: tone),
        ),
      ],
    );
  }
}

// ============ 色彩读数 ============

class _ColorReadingsSection extends ConsumerWidget {
  final String photoId;
  const _ColorReadingsSection({required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skinAsync = ref.watch(skinProvider(photoId));
    final paletteAsync = ref.watch(paletteProvider(
      (photoId: photoId, algorithm: PaletteAlgorithm.celebi, desired: 5),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 色卡（ColorCard 内部自行 watch paletteProvider，无需外层包）
        ColorCard(photoId: photoId),
        const SizedBox(height: 8),
        // 肤色读数
        skinAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (skin) {
            if (skin.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DetailColors.cardSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('未检出肤色',
                    style:
                        TextStyle(color: DetailColors.textMuted, fontSize: 11)),
              );
            }
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 2.2,
              children: [
                if (skin.hueOffset != null)
                  _ReadingTile(
                      label: '色相偏差 ΔH',
                      value: skin.hueOffset!.toStringAsFixed(0),
                      unit: '°'),
                if (skin.saturation != null)
                  _ReadingTile(
                      label: '饱和度',
                      value: skin.saturation!.toStringAsFixed(0),
                      unit: '%'),
                if (skin.skinLuminance != null)
                  _ReadingTile(
                      label: '肤色明度',
                      value: skin.skinLuminance!.toStringAsFixed(0),
                      unit: '%'),
              ],
            );
          },
        ),
        // 和谐度（依赖色卡）
        const SizedBox(height: 8),
        paletteAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (palette) => HarmonyCard(palette: palette),
        ),
      ],
    );
  }
}

// ============ 隔离读数 ============

class _IsolationReadingsSection extends ConsumerWidget {
  final String photoId;
  const _IsolationReadingsSection({required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skinAsync = ref.watch(skinProvider(photoId));

    final tiles = <Widget>[];

    // SLS / SCS（来自 skin）
    final skin = skinAsync.asData?.value;
    if (skin != null && !skin.isEmpty) {
      if (skin.luminanceSeparation != null) {
        tiles.add(_ReadingTile(
            label: '明度隔离 SLS',
            value: skin.luminanceSeparation!.toStringAsFixed(0),
            unit: '%'));
      }
      if (skin.colorSeparation != null) {
        tiles.add(_ReadingTile(
            label: '色彩隔离 SCS',
            value: skin.colorSeparation!.toStringAsFixed(0),
            unit: '°'));
      }
    }

    // v7.0：STI/FLC 行已移除（依赖 Face Mesh，SCRFD 只给 5 点无法计算）。
    // advanced 仍含 black_point/white_point/ten_tonal（在影调 section 展示）。

    if (tiles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: DetailColors.cardSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('未检出主体（无脸或侧脸），隔离度指标不可用',
            style: TextStyle(color: DetailColors.textMuted, fontSize: 11, height: 1.4)),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 2.5,
      children: tiles,
    );
  }
}

// ============ 拍摄参数（EXIF）============

class _ExifReadingsSection extends ConsumerWidget {
  final String photoId;
  const _ExifReadingsSection({required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exifAsync = ref.watch(exifInfoProvider(photoId));

    return exifAsync.when(
      loading: () => const SizedBox(
          height: 60, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('EXIF 加载失败: $e',
          style: const TextStyle(color: DetailColors.warning, fontSize: 11)),
      data: (exif) {
        if (exif == null || exif.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: DetailColors.cardSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('本照片无拍摄参数',
                style:
                    TextStyle(color: DetailColors.textMuted, fontSize: 11)),
          );
        }
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DetailColors.cardSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (exif.cameraDisplay != null)
                _ExifLine(label: '相机', value: exif.cameraDisplay!),
              if (exif.lensModel != null)
                _ExifLine(label: '镜头', value: exif.lensModel!),
              if (exif.exposureTriple.isNotEmpty)
                _ExifLine(label: '曝光', value: exif.exposureTriple, mono: true),
              if (exif.takenAt != null)
                _ExifLine(label: '拍摄时间', value: _formatDate(exif.takenAt!)),
            ],
          ),
        );
      },
    );
  }

  static String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _ExifLine extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _ExifLine({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label,
                style: const TextStyle(
                    color: DetailColors.textMuted, fontSize: 11)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                  color: DetailColors.textPrimary,
                  fontSize: 12,
                  fontFamily: mono ? 'monospace' : null,
                )),
          ),
        ],
      ),
    );
  }
}
