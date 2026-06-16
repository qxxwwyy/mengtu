// album_page.dart — 相册列表页
//
// 显示所有相册，支持创建/编辑/删除
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import '../providers/database_provider.dart';
import '../services/database/app_database.dart';
import 'album_detail_page.dart';

/// 相册列表 Provider
final albumsProvider = StreamProvider<List<Album>>((ref) async* {
  final db = ref.watch(appDatabaseProvider);
  yield* db.albumDao.watchAllAlbums();
});

class AlbumPage extends ConsumerStatefulWidget {
  const AlbumPage({super.key});

  @override
  ConsumerState<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<AlbumPage> {
  void _createAlbum() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建相册'),
        content: TextField(
          controller: nameController,
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
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final db = ref.read(appDatabaseProvider);
              final id = const Uuid().v4();
              await db.albumDao.insertAlbum(
                AlbumsCompanion.insert(
                  id: id,
                  name: name,
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(albumsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('相册'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createAlbum,
          ),
        ],
      ),
      body: albumsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (albums) {
          if (albums.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_album_outlined,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有相册',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _createAlbum,
                    child: const Text('创建第一个相册'),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return _AlbumCard(
                album: album,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailPage(albumId: album.id),
                    ),
                  );
                },
                onLongPress: () {
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
                              _editAlbum(album);
                            },
                          ),
                          ListTile(
                            leading:
                                const Icon(Icons.delete, color: Colors.red),
                            title: const Text('删除',
                                style: TextStyle(color: Colors.red)),
                            onTap: () {
                              Navigator.pop(ctx);
                              _deleteAlbum(album);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// 相册卡片（封面图 + 名称 + 数量）
class _AlbumCard extends ConsumerWidget {
  final Album album;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AlbumCard({
    required this.album,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 封面图（自动取首张或 coverPhotoId）
              FutureBuilder<Photo?>(
                future: db.albumDao.getCoverPhoto(album.id,
                    coverPhotoId: album.coverPhotoId),
                builder: (context, snapshot) {
                  final cover = snapshot.data;
                  if (cover == null) {
                    return Center(
                      child: Icon(Icons.photo_album,
                          size: 40,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                    );
                  }
                  final path = cover.thumbnailPath.isNotEmpty
                      ? cover.thumbnailPath
                      : cover.filePath;
                  return Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(Icons.broken_image,
                          size: 40,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                    ),
                  );
                },
              ),
              // 底部渐变遮罩 + 信息
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        album.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      FutureBuilder<int>(
                        future: db.albumDao.getPhotoCount(album.id),
                        builder: (context, snapshot) {
                          return Text(
                            '${snapshot.data ?? 0} 张',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
