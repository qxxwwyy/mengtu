// plan_dao.dart — 拍摄策划 DAO（v2.0）
import 'dart:convert';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'plan_dao.g.dart';

/// Shot list 条目
class ShotItem {
  final String desc;
  final bool done;
  const ShotItem({required this.desc, this.done = false});

  Map<String, dynamic> toJson() => {'desc': desc, 'done': done};
  factory ShotItem.fromJson(Map<String, dynamic> j) =>
      ShotItem(desc: j['desc'] as String, done: j['done'] as bool? ?? false);
}

/// 器材条目
class GearItem {
  final String lens;
  final String note;
  const GearItem({required this.lens, this.note = ''});

  Map<String, dynamic> toJson() => {'lens': lens, 'note': note};
  factory GearItem.fromJson(Map<String, dynamic> j) =>
      GearItem(lens: j['lens'] as String, note: j['note'] as String? ?? '');
}

@DriftAccessor(tables: [ShootingPlans, PlanPhotos, PlanTemplates, Photos])
class PlanDao extends DatabaseAccessor<AppDatabase> with _$PlanDaoMixin {
  PlanDao(super.db);

  // ============ 策划 CRUD ============

  Future<List<ShootingPlan>> getAllPlans() => select(shootingPlans).get();

  Stream<List<ShootingPlan>> watchAllPlans() =>
      (select(shootingPlans)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch();

  Future<ShootingPlan?> getPlanById(String id) =>
      (select(shootingPlans)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> insertPlan(ShootingPlansCompanion plan) async {
    final id = plan.id.value;
    await into(shootingPlans).insert(plan);
    return id;
  }

  Future<void> updatePlan(ShootingPlansCompanion plan) =>
      (update(shootingPlans)..where((t) => t.id.equals(plan.id.value)))
          .write(plan);

  Future<void> deletePlan(String id) =>
      (delete(shootingPlans)..where((t) => t.id.equals(id))).go();

  // ============ shot list / gear list 序列化辅助 ============

  List<ShotItem> parseShotList(String json) {
    final list = jsonDecode(json) as List;
    return list.map((e) => ShotItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  String encodeShotList(List<ShotItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  List<GearItem> parseGearList(String json) {
    final list = jsonDecode(json) as List;
    return list.map((e) => GearItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  String encodeGearList(List<GearItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  // ============ 策划-照片关联 ============

  /// 添加照片到策划（区分参考图/实拍图）
  Future<void> addPhotoToPlan(String planId, String photoId,
      {String role = 'result'}) async {
    await into(planPhotos).insert(PlanPhotosCompanion.insert(
      planId: planId,
      photoId: photoId,
      role: Value(role),
    ));
  }

  /// 移除策划中的照片
  Future<void> removePhotoFromPlan(String planId, String photoId) =>
      (delete(planPhotos)
            ..where((t) => t.planId.equals(planId) & t.photoId.equals(photoId)))
          .go();

  /// 获取策划的所有照片（含角色）
  Future<List<PlanPhoto>> getPlanPhotos(String planId) =>
      (select(planPhotos)..where((t) => t.planId.equals(planId))).get();

  /// 获取策划的参考图
  Future<List<String>> getReferencePhotoIds(String planId) async {
    final rows = await (select(planPhotos)
          ..where((t) => t.planId.equals(planId) & t.role.equals('reference')))
        .get();
    return rows.map((r) => r.photoId).toList();
  }

  /// 获取策划的实拍图（按加入顺序）
  Future<List<Photo>> getResultPhotos(String planId) async {
    final query = select(photos).join([
      innerJoin(planPhotos, planPhotos.photoId.equalsExp(photos.id)),
    ])
      ..where(planPhotos.planId.equals(planId) &
          planPhotos.role.equals('result'))
      ..orderBy([OrderingTerm(expression: planPhotos.sortOrder)]);
    final rows = await query.get();
    return rows.map((row) => row.readTable(photos)).toList();
  }

  /// 统计实拍图数量（用于 shot list 完成度展示）
  Future<int> getResultPhotoCount(String planId) async {
    final count = countAll();
    final query = selectOnly(planPhotos)
      ..addColumns([count])
      ..where(planPhotos.planId.equals(planId) &
          planPhotos.role.equals('result'));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  // ============ 模板 ============

  Future<List<PlanTemplate>> getAllTemplates() =>
      select(planTemplates).get();

  Future<String> insertTemplate(PlanTemplatesCompanion template) async {
    final id = template.id.value;
    await into(planTemplates).insert(template);
    return id;
  }

  Future<void> deleteTemplate(String id) =>
      (delete(planTemplates)..where((t) => t.id.equals(id))).go();

  /// 插入内置模板（首次启动时调用）
  Future<void> ensureBuiltinTemplates() async {
    final existing = await getAllTemplates();
    if (existing.isNotEmpty) return;

    // 内置模板 1：人像外拍
    await insertTemplate(PlanTemplatesCompanion.insert(
      id: 'builtin-portrait',
      name: '人像外拍',
      gearList: Value(encodeGearList(const [
        GearItem(lens: '85mm f/1.4', note: '主拍半身/特写'),
        GearItem(lens: '35mm f/1.4', note: '环境人像'),
      ])),
      shotList: Value(encodeShotList(const [
        ShotItem(desc: '全身环境人像'),
        ShotItem(desc: '半身特写'),
        ShotItem(desc: '面部特写'),
        ShotItem(desc: '逆光剪影'),
        ShotItem(desc: '背影/侧影'),
      ])),
    ));

    // 内置模板 2：街拍
    await insertTemplate(PlanTemplatesCompanion.insert(
      id: 'builtin-street',
      name: '街头摄影',
      gearList: Value(encodeGearList(const [
        GearItem(lens: '35mm f/2', note: '挂机头'),
      ])),
      shotList: Value(encodeShotList(const [
        ShotItem(desc: '建筑线条/几何'),
        ShotItem(desc: '街头人物瞬间'),
        ShotItem(desc: '光影对比'),
        ShotItem(desc: '橱窗反射'),
      ])),
    ));

    // 内置模板 3：静物
    await insertTemplate(PlanTemplatesCompanion.insert(
      id: 'builtin-stilllife',
      name: '静物/产品',
      gearList: Value(encodeGearList(const [
        GearItem(lens: '50mm f/2.8 微距', note: '细节'),
      ])),
      shotList: Value(encodeShotList(const [
        ShotItem(desc: '整体场景'),
        ShotItem(desc: '材质细节特写'),
        ShotItem(desc: '45度俯拍'),
      ])),
    ));
  }
}
