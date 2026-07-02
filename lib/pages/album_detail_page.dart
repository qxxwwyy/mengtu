// album_detail_page.dart — 相册详情页
//
// 显示相册内的照片，支持添加/移除照片。
// v2.1：顶部新增标签编辑面板（标签是相册的子系统）；AppBar 标题改为 reactive。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../providers/database_provider.dart';
import '../providers/album_provider.dart';
import '../providers/tag_provider.dart';
import '../services/database/app_database.dart';
import '../widgets/photo_card.dart';
import 'detail_page.dart';
import '../theme/app_theme.dart';

class AlbumDetailPage extends ConsumerStatefulWidget {
  final String albumId;

  const AlbumDetailPage({super.key, required this.albumId});

  @override
  ConsumerState<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends ConsumerState<AlbumDetailPage> {
  bool _isWaterfallView = false;

  Future<void> _addPhotos() async {
    // 权限预检：与 home_page 一致（注意事项 #6）。
    // 用 hasAccess（含 limited 部分授权）而非 isAuth（仅 authorized），
    // 避免 Android 14+/iOS「仅允许访问选中照片」的已授权用户误弹权限提示。
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('需要相册权限才能导入照片，请在设置中开启'),
          action: SnackBarAction(
            label: '设置',
            onPressed: () => PhotoManager.openSetting(),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        maxAssets: 100,
        requestType: RequestType.image,
      ),
    );

    if (assets == null || assets.isEmpty) return;

    // 转换为文件路径
    final filePaths = <String>[];
    for (final asset in assets) {
      final file = await asset.file;
      if (file != null) filePaths.add(file.path);
    }

    if (filePaths.isEmpty) return;

    // 导入照片，用返回的 importedPhotoIds 精确加入相册（避免全表 diff 误加并发导入的照片）
    final db = ref.read(appDatabaseProvider);
    final importService = await ref.read(importServiceProvider.future);
    final result = await importService.importPhotos(filePaths);

    var added = 0;
    for (final photoId in result.importedPhotoIds) {
      await db.albumDao.addPhotoToAlbum(widget.albumId, photoId, sortOrder: added);
      added++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 $added 张照片到相册')),
      );
    }
  }

  Future<void> _addExistingPhotos() async {
    final db = ref.read(appDatabaseProvider);
    final allPhotos = await db.photoDao.getAllPhotos();
    final albumPhotos = await db.albumDao.getPhotosInAlbum(widget.albumId);
    final albumPhotoIds = albumPhotos.map((p) => p.id).toSet();

    // 过滤出不在相册中的照片
    final availablePhotos =
        allPhotos.where((p) => !albumPhotoIds.contains(p.id)).toList();

    if (availablePhotos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可添加的照片')),
        );
      }
      return;
    }

    // 全屏选择页
    if (!mounted) return;
    final albumName =
        ref.read(albumByIdProvider(widget.albumId)).maybeWhen(
              data: (a) => a?.name ?? '相册',
              orElse: () => '相册',
            );
    final selectedIds = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoSelectionPage(
          photos: availablePhotos,
          albumName: albumName,
        ),
        fullscreenDialog: true,
      ),
    );

    if (selectedIds == null || selectedIds.isEmpty) return;

    // 从当前相册照片数开始递增 sortOrder，确保新照片追加到末尾而非顶到最前
    // （否则新加的照片 sortOrder=0 会越过已有照片跳到顶部，违反用户预期）
    var nextOrder = await db.albumDao.getPhotoCount(widget.albumId);
    for (final photoId in selectedIds) {
      await db.albumDao.addPhotoToAlbum(widget.albumId, photoId,
          sortOrder: nextOrder);
      nextOrder++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 ${selectedIds.length} 张照片')),
      );
    }
  }

  Future<void> _removePhoto(String photoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从相册移除'),
        content: const Text('确定要将这张照片从相册中移除吗？照片本身不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(appDatabaseProvider);
    await db.albumDao.removePhotoFromAlbum(widget.albumId, photoId);
  }

  void _showPhotoOptions(Photo photo) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('设为相册封面'),
              onTap: () async {
                Navigator.pop(ctx);
                final db = ref.read(appDatabaseProvider);
                await db.albumDao.setCoverPhoto(widget.albumId, photo.id);
                // albumByIdProvider 是 stream，DB 变更会自动刷新 AppBar 标题
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle, color: StatusColors.error),
              title: const Text('从相册移除', style: TextStyle(color: StatusColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _removePhoto(photo.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(albumPhotosProvider(widget.albumId));
    final albumAsync = ref.watch(albumByIdProvider(widget.albumId));
    final albumName =
        albumAsync.maybeWhen(data: (a) => a?.name, orElse: () => null) ??
            '相册';

    return Scaffold(
      appBar: AppBar(
        title: Text(albumName),
        actions: [
          IconButton(
            icon: Icon(_isWaterfallView ? Icons.grid_view : Icons.view_quilt),
            tooltip: _isWaterfallView ? '网格视图' : '瀑布流视图',
            onPressed: () => setState(() => _isWaterfallView = !_isWaterfallView),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'add_existing':
                  _addExistingPhotos();
                  break;
                case 'import_new':
                  _addPhotos();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add_existing',
                child: Text('从已有照片添加'),
              ),
              const PopupMenuItem(
                value: 'import_new',
                child: Text('导入新照片'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部标签编辑面板（标签是相册的子系统）
          _buildTagPanel(),
          // 照片区
          Expanded(
            child: photosAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
              data: (photos) => _buildPhotoGrid(photos),
            ),
          ),
        ],
      ),
    );
  }

  /// 相册标签编辑面板：横向 chips + 末尾 ＋ 添加
  Widget _buildTagPanel() {
    final tagsAsync = ref.watch(albumTagsProvider(widget.albumId));
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: tagsAsync.when(
        loading: () => const SizedBox(
            height: 32, child: Center(child: SizedBox.shrink())),
        error: (_, __) => const SizedBox(height: 32),
        data: (tags) {
          return SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...tags.map((tag) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Chip(
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        labelPadding:
                            const EdgeInsets.only(left: 4, right: 2),
                        label: Text(tag.name),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => ref
                            .read(tagActionsProvider.notifier)
                            .removeTagFromAlbum(widget.albumId, tag.id),
                      ),
                    )),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('标签'),
                    onPressed: () => _showTagPicker(tags),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 标签选择器（复用已有全局标签 / 新建）
  Future<void> _showTagPicker(List<Tag> currentTags) async {
    final db = ref.read(appDatabaseProvider);
    final allTags = await db.tagDao.getAllTags();
    final currentIds = currentTags.map((t) => t.id).toSet();
    if (!mounted) return;

    final newTagController = TextEditingController();
    final selectedIds = <String>{};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Text('选择标签',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新建'),
                          onPressed: () async {
                            await showDialog(
                              context: ctx,
                              builder: (dctx) => AlertDialog(
                                title: const Text('新建标签'),
                                content: TextField(
                                  controller: newTagController,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                      hintText: '标签名'),
                                  onSubmitted: (v) {
                                    Navigator.pop(dctx, v.trim());
                                  },
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dctx),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(
                                        dctx, newTagController.text.trim()),
                                    child: const Text('创建'),
                                  ),
                                ],
                              ),
                            ).then((name) async {
                              if (name == null || name.isEmpty) return;
                              await ref
                                  .read(tagActionsProvider.notifier)
                                  .addTagToAlbum(widget.albumId, name);
                              if (ctx.mounted) Navigator.pop(ctx);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                    ),
                    child: allTags.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('还没有标签，点右上角新建'),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: allTags.length,
                            itemBuilder: (_, i) {
                              final tag = allTags[i];
                              final alreadyAdded = currentIds.contains(tag.id);
                              final isSelected =
                                  selectedIds.contains(tag.id);
                              return ListTile(
                                leading: Icon(
                                  alreadyAdded
                                      ? Icons.check
                                      : (isSelected
                                          ? Icons.check_circle
                                          : Icons.label_outline),
                                  color: alreadyAdded
                                      ? Theme.of(ctx)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.35)
                                      : (isSelected
                                          ? Theme.of(ctx).colorScheme.primary
                                          : null),
                                ),
                                title: Text(tag.name,
                                    style: alreadyAdded
                                        ? TextStyle(
                                            color: Theme.of(ctx)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.4))
                                        : null),
                                enabled: !alreadyAdded,
                                onTap: alreadyAdded
                                    ? null
                                    : () {
                                        setSheetState(() {
                                          if (isSelected) {
                                            selectedIds.remove(tag.id);
                                          } else {
                                            selectedIds.add(tag.id);
                                          }
                                        });
                                      },
                              );
                            },
                          ),
                  ),
                  if (selectedIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton(
                        onPressed: () async {
                          await db.tagDao.addTagsToAlbum(
                              widget.albumId, selectedIds.toList());
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Text('添加 ${selectedIds.length} 个标签'),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPhotoGrid(List<Photo> photos) {
    if (photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_outlined,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '相册还没有照片',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _addExistingPhotos,
              child: const Text('添加照片'),
            ),
          ],
        ),
      );
    }

    if (_isWaterfallView) {
      return MasonryGridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        padding: const EdgeInsets.all(6),
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photo = photos[index];
          // 回调传给 PhotoCard（与 home_page 一致），不外包 GestureDetector：
          // PhotoCard 内部 GestureDetector 注册了按压动画 recognizer，
          // 若外部再包一层 GestureDetector 且 PhotoCard.onTap 为 null，
          // 内部 recognizer 会赢得手势竞技场并吞掉 tap，外层永远收不到。
          return PhotoCard(
            key: ValueKey(photo.id),
            photo: photo,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetailPage(photoId: photo.id),
                ),
              );
            },
            onLongPress: () => _showPhotoOptions(photo),
          );
        },
      );
    }

    return ReorderableGridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: photos.length,
      onReorder: (oldIndex, newIndex) async {
        final orderedPhotos = List<Photo>.from(photos);
        // 标准 Flutter reorder 语义：向下移动时 newIndex 需 -1 修正
        final adjustedIndex =
            newIndex > oldIndex ? newIndex - 1 : newIndex;
        final element = orderedPhotos.removeAt(oldIndex);
        orderedPhotos.insert(adjustedIndex, element);

        final db = ref.read(appDatabaseProvider);
        await db.albumDao.updatePhotosSortOrder(
          albumId: widget.albumId,
          orderedPhotoIds: orderedPhotos.map((p) => p.id).toList(),
        );
        HapticFeedback.mediumImpact();
      },
      itemBuilder: (context, index) {
        final photo = photos[index];
        // 同上：回调传给 PhotoCard，不外包 GestureDetector
        return PhotoCard(
          key: ValueKey(photo.id),
          photo: photo,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetailPage(photoId: photo.id),
              ),
            );
          },
          onLongPress: () => _showPhotoOptions(photo),
        );
      },
    );
  }
}

/// 全屏照片选择页（替代 AlertDialog 选择器）
class PhotoSelectionPage extends StatefulWidget {
  final List<Photo> photos;
  final String albumName;

  const PhotoSelectionPage({
    super.key,
    required this.photos,
    required this.albumName,
  });

  @override
  State<PhotoSelectionPage> createState() => _PhotoSelectionPageState();
}

class _PhotoSelectionPageState extends State<PhotoSelectionPage> {
  final Set<String> _selectedIds = {};
  bool _selectMode = false; // true=单张点击切换选中，false=点击查看详情

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_selectMode
            ? '已选 ${_selectedIds.length} 张'
            : '选择照片 · ${widget.albumName}'),
        actions: [
          TextButton(
            onPressed: _selectedIds.isEmpty
                ? null
                : () => Navigator.pop(context, _selectedIds),
            child: Text(
              '添加 (${_selectedIds.length})',
              style: TextStyle(
                color: _selectedIds.isEmpty ? null : cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 提示栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.primary.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(Icons.touch_app, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _selectMode
                        ? '点击照片切换选中，再次点击取消'
                        : '长按照片进入选择模式，然后点击多张',
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
                if (_selectMode)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectMode = false;
                        _selectedIds.clear();
                      });
                    },
                    child: const Text('退出选择', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
          // 照片网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: widget.photos.length,
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                final isSelected = _selectedIds.contains(photo.id);

                return GestureDetector(
                  onTap: () {
                    if (_selectMode) {
                      setState(() {
                        if (isSelected) {
                          _selectedIds.remove(photo.id);
                        } else {
                          _selectedIds.add(photo.id);
                        }
                      });
                    }
                  },
                  onLongPress: () {
                    setState(() {
                      if (_selectMode) {
                        // 已在选择模式：长按 toggle 选中状态（与 onTap 一致）
                        if (isSelected) {
                          _selectedIds.remove(photo.id);
                        } else {
                          _selectedIds.add(photo.id);
                        }
                      } else {
                        // 首次进入选择模式：选中当前
                        _selectMode = true;
                        _selectedIds.add(photo.id);
                      }
                    });
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 用 IgnorePointer 包裹 PhotoCard 防止其内部手势干扰
                      IgnorePointer(
                        child: PhotoCard(photo: photo),
                      ),
                      // 选中蒙版
                      if (isSelected)
                        Container(
                          color: cs.primary.withValues(alpha: 0.3),
                        ),
                      // 勾选标记
                      if (isSelected)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(Icons.check,
                                size: 16, color: AppColors.onPhotoText),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
