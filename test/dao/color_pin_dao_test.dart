// color_pin_dao_test.dart — 取色点 DAO 单元测试
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/database/app_database.dart';
import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async => await db.close());

  group('ColorPinDao CRUD', () {
    test('insertPin + getPinsForPhoto', () async {
      final photoId = await insertTestPhoto(db);
      await db.colorPinDao.insertPin(ColorPinsCompanion.insert(
        id: 'pin1',
        photoId: photoId,
        x: 100,
        y: 200,
        r: 255,
        g: 0,
        b: 0,
      ));

      final pins = await db.colorPinDao.getPinsByPhotoId(photoId);
      expect(pins.length, 1);
      expect(pins.first.r, 255);
      expect(pins.first.x, 100);
    });

    test('getPinsForPhoto 不存在的照片返回空', () async {
      final pins = await db.colorPinDao.getPinsByPhotoId('nonexistent');
      expect(pins, isEmpty);
    });

    test('deletePin 删除单个取色点', () async {
      final photoId = await insertTestPhoto(db);
      await db.colorPinDao.insertPin(ColorPinsCompanion.insert(
        id: 'pin1',
        photoId: photoId,
        x: 0,
        y: 0,
        r: 0,
        g: 0,
        b: 0,
      ));

      await db.colorPinDao.deletePin('pin1');

      final pins = await db.colorPinDao.getPinsByPhotoId(photoId);
      expect(pins, isEmpty);
    });

    test('deletePinsForPhoto 批量删除照片所有取色点', () async {
      final photoId = await insertTestPhoto(db);
      await db.colorPinDao.insertPin(
          ColorPinsCompanion.insert(id: 'p1', photoId: photoId, x: 1, y: 1, r: 0, g: 0, b: 0));
      await db.colorPinDao.insertPin(
          ColorPinsCompanion.insert(id: 'p2', photoId: photoId, x: 2, y: 2, r: 0, g: 0, b: 0));
      await db.colorPinDao.insertPin(
          ColorPinsCompanion.insert(id: 'p3', photoId: photoId, x: 3, y: 3, r: 0, g: 0, b: 0));

      await db.colorPinDao.deletePinsByPhotoId(photoId);

      final pins = await db.colorPinDao.getPinsByPhotoId(photoId);
      expect(pins, isEmpty);
    });

    test('多张照片的取色点互不影响', () async {
      final photoId1 = await insertTestPhoto(db, id: 'ph1', fileHash: 'hash_ph1');
      final photoId2 = await insertTestPhoto(db, id: 'ph2', fileHash: 'hash_ph2');
      await db.colorPinDao.insertPin(
          ColorPinsCompanion.insert(id: 'p1', photoId: photoId1, x: 1, y: 1, r: 0, g: 0, b: 0));
      await db.colorPinDao.insertPin(
          ColorPinsCompanion.insert(id: 'p2', photoId: photoId2, x: 2, y: 2, r: 0, g: 0, b: 0));

      final pins1 = await db.colorPinDao.getPinsByPhotoId(photoId1);
      final pins2 = await db.colorPinDao.getPinsByPhotoId(photoId2);

      expect(pins1.length, 1);
      expect(pins2.length, 1);
    });
  });

  group('ColorPinDao watch 流', () {
    test('watchPinsForPhoto 插入后自动推送', () async {
      final photoId = await insertTestPhoto(db);
      final stream = db.colorPinDao.watchPinsByPhotoId(photoId);

      expect(stream, emitsInOrder([
        isEmpty, // 初始空
        hasLength(1), // 插入后 1 个
      ]));

      await pumpEventQueue();
      await db.colorPinDao.insertPin(
          ColorPinsCompanion.insert(id: 'p1', photoId: photoId, x: 0, y: 0, r: 0, g: 0, b: 0));
    });
  });
}
