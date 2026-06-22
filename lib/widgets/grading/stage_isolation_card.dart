// stage_isolation_card.dart — 阶③主体手法（v3.5 PR3）
//
// 数据来源：skinProvider（SLS 明度隔离/SCS 色彩隔离/FLC 面部反差）+
// sharpnessProvider（前景/背景锐度，可选）。
//
// 解读措辞：SLS 高 → 主体明度突出；FLC 高 → 侧光立体骨相；SCS 高 → 色彩脱离背景。
//
// 容错：无脸 → SLS/SCS/FLC 全 null，显示「未检出」；sharpness 按需 watch
// （首次计算有延迟，loading 态显示占位）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/advanced_portrait_metrics.dart';
import '../../providers/analysis_provider.dart';
import '../../providers/sharpness_provider.dart';
import 'interpretation_row.dart';
import 'stage_card.dart';

/// 阶③主体手法卡片
class StageIsolationCard extends ConsumerStatefulWidget {
  final String photoId;

  /// 从 GradingPanel 传入的 advanced 指标（FLC 在此）
  final AsyncValue<AdvancedPortraitMetrics?> advanced;

  const StageIsolationCard({
    super.key,
    required this.photoId,
    required this.advanced,
  });

  @override
  ConsumerState<StageIsolationCard> createState() => _StageIsolationCardState();
}

class _StageIsolationCardState extends ConsumerState<StageIsolationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final skinAsync = ref.watch(skinProvider(widget.photoId));

    final summary = skinAsync.maybeWhen(
      data: (s) {
        if (s.isEmpty) return '未检出主体';
        final sls = s.luminanceSeparation;
        if (sls == null) return '主体分析中';
        return sls > 0 ? '主体提亮' : (sls < 0 ? '主体压暗' : '平光');
      },
      orElse: () => '分析中…',
    );

    return StageCard(
      index: 3,
      title: '主体手法',
      summary: summary,
      expanded: _expanded,
      onTap: () => setState(() => _expanded = !_expanded),
      children: [
        if (_expanded) _buildInterpretation(skinAsync),
      ],
    );
  }

  Widget _buildInterpretation(AsyncValue<dynamic> skinAsync) {
    return skinAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => Text('主体分析失败：$e',
          style: const TextStyle(color: InterpretationStatus.bad, fontSize: 11)),
      data: (skin) {
        final s = skin;
        if (s.isEmpty) {
          return const Text('未检出人脸主体，无法计算隔离度。',
              style: TextStyle(color: InterpretationStatus.low, fontSize: 11, height: 1.4));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SLS 明度隔离
            if (s.luminanceSeparation != null) ...[
              InterpretationRow(
                icon: Icons.brightness_6_outlined,
                label: '明度隔离 SLS',
                value: '${s.luminanceSeparation!.toStringAsFixed(0)}%',
                statusColor: s.luminanceSeparation!.abs() > 15
                    ? InterpretationStatus.good
                    : InterpretationStatus.neutral,
                interpretation: s.luminanceSeparation! > 15
                    ? '样片手法：主体明度比背景高 ${s.luminanceSeparation!.toStringAsFixed(0)}%，'
                        '视觉焦点稳稳汇聚在面部 —— 经典提亮主体手法。'
                    : (s.luminanceSeparation! < -15
                        ? '样片手法：主体明度比背景低 ${s.luminanceSeparation!.abs().toStringAsFixed(0)}%，'
                            '低调压暗主体 —— 神秘/压抑氛围的常用手法。'
                        : '样片手法：主体与背景明度接近（SLS ${s.luminanceSeparation!.toStringAsFixed(0)}%），'
                            '融为一体 —— 平等叙事或低对比风格。'),
              ),
              const SizedBox(height: 8),
            ],
            // SCS 色彩隔离
            if (s.colorSeparation != null) ...[
              InterpretationRow(
                icon: Icons.color_lens_outlined,
                label: '色彩隔离 SCS',
                value: '${s.colorSeparation!.toStringAsFixed(0)}°',
                statusColor: s.colorSeparation! > 60
                    ? InterpretationStatus.good
                    : InterpretationStatus.neutral,
                interpretation: s.colorSeparation! > 60
                    ? '样片手法：肤色与背景色相距 ${s.colorSeparation!.toStringAsFixed(0)}°，'
                        '色彩反差大 —— 主体从环境中鲜明脱离。'
                    : '样片手法：肤色与背景色相距 ${s.colorSeparation!.toStringAsFixed(0)}°，'
                        '色彩同源 —— 和谐统一的色调处理。',
              ),
              const SizedBox(height: 8),
            ],
            // FLC 面部反差（来自 advanced）
            widget.advanced.maybeWhen(
              data: (a) => a?.faceLightingContrast == null
                  ? const SizedBox.shrink()
                  : InterpretationRow(
                      icon: Icons.wb_sunny_outlined,
                      label: '面部光比 FLC',
                      value: a!.faceLightingContrast!.toStringAsFixed(2),
                      statusColor: a.faceLightingContrast! > 0.3
                          ? InterpretationStatus.good
                          : InterpretationStatus.neutral,
                      interpretation: a.faceLightingContrast! > 0.4
                          ? '样片手法：面部光比 ${a.faceLightingContrast!.toStringAsFixed(2)}'
                              '（侧光强烈），塑造了立体骨相 —— 港风/电影调典型用光。'
                          : (a.faceLightingContrast! > 0.2
                              ? '样片手法：面部光比 ${a.faceLightingContrast!.toStringAsFixed(2)}'
                                  '（柔光侧照），骨相清晰但不生硬 —— 商业人像常用。'
                              : '样片手法：面部光比 ${a.faceLightingContrast!.toStringAsFixed(2)}'
                                  '（接近平光），肤色均匀 —— 美妆/清新风格。'),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            // 锐度对比（可选，按需 watch，loading 不阻塞其它行）
            _buildSharpnessRow(),
          ],
        );
      },
    );
  }

  /// 前景/背景锐度对比（sharpnessProvider 首次计算有延迟）
  Widget _buildSharpnessRow() {
    final sharpAsync = ref.watch(sharpnessProvider(widget.photoId));
    return sharpAsync.maybeWhen(
      data: (map) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InterpretationRow(
          icon: Icons.center_focus_strong_outlined,
          label: '合焦分离',
          value:
              '${map.foregroundScore.toStringAsFixed(0)}/${map.backgroundScore.toStringAsFixed(0)}',
          statusColor: map.foregroundScore > map.backgroundScore * 1.5
              ? InterpretationStatus.good
              : InterpretationStatus.neutral,
          interpretation: map.foregroundScore > map.backgroundScore * 1.5
              ? '样片手法：前景锐度（${map.foregroundScore.toStringAsFixed(0)}）'
                  '远高于背景（${map.backgroundScore.toStringAsFixed(0)}），'
                  '虚实分离强 —— 大光圈虚化突出主体。'
              : '样片手法：前景背景锐度接近（${map.foregroundScore.toStringAsFixed(0)}/'
                  '${map.backgroundScore.toStringAsFixed(0)}），全景清晰 —— 广角/小光圈叙事。',
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
