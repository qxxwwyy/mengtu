// async_views.dart — 统一异步加载/错误视图（跨页一致性组件）
//
// 消除审计清单第五节的「加载态 4 种 / 错误态 5 种文案」问题：
// 所有页面的 loading 分支用 [AsyncLoadingView]，error 分支用 [AsyncErrorView]。
// 颜色走 Theme 语义槽位（ThemeData 由 app_theme token 构建，暗/浅主题自适应）。
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 统一加载态（居中小转圈，不打断布局节奏）
class AsyncLoadingView extends StatelessWidget {
  final double height;

  const AsyncLoadingView({super.key, this.height = 64});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// 统一错误态（图标 + 文案 + 可选重试）
///
/// [message] 面向用户的短文案（不暴露异常对象）；[onRetry] 提供时显示重试按钮。
class AsyncErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const AsyncErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: Spacing.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 32, color: scheme.onSurfaceVariant),
            SizedBox(height: Spacing.sm),
            Text(message, style: AppTypography.bodySecondary,
                textAlign: TextAlign.center),
            if (onRetry != null) ...[
              SizedBox(height: Spacing.md),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 统一行内错误提示（列表项/卡片内嵌场景，比 AsyncErrorView 轻）
class AsyncErrorLine extends StatelessWidget {
  final String message;

  const AsyncErrorLine({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline,
            size: 14, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 6),
        Flexible(
          child: Text(message, style: AppTypography.captionWith(
              Theme.of(context).colorScheme.error)),
        ),
      ],
    );
  }
}
