// harmony_card.dart — 色彩和谐度分析卡片
//
// v8.1：作为详情页生态组件改用 DetailColors（永远暗色，gotcha #26 —— 此前
// 依赖 Theme.of(context).colorScheme，浅色主题会泄漏进详情页）；token 化清账。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/harmony_service.dart';
import '../models/palette_result.dart';
import 'color_wheel.dart';
import '../theme/app_theme.dart';

/// 和谐度分析卡片
class HarmonyCard extends ConsumerWidget {
  final PaletteResult palette;

  const HarmonyCard({super.key, required this.palette});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = analyzeHarmony(palette);

    return SingleChildScrollView(
      padding: Spacing.all(Spacing.md),
      child: Column(
        children: [
          // 色轮
          ColorWheel(result: result),
          const SizedBox(height: 12),
          // 配色方案标签
          Container(
            padding: Spacing.hv(Spacing.md, 6),
            decoration: BoxDecoration(
              color: DetailColors.accent.withValues(alpha: 0.15),
              borderRadius: Radii.lgBorder,
              border: Border.all(
                color: DetailColors.accent.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              result.type.label,
              style: AppTypography.labelWith(DetailColors.accent),
            ),
          ),
          const SizedBox(height: 8),
          // 置信度条
          if (result.confidence > 0) ...[
            Row(
              children: [
                Text('置信度', style: AppTypography.captionWith(DetailColors.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: result.confidence,
                    backgroundColor: DetailColors.controlSurface,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(DetailColors.accent),
                    minHeight: 4,
                    borderRadius: Radii.xsBorder,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${(result.confidence * 100).round()}%',
                    style: AppTypography.mono.copyWith(fontSize: 11)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // 描述
          Container(
            width: double.infinity,
            padding: Spacing.all(Spacing.md),
            decoration: BoxDecoration(
              color: DetailColors.controlSurface,
              borderRadius: Radii.mdBorder,
            ),
            child: Text(
              result.description,
              style: AppTypography.captionWith(DetailColors.textSecondary)
                  .copyWith(height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          // 色相值列表
          if (result.hues.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: result.hues.map((hue) {
                final color = HSLColor.fromAHSL(
                  1.0,
                  hue.toDouble(),
                  0.8,
                  0.6,
                ).toColor();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ChartColors.gridLight,
                          width: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('$hue°', style: AppTypography.mono.copyWith(fontSize: 11)),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
