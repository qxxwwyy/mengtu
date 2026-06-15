// import_service.dart — 批量导入、去重、缩略图生成
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'database/app_database.dart';

const _uuid = Uuid();

/// 导入结果
class ImportResult {
  final int successCount;
  final int skippedCount;
  final int failedCount;
  final List<String> failedFiles;
  final List<String> importedPhotoIds; // 新导入（含去重命中已有）的照片 ID

  ImportResult({
    required this.successCount,
    required this.skippedCount,
    required this.failedCount,
    required this.failedFiles,
    required this.importedPhotoIds,
  });
}

/// 照片导入服务
class ImportService {
  final AppDatabase _db;
  final String _thumbnailsDir;

  ImportService._(this._db, this._thumbnailsDir);

  /// 初始化（获取应用私有目录）
  static Future<ImportService> create(AppDatabase db) async {
    final appDir = await getApplicationDocumentsDirectory();
    final thumbnailsDir = p.join(appDir.path, 'thumbnails');
    await Directory(thumbnailsDir).create(recursive: true);
    return ImportService._(db, thumbnailsDir);
  }

  /// 批量导入照片
  /// [filePaths] 源文件路径列表
  /// [onProgress] 进度回调（已处理数 / 总数）
  Future<ImportResult> importPhotos(
    List<String> filePaths, {
    void Function(int processed, int total)? onProgress,
  }) async {
    var success = 0;
    var skipped = 0;
    var failed = 0;
    final failedFiles = <String>[];
    final importedPhotoIds = <String>[];

    final total = filePaths.length;
    for (var i = 0; i < filePaths.length; i++) {
      final srcPath = filePaths[i];
      try {
        // 1. 合并计算：hash + 缩略图 + 宽高，单次 Isolate（避免 3 次 I/O）
        final result = await compute(
          _processPhotoIsolate,
          (srcPath, _thumbnailsDir),
        );

        // 2. 去重检查
        final existing = await _db.photoDao.getPhotoByHash(result.hash);
        if (existing != null) {
          // 重复照片，清理刚生成的缩略图，但记录已有 photoId
          final thumbFile = File(result.thumbPath);
          if (await thumbFile.exists()) await thumbFile.delete();
          importedPhotoIds.add(existing.id);
          skipped++;
          onProgress?.call(i + 1, total);
          continue;
        }

        // 3. 不复制照片，直接使用原始路径（节省存储空间）
        final fileName = p.basename(srcPath);
        final photoId = _uuid.v4();

        try {
          // 4. 写入数据库（filePath = 原始路径，不复制）
          final fileStat = await File(srcPath).stat();
          await _db.photoDao.insertPhoto(PhotosCompanion.insert(
            id: photoId,
            filePath: srcPath, // 直接引用原始文件路径
            thumbnailPath: result.thumbPath,
            fileName: fileName,
            fileSize: Value(fileStat.size),
            fileHash: Value(result.hash),
            width: Value(result.width),
            height: Value(result.height),
          ));

          importedPhotoIds.add(photoId);
          success++;
        } catch (e) {
          // 导入失败，清理缩略图
          final thumbFile = File(result.thumbPath);
          if (await thumbFile.exists()) await thumbFile.delete();

          // 唯一约束冲突（并发导入竞态的最后防线）：
          // 按 hash 重查已有记录，计入 importedPhotoIds + skipped，而非 rethrow 计 failed
          if (e.toString().contains('UNIQUE constraint')) {
            final existing = await _db.photoDao.getPhotoByHash(result.hash);
            if (existing != null) {
              importedPhotoIds.add(existing.id);
              skipped++;
              onProgress?.call(i + 1, total);
              continue;
            }
          }
          rethrow;
        }
      } catch (e) {
        debugPrint('Import failed: $srcPath — $e');
        failed++;
        failedFiles.add(srcPath);
      }
      onProgress?.call(i + 1, total);
    }

    return ImportResult(
      successCount: success,
      skippedCount: skipped,
      failedCount: failed,
      failedFiles: failedFiles,
      importedPhotoIds: importedPhotoIds,
    );
  }

  /// 删除照片（缩略图 + 数据库记录 + 标签关联）
  /// 原始照片文件不删除（属于用户系统相册，仅移除引用）
  /// DB 操作包在事务中，确保一致性
  Future<void> deletePhoto(String photoId) async {
    final photo = await _db.photoDao.getPhotoById(photoId);
    if (photo == null) return;

    // DB 操作包在事务中（删关联 + 删记录）
    await _db.transaction(() async {
      await _db.tagDao.removeTagsByPhoto(photoId);
      await _db.colorPinDao.deletePinsByPhotoId(photoId);
      await _db.albumDao.removePhotoFromAllAlbums(photoId);
      await _db.photoDao.deletePhoto(photoId);
    });

    // 只删除应用生成的缩略图，不删除原始照片文件
    final thumb = File(photo.thumbnailPath);
    if (await thumb.exists()) {
      try {
        await thumb.delete();
      } catch (e) {
        debugPrint('Warning: failed to delete thumbnail: $e');
      }
    }
  }

  /// 为单张照片重新生成缩略图（清缓存后 photo_card 按需调用）
  /// 返回新的缩略图路径；失败返回空字符串
  Future<String> regenerateThumbnail(String photoId) async {
    final photo = await _db.photoDao.getPhotoById(photoId);
    if (photo == null) return '';

    try {
      final result = await compute(
        _generateThumbnailIsolate,
        (photo.filePath, _thumbnailsDir),
      );
      // 回填 DB
      await _db.photoDao.updateThumbnailPath(photoId, result);
      return result;
    } catch (e) {
      debugPrint('Regenerate thumbnail failed: $photoId — $e');
      return '';
    }
  }
}

/// Isolate 入口参数
class _PhotoProcessResult {
  final String hash;
  final String thumbPath;
  final int width;
  final int height;

  _PhotoProcessResult(this.hash, this.thumbPath, this.width, this.height);
}

/// 合并 Isolate：一次读取 → SHA256 → 解码 → 缩略图 + 宽高
/// 替代之前 3 个独立 Isolate（hash + thumbnail + dimensions）
_PhotoProcessResult _processPhotoIsolate((String, String) args) {
  final (srcPath, thumbDir) = args;
  final bytes = File(srcPath).readAsBytesSync();

  // 1. SHA256（crypto 包）
  final hash = sha256.convert(bytes).toString();

  // 2. 解码图片
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    // 解码失败：抛异常，由 importPhotos 外层 catch 捕获并计入 failedFiles
    // 不写缩略图、不返回脏数据（width=0 / 指向不存在的 thumbPath）
    throw FormatException('无法解码图片: $srcPath');
  }

  // 3. 解码成功才生成缩略图 + 真实宽高
  final width = decoded.width;
  final height = decoded.height;
  final thumbId = _uuid.v4();
  final thumbPath = '$thumbDir/thumb_$thumbId.jpg';
  final thumb = img.copyResize(decoded, width: 360);
  final thumbBytes = img.encodeJpg(thumb, quality: 85);
  File(thumbPath).writeAsBytesSync(thumbBytes);

  return _PhotoProcessResult(hash, thumbPath, width, height);
}

/// Isolate 入口：仅生成缩略图（用于清缓存后按需重生成）
/// 返回缩略图路径；解码失败抛异常（调用方 catch 后返回空串）
String _generateThumbnailIsolate((String, String) args) {
  final (srcPath, thumbDir) = args;
  final bytes = File(srcPath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw FormatException('无法解码图片: $srcPath');
  }
  final thumbId = _uuid.v4();
  final thumbPath = '$thumbDir/thumb_$thumbId.jpg';
  final thumb = img.copyResize(decoded, width: 360);
  final thumbBytes = img.encodeJpg(thumb, quality: 85);
  File(thumbPath).writeAsBytesSync(thumbBytes);
  return thumbPath;
}
