// album_provider.dart — 相册状态管理
//
// v2.1：集中相册相关 provider，修复此前相册 provider 散落在 page 文件、
// 被 profile_page 跨页 `show albumsProvider` 的耦合（见 tag_dao/album_page）。
// 标签作为相册的子系统，其关联 provider 也集中于此。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database/app_database.dart';
import '../services/database/daos/album_dao.dart' show AlbumWithTags;
import 'database_provider.dart';

/// 全部相册流（实时监听 DB 变化，创建/编辑/删除后自动刷新）
final albumsProvider = StreamProvider<List<Album>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.albumDao.watchAllAlbums();
});

/// 相册列表聚合流：相册 + 标签 + 照片数（消除相册列表 N+1 查询）
final albumsWithTagsProvider =
    StreamProvider<List<AlbumWithTags>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.albumDao.watchAlbumsWithTagInfo();
});

/// 单个相册流（reactive AppBar 标题，修 album_detail_page initState 过时问题）
final albumByIdProvider =
    StreamProvider.family<Album?, String>((ref, albumId) {
  final db = ref.watch(appDatabaseProvider);
  return db.albumDao.watchAlbumById(albumId);
});

/// 相册内的照片流（实时监听）
final albumPhotosProvider =
    StreamProvider.family<List<Photo>, String>((ref, albumId) {
  final db = ref.watch(appDatabaseProvider);
  return db.albumDao.watchPhotosInAlbum(albumId);
});

/// 相册的标签流（实时监听）—— 标签是相册的子系统
final albumTagsProvider =
    StreamProvider.family<List<Tag>, String>((ref, albumId) {
  final db = ref.watch(appDatabaseProvider);
  return db.tagDao.watchTagsForAlbum(albumId);
});

/// 按标签筛选的相册流（供相册列表顶栏 chips 筛选）
final albumsByTagProvider =
    StreamProvider.family<List<Album>, String>((ref, tagId) {
  final db = ref.watch(appDatabaseProvider);
  return db.albumDao.watchAlbumsByTag(tagId);
});

/// 包含某照片的所有相册流（详情页信息 Tab「所属相册」用）
final photoAlbumsProvider =
    StreamProvider.family<List<Album>, String>((ref, photoId) {
  final db = ref.watch(appDatabaseProvider);
  return db.albumDao.watchAlbumsForPhoto(photoId);
});

/// 相册列表顶栏当前选中的筛选标签 ID（null = 全部）
class AlbumTagFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? tagId) => state = tagId;
}

final albumTagFilterProvider =
    NotifierProvider<AlbumTagFilterNotifier, String?>(
        AlbumTagFilterNotifier.new);
