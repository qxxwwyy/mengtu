// tone_info_card.dart — 影调信息组件（五区域占比 + 基调标签 + 统计指标）
import 'package:flutter/material.dart';
import '../models/tone_result.dart';
import '../theme/app_theme.dart';

/// 影调信息展示
class ToneInfoCard extends StatelessWidget {
  final ToneResult tone;

  const ToneInfoCard({super.key, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToneKeyBadge(context),
          const SizedBox(height: 12),
          _buildZoneBars(context),
          const SizedBox(height: 12),
          _buildStatsGrid(context),
        ],
      ),
    );
  }

  Widget _buildToneKeyBadge(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: Radii.lgBorder,
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_toneKeyIcon, color: accent, size: 18),
          const SizedBox(width: 6),
          Text(
            tone.toneKeyLabel,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text('· ${tone.toneRangeLabel}',
              style: TextStyle(color: secondary, fontSize: 12)),
        ],
      ),
    );
  }

  IconData get _toneKeyIcon {
    switch (tone.toneKey) {
      case 'high':
        return Icons.wb_sunny;
      case 'low':
        return Icons.brightness_3;
      case 'mid':
        return Icons.brightness_medium;
      case 'full':
        return Icons.auto_awesome;
      default:
        return Icons.brightness_medium;
    }
  }

  Widget _buildZoneBars(BuildContext context) {
    final labelColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    // 影调五区域色用 ChartColors 统一定义
    final blackColor = ChartColors.toneBlacks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('明度分区',
            style: TextStyle(
                fontSize: 12, color: labelColor, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _ZoneBar(
            label: '黑色', ratio: tone.blacks, color: blackColor),
        const SizedBox(height: 6),
        _ZoneBar(
            label: '阴影', ratio: tone.shadows, color: ChartColors.toneShadows),
        const SizedBox(height: 6),
        _ZoneBar(
            label: '中间调', ratio: tone.midtones, color: ChartColors.toneMidtones),
        const SizedBox(height: 6),
        _ZoneBar(
            label: '高光', ratio: tone.highlights, color: ChartColors.toneHighlights),
        const SizedBox(height: 6),
        _ZoneBar(
            label: '白色',
            ratio: tone.whites,
            color: ChartColors.toneWhites,
            textColor: AppColors.lightTextPrimary),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    final labelColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('统计指标',
            style: TextStyle(
                fontSize: 12, color: labelColor, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.6,
          children: [
            _StatCell(label: '均值', value: tone.mean.toStringAsFixed(1), accent: accent),
            _StatCell(label: '中位数', value: tone.median.toStringAsFixed(0), accent: accent),
            _StatCell(label: '标准差', value: tone.std.toStringAsFixed(1), accent: accent),
            _StatCell(label: '峰值', value: tone.peakPosition.toStringAsFixed(0), accent: accent),
            _StatCell(label: '最暗', value: '${tone.minVal}', accent: accent),
            _StatCell(label: '最亮', value: '${tone.maxVal}', accent: accent),
          ],
        ),
      ],
    );
  }
}

/// 区域占比横向条
class _ZoneBar extends StatelessWidget {
  final String label;
  final double ratio;
  final Color color;
  final Color? textColor;

  const _ZoneBar({
    required this.label,
    required this.ratio,
    required this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor =
        textColor ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: Radii.xsBorder,
            child: LinearProgressIndicator(
              value: (ratio / 100).clamp(0.0, 1.0),
              minHeight: 16,
              backgroundColor: color.withValues(alpha: 0.15),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          child: Text(
            '${ratio.toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500, color: labelColor),
          ),
        ),
      ],
    );
  }
}

/// 统计指标单元格
class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _StatCell({required this.label, required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: Radii.smBorder,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4))),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: accent)),
        ],
      ),
    );
  }
}
