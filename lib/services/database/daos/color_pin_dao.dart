// color_pin_dao.dart — 取色点数据访问对象
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'color_pin_dao.g.dart';

/// 取色点 DAO
@DriftAccessor(tables: [ColorPins])
class ColorPinDao extends DatabaseAccessor<AppDatabase>
    with _$ColorPinDaoMixin {
  ColorPinDao(super.db);

  /// 按照片 ID 查询取色点（按创建时间排序）
  Future<List<ColorPin>> getPinsByPhotoId(String photoId) {
    return (select(colorPins)
          ..where((p) => p.photoId.equals(photoId))
          ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
        .get();
  }

  /// 监听照片的取色点变化
  Stream<List<ColorPin>> watchPinsByPhotoId(String photoId) {
    return (select(colorPins)
          ..where((p) => p.photoId.equals(photoId))
          ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
        .watch();
  }

  /// 添加取色点
  Future<int> insertPin(ColorPinsCompanion pin) {
    return into(colorPins).insert(pin);
  }

  /// 删除取色点
  Future<int> deletePin(String pinId) {
    return (delete(colorPins)..where((p) => p.id.equals(pinId))).go();
  }

  /// 删除照片的所有取色点
  Future<int> deletePinsByPhotoId(String photoId) {
    return (delete(colorPins)..where((p) => p.photoId.equals(photoId))).go();
  }
}
