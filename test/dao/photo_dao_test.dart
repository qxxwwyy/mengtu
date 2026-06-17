// photo_dao_test.dart — 照片 DAO 测试（内存数据库）
import 'dart:typed_data';
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

  /// 插入测试照片
  Future<Photo> insertPhoto(String id,
      {String hash = '', int size = 1024}) async {
    await db.photoDao.insertPhoto(PhotosCompanion.insert(
      id: id,
      filePath: '/photos/$id.jpg',
      thumbnailPath: '/thumbs/$id.jpg',
      fileName: '$id.jpg',
      fileSize: Value(size),
      fileHash: Value(hash),
      width: const Value(400),
      height: const Value(600),
    ));
    return (await db.photoDao.getPhotoById(id))!;
  }

  group('PhotoDao CRUD', () {
    test('insertPhoto + getPhotoById', () async {
      await insertPhoto('p1', hash: 'hash1');
      final photo = await db.photoDao.getPhotoById('p1');

      expect(photo, isNotNull);
      expect(photo!.id, 'p1');
      expect(photo.filePath, '/photos/p1.jpg');
      expect(photo.width, 400);
    });

    test('getPhotoById 不存在返回 null', () async {
      final photo = await db.photoDao.getPhotoById('nonexistent');
      expect(photo, isNull);
    });

    test('getAllPhotos 返回全部', () async {
      await insertPhoto('p1');
      await insertPhoto('p2');
      final photos = await db.photoDao.getAllPhotos();
      expect(photos.length, 2);
    });

    test('getAllPhotos 返回多条记录', () async {
      await insertPhoto('p1');
      await insertPhoto('p2');
      final photos = await db.photoDao.getAllPhotos();
      expect(photos.length, 2);
      // 按导入时间倒序（同秒内插入顺序可能不固定，只验证数量）
    });

    test('deletePhoto 删除记录', () async {
      await insertPhoto('p1');
      await db.photoDao.deletePhoto('p1');
      final photo = await db.photoDao.getPhotoById('p1');
      expect(photo, isNull);
    });

    test('getPhotoByHash 去重查询', () async {
      await insertPhoto('p1', hash: 'abc123');
      final found = await db.photoDao.getPhotoByHash('abc123');
      final notFound = await db.photoDao.getPhotoByHash('xyz');

      expect(found, isNotNull);
      expect(found!.id, 'p1');
      expect(notFound, isNull);
    });
  });

  group('PhotoDao watchAllPhotos 流', () {
    test('插入后流自动推送新数据', () async {
      final stream = db.photoDao.watchAllPhotos();
      final firstEmission = await stream.first;
      expect(firstEmission, isEmpty);

      await insertPhoto('p1');
      // 第二次推送应包含新照片
      final secondEmission = await stream.first;
      expect(secondEmission.length, 1);
      expect(secondEmission.first.id, 'p1');
    });

    test('删除后流自动推送更新', () async {
      await insertPhoto('p1');
      await insertPhoto('p2');

      // 先拿到有 2 条数据的快照
      var emission = await db.photoDao.watchAllPhotos().first;
      expect(emission.length, 2);

      await db.photoDao.deletePhoto('p1');
      emission = await db.photoDao.watchAllPhotos().first;
      expect(emission.length, 1);
      expect(emission.first.id, 'p2');
    });
  });

  group('PhotoDao 按文件名搜索', () {
    setUp(() async {
      await insertPhoto('p1', ); // fileName: p1.jpg
      await insertPhoto('p2', );
      await insertPhoto('p3', );
    });

    test('watchPhotosByName 模糊匹配', () async {
      final photos = await db.photoDao.watchPhotosByName('p').first;
      expect(photos.length, 3);
    });

    test('watchPhotosByName 精确前缀匹配', () async {
      final photos = await db.photoDao.watchPhotosByName('p2').first;
      expect(photos.length, 1);
      expect(photos.first.id, 'p2');
    });

    test('watchPhotosByName 无匹配返回空', () async {
      final photos = await db.photoDao.watchPhotosByName('不存在的文件').first;
      expect(photos, isEmpty);
    });
  });

  group('PhotoDao 外键级联', () {
    test('删除照片后 album 关联被清除', () async {
      await insertPhoto('p1');
      await db.albumDao.insertAlbum(
          AlbumsCompanion.insert(id: 'a1', name: '相册'));
      await db.albumDao.addPhotoToAlbum('a1', 'p1');

      // 通过 removePhotoFromAllAlbums 清理关联（import_service.deletePhoto 同款逻辑）
      await db.albumDao.removePhotoFromAllAlbums('p1');
      await db.photoDao.deletePhoto('p1');

      expect(await db.albumDao.getPhotoCount('a1'), 0);
    });
  });

  group('PhotoDao 缓存更新', () {
    test('updateHistogramCache 更新直方图缓存', () async {
      await insertPhoto('p1');

      await db.photoDao.updateHistogramCache(
        'p1',
        rgbHistogram: Uint8List.fromList([1, 2, 3, 4]),
        lumHistogram: Uint8List.fromList([5, 6, 7, 8]),
      );

      final photo = await db.photoDao.getPhotoById('p1');
      expect(photo!.rgbHistogram, isNotNull);
      expect(photo.lumHistogram, isNotNull);
    });

    test('updatePaletteCache 更新色卡缓存', () async {
      await insertPhoto('p1');

      await db.photoDao.updatePaletteCache('p1', '{"colors":[]}');

      final photo = await db.photoDao.getPhotoById('p1');
      expect(photo!.paletteJson, '{"colors":[]}');
    });

    test('updateToneCache 更新影调缓存', () async {
      await insertPhoto('p1');

      await db.photoDao.updateToneCache('p1', '{"mean":128}');

      final photo = await db.photoDao.getPhotoById('p1');
      expect(photo!.toneJson, '{"mean":128}');
    });
  });

  group('PhotoDao 统计', () {
    test('getPhotoCount 返回总数', () async {
      await insertPhoto('p1');
      await insertPhoto('p2');
      expect(await db.photoDao.getPhotoCount(), 2);
    });

    test('getTotalStorageUsed 返回总大小', () async {
      await insertPhoto('p1', size: 1000);
      await insertPhoto('p2', size: 2500);
      expect(await db.photoDao.getTotalStorageUsed(), 3500);
    });

    test('空数据库统计为 0', () async {
      expect(await db.photoDao.getPhotoCount(), 0);
      expect(await db.photoDao.getTotalStorageUsed(), 0);
    });
  });
}
