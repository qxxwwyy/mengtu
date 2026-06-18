// analysis_provider.dart — 直方图/色卡/影调分析状态管理
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/histogram_service.dart';
import '../services/palette_service.dart';
import '../services/tone_service.dart';
import '../services/face_service.dart';
import '../models/tone_result.dart';
import '../models/palette_result.dart';
import 'database_provider.dart';
import 'photo_provider.dart';

/// 直方图数据
final histogramProvider =
    FutureProvider.family<HistogramData, String>((ref, photoId) async {
  final db = ref.watch(appDatabaseProvider);
  // watch photoByIdProvider 而非直连 DAO：invalidating photoByIdProvider
  // 会级联刷新本 provider（gotcha #24）。否则 EXIF 重读后直方图仍显示旧缓存。
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) throw Exception('Photo not found');

  // 有缓存则读缓存（v1.0.0 新增 hue 独立存储）
  if (photo.rgbHistogram != null && photo.lumHistogram != null) {
    final rgb = photo.rgbHistogram!; // 1536 bytes (256×3×2)
    final lum = photo.lumHistogram!; // 512 bytes (256×2)
    final hue = photo.hueHistogram; // 720 bytes (360×2)，旧数据可能为 null
    // 合并为 fromBytes 期望的格式
    final combined = hue != null
        ? Uint8List.fromList([...rgb, ...lum, ...hue])
        : Uint8List.fromList([...rgb, ...lum]);
    return HistogramData.fromBytes(combined);
  }

  // 首次计算
  final hist = await computeHistogram(photo.filePath);
  // 缓存到数据库（Uint16List 格式，hue 独立列）
  final combined = hist.toBytes(); // 2768 bytes
  await db.photoDao.updateHistogramCache(
    photoId,
    rgbHistogram: Uint8List.fromList(combined.sublist(0, 1536)),
    lumHistogram: Uint8List.fromList(combined.sublist(1536, 2048)),
    hueHistogram: Uint8List.fromList(combined.sublist(2048, 2768)),
  );
  return hist;
});

/// 色卡参数（photoId + 算法 + 数量）
typedef PaletteParams = ({String photoId, PaletteAlgorithm algorithm, int desired});

/// 色卡数据（带 SQLite 缓存，仅默认算法+5色时缓存）
final paletteProvider =
    FutureProvider.family<PaletteResult, PaletteParams>((ref, params) async {
  final db = ref.watch(appDatabaseProvider);
  final photo = await ref.watch(photoByIdProvider(params.photoId).future);
  if (photo == null) throw Exception('Photo not found');

  // 仅默认参数（Celebi + 5色）使用 DB 缓存
  final isDefault =
      params.algorithm == PaletteAlgorithm.celebi && params.desired == 5;

  if (isDefault && photo.paletteJson != null && photo.paletteJson!.isNotEmpty) {
    final cached = PaletteResult.fromJsonString(photo.paletteJson);
    if (cached.colors.isNotEmpty) return cached;
  }

  // 计算
  final palette = await extractPalette(
    photo.filePath,
    desired: params.desired,
    algorithm: params.algorithm,
  );

  // 仅默认参数缓存
  if (isDefault) {
    await db.photoDao.updatePaletteCache(params.photoId, palette.toJsonString());
  }
  return palette;
});

/// 影调分析结果（复用直方图亮度数据，不重新读图）
/// tone_service 从 lum 直方图计算统计量，纯内存操作，极快
final toneProvider =
    FutureProvider.family<ToneResult, String>((ref, photoId) async {
  final db = ref.watch(appDatabaseProvider);
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) throw Exception('Photo not found');

  // 读缓存
  final cached = ToneResult.fromJsonString(photo.toneJson);
  if (cached != null) {
    // v3.0：旧缓存可能缺 skin 数据（来自 Phase 1 的 toneJson）。
    // skinProvider 独立异步补算，toneProvider 不阻塞 UI。
    return cached;
  }

  // 复用直方图亮度数据计算影调
  final hist = await ref.watch(histogramProvider(photoId).future);
  final tone = analyzeTone(hist.lum);
  await db.photoDao.updateToneCache(photoId, tone.toJsonString());
  return tone;
});

/// v3.0：已解压的 BlazeFace 模型文件路径
///
/// 在 app 启动或首次需要人脸检测时调用 [ensureModelExtracted]。
/// 返回 null 表示 asset 缺失 / 平台不支持 → skinProvider 降级。
final modelPathProvider = FutureProvider<String?>((ref) async {
  return ensureModelExtracted();
});

/// v3.0：人脸肤色分析（BlazeFace ROI 提取）
///
/// 独立于 [toneProvider]，避免阻塞直方图/影调 Tab 的快速渲染。
/// 无脸检测或模型加载失败时返回 [SkinAnalysis.empty]。
///
/// 调用方：[DetailBottomPanel] 的 ToneGuideCard，按 hasSkin 动态展示。
/// 注意：此 provider **不写回 toneJson 缓存**，因为肤色数据依赖
/// 用户是否打开了详情页（非全量预计算），缓存策略见 import_service。
final skinProvider =
    FutureProvider.family<SkinAnalysis, String>((ref, photoId) async {
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) throw Exception('Photo not found');
  final modelPath = await ref.watch(modelPathProvider.future);
  if (modelPath == null) return const SkinAnalysis();
  return analyzeSkinTone(photo.filePath, modelPath: modelPath);
});
