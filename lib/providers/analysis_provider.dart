// analysis_provider.dart — 直方图/色卡/影调分析状态管理
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/histogram_service.dart';
import '../services/palette_service.dart';
import '../services/tone_service.dart';
import '../services/face_service.dart';
import '../models/tone_result.dart';
import '../models/palette_result.dart';
import '../models/advanced_portrait_metrics.dart';
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

/// v3.0：已解压的 BlazeFace short_range 模型文件路径
///
/// 在 app 启动或首次需要人脸检测时调用 [ensureModelsExtracted]。
/// 返回 null 表示 asset 缺失 / 平台不支持 → skinProvider 降级。
final modelPathProvider = FutureProvider<String?>((ref) async {
  return ensureModelsExtracted();
});

/// v3.1：full_range_sparse 模型文件路径（short 检测不到脸时的回退模型）
final fullModelPathProvider = FutureProvider<String?>((ref) async {
  return getFullModelPath();
});

/// v3.5：face_mesh 模型文件路径（STI/FLC 依赖）
///
/// 独立于 [modelPathProvider]（mesh 失败不应阻塞 BlazeFace 检测）。
/// 返回 null 表示 asset 缺失（face_mesh.tflite 未打包）→ STI/FLC 为 null，
/// 但 ΔH/饱和/SLS/SCS 仍由 BlazeFace ROI 产出。
final meshModelPathProvider = FutureProvider<String?>((ref) async {
  return ensureMeshModelExtracted();
});

/// v3.1：手动肤色校准选中状态（会话级，不持久化）
///
/// 用户在取色点列表点击「校准肤色」时，把该 pin 的 RGB 写入此 provider。
/// skinProvider 优先用手动结果，未选中时回退到 BlazeFace 自动检测。
/// 切换照片/退出详情页时由 UI 清空（传 null）。
final manualSkinSelectionProvider =
    NotifierProvider<ManualSkinSelectionNotifier, ({String photoId, List<double> rgb})?>(
  ManualSkinSelectionNotifier.new,
);

class ManualSkinSelectionNotifier
    extends Notifier<({String photoId, List<double> rgb})?> {
  @override
  ({String photoId, List<double> rgb})? build() => null;

  void select(String photoId, int r, int g, int b) =>
      state = (photoId: photoId, rgb: [r.toDouble(), g.toDouble(), b.toDouble()]);

  void clear() => state = null;
}

/// v3.0：人脸肤色分析（BlazeFace ROI 提取）
///
/// 独立于 [toneProvider]，避免阻塞直方图/影调 Tab 的快速渲染。
/// 无脸检测或模型加载失败时返回 [SkinAnalysis.empty]。
///
/// v3.1：手动校准优先 —— 若用户在取色点列表选中了某个 pin 作为肤色基准，
/// 直接用该点 RGB 算色相/饱和度（跳过人脸检测，即使 TFLite 不可用也工作）。
/// 未选中时回退到 short→full 双模型自动检测。
///
/// v3.5：三段式检测链 short→full→mesh。Face Mesh 命中时额外产出 STI/FLC
/// （叠加到 bbox ROI 的 ΔH/饱和/SLS/SCS 上）。mesh 失败/未配置 → STI/FLC null，
/// 其余指标照常返回。
///
/// 调用方：[DetailBottomPanel] 的 ToneGuideCard，按 hasSkin 动态展示。
/// 注意：此 provider **不写回 toneJson 缓存**，因为肤色数据依赖
/// 用户是否打开了详情页（非全量预计算），缓存策略见 import_service。
final skinProvider =
    FutureProvider.family<SkinAnalysis, String>((ref, photoId) async {
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) throw Exception('Photo not found');

  // v3.1：手动校准优先（watch 确保用户切换校准点时刷新）
  final manual = ref.watch(manualSkinSelectionProvider);
  if (manual != null && manual.photoId == photoId) {
    return analyzeSkinTone(
      photo.filePath,
      manualSkinRgb: manual.rgb,
    );
  }

  // 自动检测：short（主）→ full（回退）→ mesh（STI/FLC）
  final modelPath = await ref.watch(modelPathProvider.future);
  final fullModelPath = await ref.watch(fullModelPathProvider.future);
  final meshModelPath = await ref.watch(meshModelPathProvider.future);
  if (modelPath == null) return const SkinAnalysis();
  return analyzeSkinTone(
    photo.filePath,
    shortModelPath: modelPath,
    fullModelPath: fullModelPath,
    meshModelPath: meshModelPath, // v3.5：null 时降级（STI/FLC null）
  );
});

/// v3.5：聚合 advanced 指标（black_point/white_point/ten_tonal + STI/FLC）
///
/// 合并两个数据源：
/// 1. 直方图可算部分（black_point_offset/white_point_compression/ten_tonal_type）
///    — 由 [toneProvider] 已写入的 toneJson 缓存或现算
/// 2. Face Mesh 依赖部分（skin_sti/face_lighting_contrast）
///    — 由 [skinProvider] 产出，可能为 null（无脸/侧脸/mesh 失败）
///
/// 重算策略（gotcha #39）：
/// - 直方图部分缺字段 → 强制重算（纯函数，必有结果）
/// - STI/FLC 缺 → 容错（不触发重算，避免无脸照片陷入"无脸→空→重算→还是空"死循环）
///
/// 缓存：合并写入 toneJson 的 'advanced' 键（保留 ToneResult 扁平字段不变）。
final advancedMetricsProvider =
    FutureProvider.family<AdvancedPortraitMetrics?, String>(
        (ref, photoId) async {
  final db = ref.watch(appDatabaseProvider);
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) return null;

  // 1. 先尝试读缓存（完整 advanced 键）
  final cached = AdvancedPortraitMetrics.fromJsonString(photo.toneJson);
  if (cached != null) {
    // 缓存的直方图部分有效。但 STI/FLC 可能仍缺（旧缓存/无脸时写入）→ 尝试补算。
    if (cached.skinSti != null && cached.faceLightingContrast != null) {
      return cached; // 完整缓存，直接返回
    }
  }

  // 2. 现算直方图可算部分（强制必有结果）
  final hist = await ref.watch(histogramProvider(photoId).future);
  final tone = await ref.watch(toneProvider(photoId).future);
  final total = hist.lum.fold<int>(0, (a, b) => a + b);
  final blackPoint = calculateBlackPointOffset(hist.lum, total);
  final whitePoint = calculateWhitePointCompression(hist.lum, total);
  final tenTonal = classifyTenTonalType(tone.toneKey, tone.toneRange);

  // 3. 从 skinProvider 补 STI/FLC（可能为 null：无脸/侧脸/mesh 失败）
  final skin = await ref.watch(skinProvider(photoId).future);

  final metrics = AdvancedPortraitMetrics(
    skinSti: skin.sti,
    faceLightingContrast: skin.flc,
    blackPointOffset: blackPoint,
    whitePointCompression: whitePoint,
    tenTonalType: tenTonal,
  );

  // 4. 回写缓存（合并到现有 toneJson 的 advanced 键，保留 ToneResult 扁平字段）
  final merged =
      AdvancedPortraitMetrics.mergeIntoToneJson(photo.toneJson, metrics);
  await db.photoDao.updateToneCache(photoId, merged);

  return metrics;
});
