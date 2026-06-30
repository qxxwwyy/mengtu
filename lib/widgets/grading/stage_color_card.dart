// stage_color_card.dart — 阶②色彩手法（v3.5 PR3）
//
// 数据来源：skinProvider（ΔH 色相偏差/饱和度/STI 通透度）。
// 解读措辞：STI 高 → 肤色通透；ΔH → 色相对齐达芬奇线；饱和 → 浓郁/克制。
//
// 容错：无脸/侧脸 → skinProvider 返回空 SkinAnalysis，STI/ΔH 显示「未检出」。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/advanced_portrait_metrics.dart';
import '../../models/tone_result.dart';
import '../../providers/analysis_provider.dart';
import 'interpretation_row.dart';
import 'skin_radar.dart';
import 'stage_card.dart';

/// 阶②色彩手法卡片
class StageColorCard extends ConsumerStatefulWidget {
  final String photoId;

  /// 从 GradingPanel 传入的 advanced 指标（STI 也在此，但此处直接用 skinProvider
  /// 保持单一数据源 —— advanced 的 STI 即来自 skinProvider）
  final AsyncValue<AdvancedPortraitMetrics?> advanced;

  const StageColorCard({
    super.key,
    required this.photoId,
    required this.advanced,
  });

  @override
  ConsumerState<StageColorCard> createState() => _StageColorCardState();
}

class _StageColorCardState extends ConsumerState<StageColorCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final skinAsync = ref.watch(skinProvider(widget.photoId));

    final summary = skinAsync.maybeWhen(
      data: (s) => s.isEmpty
          ? '未检出肤色'
          : '肤色 ΔH ${s.hueOffset?.toStringAsFixed(0) ?? '—'}°',
      orElse: () => '分析中…',
    );

    return StageCard(
      index: 2,
      title: '色彩手法',
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
      error: (e, _) => Text('肤色分析失败：$e',
          style: const TextStyle(color: InterpretationStatus.bad, fontSize: 11)),
      data: (skin) {
        // skin 是 SkinAnalysis
        final s = skin;
        if (s.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // v6.0（问题8）：无肤色时也显示空雷达占位 + 引导手动校准
              const Text('未检出肤色。可尝试用取色工具长按皮肤区域手动校准。',
                  style: TextStyle(
                      color: InterpretationStatus.low,
                      fontSize: 11,
                      height: 1.4)),
              const SizedBox(height: 8),
              SkinRadar(
                skin: const SkinAnalysis(),
                advanced: widget.advanced.asData?.value,
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // v6.0（问题8）：肤色雷达图 —— 心心念念的「肤色合理性」可视化模块，
            // 放在色彩卡片展开内容顶部。5 维雷达（ΔH/饱和/明度/STI/SLS），
            // 中心=理想肤色，越饱满越健康。下方保留文字解读行。
            SkinRadar(
              skin: s,
              advanced: widget.advanced.asData?.value,
            ),
            const SizedBox(height: 10),
            // STI 通透度（来自 advanced，可能为 null：无脸/侧脸/mesh 失败）
            widget.advanced.maybeWhen(
              data: (a) => a?.skinSti == null
                  ? const SizedBox.shrink()
                  : InterpretationRow(
                      icon: Icons.opacity,
                      label: '通透度 STI',
                      value: a!.skinSti!.toStringAsFixed(2),
                      statusColor: a.skinSti! > 0.7
                          ? InterpretationStatus.good
                          : (a.skinSti! < 0.4
                              ? InterpretationStatus.warn
                              : InterpretationStatus.neutral),
                      interpretation: a.skinSti! > 0.7
                          ? '样片手法：肤色通透自然（STI ${a.skinSti!.toStringAsFixed(2)}），'
                              '落在理想区间 —— 明度适中、饱和克制、色相对齐达芬奇线。'
                          : (a.skinSti! < 0.4
                              ? '样片手法：肤色偏沉闷（STI ${a.skinSti!.toStringAsFixed(2)}），'
                                  '可能明度过低或饱和过高 —— 泥泞感。'
                              : '样片手法：肤色通透度中等（STI ${a.skinSti!.toStringAsFixed(2)}）。'),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            if (s.hueOffset != null) ...[
              const SizedBox(height: 8),
              InterpretationRow(
                icon: Icons.palette_outlined,
                label: '色相偏差 ΔH',
                value: '${s.hueOffset!.toStringAsFixed(0)}°',
                statusColor: s.hueOffset!.abs() < 10
                    ? InterpretationStatus.good
                    : (s.hueOffset!.abs() > 25
                        ? InterpretationStatus.warn
                        : InterpretationStatus.neutral),
                interpretation: s.hueOffset!.abs() < 10
                    ? '样片手法：肤色色相对齐达芬奇线（ΔH ${s.hueOffset!.toStringAsFixed(0)}°），'
                        '自然通透 —— 标准肤色处理。'
                    : (s.hueOffset! > 0
                        ? '样片手法：肤色偏黄绿（ΔH +${s.hueOffset!.toStringAsFixed(0)}°），'
                            '可能偏暖或欠曝 —— 复刻青橙调则反向。'
                        : '样片手法：肤色偏品红（ΔH ${s.hueOffset!.toStringAsFixed(0)}°），'
                            '可能偏冷或过曝 —— 需向暖色校准。'),
              ),
            ],
            if (s.saturation != null) ...[
              const SizedBox(height: 8),
              InterpretationRow(
                icon: Icons.water_drop_outlined,
                label: '饱和度',
                value: '${s.saturation!.toStringAsFixed(0)}%',
                statusColor: s.saturation! > 70
                    ? InterpretationStatus.warn
                    : (s.saturation! < 20
                        ? InterpretationStatus.low
                        : InterpretationStatus.good),
                interpretation: s.saturation! > 70
                    ? '样片手法：高饱和（${s.saturation!.toStringAsFixed(0)}%），'
                        '色彩浓郁 —— 适合浓郁港风/电影调，日系则需降饱和。'
                    : (s.saturation! < 20
                        ? '样片手法：低饱和（${s.saturation!.toStringAsFixed(0)}%），'
                            '色彩克制 —— 日系/低饱和人像的标志。'
                        : '样片手法：饱和适中（${s.saturation!.toStringAsFixed(0)}%），'
                            '肤色自然不抢眼。'),
              ),
            ],
          ],
        );
      },
    );
  }
}
