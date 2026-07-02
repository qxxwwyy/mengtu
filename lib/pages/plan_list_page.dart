// plan_list_page.dart — 拍摄策划列表（v2.0）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/plan_provider.dart';
import '../services/database/app_database.dart';
import 'plan_edit_page.dart';
import 'plan_detail_page.dart';
import '../theme/app_theme.dart';

class PlanListPage extends ConsumerWidget {
  const PlanListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(allPlansProvider);
    final filter = ref.watch(planStatusFilterProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('策划',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: theme.colorScheme.primary)),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'plan_fab',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PlanEditPage())),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // 状态筛选 chips
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: PlanStatusFilter.values.map((f) {
                final selected = filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8, top: 6),
                  child: FilterChip(
                    label: Text(_filterLabel(f)),
                    selected: selected,
                    onSelected: (_) =>
                        ref.read(planStatusFilterProvider.notifier).set(f),
                  ),
                );
              }).toList(),
            ),
          ),
          // 策划列表
          Expanded(
            child: plansAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('加载失败',
                      style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                ),
              ),
              data: (plans) {
                final filtered = filter == PlanStatusFilter.all
                    ? plans
                    : plans.where((p) => p.status == _filterStatus(filter)).toList();
                if (filtered.isEmpty) {
                  return _buildEmptyState(context, theme);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _PlanCard(
                    plan: filtered[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlanDetailPage(planId: filtered[i].id),
                      ),
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

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('还没有拍摄策划',
                style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 8),
            Text(
              '点击右下角 + 创建策划\n提前规划主题、器材、shot list',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ),
          ],
        ),
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
        borderRadius: Radii.legacy12Border,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusInfo.$2.withValues(alpha: 0.15),
                      borderRadius: Radii.legacy8Border,
                    ),
                    child: Text(
                      statusInfo.$1,
                      style:
                          TextStyle(fontSize: 11, color: statusInfo.$2),
                    ),
                  ),
                ],
              ),
              if (plan.style.isNotEmpty || plan.theme.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [if (plan.style.isNotEmpty) plan.style, if (plan.theme.isNotEmpty) plan.theme]
                      .join(' · '),
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (plan.location.isNotEmpty || plan.plannedDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (plan.location.isNotEmpty)
                      Icon(Icons.location_on_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                    if (plan.location.isNotEmpty) ...[
                      const SizedBox(width: 2),
                      Text(plan.location,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                    ],
                    if (plan.location.isNotEmpty && plan.plannedDate != null)
                      Text(' · ',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                    if (plan.plannedDate != null) ...[
                      Icon(Icons.calendar_today_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                      const SizedBox(width: 2),
                      Text(
                        '${plan.plannedDate!.month}/${plan.plannedDate!.day}',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                      ),
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
