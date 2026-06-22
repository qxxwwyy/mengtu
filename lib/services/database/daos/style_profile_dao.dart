// style_profile_dao.dart — 风格档案 DAO（v3.5）
//
// 用户自定义风格档案 + 内置理论档案的 CRUD，及档案-照片关联管理。
// FK 约束（cascade/setNull）在测试内存库（NativeDatabase.memory()）不生效
// （gotcha #40），本 DAO 自管级联：删档案/删照片时事务内显式清理关联，
// 不依赖 PRAGMA foreign_keys=ON。
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'style_profile_dao.g.dart';

/// 风格档案 DAO
@DriftAccessor(tables: [StyleProfiles, StyleProfilePhotos, Photos])
class StyleProfileDao extends DatabaseAccessor<AppDatabase>
    with _$StyleProfileDaoMixin {
  StyleProfileDao(super.db);

  // ============ 档案 CRUD ============

  /// 查询所有档案（按更新时间倒序）
  Future<List<StyleProfile>> getAllProfiles() =>
      (select(styleProfiles)
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  /// 监听所有档案变化（列表页 reactive）
  Stream<List<StyleProfile>> watchAllProfiles() =>
      (select(styleProfiles)
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch();

  /// 按 ID 查询档案
  Future<StyleProfile?> getProfileById(String id) =>
      (select(styleProfiles)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// 创建档案，返回档案 ID
  Future<String> insertProfile(StyleProfilesCompanion entry) async {
    await into(styleProfiles).insert(entry);
    return entry.id.value;
  }

  /// 更新档案基本信息（名称/描述等）
  Future<int> updateProfile(StyleProfilesCompanion entry) =>
      (update(styleProfiles)..where((t) => t.id.equals(entry.id.value)))
          .write(entry);

  /// 删除档案（事务内先清关联，再删档案）
  ///
  /// gotcha #40：测试内存库 FK cascade 不生效，必须显式清理。
  Future<int> deleteProfile(String id) {
    return transaction(() async {
      await (delete(styleProfilePhotos)
            ..where((t) => t.profileId.equals(id)))
          .go();
      return (delete(styleProfiles)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 更新档案指纹统计 JSON（添加/移除照片后由 FingerprintService 调用）
  Future<int> updateFingerprintStats(
          String id, String? fingerprintStatsJson) =>
      (update(styleProfiles)..where((t) => t.id.equals(id))).write(
          StyleProfilesCompanion(
              fingerprintStats: Value(fingerprintStatsJson),
              updatedAt: Value(DateTime.now())));

  // ============ 档案-照片关联 ============

  /// 添加照片到档案（insertOrIgnore 幂等：重复加入不报错）
  Future<void> addPhotoToProfile(String profileId, String photoId) =>
      into(styleProfilePhotos).insert(
        StyleProfilePhotosCompanion.insert(
            profileId: profileId, photoId: photoId),
        mode: InsertMode.insertOrIgnore,
      );

  /// 从档案移除单张照片
  Future<int> removePhotoFromProfile(String profileId, String photoId) =>
      (delete(styleProfilePhotos)
            ..where((t) =>
                t.profileId.equals(profileId) & t.photoId.equals(photoId)))
          .go();

  /// 从所有档案移除照片（删除照片时调用，gotcha #31）
  ///
  /// 由 [ImportService.deletePhoto] 事务内调用，避免 FK 约束失败。
  Future<int> removePhotoFromAllProfiles(String photoId) =>
      (delete(styleProfilePhotos)..where((t) => t.photoId.equals(photoId)))
          .go();

  // ============ 查询 ============

  /// 获取档案内所有照片（用于批量算指纹）
  ///
  /// 注意：photoId 列允许 NULL（FK setNull 后），过滤掉这些孤儿行。
  Future<List<Photo>> getProfilePhotos(String profileId) async {
    final query = select(styleProfilePhotos).join([
      innerJoin(photos, photos.id.equalsExp(styleProfilePhotos.photoId)),
    ])
      ..where(styleProfilePhotos.profileId.equals(profileId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(photos)).toList();
  }

  /// 获取档案内照片数（用于相似度分层置信度，N<5 只显示定性）
  Future<int> getProfilePhotoCount(String profileId) async {
    final count = styleProfilePhotos.profileId.count();
    final query = selectOnly(styleProfilePhotos)
      ..addColumns([count])
      ..where(styleProfilePhotos.profileId.equals(profileId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }
}
