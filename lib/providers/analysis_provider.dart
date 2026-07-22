// analysis_provider.dart — 直方图/色卡/影调分析状态管理
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/histogram_service.dart';
import '../services/palette_service.dart';
import '../services/tone_service.dart';
import '../services/face_service.dart';
import '../services/image_scope_service.dart';
import '../services/scrfd_service.dart' show detectPrimaryFaceWithScrfd, FaceDetection;
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

  // 首次计算（优先使用缩略图以极速解析直方图，防止 48MP 大图 OOM，若缩略图文件不存在则退回原图）
  final useThumb = photo.thumbnailPath.isNotEmpty && File(photo.thumbnailPath).existsSync();
  final targetPath = useThumb ? photo.thumbnailPath : photo.filePath;
  final hist = await computeHistogram(targetPath);
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

  // 计算（优先使用缩略图以大幅提速并防止大图 OOM，若不存在退回原图）
  final useThumb = photo.thumbnailPath.isNotEmpty && File(photo.thumbnailPath).existsSync();
  final targetPath = useThumb ? photo.thumbnailPath : photo.filePath;
  final palette = await extractPalette(
    targetPath,
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

/// v7.0：modelPath/fullModelPath/meshModelPath providers 已移除
/// （BlazeFace/ML Kit/Face Mesh 全部替换为 SCRFD，scrfd_service 内部管理模型路径）。

/// v6.2：色彩手法卡片展开状态（会话级，按 photoId 作用域）
///
/// 详情页的人脸检测框（FaceBBoxOverlay）只在「色彩手法」卡片展开时显示，
/// 告诉用户肤色识别落在脸部哪个区域（gotcha #62）。卡片折叠/切照片时回退 null。
/// StageColorCard 在 onTap 时 set/clear；detail_page watch 本 provider 决定 bbox 可见性。
final colorCardExpandedProvider = NotifierProvider<ColorCardExpandedNotifier, String?>(
  ColorCardExpandedNotifier.new,
);

class ColorCardExpandedNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setExpanded(String photoId) => state = photoId;

  void setCollapsed(String photoId) {
    if (state == photoId) state = null;
  }
}

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

/// v6.1：主脸检测 bbox（归一化 0~1）—— 详情页可视化用
///
/// v7.0：用 SCRFD (NCNN) 检测主脸（主线程 FFI 同步调用），返回 bbox + 显示尺寸
/// 让用户直观看到「肤色识别落到脸部哪个区域」。无脸返回 null；
/// SCRFD init 失败（模型缺失/平台不支持）返回 null。
///
/// 此 provider 与 skinProvider 共享检测结果：skinProvider 复用本 provider 的 bbox
/// （避免重复检测）。
final detectedFaceProvider =
    FutureProvider.family<FaceDetection?, String>((ref, photoId) async {
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) return null;
  return detectPrimaryFaceWithScrfd(
    photo.filePath,
    thumbnailPath: photo.thumbnailPath,
    originalWidth: photo.width,
    originalHeight: photo.height,
  );
});

/// v3.0：人脸肤色分析（SCRFD bbox ROI 提取）
///
/// 独立于 [toneProvider]，避免阻塞直方图/影调 Tab 的快速渲染。
/// 无脸检测或模型加载失败时返回 [SkinAnalysis.empty]。
///
/// v3.1：手动校准优先 —— 若用户在取色点列表选中了某个 pin 作为肤色基准，
/// 直接用该点 RGB 算色相/饱和度（跳过人脸检测）。
///
/// v7.0：复用 [detectedFaceProvider]（SCRFD）的 bbox，在 bbox 内缩 20% 后
/// 采样像素统计 ΔH/饱和/SLS/SCS/skinLuminance/bgLuminance（face_service.Isolate）。
/// SCRFD 只给 5 点，无法计算 STI/FLC（已移除）。
///
/// 调用方：肤色示波器 + 主体手法卡片 + 洞察卡片，按 hasSkin 动态展示。
/// 注意：此 provider **不写回 toneJson 缓存**，因为肤色数据依赖
/// 用户是否打开了详情页（非全量预计算），缓存策略见 import_service。
final skinProvider =
    FutureProvider.family<SkinAnalysis, String>((ref, photoId) async {
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) throw Exception('Photo not found');

  // 优先使用更轻量的缩略图进行肤色统计，提速 100x 且无 OOM 风险
  final useThumb = photo.thumbnailPath.isNotEmpty && File(photo.thumbnailPath).existsSync();
  final targetPath = useThumb ? photo.thumbnailPath : photo.filePath;

  // v3.1：手动校准优先（watch 确保用户切换校准点时刷新）
  final manual = ref.watch(manualSkinSelectionProvider);
  if (manual != null && manual.photoId == photoId) {
    return analyzeSkinTone(
      targetPath,
      manualSkinRgb: manual.rgb,
    );
  }

  // v7.0：复用 SCRFD 预检测的 bbox（与 detectedFaceProvider 共享）
  final detection = await ref.watch(detectedFaceProvider(photoId).future);
  final primaryFace = detection?.rawFace; // Use unrotated rawFace for raw image pixel sampling

  return analyzeSkinTone(
    targetPath,
    primaryFace: primaryFace, // SCRFD bbox，null 时返回空 SkinAnalysis
  );
});

/// v7.2：全图像素色彩分布（Cb/Cr 平面，用于达芬奇 broadcast vectorscope）
///
/// 从缩略图对整张图做 Cb/Cr 2D binning（64×64），不过滤色相段。
/// 任何照片（含无脸照片）都有数据 → 修复 v7.1「像素云画不出来」bug：
/// 不再依赖 skinProvider 的 ROI 结果，示波器像素云始终来自全图采样。
/// skinRoi 模式额外叠加肤色光点（来自 skinProvider 的 chromaCb/Cr）。
///
/// 性能：Isolate 内 step=2 降采样，缩略图 ~60K 像素 → ~15K 次计算。
///
/// 缓存策略（评审 M3）：**当前无 SQLite 缓存**（区别于
/// histogramProvider/paletteProvider/toneProvider 都有 DB 缓存列）。Riverpod
/// family 缓存让同一 photoId 在同一 ProviderContainer 内不重算，但跨照片切换
/// 后回来会重跑 Isolate 采样。若未来成为性能热点，可仿 histogram 模式：
/// 把 bins 序列化成 Uint16List（clamp 65535，gotcha #18）存到 photo 表新列
/// `chroma_bins`（需 schemaVersion 升级 + 迁移）。当前 Isolate 已足够快，
/// 且示波器是详情页懒加载（非全量预计算），暂不缓存。
final imageScopeProvider =
    FutureProvider.family<List<int>, String>((ref, photoId) async {
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) throw Exception('Photo not found');

  final useThumb = photo.thumbnailPath.isNotEmpty && File(photo.thumbnailPath).existsSync();
  final targetPath = useThumb ? photo.thumbnailPath : photo.filePath;
  return sampleImageChroma(targetPath);
});

/// v7.1：示波器显示模式（肤色 ROI / 全图）
enum ScopeMode { skinRoi, fullImage }

/// v7.1：示波器模式切换状态（会话级，不持久化）
final scopeModeProvider =
    NotifierProvider<ScopeModeNotifier, ScopeMode>(ScopeModeNotifier.new);

class ScopeModeNotifier extends Notifier<ScopeMode> {
  @override
  ScopeMode build() => ScopeMode.skinRoi;

  void toggle() =>
      state = state == ScopeMode.skinRoi ? ScopeMode.fullImage : ScopeMode.skinRoi;
}

/// v3.5：聚合 advanced 指标（black_point/white_point/ten_tonal）
///
/// 数据源：直方图可算部分（black_point_offset/white_point_compression/ten_tonal_type）
///   — 由 [toneProvider] 已写入的 toneJson 缓存或现算
///
/// 重算策略（gotcha #39）：直方图部分缺字段 → 强制重算（纯函数，必有结果）。
/// v7.0：原 STI/FLC（Face Mesh 依赖）已移除（SCRFD 只给 5 点）。
///
/// 缓存：合并写入 toneJson 的 'advanced' 键（保留 ToneResult 扁平字段不变）。
final advancedMetricsProvider =
    FutureProvider.family<AdvancedPortraitMetrics?, String>(
        (ref, photoId) async {
  final db = ref.watch(appDatabaseProvider);
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  if (photo == null) return null;

  // gotcha #33 修正：上游 provider 必须无条件 watch，建立依赖边，
  // 让 invalidate 能级联（原实现 cache-hit 提前 return 跳过 watch，导致
  // 直方图/skin 变化时 advanced 不刷新）。
  final hist = await ref.watch(histogramProvider(photoId).future);
  final tone = await ref.watch(toneProvider(photoId).future);
  // skin 仍 watch（建立依赖边，但不 await，避免阻塞直方图/影调等纯直方图指标卡片的首屏快速渲染）
  ref.watch(skinProvider(photoId));

  // 复用 tone_service.computeAdvancedMetrics 纯函数（与
  // precomputeAnalysisForPhotos 共享同一份计算逻辑，gotcha #49）
  final metrics = computeAdvancedMetrics(
    lumHist: hist.lum,
    toneKey: tone.toneKey,
    toneRange: tone.toneRange,
  );

  // 回写缓存（合并到现有 toneJson 的 advanced 键，保留 ToneResult 扁平字段）
  final merged =
      AdvancedPortraitMetrics.mergeIntoToneJson(photo.toneJson, metrics);
  await db.photoDao.updateToneCache(photoId, merged);

  return metrics;
});
