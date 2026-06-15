// plan_provider.dart — 拍摄策划状态管理（v2.0）
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database/app_database.dart';
import 'database_provider.dart';

/// 所有策划流（实时监听 DB 变化）
final allPlansProvider = StreamProvider<List<ShootingPlan>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.planDao.watchAllPlans();
});

/// 所有模板
final allTemplatesProvider = FutureProvider<List<PlanTemplate>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  await db.planDao.ensureBuiltinTemplates();
  return db.planDao.getAllTemplates();
});

/// 单个策划详情
final planByIdProvider =
    FutureProvider.family<ShootingPlan?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return db.planDao.getPlanById(id);
});

/// 策划的实拍照片流
final planResultPhotosProvider =
    FutureProvider.family<List<Photo>, String>((ref, planId) {
  final db = ref.watch(appDatabaseProvider);
  return db.planDao.getResultPhotos(planId);
});

/// 策划状态筛选
enum PlanStatusFilter { all, planning, shooting, completed, archived }

final planStatusFilterProvider =
    NotifierProvider<_PlanStatusFilterNotifier, PlanStatusFilter>(
        _PlanStatusFilterNotifier.new);

class _PlanStatusFilterNotifier extends Notifier<PlanStatusFilter> {
  @override
  PlanStatusFilter build() => PlanStatusFilter.all;

  void set(PlanStatusFilter f) => state = f;
}
