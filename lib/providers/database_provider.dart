// database_provider.dart — 提供 AppDatabase 和 ImportService 单例
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database/app_database.dart';
import '../services/import_service.dart';

/// 全局数据库实例
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// ImportService 实例（延迟初始化）
final importServiceProvider = FutureProvider<ImportService>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return ImportService.create(db);
});
