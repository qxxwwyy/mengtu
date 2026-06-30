// face_service.dart — 离线人脸检测 + 肤色 ROI 提取服务（v3.0 阶段二，v3.5 三段式 Face Mesh）
//
// 基于 MediaPipe BlazeFace TFLite 模型，在导入照片时一次性运行人脸检测，
// 提取主脸 ROI（按面积最大，过滤置信度<0.5 的杂点），在 ROI 内统计肤色 HSL
// 指标，与 [ToneService] 协同生成完整 SkinAnalysis。
//
// v3.5 三段式检测链：
// 1. BlazeFace short_range（自拍近距）→ 主脸 bbox
// 2. short 未命中 → full_range_sparse（远景全身）回退
// 3. 命中主脸 → Face Mesh（468 landmarks）精修 ROI + 计算 STI/FLC
// 4. mesh 失败/侧脸 → 降级用 bbox ROI（仍产出 ΔH/饱和/SLS/SCS，STI/FLC 为 null）
//
// 性能策略：
// - 整个检测+ROI 统计在 Isolate 内执行（compute），不阻塞 UI
// - 模型加载用 lazy singleton（首次调用时 Interpreter.fromFile）
// - ROI 内缩 20%（避开头发/耳朵/背景边缘）
//
// 降级设计（每层失败都有出路，不阻塞主流程）：
// - 模型加载失败（如平台不支持）→ 返回 null → ToneResult.skin 为空
// - 未检测到脸 → 返回 null → UI 提示"开启取色工具长按皮肤手动校准"
// - 多脸合影 → 按 BBox 面积降序取最大者作为主脸 ROI
// - v3.5：Face Mesh 失败 → 降级 bbox ROI（STI/FLC null，但仍有 ΔH/饱和/SLS/SCS）
//
// v6.0 根因修复（BlazeFace 解码错误，参考 MediaPipe 官方 SsdAnchorsCalculator +
// patlevin/face-detection-tflite 权威实现）：
//   原实现三大致命 bug 导致「永远检测不到脸」：
//   (1) classifier 输出是 logit，原代码当概率用（未 sigmoid）→ 阈值 0.5 永远过不了
//   (2) 中心点解码 `cx = anchor[0] + r[0]` 错误：r[0] 是 INPUT_SIZE 像素空间的偏移，
//       需 `/ inputSize` 归一化到 [0,1] 才能与归一化 anchor 坐标相加。原实现中心点
//       偏离几百倍 → bbox 全部跑到画面外
//   (3) 宽高解码同样漏了 `/ inputSize`，且 full_range（input 192）共用 896 short 锚点
//       （input 128）→ 回退模型完全失效
//
// 正确的 MediaPipe face_detection 解码公式（patlevin fdlite/blazeface.py 验证）：
//   score       = sigmoid(classifier_logit)
//   cx          = anchor.x_center + regressor[0] / inputSize
//   cy          = anchor.y_center + regressor[1] / inputSize
//   w           = regressor[2] / inputSize
//   h           = regressor[3] / inputSize
//   （anchor 中心已在 [0,1] 归一化空间；box 回归值是 INPUT_SIZE 像素空间的绝对偏移，
//    fixed_anchor_size:true 的 MediaPipe face 模型不乘 anchor.w/h）
//
// 双模型自动回退：short_range（自拍近距）检测不到脸时回退到 full_range（远距全身）。
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

/// Face Mesh 检测结果（468 landmarks，v3.5 新增）
///
/// 由 MediaPipe Face Mesh 模型产出，在 BlazeFace 主脸 bbox 内 crop+resize 到
/// 192×192 推理，输出 468 个归一化 3D 坐标。landmark 坐标已从 crop 空间转回
/// 原图归一化空间（[landmarks] 的 x/y 是相对原图的 0~1）。
class FaceMeshResult {
  /// 468 个归一化坐标 [x, y, z]：x/y 相对原图 0~1，z 是深度（模型原始空间）
  final List<List<double>> landmarks;

  /// 每个 landmark 的可见性近似 [0, 1]（用于 FLC 侧脸判定）
  ///
  /// 旧格式 face_mesh.tflite 无原生 visibility，用 z 深度归一化近似：
  /// z 越接近相机（正值大）→ 越可见；侧脸时背向相机的 landmark z 很负 → 接近 0。
  final List<double> visibility;

  const FaceMeshResult({required this.landmarks, required this.visibility});
}

/// Face Mesh 关键 landmark 索引（MediaPipe 官方拓扑，v3.5 新增）
///
/// 索引值是 MediaPipe Face Mesh 468 点拓扑的固定编号，不应修改。
class FaceMeshIndices {
  FaceMeshIndices._();

  static const noseTip = 1;
  static const leftEyeOuter = 33;
  static const rightEyeOuter = 133;
  static const leftCheek = 50;
  static const rightCheek = 280;
  static const foreheadCenter = 10;
  static const chin = 152;

  /// 左半脸 landmark 集合（用于 FLC 左脸明度采样）
  static const leftFaceRegion = [50, 101, 36, 0, 267, 269, 270, 187, 207];

  /// 右半脸 landmark 集合（用于 FLC 右脸明度采样）
  static const rightFaceRegion = [280, 330, 266, 173, 414, 440, 399, 427];

  /// 脸颊采样区（用于 STI，避开眼/鼻/口的肤色纯区）
  static const cheekRegion = [50, 280, 101, 330, 36, 266, 205, 425];
}

/// STI/FLC 可见性阈值：低于此值的 landmark 视为不可见（侧脸/遮挡）
const _kVisibilityThreshold = 0.5;

/// 肤色分析参数（Isolate 间传递，需可序列化）
class _FaceAnalysisArgs {
  final String imagePath;
  final String shortModelPath; // short_range 模型文件路径（已解压）
  final String fullModelPath; // full_range_sparse 模型文件路径（已解压）
  final String meshModelPath; // v3.5: face_mesh 模型文件路径（已解压）
  final bool isP3ColorSpace; // 是否需要 Display P3 → sRGB 补偿
  final List<double>? manualSkinRgb; // 手动覆盖：取色点 RGB [r,g,b] 0-255

  const _FaceAnalysisArgs(
    this.imagePath,
    this.shortModelPath,
    this.fullModelPath,
    this.meshModelPath,
    this.isP3ColorSpace,
    this.manualSkinRgb,
  );
}

/// short_range 模型输入尺寸（自拍近距）
const _shortModelInputSize = 128;

/// full_range_sparse 模型输入尺寸（远景全身，更大输入）
const _fullModelInputSize = 192;

/// 置信度阈值（过滤背景噪声）
const _minConfidence = 0.5;

/// NMS IoU 阈值
const _nmsIouThreshold = 0.3;

/// 检测上限（避免合影场景跑太多 BBox）
const _maxDetections = 10;

/// 模型 asset keys
const _kShortModelAssetKey =
    'assets/models/face_detection_short_range.tflite';
const _kFullModelAssetKey =
    'assets/models/face_detection_full_range_sparse.tflite';
const _kMeshModelAssetKey = 'assets/models/face_mesh.tflite'; // v3.5 新增

/// 检测照片中的主脸，提取肤色 ROI 统计指标 + v3.5 STI/FLC（Face Mesh 依赖）。
///
/// [imagePath] 照片绝对路径；[shortModelPath]/[fullModelPath]/[meshModelPath]
/// 为已解压到临时目录的 .tflite 路径（由 [ensureModelsExtracted] 提供，
/// Isolate 无法读 asset，必须先解压）。
/// 三段式检测链：short（主）→ full（远景回退）→ mesh（landmark 精修 + STI/FLC）。
/// [isP3ColorSpace] 为 true 时对像素做 P3→sRGB 补偿。
///
/// **手动覆盖模式**：当 [manualSkinRgb] 非空时，跳过人脸检测，直接用该 RGB
/// （取色点）计算色相偏差和饱和度，作为 BlazeFace 失败时的备用通路。
Future<SkinAnalysis> analyzeSkinTone(
  String imagePath, {
  String? shortModelPath,
  String? fullModelPath,
  String? meshModelPath, // v3.5 新增
  bool isP3ColorSpace = false,
  List<double>? manualSkinRgb,
}) async {
  return compute(
    _analyzeSkinIsolate,
    _FaceAnalysisArgs(
      imagePath,
      shortModelPath ?? '',
      fullModelPath ?? '',
      meshModelPath ?? '',
      isP3ColorSpace,
      manualSkinRgb,
    ),
  );
}

/// Isolate 入口（v3.5 三段式：short → full → mesh）
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

  // 自动模式：三段式检测
  // 1) short_range（自拍近距）→ 主脸 bbox
  DetectedFace? face;
  if (args.shortModelPath.isNotEmpty) {
    face = await _detectPrimaryFace(decoded, args.shortModelPath,
        inputSize: _shortModelInputSize);
  }
  // 2) short 未命中 → full_range（远处/全身/小脸场景召回更好）
  if (face == null && args.fullModelPath.isNotEmpty) {
    face = await _detectPrimaryFace(decoded, args.fullModelPath,
        inputSize: _fullModelInputSize);
  }
  if (face == null) {
    return const SkinAnalysis(); // 无脸 → 空结果，UI 提示手动校准
  }

  // 3) v3.5: Face Mesh landmark 推理（精修 ROI + STI/FLC）
  FaceMeshResult? mesh;
  if (args.meshModelPath.isNotEmpty) {
    mesh = await _runFaceMesh(decoded, face, args.meshModelPath);
  }

  if (mesh != null) {
    // 用 mesh 计算 STI/FLC，叠加到 bbox ROI 的肤色统计上
    final base = _analyzeRoiSkin(decoded, face, args.isP3ColorSpace);
    final sti = calculateSti(mesh, decoded, args.isP3ColorSpace);
    final flc = calculateFlc(mesh, decoded, args.isP3ColorSpace);
    return SkinAnalysis(
      hueOffset: base.hueOffset,
      saturation: base.saturation,
      luminanceSeparation: base.luminanceSeparation,
      colorSeparation: base.colorSeparation,
      skinLuminance: base.skinLuminance,
      bgLuminance: base.bgLuminance,
      sti: sti, // 可空：无可见脸颊 landmark → null
      flc: flc, // 可空：侧脸/遮挡 → null
    );
  }
  // 降级：mesh 失败/未配置 → 用现有 bbox ROI 逻辑（STI/FLC 为 null）
  return _analyzeRoiSkin(decoded, face, args.isP3ColorSpace);
}

/// 在主脸 ROI 内统计肤色 HSL 指标 + 计算 SLS / SCS 隔离度
///
/// v3.2 性能优化：原实现分两次遍历 —— 先遍历 ROI 统计肤色，再遍历全图
/// （排除 ROI）统计背景。全图遍历是主要成本（4MP 图 × step=2 ≈ 100 万像素）。
/// 现合并为**一次全图遍历**：命中 ROI 累加肤色统计，否则累加背景统计。
/// 同时把 `getPixel(x,y)` 的 3 次调用（取 r/g/b）合并为 1 次，省 2/3 的
/// Pixel 对象分配。整体提速约 2x。
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
  final roiXMin = xMin + padX;
  final roiXMax = xMax - padX;
  final roiYMin = yMin + padY;
  final roiYMax = yMax - padY;

  // 肤色 ROI 累加器
  double sumHue = 0;
  double sumSat = 0;
  double sumLum = 0;
  int skinCount = 0;

  // 背景累加器（全图排除 ROI）
  double bgSumLum = 0;
  int bgLumCount = 0;
  // 背景色相直方图（24 bins，每 15°），用于找主导色相
  final bgHueBins = List.filled(24, 0);
  int bgHueCount = 0;

  const step = 2;
  // 单次遍历：肤色 ROI（内缩后）内 → 肤色统计；
  // 原始 ROI bbox（未内缩）外 → 背景统计；内缩环（两者之间）→ 跳过。
  // 这样与原双遍历实现完全等价（内缩环既不进肤色也不进背景）。
  for (var y = 0; y < imgH; y += step) {
    final inBboxY = y >= yMin && y <= yMax;
    for (var x = 0; x < imgW; x += step) {
      final inBbox = inBboxY && x >= xMin && x <= xMax;
      if (!inBbox) {
        // 背景：累计 L + 色相直方图
        final p = image.getPixel(x, y);
        var r = p.r.toInt();
        var g = p.g.toInt();
        var b = p.b.toInt();
        if (isP3) {
          final srgb = convertP3ToSrgb(r, g, b);
          r = srgb[0];
          g = srgb[1];
          b = srgb[2];
        }
        final hsl = _rgbToHsl(r, g, b);
        bgSumLum += hsl[2];
        bgLumCount++;
        if (hsl[1] > 0.1) {
          bgHueBins[(hsl[0] / 15).floor().clamp(0, 23)]++;
          bgHueCount++;
        }
        continue;
      }
      // 在 bbox 内但不在内缩 ROI 内 → 跳过（与原实现等价）
      final inRoi = inBboxY &&
          x >= roiXMin &&
          x <= roiXMax &&
          y >= roiYMin &&
          y <= roiYMax;
      if (!inRoi) continue;

      // 肤色 ROI 内：一次 getPixel 取 r/g/b（原实现调用 3 次，省 2/3 Pixel 分配）
      final p = image.getPixel(x, y);
      var r = p.r.toInt();
      var g = p.g.toInt();
      var b = p.b.toInt();
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
        skinCount++;
      }
    }
  }

  if (skinCount == 0) return const SkinAnalysis();

  double avgHue = sumHue / skinCount;
  if (avgHue < 0) avgHue += 360;
  final avgSat = sumSat / skinCount * 100;
  final avgLum = sumLum / skinCount * 100;

  // 背景平均 L
  final bgAvgLum = bgLumCount > 0 ? bgSumLum / bgLumCount * 100 : 0.0;
  // 背景主导色相 = bin 数最多的区段中心
  var maxBin = 0;
  var maxCount = 0;
  for (var i = 0; i < 24; i++) {
    if (bgHueBins[i] > maxCount) {
      maxCount = bgHueBins[i];
      maxBin = i;
    }
  }
  final bgDominantHue = bgHueCount > 0 ? (maxBin * 15 + 7.5) : 0.0;

  // SLS = 肤色 L − 背景 L（百分比）
  final sls = avgLum - bgAvgLum;
  // SCS = 肤色色相与背景主导色相的环形最短距离
  final scs = _hueRingDistance(avgHue, bgDominantHue);

  return SkinAnalysis(
    hueOffset: skinHueOffset(avgHue),
    saturation: avgSat,
    luminanceSeparation: sls,
    colorSeparation: scs,
    skinLuminance: avgLum,
    bgLuminance: bgAvgLum,
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
///
/// v3.2：已合并进 [_analyzeRoiSkin] 的单次全图遍历（肤色/背景同一次扫描），
/// 此独立函数及其返回类型已删除。若未来需要单独的背景统计，可基于
/// [_analyzeRoiSkin] 的内联实现重建。

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

// ============ v3.5 Face Mesh 推理 + STI/FLC 算法 ============
//
// 以下函数中，[calculateSti] / [calculateFlc] 是纯函数（仅依赖 FaceMeshResult +
// img.Image），便于在 Isolate 外做单元测试（构造合成 mesh 数据验证边界条件）。
// [_runFaceMesh] 是推理函数（依赖 TFLite Interpreter），只能在 Isolate 内运行。

/// Face Mesh 模型固定输入尺寸（MediaPipe face_landmark：192×192）
const _meshInputSize = 192;

/// 在人脸 bbox 内运行 Face Mesh，返回 468 landmarks（v3.5 新增）
///
/// 流程：
/// 1. 扩展 bbox 20%（留 margin 给 mesh 模型，避免边缘 landmark 被裁掉）
/// 2. crop + resize 到 192×192
/// 3. 预处理（归一化到 [0, 1]）+ 推理（输出 [1, 468, 3]）
/// 4. landmark 坐标从 crop 空间转回原图归一化空间
/// 5. visibility 近似：用 z 深度归一化（旧 face_mesh.tflite 无原生 visibility）
///
/// 任何步骤失败 → 返回 null（降级到 bbox ROI，不阻塞主流程）。
Future<FaceMeshResult?> _runFaceMesh(
    img.Image image, DetectedFace face, String meshModelPath) async {
  try {
    final interpreter = await _loadInterpreterFromPath(meshModelPath);
    if (interpreter == null) return null;

    final imgW = image.width;
    final imgH = image.height;

    // 1. 扩展 bbox（留 margin 给 mesh 模型，landmark 在边缘会更准）
    const margin = 0.2; // 各方向扩展 20%
    final x1 = ((face.left - margin) * imgW).clamp(0, imgW - 1).round();
    final y1 = ((face.top - margin) * imgH).clamp(0, imgH - 1).round();
    final x2 = ((face.right + margin) * imgW).clamp(0, imgW).round();
    final y2 = ((face.bottom + margin) * imgH).clamp(0, imgH).round();
    final cropW = (x2 - x1).clamp(1, imgW - x1);
    final cropH = (y2 - y1).clamp(1, imgH - y1);

    // 2. crop + resize 到 192×192
    final cropped =
        img.copyCrop(image, x: x1, y: y1, width: cropW, height: cropH);
    final resized =
        img.copyResize(cropped, width: _meshInputSize, height: _meshInputSize);

    // 3. 预处理（归一化到 [0, 1]，Face Mesh 标准）
    final input = List.generate(
      1,
      (_) => List.generate(_meshInputSize,
          (y) => List.generate(_meshInputSize, (x) {
                final p = resized.getPixel(x, y);
                return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
              })),
    );

    // 4. 推理（Face Mesh 输出 [1, 468, 3] landmarks）
    final output = {
      0: List.generate(
          1,
          (_) =>
              List.generate(468, (_) => List.filled(3, 0.0))),
    };
    interpreter.runForMultipleInputs([input], output);

    final landmarksRaw =
        (output[0]![0] as List).map((p) => (p as List).cast<double>()).toList();

    // 5. landmark 坐标从 crop 空间转回原图归一化空间
    final landmarks = landmarksRaw.map((p) {
      final normX = (x1 + p[0] * cropW) / imgW;
      final normY = (y1 + p[1] * cropH) / imgH;
      return [normX, normY, p[2]];
    }).toList();

    // 6. visibility 近似：z 深度归一化（旧 face_mesh.tflite 无原生 visibility）
    //    z 越接近相机（正值大）→ 越可见；侧脸时背向相机的 landmark z 很负 → 接近 0
    final zValues = landmarksRaw.map((p) => p[2]).toList();
    final zMin = zValues.reduce(math.min);
    final zMax = zValues.reduce(math.max);
    final zRange = (zMax - zMin).abs() > 1e-6 ? zMax - zMin : 1.0;
    final visibility = zValues
        .map((z) => ((z - zMin) / zRange).clamp(0.0, 1.0))
        .toList();

    return FaceMeshResult(landmarks: landmarks, visibility: visibility);
  } catch (_) {
    return null; // mesh 失败 → 降级到 bbox ROI
  }
}

/// 皮肤通透度指数 STI（v3.5，接近度公式，弃用 plan.md Y×(1−S)×(1−Texture) 乘积）
///
/// `STI = ⅓·gaussian(Y, 0.65, 0.15) + ⅓·gaussian(S, 0.25, 0.1) + ⅓·(1−|ΔH|/30)`
/// 理想肤色点：Y=0.65（明度）、S=0.25（饱和度）、H=17°（达芬奇肤色线）。
///
/// 用 [FaceMeshIndices.cheekRegion] 采样（脸颊纯肤色区，避开眼/鼻/口）。
/// 不可见 landmark（visibility < 0.5）跳过；全部不可见 → 返回 null（侧脸/遮挡）。
///
/// 纯函数：不依赖 TFLite，可在 Isolate 外用合成 mesh 测试。
@visibleForTesting
double? calculateSti(FaceMeshResult mesh, img.Image image, bool isP3) {
  final imgW = image.width;
  final imgH = image.height;

  double sumY = 0, sumS = 0, sumH = 0;
  var count = 0;
  for (final idx in FaceMeshIndices.cheekRegion) {
    if (idx >= mesh.landmarks.length) continue;
    final vis = idx < mesh.visibility.length ? mesh.visibility[idx] : 0;
    if (vis < _kVisibilityThreshold) continue; // 不可见 landmark 跳过
    final lm = mesh.landmarks[idx];
    final px = (lm[0] * imgW).clamp(0, imgW - 1).round();
    final py = (lm[1] * imgH).clamp(0, imgH - 1).round();
    final p = image.getPixel(px, py);
    var r = p.r.toInt();
    var g = p.g.toInt();
    var b = p.b.toInt();
    if (isP3) {
      final srgb = convertP3ToSrgb(r, g, b);
      r = srgb[0];
      g = srgb[1];
      b = srgb[2];
    }
    final hsl = _rgbToHsl(r, g, b);
    sumY += hsl[2]; // L [0,1]
    sumS += hsl[1]; // S [0,1]
    sumH += hsl[0]; // H [0,360]
    count++;
  }
  if (count == 0) return null; // 全部不可见 → 侧脸/遮挡，FLC 也无意义

  final avgY = sumY / count; // [0, 1]
  final avgS = sumS / count; // [0, 1]
  var avgH = sumH / count; // [0, 360]
  // ΔH 环形最短距离（相对达芬奇肤色线 17°）
  var dh = (avgH - 17).abs();
  if (dh > 180) dh = 360 - dh;
  final dhNorm = dh / 30;

  // 高斯接近度：x 越接近理想点 μ → 越接近 1；偏离 → 衰减
  double gaussian(double x, double mu, double sigma) =>
      math.exp(-((x - mu) * (x - mu)) / (2 * sigma * sigma));

  return (gaussian(avgY, 0.65, 0.15) +
          gaussian(avgS, 0.25, 0.1) +
          (1 - dhNorm.clamp(0, 1))) /
      3;
}

/// 面部反差系数 FLC（v3.5，带可见性判定，侧脸降级 null）
///
/// `FLC = |Y_left − Y_right| / (Y_left + Y_right + 1e-5)`
/// 左右脸由 face mesh 的 leftFaceRegion / rightFaceRegion 划分（脸颊外侧区）。
///
/// 可见性判定：左右脸区域平均 visibility < 0.5 → 侧脸/遮挡 → 返回 null。
/// 平光（左右明度接近）→ FLC ≈ 0；阴阳脸（一侧高光一侧阴影）→ FLC 接近 1。
///
/// 纯函数：不依赖 TFLite，可在 Isolate 外用合成 mesh 测试。
@visibleForTesting
double? calculateFlc(FaceMeshResult mesh, img.Image image, bool isP3) {
  final imgW = image.width;
  final imgH = image.height;

  // 1. 可见性检查：左右脸区域平均 visibility
  final leftVisVals = FaceMeshIndices.leftFaceRegion
      .where((i) => i < mesh.visibility.length)
      .map((i) => mesh.visibility[i])
      .toList();
  final rightVisVals = FaceMeshIndices.rightFaceRegion
      .where((i) => i < mesh.visibility.length)
      .map((i) => mesh.visibility[i])
      .toList();
  if (leftVisVals.isEmpty || rightVisVals.isEmpty) return null;
  final leftVis =
      leftVisVals.reduce((a, b) => a + b) / leftVisVals.length;
  final rightVis =
      rightVisVals.reduce((a, b) => a + b) / rightVisVals.length;
  if (leftVis < _kVisibilityThreshold || rightVis < _kVisibilityThreshold) {
    return null; // 侧脸/遮挡
  }

  // 2. 采样左右脸明度（仅可见 landmark）
  double sumYLeft = 0, sumYRight = 0;
  var cntLeft = 0, cntRight = 0;

  for (final idx in FaceMeshIndices.leftFaceRegion) {
    if (idx >= mesh.landmarks.length) continue;
    if (idx < mesh.visibility.length &&
        mesh.visibility[idx] < _kVisibilityThreshold) {
      continue;
    }
    final lm = mesh.landmarks[idx];
    final p = image.getPixel(
        (lm[0] * imgW).round().clamp(0, imgW - 1),
        (lm[1] * imgH).round().clamp(0, imgH - 1));
    var r = p.r.toInt();
    var g = p.g.toInt();
    var b = p.b.toInt();
    if (isP3) {
      final s = convertP3ToSrgb(r, g, b);
      r = s[0];
      g = s[1];
      b = s[2];
    }
    sumYLeft += _rgbToHsl(r, g, b)[2];
    cntLeft++;
  }
  for (final idx in FaceMeshIndices.rightFaceRegion) {
    if (idx >= mesh.landmarks.length) continue;
    if (idx < mesh.visibility.length &&
        mesh.visibility[idx] < _kVisibilityThreshold) {
      continue;
    }
    final lm = mesh.landmarks[idx];
    final p = image.getPixel(
        (lm[0] * imgW).round().clamp(0, imgW - 1),
        (lm[1] * imgH).round().clamp(0, imgH - 1));
    var r = p.r.toInt();
    var g = p.g.toInt();
    var b = p.b.toInt();
    if (isP3) {
      final s = convertP3ToSrgb(r, g, b);
      r = s[0];
      g = s[1];
      b = s[2];
    }
    sumYRight += _rgbToHsl(r, g, b)[2];
    cntRight++;
  }
  if (cntLeft == 0 || cntRight == 0) return null;

  final yLeft = sumYLeft / cntLeft;
  final yRight = sumYRight / cntRight;
  return (yLeft - yRight).abs() / (yLeft + yRight + 1e-5);
}

// ============ BlazeFace 模型加载与推理 ============

/// 在 Isolate 内从文件系统路径加载 Interpreter 并检测主脸。
///
/// [inputSize] 决定 anchor 配置与 box 回归归一化：short_range=128，full_range=192。
/// 二者锚点数量/分布不同，必须用对应 [inputSize] 的 anchor 集。
///
/// v6.0 修复：classifier 需 sigmoid；box 回归值是 INPUT_SIZE 像素空间偏移，需
/// `/ inputSize` 归一化到 [0,1] 才能加到归一化 anchor 坐标上（原实现漏除 → 全画面外）。
Future<DetectedFace?> _detectPrimaryFace(
    img.Image image, String modelPath,
    {required int inputSize}) async {
  try {
    final interpreter = await _loadInterpreterFromPath(modelPath);
    if (interpreter == null) return null;

    // 预处理：resize 到 inputSize×inputSize，归一化到 [-1, 1]（BlazeFace 标准）
    final resized =
        img.copyResize(image, width: inputSize, height: inputSize);
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
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

    // 该 inputSize 对应的 anchor 集（不同模型锚点数/分布不同）
    final anchors = _anchorsFor(inputSize);

    // BlazeFace 输出：
    // output[0]: [1, numAnchors, 16] — regressor (每个 anchor 的 [dx,dy,w,h] + landmarks)
    // output[1]: [1, numAnchors, 1]  — classifier (每个 anchor 的 logit，需 sigmoid)
    final numAnchors = anchors.length;
    final output = {
      0: List.generate(
          1, (_) => List.generate(numAnchors, (_) => List.filled(16, 0.0))),
      1: List.generate(
          1, (_) => List.generate(numAnchors, (_) => List.filled(1, 0.0))),
    };
    interpreter.runForMultipleInputs([input], output);

    final regressors = output[0]![0] as List;
    final classifiers = output[1]![0] as List;

    // 1) 收集候选框
    final candidates = <DetectedFace>[];
    for (var i = 0; i < numAnchors; i++) {
      // classifier 输出是 logit → sigmoid 得概率（原实现漏此步，阈值永远过不了）
      final logit = (classifiers[i] as List)[0] as double;
      final score = 1.0 / (1.0 + math.exp(-logit));
      if (score < _minConfidence) continue;
      final r = regressors[i] as List;
      final anchor = anchors[i];
      // MediaPipe face_detection 解码（fixed_anchor_size，box 回归为像素绝对偏移）：
      //   cx = anchor.x + r[0] / inputSize   （anchor 在 [0,1]，r 在像素空间）
      //   cy = anchor.y + r[1] / inputSize
      //   w  = r[2] / inputSize
      //   h  = r[3] / inputSize
      final cx = anchor[0] + (r[0] as double) / inputSize;
      final cy = anchor[1] + (r[1] as double) / inputSize;
      final w = ((r[2] as double) / inputSize).clamp(0.001, 1.0);
      final h = ((r[3] as double) / inputSize).clamp(0.001, 1.0);
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

/// 按 inputSize 返回对应的 BlazeFace anchor 集（归一化 [0,1] 坐标）
///
/// - short_range (input 128)：896 anchors = (16²+8²+8²+8²)×2，stride [8,16,16,16]
/// - full_range_sparse (input 192)：与 short 同结构（stride 占输入比例相同），
///   feature map 仍为 [16,8,8,8]，anchor 中心计算同 short，故复用同一生成函数。
///
/// 每个 anchor = [cx, cy]（归一化 [0,1]，相对 feature map 空间）。
/// 中心 = ((cell_x + 0.5) / fmSize, (cell_y + 0.5) / fmSize)。
/// 每 cell 2 个 anchor（不同 aspect，由模型内部处理 size，fixed_anchor_size）。
final Map<int, List<List<double>>> _anchorsCache = {};

List<List<double>> _anchorsFor(int inputSize) {
  return _anchorsCache.putIfAbsent(inputSize, () => _buildAnchors(inputSize));
}

List<List<double>> _buildAnchors(int inputSize) {
  final anchors = <List<double>>[];
  // MediaPipe face_detection short & full：feature map [16,8,8,8]，每 cell 2 anchor
  // → (16*16 + 8*8 + 8*8 + 8*8) * 2 = 896（两个模型锚点结构一致，与 inputSize 解耦）
  const featureMapSizes = [16, 8, 8, 8];
  for (final fmSize in featureMapSizes) {
    for (var y = 0; y < fmSize; y++) {
      for (var x = 0; x < fmSize; x++) {
        // 每 cell 2 个 anchor，中心相同（不同 aspect，size 由模型 fixed_anchor_size 处理）
        final cx = (x + 0.5) / fmSize;
        final cy = (y + 0.5) / fmSize;
        anchors.add([cx, cy]);
        anchors.add([cx, cy]);
      }
    }
  }
  // 断言：short & full 均为 896，与模型输出张量第二维严格一致
  assert(anchors.length == 896,
      'BlazeFace anchors must be 896, got ${anchors.length} (inputSize=$inputSize)');
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
  if (dir == null) return null; // 临时目录不可用（如测试环境 platform channel 缺失）
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
  if (dir == null) return null;
  final path = '${dir.path}/face_detection_full_range_sparse.tflite';
  return await File(path).exists() ? path : null;
}

/// v3.5：主线程调用，把 face_mesh asset 拷贝到临时文件
///
/// 独立于 [ensureModelsExtracted]（mesh 失败不应阻塞 BlazeFace 检测）。
/// 失败返回 null（仅影响 STI/FLC，不影响 ΔH/饱和/SLS/SCS）。
Future<String?> ensureMeshModelExtracted() async {
  final dir = await _getModelsDir();
  if (dir == null) return null;
  return _extractModel(
      _kMeshModelAssetKey, '${dir.path}/face_mesh.tflite');
}

/// v3.5：获取 face_mesh 模型路径（已由 [ensureMeshModelExtracted] 解压）
/// 失败返回 null（仅影响 STI/FLC，不影响主流程）
Future<String?> getMeshModelPath() async {
  final dir = await _getModelsDir();
  if (dir == null) return null;
  final path = '${dir.path}/face_mesh.tflite';
  return await File(path).exists() ? path : null;
}

/// 向后兼容：原 [ensureModelExtracted]（单模型），内部委托给 [ensureModelsExtracted]
Future<String?> ensureModelExtracted() => ensureModelsExtracted();

/// 模型解压目录（应用临时目录下 tflite_models/）
///
/// 返回 null 表示临时目录不可用（如 platform channel 未初始化的测试环境）。
/// 调用方据此返回 null，让上层（skinProvider / precompute）走降级路径，
/// 不让 path_provider 失败阻塞整个分析流程。
Future<Directory?> _getModelsDir() async {
  try {
    // 用应用临时目录，避免污染文档目录
    // 仅在主线程调用（Isolate 内不可用 path_provider）
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/tflite_models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  } catch (_) {
    return null; // platform channel 失败（测试环境 / path_provider 异常）
  }
}

// ============ 测试用导出（@visibleForTesting）============
//
// 让单元测试能验证 anchor 数量与解码逻辑，防止 v3.0 那样的"640 vs 896
// 不匹配被 try/catch 吞掉"回归，以及 v6.0 修复 sigmoid / inputSize 归一化不回归。

/// short_range (128) 的 896 个 anchor（测试用）
@visibleForTesting
List<List<double>> get blazefaceAnchorsForTest => _anchorsFor(_shortModelInputSize);

/// 解码单个 anchor 的 regressor 输出为归一化 bbox（测试用）
///
/// [inputSize] 必须与模型实际输入一致（short=128 / full=192），
/// 因为 regressor 值是像素空间偏移，需 `/ inputSize` 归一化。
@visibleForTesting
DetectedFace decodeAnchorForTest(
    int anchorIndex, List<double> regressor, double score,
    {int inputSize = _shortModelInputSize}) {
  final anchor = _anchorsFor(inputSize)[anchorIndex];
  final cx = anchor[0] + regressor[0] / inputSize;
  final cy = anchor[1] + regressor[1] / inputSize;
  final w = (regressor[2] / inputSize).clamp(0.001, 1.0);
  final h = (regressor[3] / inputSize).clamp(0.001, 1.0);
  return DetectedFace(
    left: (cx - w / 2).clamp(0.0, 1.0),
    top: (cy - h / 2).clamp(0.0, 1.0),
    right: (cx + w / 2).clamp(0.0, 1.0),
    bottom: (cy + h / 2).clamp(0.0, 1.0),
    confidence: score,
  );
}

/// 测试用：把 classifier logit 转 sigmoid 概率
@visibleForTesting
double sigmoidForTest(double logit) => 1.0 / (1.0 + math.exp(-logit));
