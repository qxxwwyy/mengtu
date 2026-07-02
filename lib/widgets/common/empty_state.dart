// empty_state.dart — 优雅的空状态组件
//
// 入场动画（easeOutBack 弹性出现），线条微图形 + 引导文案 + CTA 按钮。
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 空状态组件
///
/// 用法：
/// ```dart
/// EmptyState(
///   icon: Icons.photo_camera_outlined,
///   title: '还没有照片',
///   subtitle: '点击右下角按钮导入你的第一张照片',
///   actionLabel: '导入照片',
///   onAction: () => _import(),
/// )
/// ```
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: AppAnimations.bounceEnterDuration,
      curve: AppAnimations.bounceEnterCurve,
      builder: (context, progress, _) {
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - progress)),
            child: Center(
              child: Padding(
                padding: Spacing.all(Spacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 图标圆环
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        color: AppColors.accent.withValues(alpha: 0.06),
                      ),
                      child: Icon(
                        icon,
                        size: 36,
                        color: AppColors.accent.withValues(alpha: 0.7),
                      ),
                    ),
                    SizedBox(height: Spacing.lg),
                    // 标题
                    Text(
                      title,
                      style: AppTypography.headline,
                      textAlign: TextAlign.center,
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: Spacing.sm),
                      Text(
                        subtitle!,
                        style: AppTypography.bodySecondary,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (actionLabel != null && onAction != null) ...[
                      SizedBox(height: Spacing.xl),
                      _ActionChip(
                        label: actionLabel!,
                        onTap: onAction!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// CTA 按钮（渐变背景胶囊）
class _ActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: Spacing.hv(Spacing.xl, Spacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent,
              AppColors.accent.withValues(alpha: 0.7),
            ],
          ),
          borderRadius: Radii.pillBorder,
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: AppTypography.label.copyWith(
            color: AppColors.bgBase,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
