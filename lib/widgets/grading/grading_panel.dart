// grading_panel.dart — 解构视图（v3.5 PR3，v6.0 修黑框）
//
// 替换 DetailBottomPanel 展开态的 6 Tab 内容，改为四阶卡片纵向滚动。
// 布局：展开区可用约 262px（308 − 顶部把手），4 张卡片用 ListView 滚动，
// 每张默认折叠（只显示标题 + 摘要），点击展开详情。
//
// v6.0（问题7）：去掉顶部 padding，卡片紧贴工具行（消除展开后顶部「大黑框」）。
//
// 数据流：watch advancedMetricsProvider 一次，作为 AsyncValue 传给各卡片，
// 避免每张卡片重复 watch（减少 provider 订阅）。
//
// gotcha #43：本组件是唯一滚动容器（ListView），各 stage 卡片不自带滚动。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/analysis_provider.dart';
import 'stage_color_card.dart';
import 'stage_insight_card.dart';
import 'stage_isolation_card.dart';
import 'stage_tonal_card.dart';

/// 解构视图：四阶卡片纵向滚动
class GradingPanel extends ConsumerWidget {
  final String photoId;

  const GradingPanel({super.key, required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 一次 watch，传给各 stage 卡片（避免重复订阅）
    final advanced = ref.watch(advancedMetricsProvider(photoId));

    return ListView(
      // v6.0：去掉顶部 vertical padding，让卡片紧贴工具行（消除「大黑框」间隙，
      // 问题7）。底部留 8 padding 防止最后一张卡片贴底。左右 12 对齐工具行按钮。
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: [
        StageTonalCard(photoId: photoId, advanced: advanced),
        const SizedBox(height: 8),
        StageColorCard(photoId: photoId),
        const SizedBox(height: 8),
        StageIsolationCard(photoId: photoId),
        const SizedBox(height: 8),
        // 阶④洞察卡片（v8.0：替代已删除的档案比对）
        StageInsightCard(photoId: photoId),
      ],
    );
  }
}
