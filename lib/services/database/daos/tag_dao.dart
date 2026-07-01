// tag_dao.dart — 标签数据访问对象
//
// v2.1：标签体系从「照片」迁移到「相册」。标签全局定义、可复用，
// 通过 [AlbumTags] 多对多关联到相册。本 DAO 只保留标签定义 CRUD
// 与相册-标签关联管理。
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'tag_dao.g.dart';

@DriftAccessor(tables: [Tags, AlbumTags])
class TagDao extends DatabaseAccessor<AppDatabase> with _$TagDaoMixin {
  TagDao(super.db);

  /// 获取全部标签
  Future<List<Tag>> getAllTags() =>
      (select(tags)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  /// 监听全部标签
  Stream<List<Tag>> watchAllTags() =>
      (select(tags)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  /// 按分组查询标签
  Future<List<Tag>> getTagsByGroup(String group) =>
      (select(tags)..where((t) => t.group.equals(group))).get();

  /// 按名称模糊查询标签
  ///
  /// 转义 LIKE 通配符（\、% 和 _）并带 escapeChar（坑 #15 在 drift 2.34+ 已支持
  /// escape 参数）。不带 escapeChar 时 SQLite 默认 LIKE 无转义符，\% 仍按
  /// 反斜杠+通配符处理，含 _ 的标签名会误匹配（如 "a_b" 命中 "axb"）。
  Future<List<Tag>> searchTagsByName(String name) {
    final escaped =
        name.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    return (select(tags)
          ..where((t) => t.name.like('%$escaped%', escapeChar: r'\'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// 创建标签
  Future<String> insertTag(TagsCompanion entry) async {
    await into(tags).insert(entry);
    return entry.id.value;
  }

  /// 更新标签
  Future<int> updateTag(Tag tag) =>
      (update(tags)..where((t) => t.id.equals(tag.id))).write(tag);

  /// 删除标签（同时级联清除相册-标签关联）
  Future<int> deleteTag(String id) async {
    return transaction(() async {
      await (delete(albumTags)..where((t) => t.tagId.equals(id))).go();
      return (delete(tags)..where((t) => t.id.equals(id))).go();
    });
  }

  // ============ 相册-标签关联 ============

  /// 为相册打标签（幂等，重复关联会被忽略）
  Future<void> addTagToAlbum(String albumId, String tagId) =>
      into(albumTags).insert(AlbumTagsCompanion(
        albumId: Value(albumId),
        tagId: Value(tagId),
      ), mode: InsertMode.insertOrIgnore);

  /// 移除相册标签
  Future<int> removeTagFromAlbum(String albumId, String tagId) =>
      (delete(albumTags)
            ..where((t) => t.albumId.equals(albumId) & t.tagId.equals(tagId)))
          .go();

  /// 删除相册的所有标签关联（删除相册时调用）
  Future<int> removeTagsFromAlbum(String albumId) =>
      (delete(albumTags)..where((t) => t.albumId.equals(albumId))).go();

  /// 获取相册的所有标签
  Future<List<Tag>> getTagsForAlbum(String albumId) async {
    final query = select(tags).join([
      innerJoin(albumTags, albumTags.tagId.equalsExp(tags.id)),
    ])
      ..where(albumTags.albumId.equals(albumId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(tags)).toList();
  }

  /// 获取相册的标签流（实时监听）
  Stream<List<Tag>> watchTagsForAlbum(String albumId) {
    final query = select(tags).join([
      innerJoin(albumTags, albumTags.tagId.equalsExp(tags.id)),
    ])
      ..where(albumTags.albumId.equals(albumId));
    return query.watch().map(
        (rows) => rows.map((row) => row.readTable(tags)).toList());
  }

  /// 批量为相册打标签（多对一相册）
  Future<void> addTagsToAlbum(String albumId, List<String> tagIds) async {
    await batch((b) {
      b.insertAll(
        albumTags,
        tagIds.map((tid) => AlbumTagsCompanion(
              albumId: Value(albumId),
              tagId: Value(tid),
            )),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }
}
