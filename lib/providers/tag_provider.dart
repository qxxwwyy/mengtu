// tag_provider.dart — 标签状态管理
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../services/database/app_database.dart';
import 'database_provider.dart';

const _uuid = Uuid();

/// 全部标签流
final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.tagDao.watchAllTags();
});

/// 某照片的标签流
final photoTagsProvider =
    StreamProvider.family<List<Tag>, String>((ref, photoId) {
  final db = ref.watch(appDatabaseProvider);
  return db.tagDao.watchTagsForPhoto(photoId);
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

  /// 为照片打标签（不存在则创建）
  Future<void> addTagToPhoto(String photoId, String tagName,
      {String group = 'custom'}) async {
    // 查找已有标签
    final existing = await _db.tagDao.searchTagsByName(tagName);
    String tagId;

    final exact = existing.where((t) => t.name == tagName).firstOrNull;
    if (exact != null) {
      tagId = exact.id;
    } else {
      tagId = await createTag(tagName, group: group);
    }
    await _db.tagDao.addTagToPhoto(photoId, tagId);
  }

  /// 移除照片标签
  Future<void> removeTagFromPhoto(String photoId, String tagId) =>
      _db.tagDao.removeTagFromPhoto(photoId, tagId);

  /// 删除标签
  Future<void> deleteTag(String tagId) => _db.tagDao.deleteTag(tagId);

  @override
  build() {}
}

final tagActionsProvider =
    NotifierProvider<TagActions, void>(TagActions.new);
