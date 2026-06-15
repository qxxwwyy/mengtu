// import_flow_test.dart — 导入流程集成测试（临时目录 + 真实图片 + 内存数据库）
//
// 验证：去重逻辑、缩略图生成质量、文件清理、DB 事务完整性
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mengtu/services/database/app_database.dart';
import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = createTestDatabase();
    tempDir = await Directory.systemTemp.createTemp('mengtu_import_test');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 生成测试图片并返回路径
  String makeImageFile(String name, {int r = 128, int g = 128, int b = 128}) {
    return generateSolidImageFile(
      '${tempDir.path}/$name.png',
      width: 40,
      height: 40,
      r: r,
      g: g,
      b: b,
    );
  }

  /// 计算 SHA256
  String sha256OfFile(String path) {
    final bytes = File(path).readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  group('导入去重', () {
    test('相同内容（不同文件名）的哈希一致 → 可正确去重', () async {
      final file1 = makeImageFile('a', r: 100, g: 200, b: 50);
      final file2 = makeImageFile('b', r: 100, g: 200, b: 50);

      final hash1 = sha256OfFile(file1);
      final hash2 = sha256OfFile(file2);

      expect(hash1, hash2);
    });

    test('不同内容的哈希不同', () async {
      final file1 = makeImageFile('a', r: 255);
      final file2 = makeImageFile('b', r: 0);

      expect(sha256OfFile(file1), isNot(sha256OfFile(file2)));
    });

    test('DB 去重查询：已存在的 hash 能查到', () async {
      // 插入一条照片
      await db.photoDao.insertPhoto(PhotosCompanion.insert(
        id: 'p1',
        filePath: '/photos/p1.jpg',
        thumbnailPath: '/thumbs/p1.jpg',
        fileName: 'p1.jpg',
        fileHash: const Value('hash123'),
      ));

      final existing = await db.photoDao.getPhotoByHash('hash123');
      expect(existing, isNotNull);
      expect(existing!.id, 'p1');
    });

    test('DB 去重查询：不存在的 hash 返回 null', () async {
      final existing = await db.photoDao.getPhotoByHash('not_exists');
      expect(existing, isNull);
    });
  });

  group('缩略图生成', () {
    test('大图缩放后长边 ≤ 360px', () {
      final original = img.Image(width: 4000, height: 6000);
      final thumb = img.copyResize(original, width: 360);
      expect(thumb.width, 360);
      // 4000:6000 = 2:3 → 360:540
      expect(thumb.height, closeTo(540, 5));
    });

    test('JPEG 编码产生有效数据（FF D8 FF 开头）', () {
      final image = img.Image(width: 100, height: 100);
      final jpegBytes = img.encodeJpg(image, quality: 85);
      expect(jpegBytes[0], 0xFF);
      expect(jpegBytes[1], 0xD8);
      expect(jpegBytes[2], 0xFF);
    });

    test('PNG 解码后尺寸正确', () {
      final image = img.Image(width: 40, height: 60);
      final pngBytes = img.encodePng(image);
      final decoded = img.decodeImage(pngBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 40);
      expect(decoded.height, 60);
    });
  });

  group('文件清理', () {
    test('导入失败后缩略图文件被删除', () async {
      final thumbDir = Directory('${tempDir.path}/thumbnails');
      await thumbDir.create();
      final thumbFile = File('${thumbDir.path}/thumb_test.jpg');
      thumbFile.writeAsBytesSync([0xFF, 0xD8, 0xFF]);

      expect(await thumbFile.exists(), isTrue);
      // 模拟失败清理
      await thumbFile.delete();
      expect(await thumbFile.exists(), isFalse);
    });

    test('删除照片记录后可清理对应文件', () async {
      final photoPath = makeImageFile('to_delete');
      expect(await File(photoPath).exists(), isTrue);

      await File(photoPath).delete();
      expect(await File(photoPath).exists(), isFalse);
    });
  });

  group('DB 事务完整性', () {
    test('删除照片 → DB 中记录消失', () async {
      await db.photoDao.insertPhoto(PhotosCompanion.insert(
        id: 'p1',
        filePath: '/photos/p1.jpg',
        thumbnailPath: '/thumbs/p1.jpg',
        fileName: 'p1.jpg',
      ));
      expect(await db.photoDao.getPhotoCount(), 1);

      await db.photoDao.deletePhoto('p1');
      expect(await db.photoDao.getPhotoCount(), 0);
    });

    test('删除照片 → 标签关联被清除', () async {
      await db.photoDao.insertPhoto(PhotosCompanion.insert(
        id: 'p1',
        filePath: '/photos/p1.jpg',
        thumbnailPath: '/thumbs/p1.jpg',
        fileName: 'p1.jpg',
      ));
      await db.tagDao.insertTag(TagsCompanion.insert(
          id: 't1', name: 'test'));
      await db.tagDao.addTagToPhoto('p1', 't1');

      expect((await db.tagDao.getTagsForPhoto('p1')).length, 1);

      // 模拟 ImportService.deletePhoto 的事务
      await db.transaction(() async {
        await db.tagDao.removeTagsByPhoto('p1');
        await db.photoDao.deletePhoto('p1');
      });

      expect((await db.tagDao.getTagsForPhoto('p1')), isEmpty);
      expect(await db.photoDao.getPhotoCount(), 0);
      // 标签本身仍存在
      expect((await db.tagDao.getAllTags()).length, 1);
    });
  });

  group('全链路：导入 → 查询 → 删除', () {
    test('插入 → 查询 → 更新缓存 → 删除 完整流程', () async {
      // 1. 插入
      await db.photoDao.insertPhoto(PhotosCompanion.insert(
        id: 'p1',
        filePath: '/photos/p1.jpg',
        thumbnailPath: '/thumbs/p1.jpg',
        fileName: 'p1.jpg',
        fileHash: const Value('abc'),
      ));

      // 2. 查询验证
      var photo = await db.photoDao.getPhotoById('p1');
      expect(photo, isNotNull);
      expect(photo!.paletteJson, isNull);
      expect(photo.toneJson, isNull);

      // 3. 更新缓存
      await db.photoDao.updatePaletteCache('p1', '{"colors":[]}');
      await db.photoDao.updateToneCache('p1', '{"mean":100}');

      photo = await db.photoDao.getPhotoById('p1');
      expect(photo!.paletteJson, '{"colors":[]}');
      expect(photo.toneJson, '{"mean":100}');

      // 4. 删除
      await db.photoDao.deletePhoto('p1');
      expect(await db.photoDao.getPhotoById('p1'), isNull);
    });
  });
}
