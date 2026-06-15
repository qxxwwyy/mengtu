// test_helpers.dart — 测试辅助工具
import 'dart:io';
import 'package:drift/native.dart';
import 'package:image/image.dart' as img;
import 'package:mengtu/services/database/app_database.dart';

/// 创建内存数据库（测试用，每次都是全新空库）
AppDatabase createTestDatabase() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

/// 创建临时目录
Future<Directory> createTempDir(String prefix) async {
  return Directory.systemTemp.createTemp('mengtu_test_$prefix');
}

/// 清理临时目录
Future<void> cleanupDir(Directory dir) async {
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

/// 生成测试用纯色图片文件（指定宽高和 RGB），返回文件路径
String generateSolidImageFile(
  String path, {
  int width = 100,
  int height = 100,
  int r = 128,
  int g = 128,
  int b = 128,
}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
  return path;
}

/// 生成测试用渐变图片（从黑到白的横向灰度渐变）
String generateGradientImageFile(
  String path, {
  int width = 256,
  int height = 100,
}) {
  final image = img.Image(width: width, height: height);
  for (var x = 0; x < width; x++) {
    final v = (x / (width - 1) * 255).round().clamp(0, 255);
    for (var y = 0; y < height; y++) {
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
  return path;
}
