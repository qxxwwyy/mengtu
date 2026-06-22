// style_profile_provider.dart — 风格档案状态管理（v3.5 PR4）
//
// Provider 层连接 StyleProfileDao + FingerprintService + ImportService。
// 提供档案列表流、指纹服务单例、照片匹配结果。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/photo_fingerprint.dart';
import '../models/style_profile_match.dart';
import '../services/database/app_database.dart';
import '../services/fingerprint_service.dart';
import 'database_provider.dart';

/// 所有风格档案流（用户自定义 + 内置理论，reactive）
final styleProfilesProvider =
    StreamProvider<List<StyleProfile>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.styleProfileDao.watchAllProfiles();
});

/// FingerprintService 单例
final fingerprintServiceProvider = Provider<FingerprintService>((ref) {
  return FingerprintService(ref.watch(appDatabaseProvider));
});

/// 照片指纹（缓存到会话，不写 DB —— 指纹是派生数据）
///
/// 依赖 DB 缓存的直方图 + toneJson，未预计算的照片在详情页打开后才有数据。
/// 创建档案时由 [ImportService.precomputeAnalysisForPhotos] 主动触发预计算。
final photoFingerprintProvider =
    FutureProvider.family<PhotoFingerprint, String>((ref, photoId) async {
  final svc = ref.watch(fingerprintServiceProvider);
  return svc.computeFingerprint(photoId);
});

/// 照片 vs 所有档案的匹配结果（按相似度降序）
///
/// 调用方：StageArchiveMatchCard（阶④卡片）。
/// 跳过未计算指纹统计的档案（fingerprintStats 为空）。
final styleProfileMatchProvider =
    FutureProvider.family<List<StyleProfileMatch>, String>(
        (ref, photoId) async {
  final svc = ref.watch(fingerprintServiceProvider);
  final fp = await ref.watch(photoFingerprintProvider(photoId).future);
  final profiles = await ref.watch(styleProfilesProvider.future);
  final db = ref.watch(appDatabaseProvider);

  final matches = <StyleProfileMatch>[];
  for (final profile in profiles) {
    if (profile.fingerprintStats == null ||
        profile.fingerprintStats!.isEmpty) {
      continue;
    }
    final sim = await svc.computeSimilarity(fp, profile.id);
    final count =
        await db.styleProfileDao.getProfilePhotoCount(profile.id);
    matches.add(StyleProfileMatch(
      profileId: profile.id,
      profileName: profile.name,
      similarity: sim,
      sampleCount: count,
      isBuiltin: profile.isBuiltin,
      builtinKey: profile.builtinKey,
      currentFingerprint: fp,
    ));
  }
  matches.sort((a, b) => b.similarity.compareTo(a.similarity));
  return matches;
});
