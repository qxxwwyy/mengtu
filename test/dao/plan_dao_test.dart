// plan_dao_test.dart — 拍摄策划 DAO 单元测试（v2.0）
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/database/app_database.dart';
import 'package:mengtu/services/database/daos/plan_dao.dart';
import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async => await db.close());

  group('PlanDao 策划 CRUD', () {
    test('insertPlan + getAllPlans', () async {
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
        id: 'plan1',
        title: '秋日公园',
      ));
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
        id: 'plan2',
        title: '街拍',
      ));

      final plans = await db.planDao.getAllPlans();
      expect(plans.length, 2);
      expect(plans.map((p) => p.title), containsAll(['秋日公园', '街拍']));
    });

    test('getPlanById', () async {
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
        id: 'plan1',
        title: '测试策划',
        style: const Value('日系'),
      ));

      final plan = await db.planDao.getPlanById('plan1');
      expect(plan, isNotNull);
      expect(plan!.title, '测试策划');
      expect(plan.style, '日系');
    });

    test('getPlanById 不存在返回 null', () async {
      final plan = await db.planDao.getPlanById('nonexistent');
      expect(plan, isNull);
    });

    test('updatePlan', () async {
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
        id: 'plan1',
        title: '原名',
      ));
      await db.planDao.updatePlan(ShootingPlansCompanion(
        id: const Value('plan1'),
        title: const Value('新名'),
        status: const Value('shooting'),
      ));

      final plan = await db.planDao.getPlanById('plan1');
      expect(plan!.title, '新名');
      expect(plan.status, 'shooting');
    });

    test('deletePlan', () async {
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
        id: 'plan1',
        title: '待删',
      ));
      await db.planDao.deletePlan('plan1');

      final plans = await db.planDao.getAllPlans();
      expect(plans, isEmpty);
    });
  });

  group('PlanDao shot list / gear 序列化', () {
    test('encodeShotList + parseShotList 往返', () {
      final items = [
        const ShotItem(desc: '全身', done: false),
        const ShotItem(desc: '特写', done: true),
      ];
      final json = db.planDao.encodeShotList(items);
      final restored = db.planDao.parseShotList(json);

      expect(restored.length, 2);
      expect(restored[0].desc, '全身');
      expect(restored[0].done, false);
      expect(restored[1].desc, '特写');
      expect(restored[1].done, true);
    });

    test('encodeGearList + parseGearList 往返', () {
      final items = [
        const GearItem(lens: '85mm', note: '主拍'),
        const GearItem(lens: '35mm'),
      ];
      final json = db.planDao.encodeGearList(items);
      final restored = db.planDao.parseGearList(json);

      expect(restored.length, 2);
      expect(restored[0].lens, '85mm');
      expect(restored[0].note, '主拍');
      expect(restored[1].lens, '35mm');
      expect(restored[1].note, '');
    });
  });

  group('PlanDao 策划-照片关联', () {
    test('addPhotoToPlan + getPlanPhotos', () async {
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
          id: 'p1', title: '策划'));
      final photoId = await insertTestPhoto(db, id: 'ph1');
      await db.planDao.addPhotoToPlan('p1', photoId, role: 'result');

      final planPhotos = await db.planDao.getPlanPhotos('p1');
      expect(planPhotos.length, 1);
      expect(planPhotos.first.role, 'result');
    });

    test('区分参考图和实拍图', () async {
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
          id: 'p1', title: '策划'));
      await insertTestPhoto(db, id: 'ref1');
      await insertTestPhoto(db, id: 'shot1');
      await db.planDao.addPhotoToPlan('p1', 'ref1', role: 'reference');
      await db.planDao.addPhotoToPlan('p1', 'shot1', role: 'result');

      final refs = await db.planDao.getReferencePhotoIds('p1');
      final results = await db.planDao.getResultPhotos('p1');

      expect(refs, ['ref1']);
      expect(results.length, 1);
      expect(results.first.id, 'shot1');
    });

    test('removePhotoFromPlan', () async {
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
          id: 'p1', title: '策划'));
      await insertTestPhoto(db, id: 'ph1');
      await db.planDao.addPhotoToPlan('p1', 'ph1');

      await db.planDao.removePhotoFromPlan('p1', 'ph1');

      final planPhotos = await db.planDao.getPlanPhotos('p1');
      expect(planPhotos, isEmpty);
    });

    test('getResultPhotoCount', () async {
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
          id: 'p1', title: '策划'));
      await insertTestPhoto(db, id: 'ph1');
      await insertTestPhoto(db, id: 'ph2');
      await db.planDao.addPhotoToPlan('p1', 'ph1');
      await db.planDao.addPhotoToPlan('p1', 'ph2');

      final count = await db.planDao.getResultPhotoCount('p1');
      expect(count, 2);
    });
  });

  group('PlanDao 模板', () {
    test('ensureBuiltinTemplates 插入内置模板', () async {
      await db.planDao.ensureBuiltinTemplates();
      final templates = await db.planDao.getAllTemplates();

      expect(templates.length, 3);
      expect(templates.map((t) => t.name),
          containsAll(['人像外拍', '街头摄影', '静物/产品']));
    });

    test('ensureBuiltinTemplates 幂等（不重复插入）', () async {
      await db.planDao.ensureBuiltinTemplates();
      await db.planDao.ensureBuiltinTemplates();
      final templates = await db.planDao.getAllTemplates();

      expect(templates.length, 3);
    });

    test('insertTemplate + deleteTemplate', () async {
      await db.planDao.insertTemplate(PlanTemplatesCompanion.insert(
        id: 'custom1',
        name: '自定义模板',
      ));
      var templates = await db.planDao.getAllTemplates();
      expect(templates.any((t) => t.id == 'custom1'), isTrue);

      await db.planDao.deleteTemplate('custom1');
      templates = await db.planDao.getAllTemplates();
      expect(templates.any((t) => t.id == 'custom1'), isFalse);
    });

    test('内置模板含预填 gear/shot list', () async {
      await db.planDao.ensureBuiltinTemplates();
      final templates = await db.planDao.getAllTemplates();
      final portrait =
          templates.firstWhere((t) => t.id == 'builtin-portrait');

      final gears = db.planDao.parseGearList(portrait.gearList);
      final shots = db.planDao.parseShotList(portrait.shotList);

      expect(gears.length, 2);
      expect(shots.length, 5);
      expect(gears.first.lens, '85mm f/1.4');
    });
  });

  group('PlanDao watch 流', () {
    test('watchAllPlans 插入后自动推送', () async {
      final stream = db.planDao.watchAllPlans();
      final first = await stream.first;
      expect(first, isEmpty);

      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
          id: 'p1', title: '新策划'));
      final second = await stream.first;
      expect(second.length, 1);
    });
  });
}
