// clipping_provider.dart — Clipping 检测结果 Provider
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/clipping_service.dart';
import 'photo_provider.dart';

/// Clipping 检测结果 Provider（按照片 ID 缓存）
final clippingProvider =
    FutureProvider.family<ClippingResult, String>((ref, photoId) async {
  // watch photoByIdProvider 而非直连 DAO：与其它分析 provider 保持一致，
  // invalidating photoByIdProvider 会级联刷新（gotcha #24）。
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) throw Exception('Photo not found');
  return detectClipping(photo.filePath);
});
