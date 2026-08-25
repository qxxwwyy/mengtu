// stage_card.dart — 通用阶卡片容器（v3.5 PR3）
//
// 四阶解构卡片的通用外壳：序号圆标 + 标题 + 摘要 + 折叠/展开。
// 折叠态只显示标题行（≈56px），展开态显示 [children] 详情。
// 动画用 AnimatedSize 220ms（与 DetailBottomPanel 一致）。
//
// 不自带滚动容器（gotcha #43）：children 应是非滚动的 Column，
// GradingPanel 的 ListView 是唯一滚动源。
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 通用阶卡片容器
///
/// 四阶解构（影调/色彩/主体/档案）共用此外壳，差异在 [children] 内容。
/// 折叠态：序号圆标 + 标题 + 摘要 + 展开箭头（单行 ≈56px）。
/// 展开态：追加 [children]（用 AnimatedSize 过渡，220ms easeInOutCubic）。
class StageCard extends StatelessWidget {
  /// 阶序号（1/2/3/4），渲染为圆标
  final int index;

  /// 卡片标题（如「影调手法」）
  final String title;

  /// 折叠态显示的摘要（如「高调 · 长调」）
  final String summary;

  /// 展开态显示的详情内容（非滚动 Column 子项）
  final List<Widget> children;

  /// 是否展开
  final bool expanded;

  /// 点击切换展开/折叠
  final VoidCallback onTap;

  const StageCard({
    super.key,
    required this.index,
    required this.title,
    required this.summary,
    required this.children,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimations.expandDuration,
      curve: AppAnimations.expandCurve,
      transform: expanded
          ? Matrix4.translationValues(0, -2, 0)
          : Matrix4.identity(),
      decoration: BoxDecoration(
        color: DetailColors.cardSurface,
        borderRadius: Radii.mdBorder,
        border: Border.all(
            color: expanded
                ? AppColors.accent.withValues(alpha: 0.5)
                : AppColors.accent.withValues(alpha: 0.25),
            width: 0.5),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: Radii.mdBorder,
          onTap: onTap,
          child: AnimatedSize(
            duration: AppAnimations.expandDuration,
            curve: AppAnimations.expandCurve,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                if (expanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 标题行（折叠/展开态都显示）
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _IndexBadge(index: index),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: AppTypography.label.copyWith(color: DetailColors.textPrimary, fontWeight: FontWeight.w600,)),
                if (summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(summary,
                        style: AppTypography.caption.copyWith(color: DetailColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            color: DetailColors.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }
}

/// 序号圆标（1/2/3/4）— 渐变填充
class _IndexBadge extends StatelessWidget {
  final int index;

  const _IndexBadge({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent,
            AppColors.accent.withValues(alpha: 0.6),
          ],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.3),
            blurRadius: 4,
            spreadRadius: 0,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: AppTypography.caption.copyWith(color: AppColors.bgBase, fontWeight: FontWeight.w700,),
      ),
    );
  }
}

// 注：InterpretationStatus 在 interpretation_row.dart 中导出，stage 卡片直接 import
// （此处不 re-export，保持单一职责）
