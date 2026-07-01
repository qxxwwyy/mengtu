// scrfd_ncnn.dart — SCRFD 人脸检测 NCNN Flutter FFI 插件（v7.0）
//
// 纯 FFI 调用 C ABI（scrfd_api.h），不经 method channel。CPU 推理，无 Vulkan。
//
// 用法：
//   final scrfd = ScrfdNcnn();
//   await scrfd.init(paramPath, binPath);   // 返回 0 成功
//   final faces = scrfd.detect(bgrBytes, w, h);  // BGR Uint8List
//   scrfd.destroy();
//
// 模型加载约定：NCNN 无法直读 Android assets，必须先复制到文件系统再传路径。
// 坐标约定：detect 输出在【输入图原始像素】空间（C++ 已 rescale 回原图，非 640-space），
// 调用方按需归一化到 0~1。
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// SCRFD 检测到的单张人脸
class ScrfdFace {
  /// bbox 左上角 x（输入图像素）
  final double x;

  /// bbox 左上角 y（输入图像素）
  final double y;

  /// bbox 宽（输入图像素）
  final double w;

  /// bbox 高（输入图像素）
  final double h;

  /// 置信度 0~1
  final double score;

  /// 5 个关键点：[(左眼x,y), (右眼x,y), (鼻尖x,y), (右嘴角x,y), (左嘴角x,y)]
  ///
  /// 顺序与 InsightFace SCRFD 一致。坐标在输入图像素空间。
  final List<({double x, double y})> landmarks;

  const ScrfdFace({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.score,
    required this.landmarks,
  });

  double get area => w * h;

  @override
  String toString() =>
      'ScrfdFace(bbox=[$x,$y,$w,$h] score=${score.toStringAsFixed(3)} '
      'kp=${landmarks.length})';
}

// ===== C ABI 绑定 =====

typedef _InitC = Int32 Function(Pointer<Utf8> paramPath, Pointer<Utf8> binPath);
typedef _InitDart = int Function(Pointer<Utf8> paramPath, Pointer<Utf8> binPath);

typedef _DestroyC = Void Function();
typedef _DestroyDart = void Function();

typedef _DetectC = Int32 Function(
    Pointer<Uint8> rgbaData, Int32 width, Int32 height, Int32 stride,
    Pointer<Float> results, Int32 maxResults);
typedef _DetectDart = int Function(
    Pointer<Uint8> rgbaData, int width, int height, int stride,
    Pointer<Float> results, int maxResults);

typedef _SetScoreThreshC = Void Function(Float);
typedef _SetScoreThreshDart = void Function(double);

typedef _SetNmsThreshC = Void Function(Float);
typedef _SetNmsThreshDart = void Function(double);

typedef _SetInputSizeC = Void Function(Int32);
typedef _SetInputSizeDart = void Function(int);

typedef _SetNumThreadsC = Void Function(Int32);
typedef _SetNumThreadsDart = void Function(int);

typedef _VersionC = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

class _ScrfdBindings {
  late final _InitDart init;
  late final _DestroyDart destroy;
  late final _DetectDart detect;
  late final _SetScoreThreshDart setScoreThreshold;
  late final _SetNmsThreshDart setNmsThreshold;
  late final _SetInputSizeDart setInputSize;
  late final _SetNumThreadsDart setNumThreads;
  late final _VersionDart version;

  _ScrfdBindings() {
    final dylib = Platform.isAndroid
        ? DynamicLibrary.open('libscrfd_ncnn.so')
        : throw UnsupportedError('SCRFD NCNN 仅支持 Android');
    init = dylib.lookupFunction<_InitC, _InitDart>('scrfd_init');
    destroy = dylib.lookupFunction<_DestroyC, _DestroyDart>('scrfd_destroy');
    detect = dylib.lookupFunction<_DetectC, _DetectDart>('scrfd_detect');
    setScoreThreshold =
        dylib.lookupFunction<_SetScoreThreshC, _SetScoreThreshDart>(
            'scrfd_set_score_threshold');
    setNmsThreshold =
        dylib.lookupFunction<_SetNmsThreshC, _SetNmsThreshDart>(
            'scrfd_set_nms_threshold');
    setInputSize = dylib.lookupFunction<_SetInputSizeC, _SetInputSizeDart>(
        'scrfd_set_input_size');
    setNumThreads = dylib.lookupFunction<_SetNumThreadsC, _SetNumThreadsDart>(
        'scrfd_set_num_threads');
    version = dylib.lookupFunction<_VersionC, _VersionDart>('scrfd_version');
  }
}

/// SCRFD NCNN 检测器
class ScrfdNcnn {
  static const int _maxFaces = 100; // 单图最多检测人脸数
  static const int _floatsPerFace = 15; // x,y,w,h,score + 5×(kx,ky)

  final _ScrfdBindings _bindings = _ScrfdBindings();
  bool _initialized = false;

  /// 初始化：加载 .param / .bin（文件系统路径，非 asset）
  ///
  /// 返回 0 成功，非 0 失败（模型文件缺失/格式错）。
  /// 可重复调用（C 端会先 destroy 旧实例）。
  Future<int> init(String paramPath, String binPath) async {
    final paramPtr = paramPath.toNativeUtf8();
    final binPtr = binPath.toNativeUtf8();
    try {
      final ret = _bindings.init(paramPtr, binPtr);
      _initialized = (ret == 0);
      return ret;
    } finally {
      calloc.free(paramPtr);
      calloc.free(binPtr);
    }
  }

  bool get isInitialized => _initialized;

  /// 版本信息（含 NCNN + SCRFD 版本）
  String get version {
    final ptr = _bindings.version();
    return ptr.toDartString();
  }

  /// 设置置信度阈值（默认 0.5）
  void setScoreThreshold(double threshold) =>
      _bindings.setScoreThreshold(threshold);

  /// 设置 NMS 阈值（默认 0.45）
  void setNmsThreshold(double threshold) =>
      _bindings.setNmsThreshold(threshold);

  /// 设置输入尺寸（默认 640，可降 480/320 提速）
  void setInputSize(int size) => _bindings.setInputSize(size);

  /// 设置推理线程数（默认 4）
  void setNumThreads(int threads) => _bindings.setNumThreads(threads);

  /// 检测人脸
  ///
  /// 检测人脸
  ///
  /// [rgbaData] RGBA 像素字节（width×height×4，无 padding）。
  /// 返回人脸列表。
  List<ScrfdFace> detect(Uint8List rgbaData, int width, int height) {
    if (!_initialized) {
      throw StateError('SCRFD 未初始化！请先调用 init()');
    }
    final results = calloc<Float>(_maxFaces * _floatsPerFace);
    try {
      // 把 Uint8List 数据拷进 native 内存（detect 直接读指针）
      final dataPtr = calloc<Uint8>(rgbaData.length);
      try {
        dataPtr.asTypedList(rgbaData.length).setAll(0, rgbaData);
        final count = _bindings.detect(
          dataPtr,
          width,
          height,
          width * 4, // stride = width * 4（RGBA，无 padding）
          results,
          _maxFaces,
        );
        final faces = <ScrfdFace>[];
        for (var i = 0; i < count; i++) {
          final base = i * _floatsPerFace;
          final lm = <({double x, double y})>[];
          for (var k = 0; k < 5; k++) {
            lm.add((
              x: results[base + 5 + k * 2],
              y: results[base + 5 + k * 2 + 1],
            ));
          }
          faces.add(ScrfdFace(
            x: results[base + 0],
            y: results[base + 1],
            w: results[base + 2],
            h: results[base + 3],
            score: results[base + 4],
            landmarks: lm,
          ));
        }
        return faces;
      } finally {
        calloc.free(dataPtr);
      }
    } finally {
      calloc.free(results);
    }
  }

  /// 释放 native 资源（删全局 Detector）。dispose 后不可再 detect。
  void destroy() {
    if (_initialized) {
      _bindings.destroy();
      _initialized = false;
    }
  }
}
