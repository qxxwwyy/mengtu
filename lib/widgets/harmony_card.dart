// harmony_card.dart — 色彩和谐度分析卡片
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
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 色轮
          ColorWheel(result: result),
          const SizedBox(height: 12),
          // 配色方案标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: Radii.lgBorder,
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              result.type.label,
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 置信度条
          if (result.confidence > 0) ...[
            Row(
              children: [
                Text(
                  '置信度',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: result.confidence,
                    backgroundColor:
                        colorScheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    minHeight: 4,
                    borderRadius: Radii.xsBorder,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(result.confidence * 100).round()}%',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // 描述
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: Radii.legacy8Border,
            ),
            child: Text(
              result.description,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.5,
              ),
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
                    Text(
                      '$hue°',
                      style: TextStyle(
                        color:
                            colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
