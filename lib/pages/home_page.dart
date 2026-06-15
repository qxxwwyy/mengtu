// home_page.dart — 首页瀑布流 + 导入 + 搜索 + 排序
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:uuid/uuid.dart';

import '../providers/photo_provider.dart';
import '../providers/database_provider.dart';
import '../services/database/app_database.dart';
import '../services/import_service.dart' show ImportResult;
import '../widgets/photo_card.dart';
import 'detail_page.dart';
import 'tag_manage_page.dart';
import 'settings_page.dart';
import 'album_page.dart';

/// 导入方式选项
enum _ImportChoice { direct, newAlbum, existingAlbum }

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  bool _isImporting = false;
  int _importProgress = 0;
  int _importTotal = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickAndImport() async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: 100,
        requestType: RequestType.image,
      ),
    );
    if (assets == null || assets.isEmpty) return;

    // 选完后弹出操作选项
    if (!mounted) return;
    final choice = await _showImportOptions();

    if (choice == null) return;

    final filePaths = <String>[];
    for (final asset in assets) {
      final file = await asset.file;
      if (file != null) filePaths.add(file.path);
    }

    switch (choice) {
      case _ImportChoice.direct:
        await _importAssets(filePaths);
        break;
      case _ImportChoice.newAlbum:
        final albumName = await _askAlbumName();
        if (albumName == null || albumName.isEmpty) {
          await _importAssets(filePaths);
        } else {
          await _importAssetsAndCreateAlbum(filePaths, albumName);
        }
        break;
      case _ImportChoice.existingAlbum:
        final albumId = await _pickExistingAlbum();
        if (albumId != null) {
          await _importAssetsAndAddToAlbum(filePaths, albumId);
        } else {
          await _importAssets(filePaths);
        }
        break;
    }
  }

  /// 导入后的操作选项弹窗
  Future<_ImportChoice?> _showImportOptions() {
    return showModalBottomSheet<_ImportChoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('导入方式',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('直接导入'),
              subtitle: const Text('照片出现在全部列表中'),
              onTap: () => Navigator.pop(ctx, _ImportChoice.direct),
            ),
            ListTile(
              leading: Icon(Icons.create_new_folder_outlined,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('新建相册并导入'),
              subtitle: const Text('创建相册，本次选的照片自动放入'),
              onTap: () => Navigator.pop(ctx, _ImportChoice.newAlbum),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('导入到已有相册'),
              subtitle: const Text('选择一个已有相册'),
              onTap: () => Navigator.pop(ctx, _ImportChoice.existingAlbum),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

  /// 选择已有相册
  Future<String?> _pickExistingAlbum() async {
    final db = ref.read(appDatabaseProvider);
    final albums = await db.albumDao.getAllAlbums();
    if (albums.isEmpty || !mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择相册'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: albums.length,
            itemBuilder: (ctx, index) {
              final album = albums[index];
              return ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(album.name),
                onTap: () => Navigator.pop(ctx, album.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 导入照片并创建新相册
  Future<void> _importAssetsAndCreateAlbum(
      List<String> filePaths, String albumName) async {
    // 先导入，获取精确的 photoId 列表
    final result = await _importAssets(filePaths);

    if (result.importedPhotoIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有照片可导入')),
        );
      }
      return;
    }

    // 创建相册
    final db = ref.read(appDatabaseProvider);
    final albumId = const Uuid().v4();
    await db.albumDao.insertAlbum(
      AlbumsCompanion.insert(id: albumId, name: albumName),
    );

    // 把导入的照片加入相册（用精确的 photoId，不做 fileName 模糊匹配）
    for (final photoId in result.importedPhotoIds) {
      await db.albumDao.addPhotoToAlbum(albumId, photoId);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${result.importedPhotoIds.length} 张照片到相册「$albumName」')),
      );
    }
  }

  /// 导入照片并添加到已有相册
  Future<void> _importAssetsAndAddToAlbum(
      List<String> filePaths, String albumId) async {
    // 先导入，获取精确的 photoId 列表
    final result = await _importAssets(filePaths);

    if (result.importedPhotoIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有照片可导入')),
        );
      }
      return;
    }

    // 把导入的照片加入相册
    final db = ref.read(appDatabaseProvider);
    final album = await db.albumDao.getAlbumById(albumId);
    final albumName = album?.name ?? '相册';
    for (final photoId in result.importedPhotoIds) {
      await db.albumDao.addPhotoToAlbum(albumId, photoId);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${result.importedPhotoIds.length} 张照片到相册「$albumName」')),
      );
    }
  }

  Future<ImportResult> _importAssets(List<String> filePaths) async {
    setState(() {
      _isImporting = true;
      _importTotal = filePaths.length;
    });

    final importService = await ref.read(importServiceProvider.future);

    final result = await importService.importPhotos(
      filePaths,
      onProgress: (processed, total) {
        setState(() => _importProgress = processed);
      },
    );

    setState(() => _isImporting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '导入 ${result.successCount} 张, 跳过 ${result.skippedCount} 张'),
        ),
      );
    }

    return result;
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
              } else if (value == 'tags') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TagManagePage()));
              } else if (value == 'albums') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AlbumPage()));
              } else if (value == 'settings') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()));
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
              const PopupMenuItem(
                value: 'tags',
                child: Row(children: [
                  Icon(Icons.label_outline),
                  SizedBox(width: 8),
                  Text('标签管理'),
                ]),
              ),
              const PopupMenuItem(
                value: 'albums',
                child: Row(children: [
                  Icon(Icons.photo_album_outlined),
                  SizedBox(width: 8),
                  Text('相册'),
                ]),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(children: [
                  Icon(Icons.settings_outlined),
                  SizedBox(width: 8),
                  Text('设置'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _isImporting
          ? _buildImportProgress()
          : photosAsync.when(
              loading: () => _buildLoadingGrid(),
              error: (e, _) => Center(child: Text('错误: $e')),
              data: (photos) {
                if (photos.isEmpty) {
                  return _buildEmptyState();
                }
                final sorted = sortOrder == SortOrder.oldest
                    ? photos.reversed.toList()
                    : photos;
                return MasonryGridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  padding: const EdgeInsets.all(6),
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    return PhotoCard(
                      photo: sorted[index],
                      onTap: () => _navigateToDetail(sorted[index].id),
                    );
                  },
                );
              },
            ),
      floatingActionButton: _isImporting
          ? null
          : FloatingActionButton(
              onPressed: _pickAndImport,
              child: const Icon(Icons.add_photo_alternate),
            ),
    );
  }

  Widget _buildImportProgress() {
    final percent = _importTotal > 0
        ? (_importProgress / _importTotal * 100).round()
        : 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_download,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              value: _importTotal > 0 ? _importProgress / _importTotal : null,
            ),
            const SizedBox(height: 12),
            Text(
              _importTotal > 0
                  ? '导入中 $_importProgress / $_importTotal（$percent%）'
                  : '正在准备...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.photo_library,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text('还没有照片',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                )),
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮，导入你的摄影作品',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
