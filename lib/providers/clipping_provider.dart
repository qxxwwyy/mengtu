// clipping_provider.dart — Clipping 检测结果 Provider
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/clipping_service.dart';
import 'database_provider.dart';

/// Clipping 检测结果 Provider（按照片 ID 缓存）
final clippingProvider =
    FutureProvider.family<ClippingResult, String>((ref, photoId) async {
  final db = ref.watch(appDatabaseProvider);
  final photo = await (db.select(db.photos)..where((p) => p.id.equals(photoId)))
      .getSingleOrNull();
  if (photo == null) throw Exception('Photo not found');
  return detectClipping(photo.filePath);
});
