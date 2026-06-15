// tables.dart — drift 表定义（photos, tags, photo_tags, color_pins, albums, album_photos）
import 'package:drift/drift.dart';

/// 照片表
/// 存储照片元信息 + 分析缓存（直方图/色卡/影调）
class Photos extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get filePath => text()(); // 原图路径（应用私有目录）
  TextColumn get thumbnailPath => text()(); // 缩略图路径
  TextColumn get fileName => text()(); // 原始文件名
  IntColumn get fileSize => integer().withDefault(const Constant(0))(); // bytes
  TextColumn get fileHash => text().withDefault(const Constant(''))(); // SHA256
  IntColumn get width => integer().withDefault(const Constant(0))();
  IntColumn get height => integer().withDefault(const Constant(0))();
  DateTimeColumn get importedAt => dateTime().withDefault(currentDateAndTime)();

  // 分析缓存（首次计算后存储，二次打开即时显示）
  // 注意：直方图使用 Uint16List（每 bin 2 字节），详见 tone_result.dart
  BlobColumn get rgbHistogram => blob().nullable()(); // 256×3 bins × 2 bytes = 1536 bytes
  BlobColumn get lumHistogram => blob().nullable()(); // 256 bins × 2 bytes = 512 bytes
  BlobColumn get hueHistogram => blob().nullable()(); // 色相直方图（RC 阶段）
  TextColumn get paletteJson => text().nullable()(); // 色卡数据 JSON
  TextColumn get toneJson => text().nullable()(); // 影调分析 JSON

  @override
  Set<Column> get primaryKey => {id};
}

/// 标签表
class Tags extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()(); // 标签名
  TextColumn get group => text().withDefault(const Constant('custom'))(); // atmosphere/scene/emotion/custom
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 照片-标签关联表（多对多）
class PhotoTags extends Table {
  TextColumn get photoId => text().references(Photos, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {photoId, tagId};
}

/// 取色点表（v1.1.0 新增）
class ColorPins extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get photoId => text().references(Photos, #id)();
  IntColumn get x => integer()(); // 像素坐标 X
  IntColumn get y => integer()(); // 像素坐标 Y
  IntColumn get r => integer()(); // 红色通道 0-255
  IntColumn get g => integer()(); // 绿色通道 0-255
  IntColumn get b => integer()(); // 蓝色通道 0-255
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 相册表（v1.1.0 新增）
class Albums extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()(); // 相册名称
  TextColumn get description => text().withDefault(const Constant(''))(); // 描述
  TextColumn get coverPhotoId => text().nullable()(); // 封面照片 ID
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 相册-照片关联表（v1.1.0 新增）
class AlbumPhotos extends Table {
  TextColumn get albumId => text().references(Albums, #id)();
  TextColumn get photoId => text().references(Photos, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))(); // 排序序号

  @override
  Set<Column> get primaryKey => {albumId, photoId};
}

// ============ v2.0 拍摄策划 ============

/// 拍摄策划表（v2.0 新增）—— 摄影师前期策划的工作台
class ShootingPlans extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get title => text()(); // 策划标题（如"秋日公园人像"）
  TextColumn get theme => text().withDefault(const Constant(''))(); // 主题
  TextColumn get style => text().withDefault(const Constant(''))(); // 风格（如"日系小清新"）
  TextColumn get moodTags => text().withDefault(const Constant('[]'))(); // 情绪标签 JSON 数组
  TextColumn get location => text().withDefault(const Constant(''))(); // 拍摄地点
  DateTimeColumn get plannedDate =>
      dateTime().nullable()(); // 计划拍摄日期
  TextColumn get gearList =>
      text().withDefault(const Constant('[]'))(); // 器材清单 JSON [{lens,note}]
  TextColumn get shotList =>
      text().withDefault(const Constant('[]'))(); // shot list JSON [{desc,done}]
  TextColumn get status =>
      text().withDefault(const Constant('planning'))(); // planning/shooting/completed/archived
  TextColumn get templateId =>
      text().nullable()(); // 来源模板 ID（可复用）
  TextColumn get coverPhotoId =>
      text().nullable()(); // 封面照片（逻辑关联，无外键约束）
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 策划-照片关联表（v2.0 新增）—— 区分参考图(reference)和实拍图(result)
class PlanPhotos extends Table {
  TextColumn get planId => text().references(ShootingPlans, #id)();
  TextColumn get photoId => text().references(Photos, #id)();
  TextColumn get role =>
      text().withDefault(const Constant('result'))(); // reference(参考) / result(实拍)
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {planId, photoId, role};
}

/// 策划模板表（v2.0 新增）—— 可复用的策划结构
class PlanTemplates extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()(); // 模板名（如"人像外拍"）
  TextColumn get gearList =>
      text().withDefault(const Constant('[]'))(); // 预填器材清单
  TextColumn get shotList =>
      text().withDefault(const Constant('[]'))(); // 预填 shot list
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
