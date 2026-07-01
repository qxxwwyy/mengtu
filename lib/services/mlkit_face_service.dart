// mlkit_face_service.dart — Google ML Kit 人脸检测服务（v6.1）
//
// 替代 BlazeFace short/full 作为主检测链：ML Kit 的 face-detection bundled 模型
// 不依赖 Google Play Services，且 minFaceSize=0.15 对大头照/小脸召回显著优于
// BlazeFace short_range（128 输入对小脸分辨率不足）。
//
// 本服务在【主 isolate】运行（ML Kit 走 platform channel，不能在 compute() 内用），
// 仅返回主脸 bbox（归一化 0~1）+ 置信度。bbox 交给 face_service.dart 的 Isolate
// 继续跑 Face Mesh（468 landmarks）算 STI/FLC + ROI 肤色统计。
//
// 坐标系对齐（v6.1 review 修复，关键）：
// - ML Kit InputImage.fromFilePath 在原生侧**应用 EXIF 旋转**，boundingBox 在
//   【旋转后图像像素】空间。
// - 但 fromFilePath 的 metadata.size 恒为 null（google_mlkit_commons 0.11.1 源码
//   确认），不能用 metadata 拿旋转后尺寸。
// - image 包 decodeImage 给的是【存储尺寸未旋转】。
// - 因此必须读 EXIF Orientation，对 90°/270° 旋转的照片：
//   (a) 显示尺寸宽高互换（用于 overlay letterbox）
//   (b) bbox 的归一化用旋转后尺寸（= 存储尺寸互换）
// - 这样 detectedFace 的归一化 bbox 始终相对【显示后图像】（与 Flutter Image.file
//   渲染、FaceBBoxOverlay 一致），下游 mesh/ROI 也基于同一空间。
//
// 参考：Google_MLKit_FaceDetection_Flutter_部署指南.md（§五/§十）
import 'dart:io';
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_service.dart' show DetectedFace;

/// v6.1：主脸检测结果（bbox + 显示尺寸）
///
/// bbox 归一化到【显示后图像】（EXIF 旋转已应用）。displayW/H 是显示尺寸，
/// 供 overlay 算 letterbox（与 Flutter Image.file 渲染空间一致）。
@immutable
class FaceDetection {
  final DetectedFace? face;
  final int displayWidth;
  final int displayHeight;

  const FaceDetection(this.face, this.displayWidth, this.displayHeight);
}

/// 全局单例 FaceDetector（懒加载，复用避免反复初始化）
FaceDetector? _singletonDetector;

/// EXIF Orientation 值 → 是否需要宽高互换（90°/270° 旋转）
bool _orientationSwapsDimensions(int orientation) =>
    orientation == 5 || orientation == 6 || orientation == 7 || orientation == 8;

/// v6.1：用 Google ML Kit 检测主脸，返回相对【显示后图像】的归一化 bbox（0~1）
///
/// [imagePath] 照片绝对路径。返回 [FaceDetection]（含 bbox + 显示尺寸），无脸时
/// face 为 null 但 displayWidth/Height 仍有值（供 overlay 算 letterbox）。
///
/// 坐标系：bbox 归一化到【显示后图像】（EXIF 旋转已应用），与 Flutter Image.file
/// 渲染空间一致。返回的 displayWidth/Height 是显示尺寸，供 overlay 算 letterbox。
Future<FaceDetection> detectPrimaryFaceWithMlKit(String imagePath) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    return const FaceDetection(null, 0, 0);
  }

  // 读存储尺寸（image 包，未旋转）
  final (storeW, storeH) = _readStoredSize(file);
  if (storeW <= 0 || storeH <= 0) {
    return const FaceDetection(null, 0, 0);
  }

  // 读 EXIF Orientation，决定显示尺寸（是否宽高互换）
  final orientation = await _readExifOrientation(file);
  final swap = _orientationSwapsDimensions(orientation);
  final displayW = swap ? storeH : storeW;
  final displayH = swap ? storeW : storeH;

  final detector = _getDetector();
  try {
    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await detector.processImage(inputImage);
    if (faces.isEmpty) return FaceDetection(null, displayW, displayH);
    DetectedFace? best;
    for (final f in faces) {
      final box = f.boundingBox;
      final face = DetectedFace(
        left: (box.left / displayW).clamp(0.0, 1.0),
        top: (box.top / displayH).clamp(0.0, 1.0),
        right: (box.right / displayW).clamp(0.0, 1.0),
        bottom: (box.bottom / displayH).clamp(0.0, 1.0),
        confidence: 1.0,
      );
      if (best == null || face.area > best.area) {
        best = face;
      }
    }
    return FaceDetection(best, displayW, displayH);
  } catch (_) {
    // platform channel 异常（如国产 ROM 缺 ML Kit 依赖）→ 返回 null，
    // 调用方回退到 BlazeFace Isolate 路径
    return FaceDetection(null, displayW, displayH);
  }
}

/// 释放检测器（应用退出时调用，避免内存泄漏；指南§十一问题7）
void disposeMlKitDetector() {
  _singletonDetector?.close();
  _singletonDetector = null;
}

/// 读图像【存储尺寸】（image 包 decode，未应用 EXIF 旋转）
(int, int) _readStoredSize(File file) {
  try {
    final decoded = img.decodeImage(file.readAsBytesSync());
    if (decoded == null) return (0, 0);
    return (decoded.width, decoded.height);
  } catch (_) {
    return (0, 0);
  }
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

FaceDetector _getDetector() {
  if (_singletonDetector != null) return _singletonDetector!;
  // 配置（指南§十场景A：静态图准确模式）
  final options = FaceDetectorOptions(
    enableLandmarks: false, // 本服务只要 bbox；landmarks 由 Face Mesh 算
    enableContours: false, // 轮廓慢（+30ms），肤色 ROI 不需要
    enableClassification: false, // 不需要微笑/睁眼概率
    enableTracking: false, // 静态图片无需追踪
    performanceMode: FaceDetectorMode.accurate, // 准确模式（静态图可接受 ~50ms）
    minFaceSize: 0.15, // 最小人脸占比 15%（指南§十场景A推荐，抓大头照）
  );
  _singletonDetector = FaceDetector(options: options);
  return _singletonDetector!;
}
