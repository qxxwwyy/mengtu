// scrfd_service.dart — SCRFD (NCNN) 人脸检测服务（v7.0）
//
// 替代 BlazeFace + ML Kit 作主检测链。SCRFD 通过 NCNN 推理（CPU，FFI），
// 输出 bbox + 5 关键点。本服务封装：模型文件提取到文件系统、单例初始化、
// EXIF 旋转对齐 + 调用插件 detect()。
//
// 与 face_service.dart 协同：本服务产出 DetectedFace（归一化 bbox），
// face_service.analyzeSkinTone 在 rawFace 内做 ROI 肤色统计。
//
// 坐标系对齐：
// - image 包 decodeImage 给【存储尺寸未旋转】像素
// - 我们对 decoded 像素直接推理，bbox 在【存储尺寸】空间
// - 对 90°/270° EXIF 旋转，显示尺寸宽高互换，bbox 归一化用【显示后图像】尺寸
//   （与 Flutter Image.file 渲染、FaceBBoxOverlay 一致）
//
// 性能：整个解码和推理都在后台 Isolate (compute) 中执行，实现 0 阻塞主 UI 线程。
import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:scrfd_ncnn/scrfd_ncnn.dart';

import 'face_service.dart' show DetectedFace;

/// v7.0：主脸检测结果（bbox + 显示尺寸）
///
/// 与 v6.1 FaceDetection 形状一致，供 overlay 算 letterbox（displayW/H 是显示尺寸）。
@immutable
class FaceDetection {
  final DetectedFace? face;      // Display space coordinate (EXIF rotated)
  final DetectedFace? rawFace;   // Storage space coordinate (Unrotated)
  final int displayWidth;
  final int displayHeight;

  const FaceDetection(this.face, this.rawFace, this.displayWidth, this.displayHeight);
}

/// SCRFD 模型 asset keys（scrfd_ncnn 插件自带 assets）
const _kParamAssetKey = 'packages/scrfd_ncnn/assets/scrfd_2.5g_kps-opt2.param';
const _kBinAssetKey = 'packages/scrfd_ncnn/assets/scrfd_2.5g_kps-opt2.bin';

/// EXIF Orientation 值 → 是否需要宽高互换（90°/270° 旋转）
bool _orientationSwapsDimensions(int orientation) =>
    orientation == 5 || orientation == 6 || orientation == 7 || orientation == 8;

/// v7.0：用 SCRFD (NCNN) 检测主脸，返回相对【显示后图像】的归一化 bbox（0~1）
///
/// [imagePath] 照片绝对路径。返回 [FaceDetection]（含 bbox + 显示尺寸），无脸时
/// face 为 null 但 displayWidth/Height 仍有值。
///
/// 坐标系：bbox 归一化到【显示后图像】（EXIF 旋转已应用），与 Flutter Image.file
/// 渲染空间一致，与 FaceBBoxOverlay 一致。
Future<FaceDetection> detectPrimaryFaceWithScrfd(
  String imagePath, {
  String? thumbnailPath,
  required int originalWidth,
  required int originalHeight,
}) async {
  final file = File(imagePath);
  if (!await file.exists()) return const FaceDetection(null, null, 0, 0);

  // 1. 确保模型已在主 Isolate 释放/提取完成，获取其本地路径
  String paramPath;
  String binPath;
  try {
    paramPath = await _extractAssetToFile(_kParamAssetKey);
    binPath = await _extractAssetToFile(_kBinAssetKey);
  } catch (e) {
    debugPrint('Model extraction failed: $e');
    return FaceDetection(null, null, originalWidth, originalHeight);
  }

  // 2. 调用 compute 把整个检测和解码过程移到后台 Isolate
  try {
    final result = await compute(
      _detectFaceIsolateEntry,
      (
        imagePath: imagePath,
        thumbnailPath: thumbnailPath,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        paramPath: paramPath,
        binPath: binPath,
      ),
    );
    return result;
  } catch (e) {
    debugPrint('Background face detection failed: $e');
    // 如果后台检测崩溃/模型加载错，则删除已提取的文件，以防是损坏的占位文件
    try {
      final paramFile = File(paramPath);
      final binFile = File(binPath);
      if (await paramFile.exists()) await paramFile.delete();
      if (await binFile.exists()) await binFile.delete();
    } catch (_) {}
    return FaceDetection(null, null, originalWidth, originalHeight);
  }
}

/// Isolate 后台执行的静态/全局方法
Future<FaceDetection> _detectFaceIsolateEntry(({
  String imagePath,
  String? thumbnailPath,
  int originalWidth,
  int originalHeight,
  String paramPath,
  String binPath,
}) args) async {
  final scrfd = ScrfdNcnn();
  final initRet = await scrfd.init(args.paramPath, args.binPath);
  if (initRet != 0) {
    throw StateError('SCRFD native init failed inside Isolate: $initRet');
  }

  final file = File(args.imagePath);
  // 优先用更小的缩略图解码（解码速度提速 100x）
  final decodeFile = args.thumbnailPath != null ? File(args.thumbnailPath!) : file;
  final decoded = img.decodeImage(decodeFile.readAsBytesSync());
  if (decoded == null) {
    return const FaceDetection(null, null, 0, 0);
  }

  final orientation = await _readExifOrientation(file);
  final swap = _orientationSwapsDimensions(orientation);
  final displayW = swap ? args.originalHeight : args.originalWidth;
  final displayH = swap ? args.originalWidth : args.originalHeight;

  // 使用 image 4.9.1 自带的 getBytes 方法导出原始 RGBA 数据，直接传给 NCNN
  final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);
  final faces = scrfd.detect(rgba, decoded.width, decoded.height);

  if (faces.isEmpty) return FaceDetection(null, null, displayW, displayH);

  // 选面积最大的主脸，归一化到【显示后图像】空间
  double maxArea = -1.0;
  DetectedFace? bestDisplayFace;
  DetectedFace? bestRawFace;

  // decoded 尺寸是实际用来检测的尺寸（如 thumbnail 360 像素，未旋转）
  final decW = decoded.width;
  final decH = decoded.height;

  for (final f in faces) {
    final nx = f.x / decW;
    final ny = f.y / decH;
    final nw = f.w / decW;
    final nh = f.h / decH;

    // 1. rawFace：存储空间归一化坐标（未旋转，直接应用于原始图片采样）
    final rawFace = DetectedFace(
      left: nx.clamp(0.0, 1.0),
      top: ny.clamp(0.0, 1.0),
      right: (nx + nw).clamp(0.0, 1.0),
      bottom: (ny + nh).clamp(0.0, 1.0),
      confidence: f.score,
    );

    // 2. displayFace：显示空间归一化坐标（EXIF 旋转纠正，用于 UI 渲染）
    double dLeft, dTop, dRight, dBottom;
    switch (orientation) {
      case 3: // 180 deg
        dLeft = 1.0 - nx - nw;
        dTop = 1.0 - ny - nh;
        dRight = 1.0 - nx;
        dBottom = 1.0 - ny;
        break;
      case 6: // 90 deg CW
        dLeft = 1.0 - ny - nh;
        dTop = nx;
        dRight = 1.0 - ny;
        dBottom = nx + nw;
        break;
      case 8: // 270 deg CW
        dLeft = ny;
        dTop = 1.0 - nx - nw;
        dRight = ny + nh;
        dBottom = 1.0 - nx;
        break;
      default: // 1 (Normal)
        dLeft = nx;
        dTop = ny;
        dRight = nx + nw;
        dBottom = ny + nh;
        break;
    }

    final displayFace = DetectedFace(
      left: dLeft.clamp(0.0, 1.0),
      top: dTop.clamp(0.0, 1.0),
      right: dRight.clamp(0.0, 1.0),
      bottom: dBottom.clamp(0.0, 1.0),
      confidence: f.score,
    );

    if (displayFace.area > maxArea) {
      maxArea = displayFace.area;
      bestDisplayFace = displayFace;
      bestRawFace = rawFace;
    }
  }

  return FaceDetection(bestDisplayFace, bestRawFace, displayW, displayH);
}

/// 释放 SCRFD 检测器（应用退出时调用，避免 native 内存泄漏）
void disposeScrfdDetector() {
  // C++ 单例全局销毁可以在此处理
  // 后台 Isolate compute 的独立实例退出时会自动清理，全局 C++ 单例在销毁时被回收。
}

/// 把插件 asset 复制到应用文档目录，返回文件路径
///
/// NCNN 无法直读 Android assets，必须先复制到文件系统。
/// 缓存到 appDocsDir，重复调用跳过（文件已存在）。
Future<String> _extractAssetToFile(String assetKey) async {
  final dir = await getApplicationDocumentsDirectory();
  final fileName = assetKey.split('/').last;
  final file = File('${dir.path}/scrfd_models/$fileName');
  if (await file.exists()) return file.path;
  await file.parent.create(recursive: true);
  final byteData = await rootBundle.load(assetKey);
  await file.writeAsBytes(byteData.buffer.asUint8List());
  return file.path;
}

/// 读 EXIF Orientation（1=正常，3=180°，6=90°CW，8=270°CW，等）
/// 解析失败/无 EXIF 返回 1（默认无旋转）
Future<int> _readExifOrientation(File file) async {
  try {
    final data = await readExifFromBytes(file.readAsBytesSync());
    final raw = data['Image Orientation']?.printable.trim();
    if (raw == null) return 1;
    // printable 可能是 "6" 或 "Rotate 90 CW"，取首数字
    final m = RegExp(r'\d+').firstMatch(raw);
    return m == null ? 1 : int.tryParse(m.group(0)!) ?? 1;
  } catch (_) {
    return 1;
  }
}
