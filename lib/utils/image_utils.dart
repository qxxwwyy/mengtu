// image_utils.dart — 降采样、缩略图生成
//
// 注意：这些函数执行同步 I/O + 全量解码，阻塞主线程。
// 调用方必须通过 compute() 在 Isolate 中执行，或在测试中直接调用。
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 生成缩略图（长边 360px），返回 JPEG bytes
@visibleForTesting
Uint8List generateThumbnailBytes(String originalPath, {int maxSize = 360}) {
  final bytes = File(originalPath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('Image decode failed: $originalPath');
  }

  final w = decoded.width;
  final h = decoded.height;
  final longestSide = w > h ? w : h;

  if (longestSide <= maxSize) {
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 85));
  }

  final scale = maxSize / longestSide;
  final thumb = img.copyResize(
    decoded,
    width: (w * scale).round(),
    height: (h * scale).round(),
    interpolation: img.Interpolation.linear,
  );

  return Uint8List.fromList(img.encodeJpg(thumb, quality: 85));
}

/// 获取图片宽高
@visibleForTesting
({int width, int height})? getImageDimensions(String path) {
  final bytes = File(path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return (width: decoded.width, height: decoded.height);
}
