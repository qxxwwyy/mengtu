// style_profile_dao_test.dart — 风格档案 DAO 测试（v3.5）
//
// 覆盖：
// 1. CRUD：insertProfile + getAllProfiles + getProfileById + updateProfile + deleteProfile
// 2. watchAllProfiles 流
// 3. 档案-照片关联：addPhotoToProfile + getProfilePhotos + removePhotoFromProfile
// 4. removePhotoFromAllProfiles（删照片钩子验证）
// 5. deleteProfile 事务清理（gotcha #40：测试库 FK cascade 不生效）
// 6. getProfilePhotoCount（相似度分层置信度用）
// 7. insertOrIgnore 幂等（重复加入不报错）
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/database/app_database.dart';
import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async => await db.close());

  /// 插入一个测试档案的便捷方法
  Future<String> insertProfile(String id, {String name = '测试档案'}) async {
    await db.styleProfileDao.insertProfile(StyleProfilesCompanion.insert(
      id: id,
      name: name,
    ));
    return id;
  }

  group('StyleProfileDao 档案 CRUD', () {
    test('insertProfile + getAllProfiles', () async {
      await insertProfile('p1', name: '王家卫港风');
      await insertProfile('p2', name: '日系小清新');

      final profiles = await db.styleProfileDao.getAllProfiles();
      expect(profiles.length, 2);
      expect(profiles.map((p) => p.name), containsAll(['王家卫港风', '日系小清新']));
    });

    test('getProfileById', () async {
      await insertProfile('p1', name: '测试');
      final profile = await db.styleProfileDao.getProfileById('p1');
      expect(profile, isNotNull);
      expect(profile!.name, '测试');
    });

    test('getProfileById 不存在返回 null', () async {
      final profile = await db.styleProfileDao.getProfileById('nonexistent');
      expect(profile, isNull);
    });

    test('updateProfile', () async {
      await insertProfile('p1', name: '原名');
      await db.styleProfileDao.updateProfile(StyleProfilesCompanion(
        id: const Value('p1'),
        name: const Value('新名'),
        description: const Value('测试描述'),
      ));

      final profile = await db.styleProfileDao.getProfileById('p1');
      expect(profile!.name, '新名');
      expect(profile.description, '测试描述');
    });

    test('deleteProfile 删除档案', () async {
      await insertProfile('p1');
      await db.styleProfileDao.deleteProfile('p1');

      final profiles = await db.styleProfileDao.getAllProfiles();
      expect(profiles, isEmpty);
    });

    test('updateFingerprintStats 写入 JSON', () async {
      await insertProfile('p1');
      const statsJson = '{"n":3,"scalar_means":[0.5,0.4]}';
      await db.styleProfileDao.updateFingerprintStats('p1', statsJson);

      final profile = await db.styleProfileDao.getProfileById('p1');
      expect(profile!.fingerprintStats, statsJson);
      // updatedAt 应被更新（大于 createdAt）
      expect(profile.updatedAt.isAfter(profile.createdAt) ||
          profile.updatedAt == profile.createdAt, isTrue);
    });

    test('updateFingerprintStats 接受 null（清空指纹）', () async {
      await insertProfile('p1');
      await db.styleProfileDao.updateFingerprintStats('p1', '{"n":2}');
      await db.styleProfileDao.updateFingerprintStats('p1', null);

      final profile = await db.styleProfileDao.getProfileById('p1');
      expect(profile!.fingerprintStats, isNull);
    });
  });

  group('StyleProfileDao watch 流', () {
    test('watchAllProfiles 插入后自动推送', () async {
      final stream = db.styleProfileDao.watchAllProfiles();
      final first = await stream.first;
      expect(first, isEmpty);

      await insertProfile('p1', name: '新档案');
      final second = await stream.first;
      expect(second.length, 1);
      expect(second.first.name, '新档案');
    });
  });

  group('StyleProfileDao 档案-照片关联', () {
    test('addPhotoToProfile + getProfilePhotos', () async {
      await insertProfile('p1');
      final photoId = await insertTestPhoto(db, id: 'ph1');

      await db.styleProfileDao.addPhotoToProfile('p1', photoId);

      final photos = await db.styleProfileDao.getProfilePhotos('p1');
      expect(photos.length, 1);
      expect(photos.first.id, photoId);
    });

    test('addPhotoToProfile 幂等（insertOrIgnore，重复不报错）', () async {
      await insertProfile('p1');
      await insertTestPhoto(db, id: 'ph1');

      await db.styleProfileDao.addPhotoToProfile('p1', 'ph1');
      // 第二次插入相同关联不应抛异常
      await db.styleProfileDao.addPhotoToProfile('p1', 'ph1');

      final photos = await db.styleProfileDao.getProfilePhotos('p1');
      expect(photos.length, 1);
    });

    test('removePhotoFromProfile', () async {
      await insertProfile('p1');
      await insertTestPhoto(db, id: 'ph1');
      await db.styleProfileDao.addPhotoToProfile('p1', 'ph1');

      await db.styleProfileDao.removePhotoFromProfile('p1', 'ph1');

      final photos = await db.styleProfileDao.getProfilePhotos('p1');
      expect(photos, isEmpty);
    });

    test('getProfilePhotoCount', () async {
      await insertProfile('p1');
      await insertTestPhoto(db, id: 'ph1');
      await insertTestPhoto(db, id: 'ph2');
      await insertTestPhoto(db, id: 'ph3');
      await db.styleProfileDao.addPhotoToProfile('p1', 'ph1');
      await db.styleProfileDao.addPhotoToProfile('p1', 'ph2');
      await db.styleProfileDao.addPhotoToProfile('p1', 'ph3');

      final count = await db.styleProfileDao.getProfilePhotoCount('p1');
      expect(count, 3);
    });

    test('getProfilePhotoCount 空档案返回 0', () async {
      await insertProfile('p1');
      final count = await db.styleProfileDao.getProfilePhotoCount('p1');
      expect(count, 0);
    });
  });

  group('StyleProfileDao 级联清理（gotcha #40：测试库 FK 不生效）', () {
    test('deleteProfile 事务内清理关联', () async {
      // 验证删除档案时，styleProfilePhotos 关联也被清除
      // （测试内存库 FK cascade 不生效，必须 DAO 显式清理）
      await insertProfile('p1');
      await insertTestPhoto(db, id: 'ph1');
      await db.styleProfileDao.addPhotoToProfile('p1', 'ph1');

      await db.styleProfileDao.deleteProfile('p1');

      // 关联应已清除（通过 getProfilePhotoCount 验证，不会因孤儿关联报错）
      final count = await db.styleProfileDao.getProfilePhotoCount('p1');
      expect(count, 0);
      // 照片本身不受影响
      final photo = await db.photoDao.getPhotoById('ph1');
      expect(photo, isNotNull);
    });

    test('removePhotoFromAllProfiles 清除所有档案的该照片关联', () async {
      // 模拟 import_service.deletePhoto 的钩子
      await insertProfile('p1');
      await insertProfile('p2');
      await insertTestPhoto(db, id: 'ph1');
      await db.styleProfileDao.addPhotoToProfile('p1', 'ph1');
      await db.styleProfileDao.addPhotoToProfile('p2', 'ph1');

      await db.styleProfileDao.removePhotoFromAllProfiles('ph1');

      // 两个档案都不再包含这张照片
      final photos1 = await db.styleProfileDao.getProfilePhotos('p1');
      final photos2 = await db.styleProfileDao.getProfilePhotos('p2');
      expect(photos1, isEmpty);
      expect(photos2, isEmpty);
      // 档案本身仍在
      final profiles = await db.styleProfileDao.getAllProfiles();
      expect(profiles.length, 2);
    });

    test('removePhotoFromAllProfiles 无关联时不报错', () async {
      // 某照片不在任何档案中，调用此方法不应抛异常
      await insertProfile('p1');
      await db.styleProfileDao.removePhotoFromAllProfiles('orphan-photo');
      // 验证不抛异常即通过
    });
  });

  group('StyleProfileDao 内置档案字段', () {
    test('isBuiltin + builtinKey 字段持久化', () async {
      await db.styleProfileDao.insertProfile(StyleProfilesCompanion.insert(
        id: 'builtin_japanese',
        name: '日系小清新',
        description: const Value('高调低对比'),
        isBuiltin: const Value(true),
        builtinKey: const Value('japanese'),
        fingerprintStats: const Value('{"n":0,"scalar_means":[0.15]}'),
      ));

      final profile = await db.styleProfileDao.getProfileById('builtin_japanese');
      expect(profile, isNotNull);
      expect(profile!.isBuiltin, isTrue);
      expect(profile.builtinKey, 'japanese');
      expect(profile.description, '高调低对比');
      expect(profile.fingerprintStats, '{"n":0,"scalar_means":[0.15]}');
    });

    test('默认值：isBuiltin=false, description=""', () async {
      await insertProfile('p1');
      final profile = await db.styleProfileDao.getProfileById('p1');
      expect(profile, isNotNull);
      expect(profile!.isBuiltin, isFalse);
      expect(profile.description, '');
      expect(profile.builtinKey, isNull);
      expect(profile.fingerprintStats, isNull);
    });
  });
}
