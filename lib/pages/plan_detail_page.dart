// plan_detail_page.dart — 策划详情（v2.0；v8.1 重做：token 化 + 三态 + 照片点击放大）
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/plan_provider.dart';
import '../providers/database_provider.dart';
import '../services/database/daos/plan_dao.dart';
import '../services/database/app_database.dart';
import '../theme/app_theme.dart';
import '../widgets/common/async_views.dart';
import '../widgets/common/empty_state.dart';
import '../utils/date_format.dart';
import '../widgets/common/page_transitions.dart';
import 'plan_edit_page.dart';
import 'album_detail_page.dart';

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
      _shotList[index] = ShotItem(id: item.id, desc: item.desc, done: !item.done);
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: StatusColors.error),
              child: const Text('删除')),
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
              await Navigator.push(context, detailPageRoute(
                PlanEditPage(planId: widget.planId),
              ));
              _loadDetails();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            color: StatusColors.error,
            onPressed: _deletePlan,
          ),
        ],
      ),
      body: planAsync.when(
        loading: () => const AsyncLoadingView(height: 200),
        error: (_, __) => AsyncErrorView(
          message: '策划加载失败',
          onRetry: () => ref.invalidate(planByIdProvider(widget.planId)),
        ),
        data: (plan) {
          if (plan == null) {
            return const EmptyState(
              icon: Icons.event_busy,
              title: '策划不存在',
              subtitle: '它可能已被删除',
            );
          }
          return ListView(
            padding: Spacing.all(Spacing.lg),
            children: [
              // 基本信息
              Text(plan.title, style: AppTypography.headline),
              if (plan.style.isNotEmpty || plan.theme.isNotEmpty) ...[
                SizedBox(height: Spacing.xs + 2),
                Text(
                  [if (plan.style.isNotEmpty) plan.style, if (plan.theme.isNotEmpty) plan.theme].join(' · '),
                  style: AppTypography.bodySecondary,
                ),
              ],
              if (plan.location.isNotEmpty || plan.plannedDate != null) ...[
                SizedBox(height: Spacing.xs),
                Text(
                  [
                    if (plan.location.isNotEmpty) plan.location,
                    if (plan.plannedDate != null) fmtDate(plan.plannedDate!),
                  ].join('  ·  '),
                  style: AppTypography.captionWith(AppColors.textMuted),
                ),
              ],

              // v3.0: 关联样片相册卡片（点击一键跳转浏览）
              if (plan.associatedAlbumId != null &&
                  plan.associatedAlbumId!.isNotEmpty) ...[
                SizedBox(height: Spacing.md),
                _AssociatedAlbumCard(albumId: plan.associatedAlbumId!),
              ],

              SizedBox(height: Spacing.xl),
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
                          ? AppTypography.bodyWith(AppColors.textMuted)
                              .copyWith(decoration: TextDecoration.lineThrough)
                          : AppTypography.body,
                    ),
                  );
                }),

              SizedBox(height: Spacing.lg),
              // 器材清单
              _SectionTitle(title: '器材清单'),
              if (_gearList.isEmpty)
                _emptyHint('还没有器材清单')
              else
                ..._gearList.where((g) => g.lens.isNotEmpty).map((g) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.camera_alt_outlined,
                          size: 20, color: theme.colorScheme.primary),
                      title: Text(g.lens, style: AppTypography.body),
                      subtitle: g.note.isNotEmpty
                          ? Text(g.note, style: AppTypography.captionMuted)
                          : null,
                    )),

              SizedBox(height: Spacing.lg),
              // 实拍照片
              _SectionTitle(title: '实拍照片'),
              resultPhotosAsync.when(
                loading: () => const AsyncLoadingView(height: 100),
                error: (_, __) => const AsyncErrorLine(message: '实拍照片加载失败'),
                data: (photos) {
                  if (photos.isEmpty) {
                    return _emptyHint('还没有实拍照片，拍摄后从相册详情加入');
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: photos.length,
                    itemBuilder: (_, i) {
                      final photo = photos[i];
                      return ClipRRect(
                        borderRadius: Radii.smBorder,
                        child: GestureDetector(
                          // v8.1：九宫格点击放大查看（此前不可点击）
                          onTap: () => _showPhotoViewer(context, photo),
                          child: Image.file(
                            File(photo.thumbnailPath.isEmpty
                                ? photo.filePath
                                : photo.thumbnailPath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: theme.colorScheme.surface,
                              child: Icon(Icons.broken_image,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              SizedBox(height: Spacing.xxl),
            ],
          );
        },
      ),
    );
  }

  /// 实拍照片全屏查看（InteractiveViewer 缩放 + 点击关闭）
  void _showPhotoViewer(BuildContext context, Photo photo) {
    Navigator.push(
      context,
      detailPageRoute(
        Scaffold(
          backgroundColor: DetailColors.background,
          appBar: AppBar(
            title: Text(photo.fileName, style: AppTypography.caption),
            backgroundColor: DetailColors.background,
            foregroundColor: DetailColors.textPrimary,
            iconTheme: const IconThemeData(color: DetailColors.textPrimary),
          ),
          body: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(
              maxScale: 5.0,
              child: Center(
                child: Image.file(
                  File(photo.thumbnailPath.isEmpty
                      ? photo.filePath
                      : photo.thumbnailPath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: DetailColors.textMuted,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: Spacing.v(Spacing.md),
      child: Text(text, style: AppTypography.captionMuted),
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
          Text(title, style: AppTypography.titleWith(theme.colorScheme.primary)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!, style: AppTypography.labelSecondary),
          ],
        ],
      ),
    );
  }
}

/// v3.0: 策划详情页的关联样片相册卡片
///
/// 显示关联相册名 + 照片数，点击一键跳转相册详情，
/// 方便在拍摄现场滑动大图向模特演示 Pose / 光影，
/// 后期可做实拍 / 参考同屏对比。
class _AssociatedAlbumCard extends ConsumerWidget {
  final String albumId;

  const _AssociatedAlbumCard({required this.albumId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(appDatabaseProvider);
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: InkWell(
        borderRadius: Radii.mdBorder,
        onTap: () {
          Navigator.push(
            context,
            detailPageRoute(AlbumDetailPage(albumId: albumId)),
          );
        },
        child: Padding(
          padding: Spacing.all(Spacing.md),
          child: FutureBuilder<Album?>(
            future: db.albumDao.getAlbumById(albumId),
            builder: (ctx, snap) {
              // 相册可能已被删除（FK setNull 把 associated_album_id 置空，
              // 但已加载的 plan 缓存仍是旧 id）→ 提示并隐藏
              final album = snap.data;
              if (snap.connectionState != ConnectionState.done) {
                return const AsyncLoadingView(height: 32);
              }
              if (album == null) {
                return Row(
                  children: [
                    Icon(Icons.link_off, color: theme.colorScheme.error, size: 20),
                    const SizedBox(width: 8),
                    const AsyncErrorLine(message: '关联相册已删除'),
                  ],
                );
              }
              return Row(
                children: [
                  Icon(Icons.photo_album_outlined,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('关联样片相册',
                            style: AppTypography.captionMuted
                                .copyWith(letterSpacing: 0.5)),
                        Text(album.name, style: AppTypography.label),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant, size: 20),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
