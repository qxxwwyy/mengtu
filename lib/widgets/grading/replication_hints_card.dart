// replication_hints_card.dart — 复刻参数附录卡片（v3.5 PR5）
//
// 在阶④匹配卡片展开态底部展示，复刻参数来自 ReplicationHintsService。
// 措辞：「若想复刻此样片影调，可尝试：…」（解读式，非诊断命令式）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/advanced_portrait_metrics.dart';
import '../../models/tone_result.dart';
import '../../providers/analysis_provider.dart';
import '../../services/builtin_profiles.dart';
import '../../services/replication_hints_service.dart';
import '../../theme/app_theme.dart';

/// 复刻参数附录卡片
class ReplicationHintsCard extends ConsumerWidget {
  final String photoId;
  final AsyncValue<ToneResult> tone;
  final AsyncValue<AdvancedPortraitMetrics?> advanced;
  final String targetProfileName;
  final String? targetStyleKey;

  const ReplicationHintsCard({
    super.key,
    required this.photoId,
    required this.tone,
    required this.advanced,
    required this.targetProfileName,
    this.targetStyleKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toneVal = tone.asData?.value;
    final advVal = advanced.asData?.value;
    final skinAsync = ref.watch(skinProvider(photoId));
    final skinVal = skinAsync.asData?.value;

    final service = ReplicationHintsService();
    final targetProfile = BuiltinProfiles.getByKey(targetStyleKey);
    final targetTemplate = targetProfile?.replicationTemplate ?? const <ReplicationHint>[];

    final hints = service.generateHints(
      tone: toneVal,
      advanced: advVal,
      skin: skinVal,
      targetStyleKey: targetStyleKey,
      targetTemplate: targetTemplate,
    );

    if (hints.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DetailColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppColors.darkAccent.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 14, color: AppColors.darkAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '复刻参考：若想接近「$targetProfileName」',
                  style: const TextStyle(
                    color: AppColors.darkAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...hints.map((h) => _HintRow(hint: h)),
        ],
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  final ReplicationHint hint;
  const _HintRow({required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 类别标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.darkAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(hint.category,
                style: const TextStyle(
                    color: AppColors.darkAccent, fontSize: 10)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(hint.parameter,
                        style: const TextStyle(
                            color: DetailColors.textSecondary, fontSize: 11)),
                    const Spacer(),
                    Text(hint.value,
                        style: const TextStyle(
                          color: AppColors.darkAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        )),
                  ],
                ),
                const SizedBox(height: 2),
                Text(hint.note,
                    style: const TextStyle(
                        color: DetailColors.textMuted,
                        fontSize: 10,
                        height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
