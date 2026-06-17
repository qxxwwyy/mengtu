// tag_provider.dart — 标签状态管理
//
// v2.1：标签体系从「照片」迁移到「相册」。标签全局定义、可复用，
// 通过 AlbumTags 关联到相册。原 photoTagsProvider / addTagToPhoto 已移除。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../services/database/app_database.dart';
import 'database_provider.dart';

const _uuid = Uuid();

/// 全部标签流（标签全局定义，可复用于多个相册）
final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.tagDao.watchAllTags();
});

/// 搜索匹配的标签
final tagSearchProvider =
    FutureProvider.family<List<Tag>, String>((ref, query) {
  final db = ref.watch(appDatabaseProvider);
  if (query.isEmpty) return db.tagDao.getAllTags();
  return db.tagDao.searchTagsByName(query);
});

/// 标签操作 Notifier
class TagActions extends Notifier {
  AppDatabase get _db => ref.read(appDatabaseProvider);

  /// 创建标签
  Future<String> createTag(String name, {String group = 'custom'}) async {
    final id = _uuid.v4();
    await _db.tagDao.insertTag(TagsCompanion.insert(
      id: id,
      name: name,
      group: Value(group),
    ));
    return id;
  }

  /// 为相册打标签（不存在则创建）。用于相册详情/列表的"加标签"流程。
  Future<void> addTagToAlbum(String albumId, String tagName,
      {String group = 'custom'}) async {
    // 查找已有标签（精确匹配名称，保证全局可复用）
    final existing = await _db.tagDao.searchTagsByName(tagName);
    String tagId;

    final exact = existing.where((t) => t.name == tagName).firstOrNull;
    if (exact != null) {
      tagId = exact.id;
    } else {
      tagId = await createTag(tagName, group: group);
    }
    await _db.tagDao.addTagToAlbum(albumId, tagId);
  }

  /// 移除相册标签
  Future<void> removeTagFromAlbum(String albumId, String tagId) =>
      _db.tagDao.removeTagFromAlbum(albumId, tagId);

  /// 删除标签（全局删除，同时清除所有相册-标签关联）
  Future<void> deleteTag(String tagId) => _db.tagDao.deleteTag(tagId);

  @override
  build() {}
}

final tagActionsProvider =
    NotifierProvider<TagActions, void>(TagActions.new);
