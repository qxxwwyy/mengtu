// tag_dao_test.dart — 标签 DAO 测试（内存数据库）
//
// v2.1：标签是相册的子系统。照片不再有标签，关联改为 AlbumTags。
// 本测试覆盖全局标签 CRUD + 相册-标签关联管理。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/database/app_database.dart';
import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  Future<Tag> insertTag(String id, String name,
      {String group = 'custom'}) async {
    await db.tagDao.insertTag(TagsCompanion.insert(
      id: id,
      name: name,
      group: Value(group),
    ));
    return (await db.tagDao.getAllTags()).firstWhere((t) => t.id == id);
  }

  Future<void> insertAlbum(String id, String name) async {
    await db.albumDao.insertAlbum(AlbumsCompanion.insert(id: id, name: name));
  }

  group('TagDao CRUD', () {
    test('insertTag + getAllTags', () async {
      await insertTag('t1', '日系', group: 'atmosphere');
      final tags = await db.tagDao.getAllTags();
      expect(tags.length, 1);
      expect(tags.first.name, '日系');
      expect(tags.first.group, 'atmosphere');
    });

    test('updateTag 修改标签', () async {
      await insertTag('t1', '日系');
      final tag = (await db.tagDao.getAllTags()).first;
      final updated = tag.copyWith(name: '胶片', group: 'scene');
      await db.tagDao.updateTag(updated);

      final result = await db.tagDao.getAllTags();
      expect(result.first.name, '胶片');
      expect(result.first.group, 'scene');
    });

    test('deleteTag 删除标签', () async {
      await insertTag('t1', '日系');
      await db.tagDao.deleteTag('t1');
      final tags = await db.tagDao.getAllTags();
      expect(tags, isEmpty);
    });

    test('deleteTag 级联删除 album_tags 关联', () async {
      await insertAlbum('a1', '相册1');
      await insertTag('t1', '日系');
      await db.tagDao.addTagToAlbum('a1', 't1');

      // 验证关联存在
      var tags = await db.tagDao.getTagsForAlbum('a1');
      expect(tags.length, 1);

      // 删标签
      await db.tagDao.deleteTag('t1');

      // 关联应被清除
      tags = await db.tagDao.getTagsForAlbum('a1');
      expect(tags, isEmpty);
    });
  });

  group('TagDao 按分组查询', () {
    setUp(() async {
      await insertTag('t1', '日系', group: 'atmosphere');
      await insertTag('t2', '胶片', group: 'atmosphere');
      await insertTag('t3', '户外', group: 'scene');
      await insertTag('t4', '自定义', group: 'custom');
    });

    test('getTagsByGroup 返回指定分组', () async {
      final atmosphere = await db.tagDao.getTagsByGroup('atmosphere');
      expect(atmosphere.length, 2);
      expect(atmosphere.every((t) => t.group == 'atmosphere'), isTrue);

      final scene = await db.tagDao.getTagsByGroup('scene');
      expect(scene.length, 1);
    });
  });

  group('TagDao 按名称搜索', () {
    setUp(() async {
      await insertTag('t1', '日系');
      await insertTag('t2', '日暮');
      await insertTag('t3', '户外');
    });

    test('searchTagsByName 模糊匹配', () async {
      final results = await db.tagDao.searchTagsByName('日');
      expect(results.length, 2);
    });

    test('searchTagsByName 无匹配返回空', () async {
      final results = await db.tagDao.searchTagsByName('不存在的标签');
      expect(results, isEmpty);
    });
  });

  group('TagDao 相册标签关联', () {
    setUp(() async {
      await insertAlbum('a1', '相册1');
      await insertAlbum('a2', '相册2');
      await insertTag('t1', '日系');
      await insertTag('t2', '户外');
    });

    test('addTagToAlbum + getTagsForAlbum', () async {
      await db.tagDao.addTagToAlbum('a1', 't1');
      await db.tagDao.addTagToAlbum('a1', 't2');

      final tags = await db.tagDao.getTagsForAlbum('a1');
      expect(tags.length, 2);
    });

    test('全局可复用：同一标签可关联多个相册', () async {
      await db.tagDao.addTagToAlbum('a1', 't1');
      await db.tagDao.addTagToAlbum('a2', 't1');

      expect((await db.tagDao.getTagsForAlbum('a1')).length, 1);
      expect((await db.tagDao.getTagsForAlbum('a2')).length, 1);
      // a2 也有"日系"
      expect(
        (await db.tagDao.getTagsForAlbum('a2')).any((t) => t.name == '日系'),
        isTrue,
      );
    });

    test('removeTagFromAlbum 移除单个关联', () async {
      await db.tagDao.addTagToAlbum('a1', 't1');
      await db.tagDao.addTagToAlbum('a1', 't2');
      await db.tagDao.removeTagFromAlbum('a1', 't1');

      final tags = await db.tagDao.getTagsForAlbum('a1');
      expect(tags.length, 1);
      expect(tags.first.id, 't2');
    });

    test('addTagToAlbum 幂等（insertOrIgnore）', () async {
      await db.tagDao.addTagToAlbum('a1', 't1');
      // 重复添加不报错
      await db.tagDao.addTagToAlbum('a1', 't1');

      final tags = await db.tagDao.getTagsForAlbum('a1');
      expect(tags.length, 1);
    });

    test('watchTagsForAlbum 流自动刷新', () async {
      final stream = db.tagDao.watchTagsForAlbum('a1');
      var firstEmission = await stream.first;
      expect(firstEmission, isEmpty);

      await db.tagDao.addTagToAlbum('a1', 't1');
      firstEmission = await stream.first;
      expect(firstEmission.length, 1);
    });

    test('removeTagsFromAlbum 清除相册所有关联', () async {
      await db.tagDao.addTagToAlbum('a1', 't1');
      await db.tagDao.addTagToAlbum('a1', 't2');
      await db.tagDao.removeTagsFromAlbum('a1');

      final tags = await db.tagDao.getTagsForAlbum('a1');
      expect(tags, isEmpty);
    });
  });

  group('TagDao 批量打标签', () {
    setUp(() async {
      await insertAlbum('a1', '相册1');
      await insertTag('t1', '精选');
      await insertTag('t2', '候选');
    });

    test('addTagsToAlbum 批量关联', () async {
      await db.tagDao.addTagsToAlbum('a1', ['t1', 't2']);
      expect((await db.tagDao.getTagsForAlbum('a1')).length, 2);
    });

    test('addTagsToAlbum 幂等（insertOrIgnore）', () async {
      await db.tagDao.addTagsToAlbum('a1', ['t1', 't2']);
      // 重复执行不报错
      await db.tagDao.addTagsToAlbum('a1', ['t1', 't2']);

      final tags = await db.tagDao.getTagsForAlbum('a1');
      expect(tags.length, 2);
    });
  });

  group('TagDao watchAllTags 流', () {
    test('插入后流自动推送', () async {
      final stream = db.tagDao.watchAllTags();
      expect((await stream.first), isEmpty);

      await insertTag('t1', '日系');
      final emission = await stream.first;
      expect(emission.length, 1);
    });
  });
}
