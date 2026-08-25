// plan_list_page.dart — 拍摄策划列表（v2.0；v8.1 清账：三态统一 + token 化 + haptic）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/plan_provider.dart';
import '../services/database/app_database.dart';
import 'plan_edit_page.dart';
import 'plan_detail_page.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/common/async_views.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/common/page_transitions.dart';

class PlanListPage extends ConsumerWidget {
  const PlanListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(allPlansProvider);
    final filter = ref.watch(planStatusFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('策划'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'plan_fab',
        onPressed: () {
          HapticFeedback.selectionClick();
          Navigator.push(context, detailPageRoute(const PlanEditPage()));
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // 状态筛选 chips
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: Spacing.h(Spacing.md),
              children: PlanStatusFilter.values.map((f) {
                final selected = filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8, top: 6),
                  child: FilterChip(
                    label: Text(_filterLabel(f)),
                    selected: selected,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      ref.read(planStatusFilterProvider.notifier).set(f);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // 策划列表
          Expanded(
            child: plansAsync.when(
              loading: () => const AsyncLoadingView(height: 200),
              error: (_, __) => AsyncErrorView(
                message: '策划加载失败',
                onRetry: () => ref.invalidate(allPlansProvider),
              ),
              data: (plans) {
                final filtered = filter == PlanStatusFilter.all
                    ? plans
                    : plans.where((p) => p.status == _filterStatus(filter)).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.assignment_outlined,
                    title: filter == PlanStatusFilter.all ? '还没有拍摄策划' : '该状态下暂无策划',
                    subtitle: '点击右下角 + 创建策划\n提前规划主题、器材、shot list',
                    actionLabel: filter == PlanStatusFilter.all ? '创建策划' : null,
                    onAction: filter == PlanStatusFilter.all
                        ? () => Navigator.push(
                            context, detailPageRoute(const PlanEditPage()))
                        : null,
                  );
                }
                return ListView.builder(
                  padding: Spacing.all(Spacing.md),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _PlanCard(
                    plan: filtered[i],
                    onTap: () => Navigator.push(
                      context,
                      detailPageRoute(PlanDetailPage(planId: filtered[i].id)),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(PlanStatusFilter f) => switch (f) {
        PlanStatusFilter.all => '全部',
        PlanStatusFilter.planning => '策划中',
        PlanStatusFilter.shooting => '拍摄中',
        PlanStatusFilter.completed => '已完成',
        PlanStatusFilter.archived => '已归档',
      };

  String _filterStatus(PlanStatusFilter f) => switch (f) {
        PlanStatusFilter.all => '',
        PlanStatusFilter.planning => 'planning',
        PlanStatusFilter.shooting => 'shooting',
        PlanStatusFilter.completed => 'completed',
        PlanStatusFilter.archived => 'archived',
      };
}

/// 策划卡片
class _PlanCard extends StatelessWidget {
  final ShootingPlan plan;
  final VoidCallback onTap;

  const _PlanCard({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusInfo = _statusInfo(plan.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.mdBorder,
        child: Padding(
          padding: Spacing.all(Spacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.title,
                      style: AppTypography.title.copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: Spacing.hv(Spacing.sm, 3),
                    decoration: BoxDecoration(
                      color: statusInfo.$2.withValues(alpha: 0.15),
                      borderRadius: Radii.mdBorder,
                    ),
                    child: Text(
                      statusInfo.$1,
                      style: AppTypography.captionWith(statusInfo.$2),
                    ),
                  ),
                ],
              ),
              if (plan.style.isNotEmpty || plan.theme.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [if (plan.style.isNotEmpty) plan.style, if (plan.theme.isNotEmpty) plan.theme]
                      .join(' · '),
                  style: AppTypography.labelSecondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (plan.location.isNotEmpty || plan.plannedDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (plan.location.isNotEmpty) ...[
                      Icon(Icons.location_on_outlined,
                          size: 12, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Text(plan.location, style: AppTypography.captionWith(
                          theme.colorScheme.onSurfaceVariant)),
                    ],
                    if (plan.location.isNotEmpty && plan.plannedDate != null)
                      Text(' · ', style: AppTypography.captionWith(
                          theme.colorScheme.onSurfaceVariant)),
                    if (plan.plannedDate != null) ...[
                      Icon(Icons.calendar_today_outlined,
                          size: 12, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Text(fmtMonthDay(plan.plannedDate!),
                          style: AppTypography.captionWith(
                              theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (String, Color) _statusInfo(String status) {
    return switch (status) {
      'planning' => ('策划中', AppColors.accent),
      'shooting' => ('拍摄中', StatusColors.success),
      'completed' => ('已完成', StatusColors.neutral),
      'archived' => ('已归档', StatusColors.neutralCool),
      _ => ('未知', StatusColors.neutral),
    };
  }
}
