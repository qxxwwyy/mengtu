// stage_tonal_card.dart — 阶①影调手法（v3.5 PR3）
//
// 教学核心：当前直方图 + 半透明背景的典型影调参照叠放（ReferenceHistogram），
// 让用户直观看到「这张样片 vs 典型风格」的分布差异。
//
// 解读措辞（spec §3.5）：用「样片手法：…」式描述样片为什么这样布阶调，
// 非命令式。数据来源：toneProvider（基调/跨度/RMS）+ advancedMetricsProvider
// （黑点偏移/白点压缩/十大影调）。
//
// gotcha #32：不在 build() 内用 AsyncValue.whenData 改局部变量，所有展开态
// 内容在 .when/.maybeWhen 的 data 闭包内构建。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/advanced_portrait_metrics.dart';
import '../../models/tone_result.dart';
import '../../providers/analysis_provider.dart';
import 'interpretation_row.dart';
import 'reference_histogram.dart';
import 'stage_card.dart';

/// 阶①影调手法卡片
class StageTonalCard extends ConsumerStatefulWidget {
  final String photoId;

  /// 从 GradingPanel 传入的 advanced 指标（避免每张卡片重复 watch）
  final AsyncValue<AdvancedPortraitMetrics?> advanced;

  const StageTonalCard({
    super.key,
    required this.photoId,
    required this.advanced,
  });

  @override
  ConsumerState<StageTonalCard> createState() => _StageTonalCardState();
}

class _StageTonalCardState extends ConsumerState<StageTonalCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final toneAsync = ref.watch(toneProvider(widget.photoId));
    final histAsync = ref.watch(histogramProvider(widget.photoId));

    final summary = toneAsync.maybeWhen(
      data: (t) => '${t.toneKeyLabel} · ${t.toneRangeLabel}',
      orElse: () => '分析中…',
    );

    return StageCard(
      index: 1,
      title: '影调手法',
      summary: summary,
      expanded: _expanded,
      onTap: () => setState(() => _expanded = !_expanded),
      children: [
        if (_expanded) ...[
          // 参照直方图叠放（教学核心）
          ReferenceHistogram(
            current: histAsync.asData?.value.lum,
            currentToneKey: toneAsync.asData?.value.toneKey,
          ),
          const SizedBox(height: 12),
          // 影调解读
          _buildInterpretation(toneAsync, widget.advanced),
        ],
      ],
    );
  }

  /// 影调解读：黑点/白点/RMS/十大影调
  Widget _buildInterpretation(
      AsyncValue<ToneResult> toneAsync,
      AsyncValue<AdvancedPortraitMetrics?> advancedAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 十大影调标签（来自 advancedMetrics）
        advancedAsync.maybeWhen(
          data: (a) => a == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('十大影调：${a.tenTonalType}',
                      style: const TextStyle(
                        color: InterpretationStatus.neutral,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      )),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        // 黑点解读
        advancedAsync.maybeWhen(
          data: (a) => a == null
              ? const SizedBox.shrink()
              : InterpretationRow(
                  icon: Icons.brightness_low,
                  label: '黑点偏移',
                  value: a.blackPointOffset.toStringAsFixed(1),
                  statusColor: InterpretationStatus.neutral,
                  interpretation: a.blackPointOffset < 4
                      ? '样片手法：黑点触底，用暗部死黑换对比度冲击'
                          '—— 电影调/港风的标志特征。'
                      : '样片手法：黑点上提 ${a.blackPointOffset.toStringAsFixed(1)}，'
                          '保留暗部层次 —— 日系/中式柔和影调常见。',
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        // 白点解读
        advancedAsync.maybeWhen(
          data: (a) => a == null
              ? const SizedBox.shrink()
              : InterpretationRow(
                  icon: Icons.brightness_high,
                  label: '白点压缩',
                  value: a.whitePointCompression.toStringAsFixed(1),
                  statusColor: InterpretationStatus.neutral,
                  interpretation: a.whitePointCompression > 252
                      ? '样片手法：白点触顶，高光溢出 —— 高反差/硬光风格特征。'
                      : '样片手法：白点压缩至 ${a.whitePointCompression.toStringAsFixed(1)}，'
                          '保留高光细节 —— 柔和过渡的标志。',
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        // RMS 对比度解读
        toneAsync.maybeWhen(
          data: (t) => InterpretationRow(
            icon: Icons.contrast,
            label: 'RMS 对比度',
            value: t.rmsContrast.toStringAsFixed(1),
            statusColor: InterpretationStatus.neutral,
            interpretation: t.rmsContrast > 60
                ? '样片手法：高对比（RMS ${t.rmsContrast.toStringAsFixed(0)}），'
                    '明暗反差强烈 —— 立体感强，电影调/港风常见。'
                : (t.rmsContrast < 30
                    ? '样片手法：低对比（RMS ${t.rmsContrast.toStringAsFixed(0)}），'
                        '画面柔和 —— 日系/低饱和风格的典型特征。'
                    : '样片手法：中等对比（RMS ${t.rmsContrast.toStringAsFixed(0)}），'
                        '明暗平衡，适用面广。'),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}
