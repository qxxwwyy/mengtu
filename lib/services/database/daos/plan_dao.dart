// plan_dao.dart — 拍摄策划 DAO（v2.0）
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../app_database.dart';
import '../tables.dart';

part 'plan_dao.g.dart';

/// Shot list 条目
/// id 用于 UI 层 ValueKey 稳定标识，避免按 index 做 key 时
/// 删除中间项导致下方行的 TextEditingController 错位（光标漂移同源）。
@immutable
class ShotItem {
  final String id;
  final String desc;
  final bool done;
  const ShotItem({required this.id, required this.desc, this.done = false});

  /// 创建新条目的便捷构造（自动生成 id）
  factory ShotItem.create(String desc, {bool done = false}) =>
      ShotItem(id: shortHash(Object()), desc: desc, done: done);

  Map<String, dynamic> toJson() => {'id': id, 'desc': desc, 'done': done};
  factory ShotItem.fromJson(Map<String, dynamic> j) => ShotItem(
        // 兼容旧数据（无 id 字段）：用 desc 兜底，避免 null
        id: (j['id'] as String?) ?? j['desc'] as String? ?? '',
        desc: j['desc'] as String,
        done: j['done'] as bool? ?? false,
      );
}

/// 器材条目
@immutable
class GearItem {
  final String id;
  final String lens;
  final String note;
  const GearItem({required this.id, required this.lens, this.note = ''});

  /// 创建新条目的便捷构造（自动生成 id）
  factory GearItem.create(String lens, {String note = ''}) =>
      GearItem(id: shortHash(Object()), lens: lens, note: note);

  Map<String, dynamic> toJson() => {'id': id, 'lens': lens, 'note': note};
  factory GearItem.fromJson(Map<String, dynamic> j) => GearItem(
        id: (j['id'] as String?) ?? j['lens'] as String? ?? '',
        lens: j['lens'] as String,
        note: j['note'] as String? ?? '',
      );
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

  Future<void> deletePlan(String id) async {
    // 级联删除：先删 planPhotos 关联，再删 plan 本身
    // 外键已开启（PRAGMA foreign_keys=ON）且无 ON DELETE CASCADE，
    // 直接删 plan 会因 planPhotos 残留引用抛 FK 约束失败崩溃。
    await transaction(() async {
      await (delete(planPhotos)..where((t) => t.planId.equals(id))).go();
      await (delete(shootingPlans)..where((t) => t.id.equals(id))).go();
    });
  }

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

  /// 从所有策划中移除照片（删除照片时调用，避免 FK 约束失败）
  Future<int> removePhotoFromAllPlans(String photoId) =>
      (delete(planPhotos)..where((t) => t.photoId.equals(photoId))).go();

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
        GearItem(id: 'portrait-g1', lens: '85mm f/1.4', note: '主拍半身/特写'),
        GearItem(id: 'portrait-g2', lens: '35mm f/1.4', note: '环境人像'),
      ])),
      shotList: Value(encodeShotList(const [
        ShotItem(id: 'portrait-s1', desc: '全身环境人像'),
        ShotItem(id: 'portrait-s2', desc: '半身特写'),
        ShotItem(id: 'portrait-s3', desc: '面部特写'),
        ShotItem(id: 'portrait-s4', desc: '逆光剪影'),
        ShotItem(id: 'portrait-s5', desc: '背影/侧影'),
      ])),
    ));

    // 内置模板 2：街拍
    await insertTemplate(PlanTemplatesCompanion.insert(
      id: 'builtin-street',
      name: '街头摄影',
      gearList: Value(encodeGearList(const [
        GearItem(id: 'street-g1', lens: '35mm f/2', note: '挂机头'),
      ])),
      shotList: Value(encodeShotList(const [
        ShotItem(id: 'street-s1', desc: '建筑线条/几何'),
        ShotItem(id: 'street-s2', desc: '街头人物瞬间'),
        ShotItem(id: 'street-s3', desc: '光影对比'),
        ShotItem(id: 'street-s4', desc: '橱窗反射'),
      ])),
    ));

    // 内置模板 3：静物
    await insertTemplate(PlanTemplatesCompanion.insert(
      id: 'builtin-stilllife',
      name: '静物/产品',
      gearList: Value(encodeGearList(const [
        GearItem(id: 'still-g1', lens: '50mm f/2.8 微距', note: '细节'),
      ])),
      shotList: Value(encodeShotList(const [
        ShotItem(id: 'still-s1', desc: '整体场景'),
        ShotItem(id: 'still-s2', desc: '材质细节特写'),
        ShotItem(id: 'still-s3', desc: '45度俯拍'),
      ])),
    ));
  }
}
