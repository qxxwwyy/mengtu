// photo_dao.dart — 照片数据访问对象
//
// v2.1：标签体系迁移到相册后，照片不再有标签。原按标签搜索照片的方法已移除，
// 搜索改为按文件名（[watchPhotosByName]）。
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'photo_dao.g.dart';

@DriftAccessor(tables: [Photos])
class PhotoDao extends DatabaseAccessor<AppDatabase> with _$PhotoDaoMixin {
  PhotoDao(super.db);

  /// 获取全部照片（按导入时间倒序）
  Future<List<Photo>> getAllPhotos() =>
      (select(photos)..orderBy([(t) => OrderingTerm.desc(t.importedAt)])).get();

  /// 监听全部照片变化（导入/删除后自动刷新）
  Stream<List<Photo>> watchAllPhotos() =>
      (select(photos)..orderBy([(t) => OrderingTerm.desc(t.importedAt)])).watch();

  /// 监听按文件名模糊搜索的照片（自动刷新）
  ///
  /// 转义 LIKE 通配符（\、% 和 _）并带 escapeChar（坑 #15）。
  /// 替代 v2.1 之前按标签名搜索照片的逻辑（照片不再有标签）。
  Stream<List<Photo>> watchPhotosByName(String fileName) {
    final escaped = _escapeLike(fileName);
    return (select(photos)
          ..where((t) => t.fileName.like('%$escaped%', escapeChar: r'\'))
          ..orderBy([(t) => OrderingTerm.desc(t.importedAt)]))
        .watch();
  }

  /// 按 hash 查询照片（去重）
  Future<Photo?> getPhotoByHash(String hash) =>
      (select(photos)..where((t) => t.fileHash.equals(hash))).getSingleOrNull();

  /// 插入照片
  Future<String> insertPhoto(PhotosCompanion entry) async {
    await into(photos).insert(entry);
    return entry.id.value;
  }

  /// 获取单张照片
  Future<Photo?> getPhotoById(String id) =>
      (select(photos)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 删除照片
  Future<int> deletePhoto(String id) =>
      (delete(photos)..where((t) => t.id.equals(id))).go();

  /// 更新分析缓存
  Future<void> updateHistogramCache(
    String id, {
    Uint8List? rgbHistogram,
    Uint8List? lumHistogram,
    Uint8List? hueHistogram,
  }) =>
      (update(photos)..where((t) => t.id.equals(id))).write(PhotosCompanion(
        rgbHistogram: rgbHistogram != null ? Value(rgbHistogram) : const Value.absent(),
        lumHistogram: lumHistogram != null ? Value(lumHistogram) : const Value.absent(),
        hueHistogram: hueHistogram != null ? Value(hueHistogram) : const Value.absent(),
      ));

  /// 更新色卡缓存
  Future<void> updatePaletteCache(String id, String paletteJson) =>
      (update(photos)..where((t) => t.id.equals(id)))
          .write(PhotosCompanion(paletteJson: Value(paletteJson)));

  /// 更新影调缓存
  Future<void> updateToneCache(String id, String toneJson) =>
      (update(photos)..where((t) => t.id.equals(id)))
          .write(PhotosCompanion(toneJson: Value(toneJson)));

  /// 更新 EXIF 拍摄参数（历史照片补全 / 重新读取时调用）
  Future<void> updateExifCache(String id, String? exifJson) =>
      (update(photos)..where((t) => t.id.equals(id)))
          .write(PhotosCompanion(exifJson: Value(exifJson)));

  /// 清空所有照片的缩略图路径（清缓存后调用，配合 ImportService.regenerateThumbnail 按需重生成）
  Future<int> clearAllThumbnails() =>
      (update(photos)).write(const PhotosCompanion(thumbnailPath: Value('')));

  /// 更新单张照片的缩略图路径（重生成后回填）
  Future<void> updateThumbnailPath(String id, String thumbnailPath) =>
      (update(photos)..where((t) => t.id.equals(id)))
          .write(PhotosCompanion(thumbnailPath: Value(thumbnailPath)));

  /// 获取照片总数
  Future<int> getPhotoCount() async {
    final count = photos.id.count();
    final query = selectOnly(photos)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// 获取存储空间占用（bytes）
  Future<int> getTotalStorageUsed() async {
    final sumExp = photos.fileSize.sum();
    final query = selectOnly(photos)..addColumns([sumExp]);
    final result = await query.getSingle();
    return result.read(sumExp) ?? 0;
  }

  /// 转义 SQLite LIKE 通配符（\、% 和 _）。
  /// 配合 ESCAPE '\' 子句使用（坑 #15），让 SQLite 把反斜杠视为转义符。
  String _escapeLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}
