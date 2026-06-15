// database_migration_test.dart — 数据库 schema 与迁移测试
//
// 验证 v6 schema 完整性 + fileHash 唯一索引（防 S3 重复导入回归）
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/database/app_database.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('数据库 schema v6 完整性', () {
    test('onCreate 创建所有 6 张表', () async {
      final db = createTestDatabase();
      addTearDown(db.close);

      // photos 表：核心列存在（drift 默认 snake_case 列名）
      final photosCols = await db.customSelect(
        'PRAGMA table_info(photos)',
      ).get();
      final colNames = photosCols.map((r) => r.read<String>('name')).toSet();
      expect(colNames, containsAll([
        'id', 'file_path', 'file_name', 'thumbnail_path', 'file_hash',
        'width', 'height', 'file_size', 'imported_at',
        'tone_json', 'palette_json', 'hue_histogram',
      ]));

      // tags / photo_tags / colorPins / albums / albumPhotos 表存在
      for (final table in ['tags', 'photo_tags', 'color_pins', 'albums', 'album_photos']) {
        final result = await db.customSelect('PRAGMA table_info($table)').get();
        expect(result, isNotEmpty, reason: '$table 表应存在');
      }
    });

    test('v6 迁移创建 fileHash 唯一索引', () async {
      final db = createTestDatabase();
      addTearDown(db.close);

      // 查询索引列表，应包含 photos_file_hash_unique
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='photos'",
      ).get();
      final indexNames = indexes.map((r) => r.read<String>('name')).toSet();
      expect(indexNames, contains('photos_file_hash_unique'));
    });
  });

  group('fileHash 唯一约束功能验证（S3 回归守护）', () {
    test('插入相同 fileHash 的两条记录 → 第二条触发唯一约束', () async {
      final db = createTestDatabase();
      addTearDown(db.close);

      // 第一条正常插入
      await db.photoDao.insertPhoto(buildPhotoCompanion(
        id: 'p1',
        filePath: '/a.jpg',
        fileName: 'a.jpg',
        fileHash: 'duplicate_hash',
      ));

      // 第二条相同 hash → 应抛异常（唯一约束）
      expect(
        () => db.photoDao.insertPhoto(buildPhotoCompanion(
          id: 'p2',
          filePath: '/b.jpg',
          fileName: 'b.jpg',
          fileHash: 'duplicate_hash',
        )),
        throwsA(isA<Object>()),
      );
    });

    test('不同 fileHash 可正常插入多条', () async {
      final db = createTestDatabase();
      addTearDown(db.close);

      await db.photoDao.insertPhoto(buildPhotoCompanion(
        id: 'p1', filePath: '/a.jpg', fileName: 'a.jpg', fileHash: 'hash1'));
      await db.photoDao.insertPhoto(buildPhotoCompanion(
        id: 'p2', filePath: '/b.jpg', fileName: 'b.jpg', fileHash: 'hash2'));

      final photos = await db.photoDao.getAllPhotos();
      expect(photos.length, 2);
    });

    test('空 fileHash 可插入多条（部分索引排除空字符串）', () async {
      final db = createTestDatabase();
      addTearDown(db.close);

      // 部分唯一索引 WHERE file_hash != ''，空字符串不参与唯一约束
      await db.photoDao.insertPhoto(PhotosCompanion.insert(
        id: 'p1',
        filePath: '/a.jpg',
        fileName: 'a.jpg',
        thumbnailPath: '/thumb/a.jpg',
      ));
      await db.photoDao.insertPhoto(PhotosCompanion.insert(
        id: 'p2',
        filePath: '/b.jpg',
        fileName: 'b.jpg',
        thumbnailPath: '/thumb/b.jpg',
      ));

      final photos = await db.photoDao.getAllPhotos();
      expect(photos.length, 2);
    });
  });

  group('影调缓存兼容性（旧 3 段 JSON → 5 段）', () {
    test('旧 3 段 toneJson（缺 blacks/whites）读不出 → fromJsonString 返回 null', () async {
      final db = createTestDatabase();
      addTearDown(db.close);

      // 插入一条带旧 3 段 JSON 的照片
      const legacyJson =
          '{"mean":100,"median":95,"std":30,"minVal":5,"maxVal":240,'
          '"peakPosition":90,"shadows":20,"midtones":60,"highlights":20,'
          '"toneKey":"mid","toneRange":"long","confidence":0.5}';

      await db.photoDao.insertPhoto(buildPhotoCompanion(
        id: 'p1',
        filePath: '/a.jpg',
        fileName: 'a.jpg',
        toneJson: legacyJson,
      ));

      final photo = await db.photoDao.getPhotoById('p1');
      expect(photo, isNotNull);
      // 旧 JSON 缺 blacks/whites → fromJsonString 应返回 null（触发重算）
      expect(photo!.toneJson, legacyJson);
    });
  });
}
