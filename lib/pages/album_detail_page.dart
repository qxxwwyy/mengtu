// album_detail_page.dart — 相册详情页
//
// 显示相册内的照片，支持添加/移除照片
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../providers/database_provider.dart';
import '../services/database/app_database.dart';
import '../widgets/photo_card.dart';
import 'detail_page.dart';

/// 相册照片 Provider
final albumPhotosProvider =
    StreamProvider.family<List<Photo>, String>((ref, albumId) async* {
  final db = ref.watch(appDatabaseProvider);
  yield* db.albumDao.watchPhotosInAlbum(albumId);
});

class AlbumDetailPage extends ConsumerStatefulWidget {
  final String albumId;

  const AlbumDetailPage({super.key, required this.albumId});

  @override
  ConsumerState<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends ConsumerState<AlbumDetailPage> {
  Album? _album;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    final db = ref.read(appDatabaseProvider);
    final album = await db.albumDao.getAlbumById(widget.albumId);
    if (mounted) {
      setState(() => _album = album);
    }
  }

  Future<void> _addPhotos() async {
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
      await db.albumDao.addPhotoToAlbum(widget.albumId, photoId);
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
    final selectedIds = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoSelectionPage(
          photos: availablePhotos,
          albumName: _album?.name ?? '相册',
        ),
        fullscreenDialog: true,
      ),
    );

    if (selectedIds == null || selectedIds.isEmpty) return;

    for (final photoId in selectedIds) {
      await db.albumDao.addPhotoToAlbum(widget.albumId, photoId);
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

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(albumPhotosProvider(widget.albumId));

    return Scaffold(
      appBar: AppBar(
        title: Text(_album?.name ?? '相册'),
        actions: [
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
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (photos) {
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

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final photo = photos[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailPage(photoId: photo.id),
                    ),
                  );
                },
                onLongPress: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: ListTile(
                        leading:
                            const Icon(Icons.remove_circle, color: Colors.red),
                        title: const Text('从相册移除',
                            style: TextStyle(color: Colors.red)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _removePhoto(photo.id);
                        },
                      ),
                    ),
                  );
                },
                child: PhotoCard(
                  photo: photo,
                ),
              );
            },
          );
        },
      ),
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
                                size: 16, color: Colors.white),
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
