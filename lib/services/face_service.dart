// face_service.dart — 离线人脸检测 + 肤色 ROI 提取服务（v3.0 阶段二）
//
// 基于 MediaPipe BlazeFace TFLite 模型，在导入照片时一次性运行人脸检测，
// 提取主脸 ROI（按面积最大，过滤置信度<0.5 的杂点），在 ROI 内统计肤色 HSL
// 指标，与 [ToneService] 协同生成完整 SkinAnalysis。
//
// 性能策略：
// - 整个检测+ROI 统计在 Isolate 内执行（compute），不阻塞 UI
// - 模型加载用 lazy singleton（首次调用时 Interpreter.fromFile）
// - ROI 内缩 20%（避开头发/耳朵/背景边缘）
//
// 降级设计：
// - 模型加载失败（如平台不支持）→ 返回 null → ToneResult.skin 为空
// - 未检测到脸 → 返回 null → UI 提示"开启取色工具长按皮肤手动校准"
// - 多脸合影 → 按 BBox 面积降序取最大者作为主脸 ROI
//
// v3.1 重要修复：
// - 原 _buildAnchors 只生成 640 个 anchor（与 896 输出张量不匹配 → RangeError
//   被吞 → 永远检测不到脸）。现按 MediaPipe SsdAnchorsCalculator 正确生成 896 个。
// - 原 regressor 解码公式错误（exp(r[2])/size），改为标准 BlazeFace 解码。
// - 双模型自动回退：short_range（自拍近距）检测不到脸时回退到 full_range（远距全身）。
//
// BlazeFace 输出说明（896 anchors，4 个 stride 层 [8,16,16,16] × 每 cell 2 anchor）：
// - regressor[0..3]: 相对 anchor 的 [dx, dy, w, h]（归一化偏移）
// - classifier[0]: 人脸置信度（sigmoid 后概率）
// 后处理：NMS（非极大值抑制）+ 阈值过滤
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/tone_result.dart';
import 'tone_service.dart';

/// 检测到的人脸（归一化坐标 0~1）
class DetectedFace {
  /// 边界框（归一化 0~1，相对原图）
  final double left, top, right, bottom;

  /// 置信度（0~1）
  final double confidence;

  const DetectedFace({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
  });

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;
}

/// 肤色分析参数（Isolate 间传递，需可序列化）
class _FaceAnalysisArgs {
  final String imagePath;
  final String shortModelPath; // short_range 模型文件路径（已解压）
  final String fullModelPath; // full_range_sparse 模型文件路径（已解压）
  final bool isP3ColorSpace; // 是否需要 Display P3 → sRGB 补偿
  final List<double>? manualSkinRgb; // 手动覆盖：取色点 RGB [r,g,b] 0-255

  const _FaceAnalysisArgs(
    this.imagePath,
    this.shortModelPath,
    this.fullModelPath,
    this.isP3ColorSpace,
    this.manualSkinRgb,
  );
}

/// 模型固定输入尺寸（BlazeFace 短/全距均为 128×128）
const _modelInputSize = 128;

/// 置信度阈值（过滤背景噪声）
const _minConfidence = 0.5;

/// NMS IoU 阈值
const _nmsIouThreshold = 0.3;

/// 检测上限（避免合影场景跑太多 BBox）
const _maxDetections = 10;

/// 模型输出 anchor 数（必须与模型输出张量第二维一致）
const _numAnchors = 896;

/// 模型 asset keys
const _kShortModelAssetKey =
    'assets/models/face_detection_short_range.tflite';
const _kFullModelAssetKey =
    'assets/models/face_detection_full_range_sparse.tflite';

/// 检测照片中的主脸，提取肤色 ROI 统计指标。
///
/// [imagePath] 照片绝对路径；[shortModelPath]/[fullModelPath] 为已解压到临时目录
/// 的 .tflite 路径（由 [ensureModelsExtracted] 提供，Isolate 无法读 asset，必须先解压）。
/// short_range 检测不到脸时自动回退到 full_range（v3.1）。
/// [isP3ColorSpace] 为 true 时对像素做 P3→sRGB 补偿。
///
/// **手动覆盖模式**：当 [manualSkinRgb] 非空时，跳过人脸检测，直接用该 RGB
/// （取色点）计算色相偏差和饱和度，作为 BlazeFace 失败时的备用通路。
Future<SkinAnalysis> analyzeSkinTone(
  String imagePath, {
  String? shortModelPath,
  String? fullModelPath,
  bool isP3ColorSpace = false,
  List<double>? manualSkinRgb,
}) async {
  return compute(
    _analyzeSkinIsolate,
    _FaceAnalysisArgs(
      imagePath,
      shortModelPath ?? '',
      fullModelPath ?? '',
      isP3ColorSpace,
      manualSkinRgb,
    ),
  );
}

/// Isolate 入口
Future<SkinAnalysis> _analyzeSkinIsolate(_FaceAnalysisArgs args) async {
  final bytes = File(args.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return const SkinAnalysis();
  }

  // 手动覆盖模式：跳过人脸检测，直接从给定 RGB 算色相/饱和度
  if (args.manualSkinRgb != null && args.manualSkinRgb!.length >= 3) {
    final r = args.manualSkinRgb![0].round().clamp(0, 255);
    final g = args.manualSkinRgb![1].round().clamp(0, 255);
    final b = args.manualSkinRgb![2].round().clamp(0, 255);
    return _computeManualSkinStats(decoded, r, g, b, args.isP3ColorSpace);
  }

  // 自动模式：BlazeFace 检测人脸 ROI（v3.1: short → full 自动回退）
  DetectedFace? face;
  if (args.shortModelPath.isNotEmpty) {
    face = await _detectPrimaryFace(decoded, args.shortModelPath);
  }
  // short 未命中 → 用 full_range 再试（远处/全身/小脸场景召回更好）
  if (face == null && args.fullModelPath.isNotEmpty) {
    face = await _detectPrimaryFace(decoded, args.fullModelPath);
  }
  if (face == null) {
    return const SkinAnalysis(); // 无脸 → 空结果，UI 提示手动校准
  }

  return _analyzeRoiSkin(decoded, face, args.isP3ColorSpace);
}

/// 在主脸 ROI 内统计肤色 HSL 指标 + 计算 SLS / SCS 隔离度
SkinAnalysis _analyzeRoiSkin(
    img.Image image, DetectedFace face, bool isP3) {
  final imgW = image.width;
  final imgH = image.height;

  // 归一化 → 像素坐标
  var xMin = (face.left * imgW).round().clamp(0, imgW - 1);
  var yMin = (face.top * imgH).round().clamp(0, imgH - 1);
  var xMax = (face.right * imgW).round().clamp(0, imgW - 1);
  var yMax = (face.bottom * imgH).round().clamp(0, imgH - 1);

  // ROI 内缩 20%（避开发际线、耳朵、下巴背景边缘）
  final padX = ((xMax - xMin) * 0.1).round();
  final padY = ((yMax - yMin) * 0.1).round();
  xMin += padX;
  xMax -= padX;
  yMin += padY;
  yMax -= padY;

  // 1) 肤色 ROI 内 HSL 累加（带色相过滤，防杂光污染）
  double sumHue = 0;
  double sumSat = 0;
  double sumLum = 0;
  int count = 0;

  const step = 2;
  for (var y = yMin; y <= yMax; y += step) {
    for (var x = xMin; x <= xMax; x += step) {
      var r = image.getPixel(x, y).r.toInt();
      var g = image.getPixel(x, y).g.toInt();
      var b = image.getPixel(x, y).b.toInt();
      if (isP3) {
        final srgb = convertP3ToSrgb(r, g, b);
        r = srgb[0];
        g = srgb[1];
        b = srgb[2];
      }
      final hsl = _rgbToHsl(r, g, b);
      final h = hsl[0];
      final s = hsl[1];
      final l = hsl[2];
      // 肤色色相段：0~45° 或 320~360°（暖橙到红）
      if ((h <= 45 || h >= 320) && s >= 0.1 && s <= 0.8) {
        sumHue += (h >= 320) ? (h - 360) : h;
        sumSat += s;
        sumLum += l;
        count++;
      }
    }
  }

  if (count == 0) return const SkinAnalysis();

  double avgHue = sumHue / count;
  if (avgHue < 0) avgHue += 360;
  final avgSat = sumSat / count * 100;
  final avgLum = sumLum / count * 100;

  // 2) 背景区域：全图排除 ROI 的平均 HSL（用于 SLS / SCS 隔离度）
  final bgStats = _computeBgStats(image, xMin, yMin, xMax, yMax, isP3, step);

  // SLS = 肤色 L − 背景 L（百分比）
  final sls = avgLum - bgStats.avgLum;

  // SCS = 肤色色相（avgHue）与背景主导色相的环形最短距离
  final scs = _hueRingDistance(avgHue, bgStats.dominantHue);

  return SkinAnalysis(
    hueOffset: skinHueOffset(avgHue),
    saturation: avgSat,
    luminanceSeparation: sls,
    colorSeparation: scs,
    skinLuminance: avgLum,
    bgLuminance: bgStats.avgLum,
  );
}

/// 手动覆盖模式：仅计算色相偏差和饱和度（无背景统计，SLS/SCS 置 null）
SkinAnalysis _computeManualSkinStats(
    img.Image image, int r, int g, int b, bool isP3) {
  if (isP3) {
    final srgb = convertP3ToSrgb(r, g, b);
    r = srgb[0];
    g = srgb[1];
    b = srgb[2];
  }
  final hsl = _rgbToHsl(r, g, b);
  final h = hsl[0];
  final s = hsl[1];
  final l = hsl[2];
  return SkinAnalysis(
    hueOffset: skinHueOffset(h),
    saturation: s * 100,
    luminanceSeparation: null,
    colorSeparation: null,
    skinLuminance: l * 100,
    bgLuminance: null,
  );
}

/// 背景统计（排除 ROI 区域）：平均 L + 主导色相
_BackgroundStats _computeBgStats(
  img.Image image,
  int roiXMin,
  int roiYMin,
  int roiXMax,
  int roiYMax,
  bool isP3,
  int step,
) {
  double sumLum = 0;
  int lumCount = 0;
  // 色相直方图（24 bins，每 15°），用于找主导色相
  final hueBins = List.filled(24, 0);
  int hueCount = 0;

  for (var y = 0; y < image.height; y += step) {
    for (var x = 0; x < image.width; x += step) {
      // 跳过 ROI 内的像素
      if (x >= roiXMin && x <= roiXMax && y >= roiYMin && y <= roiYMax) {
        continue;
      }
      var r = image.getPixel(x, y).r.toInt();
      var g = image.getPixel(x, y).g.toInt();
      var b = image.getPixel(x, y).b.toInt();
      if (isP3) {
        final srgb = convertP3ToSrgb(r, g, b);
        r = srgb[0];
        g = srgb[1];
        b = srgb[2];
      }
      final hsl = _rgbToHsl(r, g, b);
      sumLum += hsl[2];
      lumCount++;
      // 仅统计有颜色的像素（饱和度>0.1），灰阶不进直方图
      if (hsl[1] > 0.1) {
        final binIndex = (hsl[0] / 15).floor().clamp(0, 23);
        hueBins[binIndex]++;
        hueCount++;
      }
    }
  }

  final avgLum = lumCount > 0 ? sumLum / lumCount * 100 : 0.0;
  // 主导色相 = bin 数最多的区段中心
  var maxBin = 0;
  var maxCount = 0;
  for (var i = 0; i < 24; i++) {
    if (hueBins[i] > maxCount) {
      maxCount = hueBins[i];
      maxBin = i;
    }
  }
  final dominantHue =
      hueCount > 0 ? (maxBin * 15 + 7.5) : 0.0; // 区段中心
  return _BackgroundStats(avgLum: avgLum, dominantHue: dominantHue);
}

class _BackgroundStats {
  final double avgLum;
  final double dominantHue;
  const _BackgroundStats({required this.avgLum, required this.dominantHue});
}

/// 两个色相在 360° 环上的最短距离
double _hueRingDistance(double h1, double h2) {
  var d = (h1 - h2).abs();
  if (d > 180) d = 360 - d;
  return d;
}

/// RGB → HSL（H: 0~360, S/L: 0~1）
List<double> _rgbToHsl(int r, int g, int b) {
  final rN = r / 255.0;
  final gN = g / 255.0;
  final bN = b / 255.0;
  final max = math.max(rN, math.max(gN, bN));
  final min = math.min(rN, math.min(gN, bN));
  double h = 0;
  double s = 0;
  final l = (max + min) / 2;
  if (max != min) {
    final d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max == rN) {
      h = (gN - bN) / d + (gN < bN ? 6 : 0);
    } else if (max == gN) {
      h = (bN - rN) / d + 2;
    } else {
      h = (rN - gN) / d + 4;
    }
    h /= 6;
  }
  return [h * 360, s, l];
}

// ============ BlazeFace 模型加载与推理 ============

/// 在 Isolate 内从文件系统路径加载 Interpreter 并检测主脸。
///
/// v3.1 修复：原实现 anchor 数（640）与模型输出（896）不匹配 → 越界被 try/catch
/// 吞掉 → 永远返回 null。现按 MediaPipe SsdAnchorsCalculator 正确生成 896 anchor。
Future<DetectedFace?> _detectPrimaryFace(
    img.Image image, String modelPath) async {
  try {
    final interpreter = await _loadInterpreterFromPath(modelPath);
    if (interpreter == null) return null;

    // 预处理：resize 到 128×128，归一化到 [-1, 1]（BlazeFace 标准）
    final resized =
        img.copyResize(image, width: _modelInputSize, height: _modelInputSize);
    final input = List.generate(
      1,
      (_) => List.generate(
        _modelInputSize,
        (y) => List.generate(
          _modelInputSize,
          (x) {
            final p = resized.getPixel(x, y);
            // 归一化到 [-1, 1]
            return [
              (p.r / 127.5) - 1.0,
              (p.g / 127.5) - 1.0,
              (p.b / 127.5) - 1.0,
            ];
          },
        ),
      ),
    );

    // BlazeFace 输出：
    // output[0]: [1, 896, 16] — regressor (每个 anchor 的 [dx,dy,w,h] + landmarks)
    // output[1]: [1, 896, 1]  — classifier (每个 anchor 的置信度，已是 sigmoid 后概率)
    final output = {
      0: List.generate(
          1, (_) => List.generate(896, (_) => List.filled(16, 0.0))),
      1: List.generate(1, (_) => List.generate(896, (_) => List.filled(1, 0.0))),
    };
    interpreter.runForMultipleInputs([input], output);

    final regressors = output[0]![0] as List;
    final classifiers = output[1]![0] as List;

    // 1) 收集候选框
    // v3.1: anchor 数量必须与输出维度一致（896），否则 _anchors[i] 越界
    final candidates = <DetectedFace>[];
    for (var i = 0; i < _numAnchors; i++) {
      final score = (classifiers[i] as List)[0] as double;
      // classifier 已是 sigmoid 后的概率，无需再套 sigmoid
      if (score < _minConfidence) continue;
      final r = regressors[i] as List;
      final anchor = _anchors[i];
      // BlazeFace 解码（归一化空间）：
      //   center = anchor_center + [dx, dy]
      //   size   = anchor_size * exp([dw, dh])（部分实现 regressor[2],[3] 是 log 空间）
      // 这里 regressor[0..3] = [dx, dy, w, h] 均在归一化 0~1 空间（模型已含尺寸回归）
      final cx = anchor[0] + (r[0] as double);
      final cy = anchor[1] + (r[1] as double);
      final w = (r[2] as double).abs().clamp(0.001, 1.0);
      final h = (r[3] as double).abs().clamp(0.001, 1.0);
      candidates.add(DetectedFace(
        left: (cx - w / 2).clamp(0.0, 1.0),
        top: (cy - h / 2).clamp(0.0, 1.0),
        right: (cx + w / 2).clamp(0.0, 1.0),
        bottom: (cy + h / 2).clamp(0.0, 1.0),
        confidence: score,
      ));
    }

    if (candidates.isEmpty) return null;

    // 2) NMS 非极大值抑制
    final nms = _nonMaxSuppression(candidates);

    // 3) 取面积最大者作为主脸
    nms.sort((a, b) => b.area.compareTo(a.area));
    return nms.isEmpty ? null : nms.first;
  } catch (e) {
    // 模型加载失败 / 推理异常 → 静默降级，返回 null
    return null;
  }
}

/// BlazeFace 896 anchors（v3.1 修正：与模型输出张量第二维严格一致）
///
/// 生成规则（MediaPipe SsdAnchorsCalculator，face_detection short/full 通用）：
///   896 = (16×16 + 8×8 + 8×8 + 8×8) × 2
///       = 4 个 stride 层 [8, 16, 16, 16]，每 cell 2 个 anchor
///   每个 anchor = [cx, cy]（归一化 0~1，相对 128×128 输入空间）
///   anchor 中心 = ((cell_x + 0.5) / feature_map_size, (cell_y + 0.5) / feature_map_size)
final List<List<double>> _anchors = _buildAnchors();

List<List<double>> _buildAnchors() {
  final anchors = <List<double>>[];
  // MediaPipe face_detection：4 个 feature map 层，stride [8,16,16,16]
  // feature map size = input_size / stride = 128/8=16, 128/16=8, 8, 8
  // 每层每 cell 2 个 anchor → (16*16 + 8*8 + 8*8 + 8*8) * 2 = 896
  const featureMapSizes = [16, 8, 8, 8];
  for (final fmSize in featureMapSizes) {
    for (var y = 0; y < fmSize; y++) {
      for (var x = 0; x < fmSize; x++) {
        // 每 cell 2 个 anchor，中心相同（尺寸不同由模型内部处理）
        final cx = (x + 0.5) / fmSize;
        final cy = (y + 0.5) / fmSize;
        anchors.add([cx, cy]);
        anchors.add([cx, cy]);
      }
    }
  }
  // 断言：必须正好 896，否则与模型输出不匹配（曾因此 bug 导致越界静默失败）
  assert(anchors.length == _numAnchors,
      'BlazeFace anchors must be $_numAnchors, got ${anchors.length}');
  return anchors;
}

/// NMS 非极大值抑制
List<DetectedFace> _nonMaxSuppression(List<DetectedFace> faces) {
  // 按置信度降序
  final sorted = List<DetectedFace>.from(faces)
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  final keep = <DetectedFace>[];
  for (final f in sorted) {
    var overlap = false;
    for (final k in keep) {
      if (_iou(f, k) > _nmsIouThreshold) {
        overlap = true;
        break;
      }
    }
    if (!overlap) {
      keep.add(f);
      if (keep.length >= _maxDetections) break;
    }
  }
  return keep;
}

/// IoU 交并比
double _iou(DetectedFace a, DetectedFace b) {
  final x1 = math.max(a.left, b.left);
  final y1 = math.max(a.top, b.top);
  final x2 = math.min(a.right, b.right);
  final y2 = math.min(a.bottom, b.bottom);
  final interW = math.max(0.0, x2 - x1);
  final interH = math.max(0.0, y2 - y1);
  final inter = interW * interH;
  final union = a.area + b.area - inter;
  return union > 0 ? inter / union : 0;
}

/// 在 Isolate 内从临时文件路径加载 Interpreter
/// （asset 需先在主线程拷贝到文件系统，Isolate 内才能读）
Future<Interpreter?> _loadInterpreterFromPath(String modelPath) async {
  try {
    // 模型已经在临时目录则直接加载；否则尝试从 asset 拷贝（Isolate 内不能 rootBundle）
    final file = File(modelPath);
    if (!await file.exists()) return null;
    return Interpreter.fromFile(file);
  } catch (_) {
    return null;
  }
}

/// 主线程调用：把两个 asset 模型拷贝到临时文件，返回路径供 Isolate 使用
///
/// v3.1: 同时解压 short_range（主用）+ full_range_sparse（回退），返回两条路径。
/// 必须在 [analyzeSkinTone] 之前调用一次。返回 null 表示 asset 缺失/平台不支持。
/// 为了向后兼容（modelPathProvider 仍是 String?），返回 short 路径；
/// full 路径通过 [_fullModelPathProvider] 单独读取。
Future<String?> ensureModelsExtracted() async {
  final dir = await _getModelsDir();
  final shortPath = await _extractModel(
      _kShortModelAssetKey, '${dir.path}/face_detection_short_range.tflite');
  // full_range_sparse 也解压，但失败不阻塞（仅回退用）
  await _extractModel(_kFullModelAssetKey,
      '${dir.path}/face_detection_full_range_sparse.tflite');
  return shortPath;
}

/// 单模型解压：若目标文件已存在则跳过，否则从 asset 拷贝
Future<String?> _extractModel(String assetKey, String targetPath) async {
  final target = File(targetPath);
  if (await target.exists()) return targetPath;
  try {
    final bytes = await rootBundle.load(assetKey);
    await target.writeAsBytes(bytes.buffer.asUint8List());
    return targetPath;
  } catch (_) {
    return null;
  }
}

/// 主线程调用：获取 full_range 模型路径（已由 [ensureModelsExtracted] 解压）
/// 失败返回 null（仅影响回退检测，不影响主流程）
Future<String?> getFullModelPath() async {
  final dir = await _getModelsDir();
  final path = '${dir.path}/face_detection_full_range_sparse.tflite';
  return await File(path).exists() ? path : null;
}

/// 向后兼容：原 [ensureModelExtracted]（单模型），内部委托给 [ensureModelsExtracted]
Future<String?> ensureModelExtracted() => ensureModelsExtracted();

Future<Directory> _getModelsDir() async {
  // 用应用临时目录，避免污染文档目录
  // 仅在主线程调用（Isolate 内不可用 path_provider）
  final base = await getTemporaryDirectory();
  final dir = Directory('${base.path}/tflite_models');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

// ============ 测试用导出（@visibleForTesting）============
//
// 让单元测试能验证 anchor 数量与解码逻辑，防止 v3.0 那样的"640 vs 896
// 不匹配被 try/catch 吞掉"回归。

/// 生成好的 896 个 anchor（测试用）
@visibleForTesting
List<List<double>> get blazefaceAnchorsForTest => _anchors;

/// 解码单个 anchor 的 regressor 输出为归一化 bbox（测试用）
@visibleForTesting
DetectedFace decodeAnchorForTest(
    int anchorIndex, List<double> regressor, double score) {
  final anchor = _anchors[anchorIndex];
  final cx = anchor[0] + regressor[0];
  final cy = anchor[1] + regressor[1];
  final w = regressor[2].abs().clamp(0.001, 1.0);
  final h = regressor[3].abs().clamp(0.001, 1.0);
  return DetectedFace(
    left: (cx - w / 2).clamp(0.0, 1.0),
    top: (cy - h / 2).clamp(0.0, 1.0),
    right: (cx + w / 2).clamp(0.0, 1.0),
    bottom: (cy + h / 2).clamp(0.0, 1.0),
    confidence: score,
  );
}
