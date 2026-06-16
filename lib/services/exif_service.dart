// exif_service.dart — EXIF 解析工具（纯函数，可在 Isolate 内调用）
//
// 从 JPEG 字节提取核心拍摄参数，返回 JSON 字符串供 Photos.exifJson 列存储。
// 设计为纯函数 + 无 Flutter 依赖，便于在 _processPhotoIsolate 内直接调用。
// EXIF 缺失或解析异常时返回空 JSON '{}'（而非抛异常，避免阻断导入）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:exif/exif.dart';

import '../models/exif_info.dart';

/// 从图片字节解析 EXIF 拍摄参数，返回 JSON 字符串
/// 无 EXIF 或解析失败时返回 null（让 DB 存 null，与"未解析过"区分）
///
/// 异步：readExifFromBytes 返回 Future，在 Isolate 内 await 即可（非 UI 线程，无阻塞风险）
Future<String?> extractExifJson(Uint8List bytes) async {
  try {
    final data = await readExifFromBytes(bytes);
    if (data.isEmpty) return null;

    String? read(String tag) => data[tag]?.printable.trim();

    // EXIF rational 值形如 "1/250"，转 double
    double? parseRational(String? raw) {
      if (raw == null) return null;
      final parts = raw.split('/');
      if (parts.length == 2) {
        final num = double.tryParse(parts[0].trim());
        final den = double.tryParse(parts[1].trim());
        if (num != null && den != null && den != 0) return num / den;
      }
      return double.tryParse(raw);
    }

    int? parseInt(String? raw) {
      if (raw == null) return null;
      // exif 包对数组类型（如 ISOSpeedRatings 是 SHORT/LONG 数组）的 printable
      // 可能输出 "[200]" 形式，需剥离方括号后解析
      final stripped = raw.replaceAll(RegExp(r'[\[\]]'), '').trim();
      return int.tryParse(stripped);
    }

    // EXIF DateTimeOriginal 格式 "YYYY:MM:DD HH:MM:SS"
    DateTime? parseTakenAt(String? raw) {
      if (raw == null) return null;
      if (raw.length >= 19 && raw[4] == ':') {
        final normalized =
            '${raw.substring(0, 4)}-${raw.substring(5, 7)}-${raw.substring(8, 10)}'
            ' ${raw.substring(11)}';
        return DateTime.tryParse(normalized);
      }
      return DateTime.tryParse(raw);
    }

    final takenAt = parseTakenAt(
        read('EXIF DateTimeOriginal') ?? read('Image DateTime'));
    final cameraMake = read('Image Make');
    final cameraModel = read('Image Model');
    final lensModel = read('EXIF LensModel') ?? read('Image LensModel');
    final fNumber = parseRational(read('EXIF FNumber'));
    final exposureTime = parseRational(read('EXIF ExposureTime'));
    final iso = parseInt(read('EXIF ISOSpeedRatings') ??
        read('EXIF PhotographicSensitivity'));
    final focalLength = parseRational(read('EXIF FocalLength'));

    final info = ExifInfo(
      takenAt: takenAt,
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      lensModel: lensModel,
      fNumber: fNumber,
      exposureTime: exposureTime,
      iso: iso,
      focalLength: focalLength,
    );

    if (info.isEmpty) return null;
    return jsonEncode(info.toJson());
  } catch (_) {
    // EXIF 解析失败不应阻断导入；返回 null（DB 存 null，UI 显示"无拍摄参数"）
    return null;
  }
}
