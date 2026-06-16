// home_page.dart — 首页瀑布流 + 导入 + 搜索 + 排序
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:uuid/uuid.dart';

import '../providers/photo_provider.dart';
import '../providers/tag_provider.dart';
import '../providers/database_provider.dart';
import '../services/database/app_database.dart';
import '../widgets/photo_card.dart';
import 'detail_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  // 多选模式
  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 快速给照片加标签（从卡片右下角图标触发，不进详情页）
  Future<void> _quickAddTag(String photoId) async {
    final db = ref.read(appDatabaseProvider);
    final allTags = await db.tagDao.getAllTags();
    final photoTags = await db.tagDao.getTagsForPhoto(photoId);
    final taggedIds = photoTags.map((t) => t.id).toSet();

    if (!mounted) return;
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
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新建'),
                          onPressed: () async {
                            final name = await _showCreateTagDialog();
                            if (name == null || name.isEmpty) return;
                            final tag = await db.tagDao
                                .insertTag(TagsCompanion.insert(
                              id: 'tag-${DateTime.now().microsecondsSinceEpoch}',
                              name: name,
                            ));
                            await db.tagDao.addTagToPhoto(tag, photoId);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已创建并添加标签「$name」')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                    ),
                    child: allTags.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('还没有标签，点右上角新建',
                                  style: TextStyle(color: Colors.white54)),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: allTags.length,
                            itemBuilder: (_, i) {
                              final tag = allTags[i];
                              final isSelected = taggedIds.contains(tag.id);
                              return ListTile(
                                leading: Icon(
                                  isSelected ? Icons.check_circle : Icons.label_outline,
                                  color: isSelected
                                      ? Theme.of(ctx).colorScheme.primary
                                      : null,
                                ),
                                title: Text(tag.name),
                                onTap: () async {
                                  if (isSelected) {
                                    await db.tagDao
                                        .removeTagFromPhoto(tag.id, photoId);
                                    taggedIds.remove(tag.id);
                                  } else {
                                    await db.tagDao
                                        .addTagToPhoto(tag.id, photoId);
                                    taggedIds.add(tag.id);
                                  }
                                  setSheetState(() {});
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 新建标签对话框（返回标签名，取消返回 null）
  Future<String?> _showCreateTagDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '标签名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  /// 批量删除选中照片
  Future<void> _batchDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除照片'),
        content: Text('确定删除选中的 ${_selectedIds.length} 张照片吗？\n'
            '原始照片文件不会被删除，仅移除应用内记录。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    final importService = await ref.read(importServiceProvider.future);
    for (final photoId in _selectedIds) {
      await importService.deletePhoto(photoId);
    }
    if (mounted) {
      setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${_selectedIds.length} 张照片')),
      );
    }
  }

  /// 批量把选中照片加入相册
  Future<void> _batchAddToAlbum() async {
    final db = ref.read(appDatabaseProvider);
    final albums = await db.albumDao.getAllAlbums();
    if (!mounted) return;
    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有相册，请先创建')),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择相册',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            ...albums.map((a) => ListTile(
                  leading: const Icon(Icons.photo_album_outlined),
                  title: Text(a.name),
                  onTap: () => Navigator.pop(ctx, a.id),
                )),
          ],
        ),
      ),
    );
    if (selected != null) {
      for (final photoId in _selectedIds) {
        await db.albumDao.addPhotoToAlbum(selected, photoId);
      }
      if (mounted) {
        setState(() {
          _selectMode = false;
          _selectedIds.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入相册')),
        );
      }
    }
  }

  /// 批量给选中照片加标签
  Future<void> _batchAddTag() async {
    final db = ref.read(appDatabaseProvider);
    final allTags = await db.tagDao.getAllTags();
    if (!mounted) return;
    if (allTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有标签，请先创建')),
      );
      return;
    }
    final selectedTagIds = <String>{};
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
                        Text('选择标签（${_selectedIds.length} 张照片）',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton(
                          onPressed: selectedTagIds.isEmpty
                              ? null
                              : () async {
                                  Navigator.pop(ctx);
                                  for (final photoId in _selectedIds) {
                                    for (final tagId in selectedTagIds) {
                                      await db.tagDao
                                          .addTagToPhoto(tagId, photoId);
                                    }
                                  }
                                  if (mounted) {
                                    setState(() {
                                      _selectMode = false;
                                      _selectedIds.clear();
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(
                                          '已给 ${_selectedIds.length} 张照片添加 ${selectedTagIds.length} 个标签')),
                                    );
                                  }
                                },
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: allTags.length,
                      itemBuilder: (_, i) {
                        final tag = allTags[i];
                        final isSelected = selectedTagIds.contains(tag.id);
                        return ListTile(
                          leading: Icon(
                            isSelected ? Icons.check_circle : Icons.label_outline,
                            color: isSelected
                                ? Theme.of(ctx).colorScheme.primary
                                : null,
                          ),
                          title: Text(tag.name),
                          onTap: () {
                            setSheetState(() {
                              if (isSelected) {
                                selectedTagIds.remove(tag.id);
                              } else {
                                selectedTagIds.add(tag.id);
                              }
                            });
                          },
                        );
                      },
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

  Future<void> _pickAndImport() async {
    // 权限预检：避免用户拒绝相册权限后无提示卡死
    // 注意：isAuth 仅匹配 authorized，会漏掉 Android 14+ 的 limited（部分授权）状态，
    // 导致已授权用户每次导入都误弹权限提示，改用 hasAccess 兼容 limited。
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
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: 100,
        requestType: RequestType.image,
      ),
    );
    if (assets == null || assets.isEmpty) return;

    final filePaths = <String>[];
    for (final asset in assets) {
      final file = await asset.file;
      if (file != null) filePaths.add(file.path);
    }
    if (filePaths.isEmpty) return;

    if (!mounted) return;

    // 显示后台导入中的 SnackBar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('正在后台导入照片...'),
          ],
        ),
        duration: Duration(days: 1), // 持续显示直到导入完成
      ),
    );

    try {
      final importService = await ref.read(importServiceProvider.future);
      final result = await importService.importPhotos(filePaths);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (result.importedPhotoIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未导入任何照片（可能已全部去重跳过）')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功导入 ${result.successCount} 张，跳过 ${result.skippedCount} 张'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '加入相册',
            onPressed: () {
              _addImportedToAlbum(result.importedPhotoIds);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入出错: $e')),
      );
    }
  }

  /// 输入相册名称
  Future<String?> _askAlbumName() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建相册'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入相册名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  /// 将导入的照片加入相册
  Future<void> _addImportedToAlbum(List<String> photoIds) async {
    final db = ref.read(appDatabaseProvider);
    final albums = await db.albumDao.getAllAlbums();
    if (!mounted) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('加入相册',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建相册'),
                    onPressed: () async {
                      final name = await _askAlbumName();
                      if (name != null && name.isNotEmpty) {
                        final albumId = const Uuid().v4();
                        await db.albumDao.insertAlbum(
                          AlbumsCompanion.insert(id: albumId, name: name),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, albumId);
                      }
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (albums.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('没有相册，请点击右上角新建'),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return ListTile(
                      leading: const Icon(Icons.photo_album_outlined),
                      title: Text(album.name),
                      onTap: () => Navigator.pop(ctx, album.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );

    if (selected != null) {
      for (final photoId in photoIds) {
        await db.albumDao.addPhotoToAlbum(selected, photoId);
      }
      final album = await db.albumDao.getAlbumById(selected);
      final albumName = album?.name ?? '相册';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功将 ${photoIds.length} 张照片加入相册「$albumName」')),
        );
      }
    }
  }

  void _navigateToDetail(String photoId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailPage(photoId: photoId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(searchQueryProvider);
    final sortOrder = ref.watch(sortOrderProvider);
    final photosAsync = searchQuery != null && searchQuery.isNotEmpty
        ? ref.watch(photosByTagSearchProvider(searchQuery))
        : ref.watch(allPhotosProvider);

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).scaffoldBackgroundColor,
                Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
              ],
            ),
          ),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: '搜索标签...',
                  hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  ref.read(searchQueryProvider.notifier).set(
                      value.isEmpty ? null : value);
                },
              )
            : Text('萌图',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.primary,
                )),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  ref.read(searchQueryProvider.notifier).set(null);
                }
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'sort') {
                ref.read(sortOrderProvider.notifier).toggle();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'sort',
                child: Row(
                  children: [
                    Icon(sortOrder == SortOrder.newest
                        ? Icons.arrow_downward
                        : Icons.arrow_upward),
                    const SizedBox(width: 8),
                    Text(sortOrder == SortOrder.newest ? '最新优先' : '最旧优先'),
                  ],
                ),
              ),
              // 相册/标签/设置已迁移到底部导航（策划 tab / 我的 tab）
            ],
          ),
        ],
      ),
      body: photosAsync.when(
              loading: () => _buildLoadingGrid(),
              error: (e, _) => Center(child: Text('错误: $e')),
              data: (photos) {
                if (photos.isEmpty) {
                  return _buildEmptyState();
                }
                final sorted = sortOrder == SortOrder.oldest
                    ? photos.reversed.toList()
                    : photos;
                // 标签筛选 chips（点击切换筛选，复用 searchQueryProvider）
                final tagsAsync = ref.watch(allTagsProvider);
                final currentQuery = ref.watch(searchQueryProvider);
                return Column(
                  children: [
                    // 标签 chips 筛选条
                    tagsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (tags) {
                        if (tags.isEmpty) return const SizedBox.shrink();
                        return SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            children: [
                              FilterChip(
                                label: const Text('全部'),
                                selected: currentQuery == null,
                                onSelected: (_) => ref
                                    .read(searchQueryProvider.notifier)
                                    .set(null),
                              ),
                              const SizedBox(width: 6),
                              ...tags.map((tag) {
                                final selected = currentQuery == tag.name;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilterChip(
                                    label: Text(tag.name),
                                    selected: selected,
                                    onSelected: (_) => ref
                                        .read(searchQueryProvider.notifier)
                                        .set(selected ? null : tag.name),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
                    // 瀑布流
                    Expanded(
                      child: MasonryGridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        padding: const EdgeInsets.all(6),
                        cacheExtent: 500,
                        itemCount: sorted.length,
                        itemBuilder: (context, index) {
                          final photo = sorted[index];
                          return PhotoCard(
                            photo: photo,
                            selectMode: _selectMode,
                            isSelected: _selectedIds.contains(photo.id),
                            onTap: () {
                              if (_selectMode) {
                                setState(() {
                                  if (_selectedIds.contains(photo.id)) {
                                    _selectedIds.remove(photo.id);
                                    if (_selectedIds.isEmpty) _selectMode = false;
                                  } else {
                                    _selectedIds.add(photo.id);
                                  }
                                });
                              } else {
                                _navigateToDetail(photo.id);
                              }
                            },
                            onLongPress: () {
                              setState(() {
                                _selectMode = true;
                                _selectedIds.add(photo.id);
                              });
                            },
                            onTagTap: _selectMode ? null : () => _quickAddTag(photo.id),
                          );
                        },
                      ),
                    ),
                    // 多选模式底部操作栏
                    if (_selectMode)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.1),
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.photo_album_outlined, size: 20),
                              label: Text('加入相册 (${_selectedIds.length})'),
                              onPressed: _selectedIds.isEmpty
                                  ? null
                                  : () => _batchAddToAlbum(),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.local_offer_outlined, size: 20),
                              label: const Text('加标签'),
                              onPressed: _selectedIds.isEmpty
                                  ? null
                                  : () => _batchAddTag(),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red),
                              label: const Text('删除',
                                  style: TextStyle(color: Colors.red)),
                              onPressed: _selectedIds.isEmpty
                                  ? null
                                  : () => _batchDelete(),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _selectMode = false;
                                _selectedIds.clear();
                              }),
                              child: const Text('取消'),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndImport,
        child: const Icon(Icons.add_photo_alternate),
      ),
    );
  }

  /// 骨架屏加载态
  Widget _buildLoadingGrid() {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(6),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: List.generate(6, (i) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.15),
          ),
        );
      }),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glowing camera container
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                    theme.colorScheme.primary.withValues(alpha: 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.camera_alt_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '还没有照片',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '开始你的摄影美学之旅吧！导入作品进行影调分析与直方图调色参考',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Premium CTA Button
            ElevatedButton.icon(
              onPressed: _pickAndImport,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
              label: const Text('导入作品', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                foregroundColor: theme.colorScheme.onPrimary,
                backgroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 4,
                shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
