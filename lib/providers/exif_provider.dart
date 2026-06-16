// exif_provider.dart — EXIF 拍摄参数 Provider + 取色点 Provider
//
// exifInfoProvider：从 Photo.exifJson 列解析为 ExifInfo?（同步，无 Isolate 开销）
// colorPinsProvider：取色点列表流（原 analysis_panel.dart 迁移，因面板组件已废弃）
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exif_info.dart';
import '../services/database/app_database.dart';
import 'database_provider.dart';
import 'photo_provider.dart';

/// 单张照片的 EXIF 拍摄参数（从 DB 列解析，null 表示无 EXIF）
final exifInfoProvider =
    FutureProvider.family<ExifInfo?, String>((ref, photoId) async {
  final photo = await ref.watch(photoByIdProvider(photoId).future);
  return ExifInfo.fromJsonString(photo?.exifJson);
});

/// 取色点列表流（监听 DB 变化自动刷新）
/// 从 analysis_panel.dart 迁移而来（该文件已废弃，逻辑移入 detail_bottom_panel）
final colorPinsProvider =
    StreamProvider.family<List<ColorPin>, String>((ref, photoId) {
  final db = ref.watch(appDatabaseProvider);
  return db.colorPinDao.watchPinsByPhotoId(photoId);
});
