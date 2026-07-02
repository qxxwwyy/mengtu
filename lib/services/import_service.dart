// import_service.dart — 批量导入、去重、缩略图生成
import 'dart:io';
import 'dart:ui' as ui;
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
import 'tone_service.dart' show analyzeTone, computeAdvancedMetrics;
import '../models/advanced_portrait_metrics.dart' show AdvancedPortraitMetrics;
import '../models/tone_result.dart' show HistogramData, ToneResult;

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

/// Isolate 元数据解析输出结果（不解码像素，防 48MP OOM）
class _PhotoMetadataResult {
  final String hash;
  final int width;
  final int height;
  final String? exifJson;

  _PhotoMetadataResult({
    required this.hash,
    required this.width,
    required this.height,
    this.exifJson,
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

  /// v3.5：测试用工厂（绕开 path_provider platform channel）
  ///
  /// [precomputeAnalysisForPhotos] 不使用 `_thumbnailsDir`，仅算分析缓存，
  /// 因此测试可注入任意临时目录，无需 platform channel 初始化。
  @visibleForTesting
  ImportService.forTesting(this._db, this._thumbnailsDir);

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
        // 1. 在 Isolate 中异步提取元数据（Hash, EXIF, 仅读头部获取尺寸）。不解码 48MP 像素，使用极低内存
        final meta = await compute(
          _parseMetadataIsolate,
          srcPath,
        );

        // 2. 去重检查
        final existing = await _db.photoDao.getPhotoByHash(meta.hash);
        if (existing != null) {
          importedPhotoIds.add(existing.id);
          skipped++;
          onProgress?.call(i + 1, total);
          continue;
        }

        // 3. 异步高效生成缩略图（主 Isolate 使用 dart:ui 的 native 硬件解码，按需下采样到 targetWidth，防止 OOM）
        final thumbId = _uuid.v4();
        final thumbPath = p.join(_thumbnailsDir, 'thumb_$thumbId.jpg');
        
        try {
          final fileBytes = await File(srcPath).readAsBytes();
          final codec = await ui.instantiateImageCodec(fileBytes, targetWidth: 360);
          final frame = await codec.getNextFrame();
          final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            await File(thumbPath).writeAsBytes(byteData.buffer.asUint8List());
          } else {
            throw Exception('Native encoding returned null');
          }
        } catch (e) {
          debugPrint('Native thumbnail generation failed for $srcPath: $e. Falling back to Isolate.');
          // 降级使用 Isolate 纯 Dart 备份方案，确保测试环境下或不支持平台的鲁棒性
          final result = await compute(
            _generateThumbnailIsolate,
            (srcPath, _thumbnailsDir),
          );
          // 覆盖拷贝到预设的 thumbPath，保持数据库路径一致
          await File(result).copy(thumbPath);
          try {
            await File(result).delete();
          } catch (_) {}
        }

        // 4. 不复制照片，直接使用原始路径（节省存储空间）
        final fileName = p.basename(srcPath);
        final photoId = _uuid.v4();

        try {
          // 5. 写入数据库（filePath = 原始路径，不复制）
          final fileStat = await File(srcPath).stat();
          await _db.photoDao.insertPhoto(PhotosCompanion.insert(
            id: photoId,
            filePath: srcPath, // 直接引用原始文件路径
            thumbnailPath: thumbPath,
            fileName: fileName,
            fileSize: Value(fileStat.size),
            fileHash: Value(meta.hash),
            width: Value(meta.width),
            height: Value(meta.height),
            exifJson: Value(meta.exifJson), // EXIF 拍摄参数（v2.0）
          ));

          importedPhotoIds.add(photoId);
          success++;
        } catch (e) {
          // 导入失败，清理缩略图
          final thumbFile = File(thumbPath);
          if (await thumbFile.exists()) await thumbFile.delete();

          // 唯一约束冲突（并发导入竞态的最后防线）：
          // 按 hash 重查已有记录，计入 importedPhotoIds + skipped，而非 rethrow 计 failed
          if (e.toString().contains('UNIQUE constraint')) {
            final existing = await _db.photoDao.getPhotoByHash(meta.hash);
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
      await _db.colorPinDao.deletePinsByPhotoId(photoId);
      await _db.albumDao.removePhotoFromAllAlbums(photoId);
      await _db.planDao.removePhotoFromAllPlans(photoId);
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

    final thumbId = _uuid.v4();
    final thumbPath = p.join(_thumbnailsDir, 'thumb_$thumbId.jpg');

    try {
      // 优先使用 Native 硬件解码，极速且低内存
      final fileBytes = await File(photo.filePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(fileBytes, targetWidth: 360);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        await File(thumbPath).writeAsBytes(byteData.buffer.asUint8List());
      } else {
        throw Exception('toByteData returned null');
      }
      await _db.photoDao.updateThumbnailPath(photoId, thumbPath);
      return thumbPath;
    } catch (e) {
      debugPrint('Native thumbnail regeneration failed: $photoId, fallback to Isolate: $e');
      try {
        final result = await compute(
          _generateThumbnailIsolate,
          (photo.filePath, _thumbnailsDir),
        );
        await File(result).copy(thumbPath);
        try {
          await File(result).delete();
        } catch (_) {}
        await _db.photoDao.updateThumbnailPath(photoId, thumbPath);
        return thumbPath;
      } catch (e2) {
        debugPrint('Fallback thumbnail regeneration failed: $e2');
        return '';
      }
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

        // 1. 直方图（若未缓存，优先使用缩略图以极速解析直方图，防止 48MP 大图 OOM，若不存在退回原图）
        if (photo.rgbHistogram == null || photo.lumHistogram == null) {
          final useThumb = photo.thumbnailPath.isNotEmpty && File(photo.thumbnailPath).existsSync();
          final targetPath = useThumb ? photo.thumbnailPath : photo.filePath;
          final hist = await computeHistogram(targetPath);
          final combined = hist.toBytes();
          await _db.photoDao.updateHistogramCache(
            photoId,
            rgbHistogram: Uint8List.fromList(combined.sublist(0, 1536)),
            lumHistogram: Uint8List.fromList(combined.sublist(1536, 2048)),
            hueHistogram: Uint8List.fromList(combined.sublist(2048, 2768)),
          );
        }

        // 2. 影调（若未缓存，含 5 段 + entropy/rms）
        var current = await _db.photoDao.getPhotoById(photoId);
        if (current == null) {
          failed++;
          continue;
        }
        if (current.toneJson == null || current.toneJson!.isEmpty) {
          if (current.rgbHistogram != null && current.lumHistogram != null) {
            final combined = current.hueHistogram != null
                ? Uint8List.fromList([
                    ...current.rgbHistogram!,
                    ...current.lumHistogram!,
                    ...current.hueHistogram!
                  ])
                : Uint8List.fromList(
                    [...current.rgbHistogram!, ...current.lumHistogram!]);
            final hist = HistogramData.fromBytes(combined);
            final tone = analyzeTone(hist.lum);
            await _db.photoDao.updateToneCache(photoId, tone.toJsonString());
            current = await _db.photoDao.getPhotoById(photoId);
            if (current == null) {
              failed++;
              continue;
            }
          }
        }

        // 3. v3.5：advanced 指标（black/white/ten_tonal，纯直方图）
        final alreadyHasAdvanced =
            AdvancedPortraitMetrics.fromJsonString(current.toneJson) != null;
        if (!alreadyHasAdvanced &&
            current.rgbHistogram != null &&
            current.lumHistogram != null &&
            current.toneJson != null) {
          final combined = current.hueHistogram != null
              ? Uint8List.fromList([
                  ...current.rgbHistogram!,
                  ...current.lumHistogram!,
                  ...current.hueHistogram!
                ])
              : Uint8List.fromList(
                  [...current.rgbHistogram!, ...current.lumHistogram!]);
          final hist = HistogramData.fromBytes(combined);
          final toneResult = ToneResult.fromJsonString(current.toneJson!);
          if (toneResult != null) {
            final adv = computeAdvancedMetrics(
              lumHist: hist.lum,
              toneKey: toneResult.toneKey,
              toneRange: toneResult.toneRange,
            );
            final mergedJson = AdvancedPortraitMetrics.mergeIntoToneJson(current.toneJson!, adv);
            await _db.photoDao.updateToneCache(photoId, mergedJson);
          }
        }

        success++;
      } catch (e) {
        debugPrint('Precompute failed for $photoId: $e');
        failed++;
      }
    }
    return (success: success, failed: failed);
  }
}

/// Isolate 入口：解析图像的元数据而不需要完整解码像素（SHA256, EXIF, 以及利用 decodeInfo 读取真实宽高）
Future<_PhotoMetadataResult> _parseMetadataIsolate(String srcPath) async {
  final bytes = File(srcPath).readAsBytesSync();

  // 1. SHA256
  final hash = sha256.convert(bytes).toString();

  // 2. EXIF
  final exifJson = await extractExifJson(bytes);

  // 3. 使用 startDecode 读取高像素原图的尺寸（不解码像素，极速且极低内存占用，防止 48MP OOM）
  int width = 0;
  int height = 0;
  try {
    final info = img.JpegDecoder().startDecode(bytes);
    if (info != null) {
      width = info.width;
      height = info.height;
    }
  } catch (_) {
    try {
      final decoder = img.findDecoderForData(bytes);
      if (decoder != null) {
        final info = decoder.startDecode(bytes);
        if (info != null) {
          width = info.width;
          height = info.height;
        }
      }
    } catch (_) {}
  }

  if (width == 0 || height == 0) {
    throw FormatException('无法解析图片尺寸: $srcPath');
  }

  return _PhotoMetadataResult(
    hash: hash,
    width: width,
    height: height,
    exifJson: exifJson,
  );
}

/// Isolate 入口：仅读取 EXIF
Future<String?> _readExifIsolate(String srcPath) async {
  final bytes = File(srcPath).readAsBytesSync();
  return extractExifJson(bytes);
}

/// Isolate 入口：仅生成缩略图（测试环境备份或降级方案）
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
