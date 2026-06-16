// album_dao.dart — 相册数据访问对象
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'album_dao.g.dart';

/// 相册 DAO
@DriftAccessor(tables: [Albums, AlbumPhotos, Photos])
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
      // 先删除关联
      await (delete(albumPhotos)
            ..where((ap) => ap.albumId.equals(albumId)))
          .go();
      // 再删除相册
      return (delete(albums)..where((a) => a.id.equals(albumId))).go();
    });
  }

  /// 添加照片到相册
  Future<int> addPhotoToAlbum(String albumId, String photoId,
      {int sortOrder = 0}) {
    return into(albumPhotos).insert(AlbumPhotosCompanion.insert(
      albumId: albumId,
      photoId: photoId,
      sortOrder: Value(sortOrder),
    ));
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
}
