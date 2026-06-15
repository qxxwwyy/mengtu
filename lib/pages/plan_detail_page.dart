// plan_detail_page.dart — 策划详情（v2.0）
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/plan_provider.dart';
import '../providers/database_provider.dart';
import '../services/database/daos/plan_dao.dart';
import '../services/database/app_database.dart';
import 'plan_edit_page.dart';

class PlanDetailPage extends ConsumerStatefulWidget {
  final String planId;

  const PlanDetailPage({super.key, required this.planId});

  @override
  ConsumerState<PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends ConsumerState<PlanDetailPage> {
  List<ShotItem> _shotList = [];
  List<GearItem> _gearList = [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final db = ref.read(appDatabaseProvider);
    final plan = await db.planDao.getPlanById(widget.planId);
    if (plan != null && mounted) {
      setState(() {
        _shotList = db.planDao.parseShotList(plan.shotList);
        _gearList = db.planDao.parseGearList(plan.gearList);
      });
    }
  }

  Future<void> _toggleShot(int index) async {
    final db = ref.read(appDatabaseProvider);
    final item = _shotList[index];
    setState(() {
      _shotList[index] = ShotItem(desc: item.desc, done: !item.done);
    });
    final plan = await db.planDao.getPlanById(widget.planId);
    if (plan != null) {
      await db.planDao.updatePlan(ShootingPlansCompanion(
        id: Value(widget.planId),
        shotList: Value(db.planDao.encodeShotList(_shotList)),
        updatedAt: Value(DateTime.now()),
      ));
    }
  }

  Future<void> _deletePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除策划'),
        content: const Text('确定删除这个策划吗？关联的照片不会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(appDatabaseProvider).planDao.deletePlan(widget.planId);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('策划已删除')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(planByIdProvider(widget.planId));
    final resultPhotosAsync = ref.watch(planResultPhotosProvider(widget.planId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('策划详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => PlanEditPage(planId: widget.planId),
              ));
              _loadDetails();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: _deletePlan,
          ),
        ],
      ),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('加载失败')),
        data: (plan) {
          if (plan == null) return const Center(child: Text('策划不存在'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 基本信息
              Text(plan.title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              if (plan.style.isNotEmpty || plan.theme.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [if (plan.style.isNotEmpty) plan.style, if (plan.theme.isNotEmpty) plan.theme].join(' · '),
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
              if (plan.location.isNotEmpty || plan.plannedDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if (plan.location.isNotEmpty) '📍 ${plan.location}',
                    if (plan.plannedDate != null)
                      '📅 ${plan.plannedDate!.year}/${plan.plannedDate!.month}/${plan.plannedDate!.day}',
                  ].join('  '),
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                ),
              ],

              const SizedBox(height: 24),
              // Shot list 完成度
              _SectionTitle(
                title: 'Shot List',
                trailing: _shotList.isNotEmpty
                    ? '${_shotList.where((s) => s.done).length}/${_shotList.length}'
                    : null,
              ),
              if (_shotList.isEmpty)
                _emptyHint('还没有 shot list，点编辑添加')
              else
                ..._shotList.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(
                      value: item.done,
                      onChanged: (_) => _toggleShot(i),
                    ),
                    title: Text(
                      item.desc,
                      style: item.done
                          ? TextStyle(decoration: TextDecoration.lineThrough, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))
                          : null,
                    ),
                  );
                }),

              const SizedBox(height: 16),
              // 器材清单
              _SectionTitle(title: '器材清单'),
              if (_gearList.isEmpty)
                _emptyHint('还没有器材清单')
              else
                ..._gearList.where((g) => g.lens.isNotEmpty).map((g) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.camera_alt_outlined,
                          size: 20, color: theme.colorScheme.primary),
                      title: Text(g.lens),
                      subtitle: g.note.isNotEmpty ? Text(g.note, style: const TextStyle(fontSize: 12)) : null,
                    )),

              const SizedBox(height: 16),
              // 实拍照片
              _SectionTitle(title: '实拍照片'),
              resultPhotosAsync.when(
                loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
                error: (_, __) => _emptyHint('加载失败'),
                data: (photos) {
                  if (photos.isEmpty) return _emptyHint('还没有实拍照片');
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: photos.length,
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(photos[i].thumbnailPath.isEmpty
                            ? photos[i].filePath
                            : photos[i].thumbnailPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: theme.colorScheme.surface,
                          child: Icon(Icons.broken_image, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35))),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              )),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!,
                style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          ],
        ],
      ),
    );
  }
}
