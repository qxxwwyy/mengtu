// test_helpers.dart — 测试辅助工具
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:mengtu/services/database/app_database.dart';
import 'package:mengtu/providers/database_provider.dart';

/// 创建内存数据库（测试用，每次都是全新空库）
AppDatabase createTestDatabase() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

/// 创建测试用 ProviderContainer（用内存 DB override appDatabaseProvider）
/// 用法：final container = createTestContainer(); ... container.dispose();
/// 注意：用真实内存 DB 而非 mock，更贴近生产行为（skill ③ 推荐真实实现优于 mock）
ProviderContainer createTestContainer({AppDatabase? db}) {
  final database = db ?? createTestDatabase();
  return ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(database),
  ]);
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

// ============ Fixture Builder ============

/// 构建测试用 Photo companion（避免每个测试重复构造）
/// filePath/fileName 是 required（表定义），其余可选
PhotosCompanion buildPhotoCompanion({
  String? id,
  String filePath = '/test/photo.jpg',
  String fileName = 'photo.jpg',
  String thumbnailPath = '/test/thumb.jpg',
  String fileHash = 'testhash',
  int width = 1000,
  int height = 1000,
  int fileSize = 50000,
  String? toneJson,
  String? paletteJson,
}) {
  return PhotosCompanion.insert(
    id: id ?? 'test-photo-${DateTime.now().microsecondsSinceEpoch}',
    filePath: filePath,
    fileName: fileName,
    thumbnailPath: thumbnailPath,
    fileHash: Value(fileHash),
    width: Value(width),
    height: Value(height),
    fileSize: Value(fileSize),
    toneJson: Value(toneJson),
    paletteJson: Value(paletteJson),
  );
}

/// 插入一张测试照片并返回 id
/// 注意：fileHash 默认用 id 派生（保证唯一），避免触发 v6 的唯一约束
Future<String> insertTestPhoto(
  AppDatabase db, {
  String? id,
  String filePath = '/test/photo.jpg',
  String fileName = 'photo.jpg',
  String? fileHash,
}) async {
  final photoId = id ?? 'photo-${DateTime.now().microsecondsSinceEpoch}';
  await db.photoDao.insertPhoto(buildPhotoCompanion(
    id: photoId,
    filePath: filePath,
    fileName: fileName,
    fileHash: fileHash ?? 'hash_$photoId',
  ));
  return photoId;
}

