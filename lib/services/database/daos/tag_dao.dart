// tag_dao.dart — 标签数据访问对象
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'tag_dao.g.dart';

@DriftAccessor(tables: [Tags, PhotoTags])
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

  /// 按名称模糊查询标签（转义 LIKE 通配符，防止 % / _ 注入）
  Future<List<Tag>> searchTagsByName(String name) {
    final escaped = _escapeLike(name);
    return (select(tags)..where((t) => t.name.like('%$escaped%'))).get();
  }

  /// 创建标签
  Future<String> insertTag(TagsCompanion entry) async {
    await into(tags).insert(entry);
    return entry.id.value;
  }

  /// 更新标签
  Future<int> updateTag(Tag tag) =>
      (update(tags)..where((t) => t.id.equals(tag.id))).write(tag);

  /// 删除标签（事务内级联删除关联）
  Future<int> deleteTag(String id) async {
    return await transaction(() async {
      await (delete(photoTags)..where((t) => t.tagId.equals(id))).go();
      return (delete(tags)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 为照片打标签
  Future<void> addTagToPhoto(String photoId, String tagId) =>
      into(photoTags).insert(PhotoTagsCompanion(
        photoId: Value(photoId),
        tagId: Value(tagId),
      ), mode: InsertMode.insertOrIgnore);

  /// 移除照片标签
  Future<int> removeTagFromPhoto(String photoId, String tagId) =>
      (delete(photoTags)
            ..where((t) => t.photoId.equals(photoId) & t.tagId.equals(tagId)))
          .go();

  /// 删除照片的所有标签关联（删除照片时调用）
  Future<int> removeTagsByPhoto(String photoId) =>
      (delete(photoTags)..where((t) => t.photoId.equals(photoId))).go();

  /// 获取照片的所有标签
  Future<List<Tag>> getTagsForPhoto(String photoId) async {
    final query = select(tags).join([
      innerJoin(photoTags, photoTags.tagId.equalsExp(tags.id)),
    ])
      ..where(photoTags.photoId.equals(photoId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(tags)).toList();
  }

  /// 获取照片的标签流（实时监听）
  Stream<List<Tag>> watchTagsForPhoto(String photoId) {
    final query = select(tags).join([
      innerJoin(photoTags, photoTags.tagId.equalsExp(tags.id)),
    ])
      ..where(photoTags.photoId.equals(photoId));
    return query.watch().map(
        (rows) => rows.map((row) => row.readTable(tags)).toList());
  }

  /// 批量打标签
  Future<void> addTagToPhotos(List<String> photoIds, String tagId) async {
    await batch((b) {
      b.insertAll(
        photoTags,
        photoIds.map((pid) => PhotoTagsCompanion(
              photoId: Value(pid),
              tagId: Value(tagId),
            )),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// 转义 SQLite LIKE 通配符（% 和 _）
  String _escapeLike(String input) {
    return input.replaceAll('%', r'\\%').replaceAll('_', r'\\_');
  }
}
