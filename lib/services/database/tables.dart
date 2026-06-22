// tables.dart — drift 表定义（photos, tags, color_pins, albums, album_photos, album_tags）
//
// v2.1：标签体系从「照片」迁移到「相册」。原 PhotoTags 表已删除（v9 migration
// 尽力迁移其数据到 AlbumTags 后 drop）。照片不再有标签。
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

  // EXIF 拍摄参数（v2.0 新增）—— JSON 存储相机/镜头/曝光/拍摄时间等
  // 详见 models/exif_info.dart，导入时由 Isolate 解析 JPEG EXIF 段写入
  TextColumn get exifJson => text().nullable()();

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

/// 照片-标签关联表已在 v2.1 移除（标签迁移到相册）。
/// 历史表名 photo_tags，v9 migration 尽力迁移其数据到 [AlbumTags] 后 drop。

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

/// 相册-标签关联表（v2.1 新增）—— 标签是相册的子系统
///
/// 标签 [Tags] 全局定义一次，可复用于多个相册（多对多）。
/// 删除相册时由 [AlbumDao.deleteAlbum] 事务内清除此关联；
/// 删除标签时由 [TagDao.deleteTag] 事务内清除此关联。
class AlbumTags extends Table {
  TextColumn get albumId => text().references(Albums, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {albumId, tagId};
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
  // v3.0 新增：关联样片相册（拍摄现场可一键跳转浏览灵感样片）
  // nullable + onDelete: setNull —— 用户删除相册时关联字段自动置空，不阻断删除
  TextColumn get associatedAlbumId => text()
      .nullable()
      .references(Albums, #id, onDelete: KeyAction.setNull)();
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

// ============ v3.5 风格档案 ============

/// 用户自定义风格档案（v3.5 新增）
///
/// 产品定位：样片解构学习工具。用户导入 N 张照片归入此档案 → 系统算每张指纹
/// → 档案 = 各维度 {mean, std} 统计。解构新照片时算其指纹与档案的标准化欧氏距离
/// → 相似度 %（详见 implementation_plan.md PR4）。
///
/// 内置理论档案（日系/港风/青橙/中式）也存此表，isBuiltin=true，fingerprintStats
/// 预填理论推导值（明确标注非统计基准）。
///
/// FK 约束：本表的 PK 无外键依赖；StyleProfilePhotos 显式关联 Photos 与本表。
/// gotcha #40：测试内存库 FK 不生效，DAO 内显式事务清理，不依赖 PRAGMA。
class StyleProfiles extends Table {
  TextColumn get id => text()(); // UUID（内置档案用 'builtin_<key>' 固定 id）
  TextColumn get name => text()(); // 用户命名（如"王家卫港风"）
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// 指纹统计 JSON：`{hist_means, hist_stds, scalar_means, scalar_stds, n}`
  ///
  /// n≥2 才有 std（n=1 时 std 全 0，匹配退化为绝对距离）。
  /// 内置理论档案的 n=0，但 scalar_means/scalar_stds 预填理论推导值。
  TextColumn get fingerprintStats => text().nullable()();

  /// 是否为内置理论档案（日系/港风/青橙/中式）
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();

  /// 理论档案的标识键（builtin=true 时有效：japanese/hongkong/cinematic/chinoiserie）
  TextColumn get builtinKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 档案-照片关联表（v3.5 新增）
///
/// - onDelete profile → cascade：删档案时关联自动清（测试库不生效，DAO 显式清）
/// - onDelete photo → setNull：删照片时关联自动清（测试库不生效，DAO 显式清，
///   见 [StyleProfileDao.removePhotoFromAllProfiles]，由 import_service.deletePhoto 调用）
///
/// 注意 photoId 不设 NOT NULL：FK setNull 时本列会变 NULL。复合 PK 仍按
/// {profileId, photoId}，setNull 后 photoId 为 NULL 的行不会与任何新插入冲突。
class StyleProfilePhotos extends Table {
  TextColumn get profileId => text()
      .references(StyleProfiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get photoId => text()
      .references(Photos, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {profileId, photoId};
}
