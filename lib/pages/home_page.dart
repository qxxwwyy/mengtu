// home_page.dart — 首页瀑布流 + 导入 + 搜索 + 排序
//
// v2.1：照片不再有标签，搜索改为按文件名；多选仅保留"加入相册/删除"。
// 标签体系已迁移到相册（相册 Tab + 相册详情）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:uuid/uuid.dart';

import '../providers/photo_provider.dart';
import '../providers/database_provider.dart';
import '../services/database/app_database.dart';
import '../widgets/photo_card.dart';
import '../widgets/common/page_transitions.dart';
import '../widgets/common/empty_state.dart';
import 'detail_page.dart';
import '../theme/app_theme.dart';

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
              child: const Text('删除', style: TextStyle(color: StatusColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;

    final importService = await ref.read(importServiceProvider.future);
    // 先记录数量再 clear，否则 SnackBar 永远显示"已删除 0 张"
    final deletedCount = _selectedIds.length;
    for (final photoId in _selectedIds) {
      await importService.deletePhoto(photoId);
    }
    if (mounted) {
      setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 $deletedCount 张照片')),
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
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择相册',
                  style: AppTypography.title.copyWith(fontWeight: FontWeight.w600)),
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
                  Text('加入相册',
                      style: AppTypography.title.copyWith(fontWeight: FontWeight.w600)),
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
      detailPageRoute(DetailPage(photoId: photoId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(searchQueryProvider);
    final sortOrder = ref.watch(sortOrderProvider);
    // v2.1：搜索从"按标签名"改为"按文件名"（标签已迁移到相册）
    final photosAsync = searchQuery != null && searchQuery.isNotEmpty
        ? ref.watch(photosByNameSearchProvider(searchQuery))
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
                  hintText: '搜索照片名称...',
                  hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  ref.read(searchQueryProvider.notifier).set(
                      value.isEmpty ? null : value);
                },
              )
            : const Text('萌图'),
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
                return Column(
                  children: [
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
                          );
                        },
                      ),
                    ),
                    // 多选模式底部操作栏（v6.1 重构：Material 底栏，避开 FAB）
                    if (_selectMode) _buildSelectionBar(),
                  ],
                );
              },
            ),
      // v6.1：多选模式下隐藏导入 FAB（避免遮挡底部操作栏的「取消」按钮，问题5）
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton(
              onPressed: _pickAndImport,
              child: const Icon(Icons.add_photo_alternate),
            ),
    );
  }

  /// v6.1：多选模式底部操作栏
  ///
  /// 问题5：原操作栏用 Row + spaceAround，按钮被导入 FAB 遮挡（尤其「取消」
  /// 在最右被盖住）。重构为：
  /// - 多选时隐藏 FAB（上方已处理），操作栏占满底部安全区
  /// - 左侧「取消」用 IconButton 醒目，右侧「加入相册」「删除」用主操作按钮
  /// - 显示已选数量 chip，操作完自动退出多选
  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    final count = _selectedIds.length;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: AppColors.divider,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // 取消（左侧，醒目，绝不被遮挡）
              IconButton(
                onPressed: () => setState(() {
                  _selectMode = false;
                  _selectedIds.clear();
                }),
                icon: const Icon(Icons.close),
                tooltip: '取消多选',
              ),
              // 已选数量
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: Radii.mdBorder,
                ),
                child: Text(
                  '已选 $count',
                  style: AppTypography.caption.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600,),
                ),
              ),
              const Spacer(),
              // 加入相册
              TextButton.icon(
                icon: const Icon(Icons.photo_album_outlined, size: 20),
                label: const Text('加入相册'),
                onPressed: count == 0 ? null : _batchAddToAlbum,
              ),
              const SizedBox(width: 4),
              // 删除
              TextButton.icon(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: theme.colorScheme.error),
                label: Text('删除',
                    style: TextStyle(color: theme.colorScheme.error)),
                onPressed: count == 0 ? null : _batchDelete,
              ),
            ],
          ),
        ),
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
          borderRadius: Radii.mdBorder,
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.15),
          ),
        );
      }),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: Icons.camera_alt_outlined,
      title: '还没有照片',
      subtitle: '导入作品进行影调分析与直方图调色参考',
      actionLabel: '导入作品',
      onAction: _pickAndImport,
    );
  }
}
