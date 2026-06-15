// photo_provider.dart — 照片列表状态管理
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database/app_database.dart';
import 'database_provider.dart';

/// 排序方式
enum SortOrder { newest, oldest }

/// 全部照片流（实时监听 DB 变化）
final allPhotosProvider = StreamProvider<List<Photo>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.photoDao.watchAllPhotos();
});

/// 单张照片
final photoByIdProvider = FutureProvider.family<Photo?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return db.photoDao.getPhotoById(id);
});

/// 搜索查询状态（带 200ms debounce，避免中文输入法连续上字时每键触发 JOIN LIKE 查询）
class SearchQueryNotifier extends Notifier<String?> {
  Timer? _debounce;

  @override
  String? build() {
    // 注册清理（Riverpod 3.x 的 Notifier 用 ref.onDispose 而非 dispose）
    ref.onDispose(() => _debounce?.cancel());
    return null;
  }

  void set(String? query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      state = query;
    });
  }
}

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String?>(SearchQueryNotifier.new);

/// 按标签搜索的照片流（自动刷新）
final photosByTagSearchProvider = StreamProvider.family<List<Photo>, String>(
    (ref, tagName) {
  final db = ref.watch(appDatabaseProvider);
  return db.photoDao.watchPhotosByTagName(tagName);
});

/// 排序状态
class SortOrderNotifier extends Notifier<SortOrder> {
  @override
  SortOrder build() => SortOrder.newest;

  void toggle() {
    state =
        state == SortOrder.newest ? SortOrder.oldest : SortOrder.newest;
  }
}

final sortOrderProvider =
    NotifierProvider<SortOrderNotifier, SortOrder>(SortOrderNotifier.new);
