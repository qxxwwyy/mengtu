// album_page.dart — 相册列表页
//
// v2.1 重构：标签成为相册的子系统。本页新增顶栏标签 chips 筛选相册，
// 卡片改为富信息展示（封面 + 名称 + 数量 + 标签 chips + 更新时间），
// 并用 albumsWithTagsProvider 聚合查询消除原 N+1 双 FutureBuilder。
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../providers/album_provider.dart';
import '../providers/tag_provider.dart';
import '../providers/database_provider.dart';
import '../services/database/app_database.dart';
import '../services/database/daos/album_dao.dart' show AlbumWithTags;
import 'album_detail_page.dart';
import '../theme/app_theme.dart';
import '../widgets/common/async_views.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/common/page_transitions.dart';

class AlbumPage extends ConsumerStatefulWidget {
  const AlbumPage({super.key});

  @override
  ConsumerState<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<AlbumPage> {
  @override
  Widget build(BuildContext context) {
    final selectedTag = ref.watch(albumTagFilterProvider);
    final tagsAsync = ref.watch(allTagsProvider);
    // 选中标签 → 按标签筛选相册（仅相册元数据）；未选 → 聚合相册+标签+数量
    final albumsAsync = selectedTag == null
        ? ref.watch(albumsWithTagsProvider)
        : ref.watch(albumsByTagProvider(selectedTag));

    return Scaffold(
      appBar: AppBar(title: const Text('相册'), actions: [
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: _createAlbum,
        ),
      ]),
      body: Column(
        children: [
          // 顶栏标签 chips（筛选相册）
          tagsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (tags) {
              if (tags.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  children: [
                    FilterChip(
                      label: const Text('全部'),
                      selected: selectedTag == null,
                      onSelected: (_) => ref
                          .read(albumTagFilterProvider.notifier)
                          .select(null),
                    ),
                    const SizedBox(width: 6),
                    ...tags.map((tag) {
                      final selected = selectedTag == tag.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(tag.name),
                          selected: selected,
                          onSelected: (_) => ref
                              .read(albumTagFilterProvider.notifier)
                              .select(selected ? null : tag.id),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
          // 相册网格
          Expanded(
            child: albumsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AsyncErrorView(
            message: '相册加载失败',
            onRetry: () => ref.invalidate(albumsWithTagsProvider),
          ),
              data: (albums) {
                if (albums.isEmpty) {
                  return _buildEmptyState();
                }
                // 两种数据源统一为 AlbumWithTags（标签筛选时无标签信息，补查）
                return _AlbumGrid(
                  items: _normalize(albums, selectedTag),
                  onEdit: _editAlbum,
                  onDelete: _deleteAlbum,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 把两种数据源统一为 AlbumWithTags 列表。
  /// 选中标签筛选时，items 来自 albumsByTagProvider（无标签聚合），
  /// 此时为每个相册补一次标签查询以保证卡片一致；未筛选时直接用聚合数据。
  List<AlbumWithTags> _normalize(List<dynamic> albums, String? selectedTag) {
    if (selectedTag == null) {
      return List<AlbumWithTags>.from(albums);
    }
    // 标签筛选分支：albums 是 List<Album>，标签异步补在卡片内
    return albums
        .map<AlbumWithTags>((a) => AlbumWithTags(album: a, tags: const [], photoCount: -1))
        .toList();
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: Icons.photo_album_outlined,
      title: '还没有相册',
      subtitle: '创建相册来整理作品集，还能挂标签快速筛选',
      actionLabel: '创建第一个相册',
      onAction: _createAlbum,
    );
  }

  void _createAlbum() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建相册'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '相册名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: '描述（可选）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final db = ref.read(appDatabaseProvider);
              await db.albumDao.insertAlbum(
                AlbumsCompanion.insert(
                  id: const Uuid().v4(),
                  name: name,
                  description: Value(descController.text.trim()),
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _editAlbum(Album album) {
    final nameController = TextEditingController(text: album.name);
    final descController = TextEditingController(text: album.description);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑相册'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '相册名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: '描述（可选）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final db = ref.read(appDatabaseProvider);
              await db.albumDao.updateAlbum(
                AlbumsCompanion(
                  id: Value(album.id),
                  name: Value(name),
                  description: Value(descController.text.trim()),
                  updatedAt: Value(DateTime.now()),
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _deleteAlbum(Album album) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除相册'),
        content: Text('确定要删除相册"${album.name}"吗？相册内的照片不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final db = ref.read(appDatabaseProvider);
              await db.albumDao.deleteAlbum(album.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: StatusColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 相册网格
class _AlbumGrid extends StatelessWidget {
  final List<AlbumWithTags> items;
  final void Function(Album album) onEdit;
  final void Function(Album album) onDelete;
  const _AlbumGrid({
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        // ValueKey 用相册 id：切换标签筛选时 Flutter 按 id 复用，
        // 避免按位置复用导致 _AlbumCard 的封面/数量回填数据显示上一个相册的脏值
        return _AlbumCard(
          key: ValueKey(item.album.id),
          item: item,
          onEdit: onEdit,
          onDelete: onDelete,
        );
      },
    );
  }
}

/// 富信息相册卡片（封面 + 名称 + 数量 + 标签 chips + 更新时间）
class _AlbumCard extends ConsumerStatefulWidget {
  final AlbumWithTags item;
  final void Function(Album album) onEdit;
  final void Function(Album album) onDelete;
  const _AlbumCard({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  ConsumerState<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends ConsumerState<_AlbumCard> {
  bool _isPressed = false;

  // 当 item 来自标签筛选分支（photoCount=-1）时，补查封面/数量
  Future<({Photo? cover, int count})>? _backfill;

  @override
  void initState() {
    super.initState();
    if (widget.item.photoCount < 0) {
      final db = ref.read(appDatabaseProvider);
      _backfill = () async {
        final cover = await db.albumDao.getCoverPhoto(widget.item.album.id,
            coverPhotoId: widget.item.album.coverPhotoId);
        final count = await db.albumDao.getPhotoCount(widget.item.album.id);
        return (cover: cover, count: count);
      }();
    }
  }

  void _openDetail() {
    Navigator.push(
      context,
      detailPageRoute(AlbumDetailPage(albumId: widget.item.album.id)),
    );
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onEdit(widget.item.album);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: StatusColors.error),
              title: const Text('删除', style: TextStyle(color: StatusColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                widget.onDelete(widget.item.album);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final album = widget.item.album;
    final db = ref.watch(appDatabaseProvider);

    return GestureDetector(
      onTap: _openDetail,
      onLongPress: _showOptions,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: Radii.mdBorder,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封面图
                _buildCover(db),
                // 底部渐变遮罩 + 信息
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 28, 10, 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.onPhotoScrim,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          album.name,
                          style: AppTypography.label.copyWith(color: AppColors.onPhotoText, fontWeight: FontWeight.w600,),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        _buildCountLine(),
                        const SizedBox(height: 6),
                        _buildTagChips(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(AppDatabase db) {
    if (_backfill != null) {
      return FutureBuilder<({Photo? cover, int count})>(
        future: _backfill,
        builder: (context, snap) {
          final cover = snap.data?.cover;
          return _coverImage(cover);
        },
      );
    }
    // 聚合分支：封面仍需单独查（聚合未带封面照片对象）
    return FutureBuilder<Photo?>(
      future: db.albumDao.getCoverPhoto(widget.item.album.id,
          coverPhotoId: widget.item.album.coverPhotoId),
      builder: (context, snap) => _coverImage(snap.data),
    );
  }

  Widget _coverImage(Photo? cover) {
    final theme = Theme.of(context);
    if (cover == null) {
      return Center(
        child: Icon(Icons.photo_album,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final path = cover.thumbnailPath.isNotEmpty
        ? cover.thumbnailPath
        : cover.filePath;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Center(
        child: Icon(Icons.broken_image,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildCountLine() {
    if (_backfill != null) {
      return FutureBuilder<({Photo? cover, int count})>(
        future: _backfill,
        builder: (context, snap) => _countText(snap.data?.count ?? 0),
      );
    }
    return _countText(widget.item.photoCount);
  }

  Widget _countText(int count) => Text(
        '$count 张',
        style: AppTypography.caption.copyWith(color: AppColors.onPhotoText,),
      );

  /// 标签 chips：最多 2 个 + "+N"（标签筛选分支无聚合标签，此时不显示）
  Widget _buildTagChips() {
    final tags = widget.item.tags;
    if (tags.isEmpty) return const SizedBox.shrink();
    const max = 2;
    final shown = tags.take(max).toList();
    final extra = tags.length - shown.length;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ...shown.map((t) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.onPhotoTextDim,
                borderRadius: Radii.smBorder,
              ),
              child: Text(
                t.name,
                style: AppTypography.captionCompact.copyWith(color: AppColors.onPhotoText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )),
        if (extra > 0)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.onPhotoTextDim,
              borderRadius: Radii.smBorder,
            ),
            child: Text(
              '+$extra',
              style: AppTypography.captionCompact.copyWith(color: AppColors.onPhotoText),
            ),
          ),
      ],
    );
  }
}
