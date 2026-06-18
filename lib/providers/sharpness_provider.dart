// sharpness_provider.dart — 锐度/合焦分析 Provider（v3.0 阶段二）
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sharpness_service.dart';
import 'photo_provider.dart';

/// 锐度地图 Provider（按 photoId 缓存）
///
/// 不写回 DB 缓存（与直方图/色卡不同）—— 峰值对焦是查看时按需计算，
/// 且 SharpnessMap 数据量较大（240×160 doubles），存 DB 不划算。
/// 首次开启"对焦"工具时计算，再次打开同一张图由 FutureProvider 自动复用。
final sharpnessProvider =
    FutureProvider.family<SharpnessMap, String>((ref, photoId) async {
  // watch photoByIdProvider 而非直连 DAO：与其它分析 provider 保持一致
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) throw Exception('Photo not found');
  return computeSharpness(photo.filePath);
});
