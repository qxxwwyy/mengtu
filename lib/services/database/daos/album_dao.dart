// album_dao.dart — 相册数据访问对象
import 'dart:async';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'album_dao.g.dart';

/// 相册 DAO
@DriftAccessor(tables: [Albums, AlbumPhotos, AlbumTags, Photos, Tags])
class AlbumDao extends DatabaseAccessor<AppDatabase> with _$AlbumDaoMixin {
  AlbumDao(super.db);

  /// 查询所有相册（按更新时间倒序）
  Future<List<Album>> getAllAlbums() {
    return (select(albums)..orderBy([(a) => OrderingTerm.desc(a.updatedAt)]))
        .get();
  }

  /// 监听所有相册变化
  Stream<List<Album>> watchAllAlbums() {
    return (select(albums)..orderBy([(a) => OrderingTerm.desc(a.updatedAt)]))
        .watch();
  }

  /// 按 ID 查询相册
  Future<Album?> getAlbumById(String albumId) {
    return (select(albums)..where((a) => a.id.equals(albumId)))
        .getSingleOrNull();
  }

  /// 监听单个相册变化（reactive AppBar 标题，修当前 initState 一次性加载的过时问题）
  Stream<Album?> watchAlbumById(String albumId) {
    return (select(albums)..where((a) => a.id.equals(albumId)))
        .watchSingleOrNull();
  }

  /// 创建相册
  Future<int> insertAlbum(AlbumsCompanion album) {
    return into(albums).insert(album);
  }

  /// 更新相册
  Future<int> updateAlbum(AlbumsCompanion album) {
    return (update(albums)..where((a) => a.id.equals(album.id.value)))
        .write(album);
  }

  /// 删除相册（级联删除关联）
  Future<int> deleteAlbum(String albumId) {
    return transaction(() async {
      // 先删除关联（相册-照片 + 相册-标签）
      await (delete(albumPhotos)
            ..where((ap) => ap.albumId.equals(albumId)))
          .go();
      await (delete(albumTags)
            ..where((at) => at.albumId.equals(albumId)))
          .go();
      // 再删除相册
      return (delete(albums)..where((a) => a.id.equals(albumId))).go();
    });
  }

  /// 添加照片到相册
  ///
  /// 用 insertOrIgnore 幂等处理：若照片已在相册中（复合 PK 冲突），不报错、不重排。
  /// 调用方需要确定排序时应显式传 sortOrder（见 [updatePhotosSortOrder]）。
  Future<int> addPhotoToAlbum(String albumId, String photoId,
      {int sortOrder = 0}) {
    return into(albumPhotos).insert(
      AlbumPhotosCompanion.insert(
        albumId: albumId,
        photoId: photoId,
        sortOrder: Value(sortOrder),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// 从相册移除照片
  Future<int> removePhotoFromAlbum(String albumId, String photoId) {
    return (delete(albumPhotos)
          ..where(
              (ap) => ap.albumId.equals(albumId) & ap.photoId.equals(photoId)))
        .go();
  }

  /// 从所有相册移除照片（删除照片时调用，避免 FK 约束失败）
  Future<int> removePhotoFromAllAlbums(String photoId) {
    return (delete(albumPhotos)..where((ap) => ap.photoId.equals(photoId)))
        .go();
  }

  /// 监听包含某照片的所有相册（详情页信息 Tab「所属相册」用）
  Stream<List<Album>> watchAlbumsForPhoto(String photoId) {
    final query = select(albums).join([
      innerJoin(albumPhotos, albumPhotos.albumId.equalsExp(albums.id)),
    ])
      ..where(albumPhotos.photoId.equals(photoId))
      ..orderBy([OrderingTerm.desc(albums.updatedAt)]);
    return query
        .map((row) => row.readTable(albums))
        .watch();
  }

  /// 获取相册内的照片（按排序序号）
  Future<List<Photo>> getPhotosInAlbum(String albumId) {
    final query = select(albumPhotos).join([
      innerJoin(photos, photos.id.equalsExp(albumPhotos.photoId)),
    ])
      ..where(albumPhotos.albumId.equals(albumId))
      ..orderBy([OrderingTerm.asc(albumPhotos.sortOrder)]);

    return query.map((row) => row.readTable(photos)).get();
  }

  /// 获取相册封面照片（优先 coverPhotoId，否则取首张）
  Future<Photo?> getCoverPhoto(String albumId, {String? coverPhotoId}) async {
    // 如果设置了封面，优先用封面
    if (coverPhotoId != null && coverPhotoId.isNotEmpty) {
      final cover = await getPhotoById(coverPhotoId);
      if (cover != null) return cover;
    }
    // 否则取首张照片
    final query = select(albumPhotos).join([
      innerJoin(photos, photos.id.equalsExp(albumPhotos.photoId)),
    ])
      ..where(albumPhotos.albumId.equals(albumId))
      ..orderBy([OrderingTerm.asc(albumPhotos.sortOrder)])
      ..limit(1);
    final rows = await query.get();
    return rows.isEmpty ? null : rows.first.readTable(photos);
  }

  /// 通过 photoId 查单张照片（辅助方法，getCoverPhoto 用）
  Future<Photo?> getPhotoById(String photoId) {
    return (select(photos)..where((t) => t.id.equals(photoId)))
        .getSingleOrNull();
  }

  /// 监听相册内的照片变化
  Stream<List<Photo>> watchPhotosInAlbum(String albumId) {
    final query = select(albumPhotos).join([
      innerJoin(photos, photos.id.equalsExp(albumPhotos.photoId)),
    ])
      ..where(albumPhotos.albumId.equals(albumId))
      ..orderBy([OrderingTerm.asc(albumPhotos.sortOrder)]);

    return query.map((row) => row.readTable(photos)).watch();
  }

  /// 获取相册照片数量
  Future<int> getPhotoCount(String albumId) async {
    final query = selectOnly(albumPhotos)
      ..where(albumPhotos.albumId.equals(albumId))
      ..addColumns([albumPhotos.photoId.count()]);
    final result = await query.getSingle();
    return result.read(albumPhotos.photoId.count()) ?? 0;
  }

  /// 设置相册封面
  Future<int> setCoverPhoto(String albumId, String? photoId) {
    return (update(albums)..where((a) => a.id.equals(albumId))).write(
      AlbumsCompanion(coverPhotoId: Value(photoId)),
    );
  }

  /// 批量更新相册照片的排序
  Future<void> updatePhotosSortOrder({
    required String albumId,
    required List<String> orderedPhotoIds,
  }) {
    return transaction(() async {
      for (int i = 0; i < orderedPhotoIds.length; i++) {
        final photoId = orderedPhotoIds[i];
        await (update(albumPhotos)
              ..where((ap) => ap.albumId.equals(albumId) & ap.photoId.equals(photoId)))
            .write(AlbumPhotosCompanion(sortOrder: Value(i)));
      }
    });
  }

  // ============ v2.1 相册-标签体系 ============

  /// 监听带有指定标签的相册（供相册列表 chips 筛选用）
  Stream<List<Album>> watchAlbumsByTag(String tagId) {
    final query = select(albums).join([
      innerJoin(albumTags, albumTags.albumId.equalsExp(albums.id)),
    ])
      ..where(albumTags.tagId.equals(tagId))
      ..orderBy([OrderingTerm.desc(albums.updatedAt)]);
    return query
        .map((row) => row.readTable(albums))
        .watch();
  }

  /// 获取某标签被多少个相册使用（标签管理页计数显示用）
  Future<int> getAlbumCountByTag(String tagId) async {
    final count = albumTags.albumId.count();
    final query = selectOnly(albumTags)
      ..where(albumTags.tagId.equals(tagId))
      ..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// 一次性聚合：每个相册的标签列表 + 照片数（消除相册列表的 N+1 查询）
  ///
  /// 返回按 updatedAt 倒序的列表，供相册列表页直接渲染。
  /// **响应式**：合并监听 albums / album_tags / album_photos 三张表，任一变化
  /// （改名相册、给相册打标签、增删相册内照片）都会重算聚合输出。
  Stream<List<AlbumWithTags>> watchAlbumsWithTagInfo() {
    // drift 的 select(...).watch() 按各 select 读取的表注册更新依赖。
    // 把三张表的 watch 流合并为单一"有变化"信号流，再 asyncMap 重算聚合。
    final changeSignal = _mergeTableSignals([
      select(albums).watch(),
      select(albumTags).watch(),
      select(albumPhotos).watch(),
    ]);
    return changeSignal.asyncMap((_) async {
      final albumList = await (select(albums)
            ..orderBy([(a) => OrderingTerm.desc(a.updatedAt)]))
          .get();
      final result = <AlbumWithTags>[];
      for (final album in albumList) {
        final tags = await _getTagsForAlbumInline(album.id);
        final photoCount = await getPhotoCount(album.id);
        result.add(AlbumWithTags(
          album: album,
          tags: tags,
          photoCount: photoCount,
        ));
      }
      return result;
    });
  }

  /// 把多个表的 watch 流合并为单一"变化"信号流（丢弃各流的值，只转发 tick）。
  /// 任一源流发射 → 合并流发射一次，触发下游 asyncMap 重算。
  ///
  /// 用 broadcast 流以支持多个监听者（如测试中多次 `.first`，或多个 Provider 订阅）。
  /// 注意：broadcast 流的 onListen/onCancel 在每次订阅时触发，源订阅随之建立/取消，
  /// 因此无监听者时不占资源；最后一个监听者取消时自动取消所有源订阅。
  Stream<void> _mergeTableSignals(List<Stream<dynamic>> sources) {
    late StreamController<void> controller;
    final subscriptions = <StreamSubscription>[];
    int activeListeners = 0;
    controller = StreamController<void>.broadcast(
      onListen: () {
        activeListeners++;
        if (activeListeners == 1) {
          // 首个监听者到来：订阅所有源流
          for (final s in sources) {
            subscriptions.add(s.listen(
              (_) {
                if (!controller.isClosed) controller.add(null);
              },
              onError: controller.addError,
            ));
          }
        }
      },
      onCancel: () {
        activeListeners--;
        if (activeListeners <= 0) {
          // 最后一个监听者离开：取消所有源订阅
          for (final sub in subscriptions) {
            sub.cancel();
          }
          subscriptions.clear();
          activeListeners = 0;
        }
      },
    );
    return controller.stream;
  }

  /// 查询相册的标签（内部聚合用，避免跨 DAO 调用）
  Future<List<Tag>> _getTagsForAlbumInline(String albumId) async {
    final query = select(tags).join([
      innerJoin(albumTags, albumTags.tagId.equalsExp(tags.id)),
    ])
      ..where(albumTags.albumId.equals(albumId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(tags)).toList();
  }
}

/// 相册 + 标签 + 照片数聚合（watchAlbumsWithTagInfo 的返回类型）
class AlbumWithTags {
  final Album album;
  final List<Tag> tags;
  final int photoCount;

  const AlbumWithTags({
    required this.album,
    required this.tags,
    required this.photoCount,
  });
}

