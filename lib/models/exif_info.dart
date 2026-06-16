// exif_info.dart — EXIF 拍摄参数模型（强类型 + JSON 序列化 + 格式化辅助）
//
// Photos.exifJson 列存此类的 JSON。导入时由 Isolate 解析 JPEG EXIF 段写入。
// UI 层通过 ExifInfo 的格式化方法直接渲染（f/2.8、1/250s、ISO 200 等）。

import 'dart:convert';

/// EXIF 拍摄参数快照
/// 所有字段均可为 null（截图/PNG/无 EXIF 的图片正常导入不报错）
class ExifInfo {
  /// 拍摄时间（EXIF DateTimeOriginal）
  final DateTime? takenAt;

  /// 相机制造商（如 Sony / Canon / Nikon）
  final String? cameraMake;

  /// 相机型号（如 ILCE-7M4 / EOS R5）
  final String? cameraModel;

  /// 镜头型号（如 FE 85mm F1.4 GM）
  final String? lensModel;

  /// 光圈值（F-number，如 2.8）
  final double? fNumber;

  /// 快门速度（曝光时间，秒）。如 1/250 存为 0.004
  final double? exposureTime;

  /// ISO 感光度（如 200）
  final int? iso;

  /// 焦距（mm，如 85）
  final double? focalLength;

  const ExifInfo({
    this.takenAt,
    this.cameraMake,
    this.cameraModel,
    this.lensModel,
    this.fNumber,
    this.exposureTime,
    this.iso,
    this.focalLength,
  });

  factory ExifInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parseTakenAt(dynamic v) {
      if (v == null) return null;
      if (v is String) {
        // 优先尝试 ISO8601（dart 序列化的格式）
        final iso = DateTime.tryParse(v);
        if (iso != null) return iso;
        // 兼容 EXIF 原始格式 "YYYY:MM:DD HH:MM:SS"
        if (v.length >= 19 && v[4] == ':') {
          final normalized =
              '${v.substring(0, 4)}-${v.substring(5, 7)}-${v.substring(8, 10)}'
              '${v.substring(10)}';
          return DateTime.tryParse(normalized);
        }
      }
      return null;
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return ExifInfo(
      takenAt: parseTakenAt(json['takenAt']),
      cameraMake: json['cameraMake'] as String?,
      cameraModel: json['cameraModel'] as String?,
      lensModel: json['lensModel'] as String?,
      fNumber: parseDouble(json['fNumber']),
      exposureTime: parseDouble(json['exposureTime']),
      iso: parseInt(json['iso']),
      focalLength: parseDouble(json['focalLength']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (takenAt != null) 'takenAt': takenAt!.toIso8601String(),
        if (cameraMake != null) 'cameraMake': cameraMake,
        if (cameraModel != null) 'cameraModel': cameraModel,
        if (lensModel != null) 'lensModel': lensModel,
        if (fNumber != null) 'fNumber': fNumber,
        if (exposureTime != null) 'exposureTime': exposureTime,
        if (iso != null) 'iso': iso,
        if (focalLength != null) 'focalLength': focalLength,
      };

  /// 序列化为 DB 列存储的 JSON 字符串
  String toJsonString() => jsonEncode(toJson());

  /// 从 DB 列的 JSON 字符串解析；null 或格式异常返回 null（provider 兜底重算无意义，直接无 EXIF）
  static ExifInfo? fromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return null;
      return ExifInfo.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 是否完全没有拍摄参数（用于 UI 判断"是否显示重新读取"按钮）
  bool get isEmpty =>
      takenAt == null &&
      cameraMake == null &&
      cameraModel == null &&
      lensModel == null &&
      fNumber == null &&
      exposureTime == null &&
      iso == null &&
      focalLength == null;

  // ============ 格式化辅助方法（UI 直接调用） ============

  /// 相机显示名（合并 Make + Model，如 "Sony ILCE-7M4"）
  /// 部分厂商 Model 已含 Make 前缀，做去重
  String? get cameraDisplay {
    final make = cameraMake?.trim();
    final model = cameraModel?.trim();
    if (make == null && model == null) return null;
    if (make == null) return model;
    if (model == null) return make;
    // 厂商名常以全称出现（NIKON CORPORATION），取首词匹配
    final makeFirstWord = make.split(' ').first;
    if (model.toUpperCase().startsWith(makeFirstWord.toUpperCase())) {
      return model;
    }
    return '$make $model';
  }

  /// 光圈格式化：2.8 → "f/2.8"
  String? get fNumberDisplay =>
      fNumber == null ? null : 'f/${_trimNumber(fNumber!)}';

  /// 快门格式化：< 1s 显示分数（1/250s），≥ 1s 显示小数（2.5s）
  String? get exposureTimeDisplay {
    final t = exposureTime;
    if (t == null) return null;
    if (t >= 1) return '${_trimNumber(t)}s';
    // 分数：四舍五入到整数分母
    final denom = (1 / t).round();
    if (denom <= 0) return '${_trimNumber(t)}s';
    return '1/$denom s';
  }

  /// ISO 格式化：200 → "ISO 200"
  String? get isoDisplay => iso == null ? null : 'ISO $iso';

  /// 焦距格式化：85 → "85mm"
  String? get focalLengthDisplay =>
      focalLength == null ? null : '${_trimNumber(focalLength!)}mm';

  /// 曝光三元组（快门 + 光圈 + ISO + 焦距）合并为一行
  /// 如 "1/250 s  f/2.8  ISO 200  85mm"
  String get exposureTriple {
    final parts = <String>[
      if (exposureTimeDisplay != null) exposureTimeDisplay!,
      if (fNumberDisplay != null) fNumberDisplay!,
      if (isoDisplay != null) isoDisplay!,
      if (focalLengthDisplay != null) focalLengthDisplay!,
    ];
    return parts.join('  ');
  }

  /// 去掉多余小数位（2.0 → "2"，2.8 → "2.8"）
  static String _trimNumber(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    // 保留 1 位小数（光圈/焦距精度足够）
    return v.toStringAsFixed(1);
  }
}
