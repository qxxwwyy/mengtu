// grading_panel.dart — 解构视图（v3.5 PR3）
//
// 替换 DetailBottomPanel 展开态的 6 Tab 内容，改为四阶卡片纵向滚动。
// 布局：展开区可用约 262px（308 − 顶部把手），4 张卡片用 ListView 滚动，
// 每张默认折叠（只显示标题 + 摘要），点击展开详情。
//
// 数据流：watch advancedMetricsProvider 一次，作为 AsyncValue 传给各卡片，
// 避免每张卡片重复 watch（减少 provider 订阅）。
//
// gotcha #43：本组件是唯一滚动容器（ListView），各 stage 卡片不自带滚动。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/analysis_provider.dart';
import 'stage_archive_match_card.dart';
import 'stage_color_card.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        StageTonalCard(photoId: photoId, advanced: advanced),
        const SizedBox(height: 8),
        StageColorCard(photoId: photoId, advanced: advanced),
        const SizedBox(height: 8),
        StageIsolationCard(photoId: photoId, advanced: advanced),
        const SizedBox(height: 8),
        StageArchiveMatchCard(photoId: photoId),
      ],
    );
  }
}
