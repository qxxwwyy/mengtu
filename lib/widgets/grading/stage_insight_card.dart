// stage_insight_card.dart — 阶④洞察卡片（v8.0）
//
// 替代已删除的 StageArchiveMatchCard（档案比对）。
// 从现有指标（tone/advanced/skin）综合生成一段整体性解读：
// 风格标签 + 三维度（影调/色彩/手法）描述 + 一句话总结。
//
// 设计理念：样片分析工具的「为什么好看」洞察，非诊断/修复指令。
// 措辞纯描述性，不带对错判断。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tone_result.dart';
import '../../providers/analysis_provider.dart';
import '../../services/insight_service.dart';
import '../../theme/app_theme.dart';
import 'stage_card.dart';

/// 阶④洞察卡片
class StageInsightCard extends ConsumerWidget {
  final String photoId;

  const StageInsightCard({super.key, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toneAsync = ref.watch(toneProvider(photoId));
    final advancedAsync = ref.watch(advancedMetricsProvider(photoId));
    final skinAsync = ref.watch(skinProvider(photoId));
    final histAsync = ref.watch(histogramProvider(photoId));

    final toneVal = toneAsync.asData?.value;
    final advVal = advancedAsync.asData?.value;
    final skinVal = skinAsync.asData?.value ?? const SkinAnalysis();
    final hueHist = histAsync.asData?.value.hue;

    if (toneVal == null) {
      return StageCard(
        index: 4,
        title: '洞察',
        summary: toneAsync.isLoading ? '分析中…' : '暂无数据',
        expanded: false,
        onTap: () {},
        children: const [SizedBox.shrink()],
      );
    }

    final service = InsightService();
    final insight = service.generate(
      tone: toneVal,
      advanced: advVal,
      skin: skinVal,
      hueHistogram: hueHist,
    );

    final summary = insight.styleLabel ?? '综合特征';

    return StageInsightExpandedCard(
      insight: insight,
      summary: summary,
    );
  }
}

/// 展开态洞察卡片（默认展开，因为这是用户最想看的）
class StageInsightExpandedCard extends StatefulWidget {
  final PhotoInsight insight;
  final String summary;

  const StageInsightExpandedCard({
    super.key,
    required this.insight,
    required this.summary,
  });

  @override
  State<StageInsightExpandedCard> createState() =>
      _StageInsightExpandedCardState();
}

class _StageInsightExpandedCardState extends State<StageInsightExpandedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final insight = widget.insight;
    return StageCard(
      index: 4,
      title: '洞察',
      summary: widget.summary,
      expanded: _expanded,
      onTap: () => setState(() => _expanded = !_expanded),
      children: [
        if (_expanded) ...[
          // 风格标签
          if (insight.styleLabel != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: Radii.mdBorder,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    '整体风格：${insight.styleLabel}',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          // 三维度解读
          _InsightSection(
            icon: Icons.tonality,
            label: '影调',
            text: insight.tonalInsight,
          ),
          const SizedBox(height: 8),
          _InsightSection(
            icon: Icons.palette_outlined,
            label: '色彩',
            text: insight.colorInsight,
          ),
          const SizedBox(height: 8),
          _InsightSection(
            icon: Icons.person_outline,
            label: '手法',
            text: insight.techniqueInsight,
          ),
          // 分隔线 + 一句话总结
          if (insight.summary.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                color: ChartColors.gridFaint,
                height: 0.5,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 14, color: AppColors.accent.withValues(alpha: 0.8)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    insight.summary,
                    style: TextStyle(
                      color: AppColors.accent.withValues(alpha: 0.9),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// 单个维度解读行
class _InsightSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;

  const _InsightSection({
    required this.icon,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: DetailColors.textSecondary),
        const SizedBox(width: 6),
        SizedBox(
          width: 32,
          child: Text(label,
              style: const TextStyle(
                color: DetailColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
        ),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                color: DetailColors.textPrimary,
                fontSize: 11,
                height: 1.5,
              )),
        ),
      ],
    );
  }
}
