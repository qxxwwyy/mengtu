// builtin_profiles_test.dart — 内置理论档案测试（v3.5 PR5）
//
// 覆盖 spec §5.4 测试列表：
// 1. ensureSeeded：首次调用插入 4 个档案
// 2. ensureSeeded：二次调用不重复插入（幂等）
// 3. isRefined=true 的档案有 replicationTemplate
// 4. isRefined=false 的档案 replicationTemplate 为空
// 5. 4 个档案的 key/name/fingerprintStats 完整
// 6. getByKey 查询
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/builtin_profiles.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('BuiltinProfiles 数据完整性', () {
    test('4 个内置档案', () {
      expect(BuiltinProfiles.profiles.length, 4);
      final keys = BuiltinProfiles.profiles.map((p) => p.key).toSet();
      expect(keys, {'japanese', 'hongkong', 'cinematic', 'chinoiserie'});
    });

    test('每个档案有 name + description + fingerprintStats', () {
      for (final p in BuiltinProfiles.profiles) {
        expect(p.name, isNotEmpty);
        expect(p.description, isNotEmpty);
        expect(p.fingerprintStats['scalar_means'], isNotNull);
        expect(p.fingerprintStats['scalar_stds'], isNotNull);
        expect(p.fingerprintStats['n'], 0); // 理论档案 n=0
      }
    });

    test('scalar_means/scalar_stds 各 7 维', () {
      for (final p in BuiltinProfiles.profiles) {
        final means = (p.fingerprintStats['scalar_means'] as List);
        final stds = (p.fingerprintStats['scalar_stds'] as List);
        expect(means.length, 7);
        expect(stds.length, 7);
      }
    });

    test('isRefined=true 的档案有 replicationTemplates', () {
      final refined =
          BuiltinProfiles.profiles.where((p) => p.isRefined).toList();
      expect(refined.length, 2); // 日系 + 港风
      for (final p in refined) {
        expect(p.replicationTemplates, isNotEmpty,
            reason: '${p.name} isRefined 但无 replicationTemplates');
      }
    });

    test('isRefined=false 的档案 replicationTemplates 为空', () {
      final notRefined =
          BuiltinProfiles.profiles.where((p) => !p.isRefined).toList();
      expect(notRefined.length, 2); // 青橙 + 中式
      for (final p in notRefined) {
        expect(p.replicationTemplates, isEmpty,
            reason: '${p.name} 未做精但已有 replicationTemplates');
      }
    });

    test('日系/港风的复刻模板至少 4 条参数', () {
      final japanese = BuiltinProfiles.getByKey('japanese')!;
      final hongkong = BuiltinProfiles.getByKey('hongkong')!;
      expect(japanese.replicationTemplates.length, greaterThanOrEqualTo(4));
      expect(hongkong.replicationTemplates.length, greaterThanOrEqualTo(4));
    });
  });

  group('getByKey 查询', () {
    test('已知 key 返回档案数据', () {
      final japanese = BuiltinProfiles.getByKey('japanese');
      expect(japanese, isNotNull);
      expect(japanese!.name, '日系小清新');
    });

    test('未知 key 返回 null', () {
      expect(BuiltinProfiles.getByKey('unknown'), isNull);
    });

    test('null key 返回 null', () {
      expect(BuiltinProfiles.getByKey(null), isNull);
    });
  });

  group('ensureSeeded 持久化（幂等）', () {
    test('首次调用插入 4 个档案', () async {
      final db = createTestDatabase();
      await BuiltinProfiles.ensureSeeded(db);

      final profiles = await db.styleProfileDao.getAllProfiles();
      expect(profiles.length, 4);
      final ids = profiles.map((p) => p.id).toSet();
      expect(ids, {
        'builtin_japanese',
        'builtin_hongkong',
        'builtin_cinematic',
        'builtin_chinoiserie',
      });
    });

    test('二次调用不重复插入（幂等）', () async {
      final db = createTestDatabase();
      await BuiltinProfiles.ensureSeeded(db);
      await BuiltinProfiles.ensureSeeded(db); // 再次调用

      final profiles = await db.styleProfileDao.getAllProfiles();
      expect(profiles.length, 4, reason: '幂等：不应重复插入');
    });

    test('插入的档案 isBuiltin=true + builtinKey 正确', () async {
      final db = createTestDatabase();
      await BuiltinProfiles.ensureSeeded(db);

      final profiles = await db.styleProfileDao.getAllProfiles();
      for (final p in profiles) {
        expect(p.isBuiltin, isTrue);
        expect(p.builtinKey, isNotNull);
        expect(p.fingerprintStats, isNotNull);
      }
    });
  });
}
