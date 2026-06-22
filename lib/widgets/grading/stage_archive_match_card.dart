// stage_archive_match_card.dart — 阶④档案比对（v3.5 PR3 空状态）
//
// PR3 只渲染「创建风格档案后可匹配」引导卡片。完整匹配列表 + 雷达图
// 由 PR4 实现（依赖 styleProfileMatchProvider / StyleProfileMatch 类型）。
//
// 设计：PR3 自包含，阶④作为占位让 GradingPanel 的 4 卡布局完整。
// PR4 接入时：检测 styleProfilesProvider 非空 → 渲染 _SimilarityTile 列表 +
// FingerprintRadar；空 → 沿用本文件的引导卡片。
import 'package:flutter/material.dart';

import 'stage_card.dart';

/// 阶④档案比对卡片（PR3 空状态）
///
/// PR4 实现真实匹配后，此卡片改为：
/// 1. watch styleProfileMatchProvider(photoId)
/// 2. 空档案 → 本文件的引导卡片
/// 3. 有匹配 → StageCard 展开态渲染 _SimilarityTile 列表 + FingerprintRadar
class StageArchiveMatchCard extends StatelessWidget {
  final String photoId;

  const StageArchiveMatchCard({super.key, required this.photoId});

  @override
  Widget build(BuildContext context) {
    return StageCard(
      index: 4,
      title: '档案比对',
      summary: '创建风格档案后可匹配',
      expanded: false,
      onTap: () {
        // PR3：无操作（或显示 SnackBar 提示）。PR4 改为展开匹配列表。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('v3.5 即将上线：导入样片创建风格档案后，可在此比对相似度'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      children: const [
        // PR3 空状态：不渲染详情。PR4 在此插入匹配列表 + 雷达图。
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
}
