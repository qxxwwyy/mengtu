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
import 'exif_service.dart';
import 'histogram_service.dart' show computeHistogram;
import 'tone_service.dart' show analyzeTone;
import '../models/tone_result.dart' show HistogramData;

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
            exifJson: Value(result.exifJson), // EXIF 拍摄参数（v2.0）
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
    // v2.1：标签迁移到相册后，照片不再有标签，removeTagsByPhoto 已移除
    // v3.5：新增风格档案关联清理（gotcha #31：删照片前清所有档案关联）
    await _db.transaction(() async {
      await _db.colorPinDao.deletePinsByPhotoId(photoId);
      await _db.albumDao.removePhotoFromAllAlbums(photoId);
      await _db.planDao.removePhotoFromAllPlans(photoId);
      await _db.styleProfileDao.removePhotoFromAllProfiles(photoId);
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

  /// 为已导入的旧照片补全 EXIF 拍摄参数（exifJson 为 null 时调用）
  /// 仅读取 EXIF 回填 DB，不重新生成缩略图。返回是否成功写入。
  Future<bool> readExifForExistingPhoto(String photoId) async {
    final photo = await _db.photoDao.getPhotoById(photoId);
    if (photo == null) return false;

    try {
      final exifJson = await compute(
        _readExifIsolate,
        photo.filePath,
      );
      await _db.photoDao.updateExifCache(photoId, exifJson);
      return exifJson != null;
    } catch (e) {
      debugPrint('Read EXIF failed: $photoId — $e');
      return false;
    }
  }

  /// v3.5 PR4：批量预计算照片的分析数据（用于档案创建/匹配）
  ///
  /// 现有架构是懒计算（详情页打开才算），档案系统需要全量数据，
  /// 必须在创建档案时主动触发（gotcha #49）。
  ///
  /// 填充 Photos 表的 rgbHistogram/lumHistogram/hueHistogram/toneJson 缓存，
  /// 不填 advanced 键（advanced 的 STI/FLC 依赖 Face Mesh，由详情页按需算）。
  ///
  /// 返回 (success, failed) 计数。
  Future<({int success, int failed})> precomputeAnalysisForPhotos(
      List<String> photoIds) async {
    var success = 0;
    var failed = 0;
    for (final photoId in photoIds) {
      try {
        final photo = await _db.photoDao.getPhotoById(photoId);
        if (photo == null) {
          failed++;
          continue;
        }

        // 1. 直方图（若未缓存）
        if (photo.rgbHistogram == null || photo.lumHistogram == null) {
          final hist = await computeHistogram(photo.filePath);
          final combined = hist.toBytes();
          await _db.photoDao.updateHistogramCache(
            photoId,
            rgbHistogram: Uint8List.fromList(combined.sublist(0, 1536)),
            lumHistogram: Uint8List.fromList(combined.sublist(1536, 2048)),
            hueHistogram: Uint8List.fromList(combined.sublist(2048, 2768)),
          );
        }

        // 2. 影调（若未缓存，含 5 段 + entropy/rms，不含 advanced 键）
        if (photo.toneJson == null || photo.toneJson!.isEmpty) {
          // 重新读 photo 拿到刚写入的直方图缓存
          final fresh = await _db.photoDao.getPhotoById(photoId);
          if (fresh?.rgbHistogram != null && fresh?.lumHistogram != null) {
            final combined = fresh!.hueHistogram != null
                ? Uint8List.fromList(
                    [...fresh.rgbHistogram!, ...fresh.lumHistogram!, ...fresh.hueHistogram!])
                : Uint8List.fromList([...fresh.rgbHistogram!, ...fresh.lumHistogram!]);
            final hist = HistogramData.fromBytes(combined);
            final tone = analyzeTone(hist.lum);
            await _db.photoDao.updateToneCache(photoId, tone.toJsonString());
          }
        }
        success++;
      } catch (e) {
        debugPrint('Precompute failed: $photoId — $e');
        failed++;
      }
    }
    return (success: success, failed: failed);
  }
}

/// Isolate 入口参数
class _PhotoProcessResult {
  final String hash;
  final String thumbPath;
  final int width;
  final int height;
  final String? exifJson; // EXIF 拍摄参数 JSON（v2.0），无 EXIF 时为 null

  _PhotoProcessResult(
      this.hash, this.thumbPath, this.width, this.height, this.exifJson);
}

/// 合并 Isolate：一次读取 → SHA256 → EXIF → 解码 → 缩略图 + 宽高
/// 替代之前 3 个独立 Isolate（hash + thumbnail + dimensions）
/// async：readExifFromBytes 返回 Future，在 Isolate 内 await（非 UI 线程）
Future<_PhotoProcessResult> _processPhotoIsolate((String, String) args) async {
  final (srcPath, thumbDir) = args;
  final bytes = File(srcPath).readAsBytesSync();

  // 1. SHA256（crypto 包）
  final hash = sha256.convert(bytes).toString();

  // 2. EXIF 拍摄参数（在解码前解析，解码失败也不影响 EXIF 提取）
  final exifJson = await extractExifJson(bytes);

  // 3. 解码图片
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    // 解码失败：抛异常，由 importPhotos 外层 catch 捕获并计入 failedFiles
    // 不写缩略图、不返回脏数据（width=0 / 指向不存在的 thumbPath）
    throw FormatException('无法解码图片: $srcPath');
  }

  // 4. 解码成功才生成缩略图 + 真实宽高
  final width = decoded.width;
  final height = decoded.height;
  final thumbId = _uuid.v4();
  final thumbPath = '$thumbDir/thumb_$thumbId.jpg';
  final thumb = img.copyResize(decoded, width: 360);
  final thumbBytes = img.encodeJpg(thumb, quality: 85);
  File(thumbPath).writeAsBytesSync(thumbBytes);

  return _PhotoProcessResult(hash, thumbPath, width, height, exifJson);
}

/// Isolate 入口：仅读取 EXIF（历史照片补全，不生成缩略图）
/// 返回 EXIF JSON 字符串；无 EXIF 或失败返回 null
Future<String?> _readExifIsolate(String srcPath) async {
  final bytes = File(srcPath).readAsBytesSync();
  return extractExifJson(bytes);
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
