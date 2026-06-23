// stage_archive_match_card.dart — 阶④档案比对（v3.5 PR4 + PR5）
//
// watch styleProfileMatchProvider 取匹配结果，按分层置信度渲染：
// - 无档案 → 引导创建
// - 有匹配 → 相似度列表 + 雷达图 + 复刻参数附录（PR5）
//
// 相似度分层（spec §3.9 O6 / gotcha 小样本信任）：
// N<5 → 定性（方向接近/差异较大）+ 置信度提示
// N>=5 → 显示 % 相似度
// 内置理论档案 → 显示 % 但标注「理论参照」
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/style_profile_match.dart';
import '../../models/tone_result.dart';
import '../../models/advanced_portrait_metrics.dart';
import '../../providers/style_profile_provider.dart';
import '../../theme/app_theme.dart';
import 'fingerprint_radar.dart';
import 'interpretation_row.dart';
import 'replication_hints_card.dart';
import 'stage_card.dart';

/// 阶④档案比对卡片
class StageArchiveMatchCard extends ConsumerWidget {
  final String photoId;

  /// 影调数据（供 PR5 复刻参数生成）
  final AsyncValue<ToneResult> tone;

  /// 高级指标（供 PR5 复刻参数生成）
  final AsyncValue<AdvancedPortraitMetrics?> advanced;

  const StageArchiveMatchCard({
    super.key,
    required this.photoId,
    required this.tone,
    required this.advanced,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(styleProfilesProvider);
    final hasProfiles = profilesAsync.maybeWhen(
      data: (profiles) => profiles.isNotEmpty,
      orElse: () => false,
    );

    // 无档案 → 引导卡片
    if (!hasProfiles) {
      return StageCard(
        index: 4,
        title: '档案比对',
        summary: '创建风格档案后可匹配',
        expanded: false,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请在「我的」Tab 创建风格档案'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        children: const [
          Text(
            '将样片导入风格档案后，这里会显示当前照片与档案的相似度比对，'
            '帮助识别这张照片接近哪种风格。',
            style: TextStyle(
              color: Color(0x55FFFFFF),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    // 有档案 → 显示匹配
    final matchesAsync = ref.watch(styleProfileMatchProvider(photoId));
    return matchesAsync.when(
      loading: () => StageCard(
        index: 4,
        title: '档案比对',
        summary: '匹配中…',
        expanded: false,
        onTap: () {},
        children: const [SizedBox.shrink()],
      ),
      error: (e, _) => StageCard(
        index: 4,
        title: '档案比对',
        summary: '匹配失败',
        expanded: false,
        onTap: () {},
        children: [Text('匹配失败：$e',
            style: const TextStyle(color: InterpretationStatus.bad, fontSize: 11))],
      ),
      data: (matches) {
        if (matches.isEmpty) {
          return StageCard(
            index: 4,
            title: '档案比对',
            summary: '档案未生成指纹',
            expanded: false,
            onTap: () {},
            children: const [
              Text('档案内无照片或指纹未计算，请在档案管理页重算。',
                  style: TextStyle(color: Color(0x55FFFFFF), fontSize: 11)),
            ],
          );
        }
        final best = matches.first;
        return _MatchedCard(
          photoId: photoId,
          matches: matches,
          best: best,
          tone: tone,
          advanced: advanced,
        );
      },
    );
  }
}

/// 已匹配的卡片（展示最佳匹配 + 列表 + 雷达图 + 复刻参数）
class _MatchedCard extends ConsumerStatefulWidget {
  final String photoId;
  final List<StyleProfileMatch> matches;
  final StyleProfileMatch best;
  final AsyncValue<ToneResult> tone;
  final AsyncValue<AdvancedPortraitMetrics?> advanced;

  const _MatchedCard({
    required this.photoId,
    required this.matches,
    required this.best,
    required this.tone,
    required this.advanced,
  });

  @override
  ConsumerState<_MatchedCard> createState() => _MatchedCardState();
}

class _MatchedCardState extends ConsumerState<_MatchedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final best = widget.best;
    return StageCard(
      index: 4,
      title: '档案比对',
      summary: '最接近：${best.profileName} · ${best.similarityText}',
      expanded: _expanded,
      onTap: () => setState(() => _expanded = !_expanded),
      children: [
        if (_expanded) ...[
          // 最佳匹配的雷达图
          FingerprintRadar(current: best.currentFingerprint),
          const SizedBox(height: 8),
          // 相似度列表
          ...widget.matches.take(3).map((m) => _SimilarityTile(match: m)),
          // 复刻参数附录（PR5）
          ReplicationHintsCard(
            photoId: widget.photoId,
            tone: widget.tone,
            advanced: widget.advanced,
            targetProfileName: best.profileName,
            targetStyleKey: best.builtinKey,
          ),
        ],
      ],
    );
  }
}

/// 相似度条目（分层置信度展示）
///
/// 颜色与文字同步分层（v3.5 二轮复核修复 P4）：
/// - 内置理论档案 → 中性 accent 色（不误导为「好」，配合「理论参照」文案）
/// - 小样本（N<5）→ 定性色（方向接近=neutral / 差异较大=low），不用 good 绿色
///   避免与 similarityText 的「差异较大」定性文字矛盾
/// - N≥5 → 才用绝对阈值的 good/warn/low
class _SimilarityTile extends StatelessWidget {
  final StyleProfileMatch match;
  const _SimilarityTile({required this.match});

  @override
  Widget build(BuildContext context) {
    final sim = match.similarity;
    final Color color;
    if (match.isBuiltin) {
      // 内置理论档案：中性色，配合 confidenceHint「理论推导值」说明
      color = InterpretationStatus.neutral;
    } else if (match.sampleCount < 5) {
      // 小样本：定性（与 similarityText 的 0.7 阈值一致）
      color = sim > 0.7
          ? InterpretationStatus.neutral
          : InterpretationStatus.low;
    } else {
      // N≥5：绝对阈值
      color = sim > 0.7
          ? InterpretationStatus.good
          : (sim > 0.4 ? InterpretationStatus.warn : InterpretationStatus.low);
    }

    // confidenceHint：内置档案或小样本时补充说明（P3，理论参照数值偏低属正常）
    final hint = match.confidenceHint;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(match.profileName,
                          style: const TextStyle(
                              color: AppColors.darkTextPrimary, fontSize: 12)),
                    ),
                    Text(match.similarityText,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        )),
                  ],
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(hint,
                      style: const TextStyle(
                        color: DetailColors.textMuted,
                        fontSize: 10,
                        height: 1.3,
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
