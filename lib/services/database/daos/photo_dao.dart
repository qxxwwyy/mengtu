// photo_dao.dart — 照片数据访问对象
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'photo_dao.g.dart';

@DriftAccessor(tables: [Photos, Tags, PhotoTags])
class PhotoDao extends DatabaseAccessor<AppDatabase> with _$PhotoDaoMixin {
  PhotoDao(super.db);

  /// 获取全部照片（按导入时间倒序）
  Future<List<Photo>> getAllPhotos() =>
      (select(photos)..orderBy([(t) => OrderingTerm.desc(t.importedAt)])).get();

  /// 监听全部照片变化（导入/删除后自动刷新）
  Stream<List<Photo>> watchAllPhotos() =>
      (select(photos)..orderBy([(t) => OrderingTerm.desc(t.importedAt)])).watch();

  /// 监听按标签名搜索的照片（自动刷新）
  ///
  /// 转义 LIKE 通配符（% 和 _）并带 escapeChar（坑 #15 在 drift 2.34+ 已支持
  /// escape 参数；早期版本需 customStatement 发原生 SQL）。
  /// 不带 escapeChar 时 SQLite 默认 LIKE 无转义符，\% 仍按反斜杠+通配符处理，
  /// 含 _ 的标签名会误匹配（如 "a_b" 命中 "axb"）。
  Stream<List<Photo>> watchPhotosByTagName(String tagName) {
    final escaped = _escapeLike(tagName);
    final query = select(photos).join([
      innerJoin(photoTags, photoTags.photoId.equalsExp(photos.id)),
      innerJoin(tags, tags.id.equalsExp(photoTags.tagId)),
    ])
      ..where(tags.name.like('%$escaped%', escapeChar: r'\'))
      ..orderBy([OrderingTerm.desc(photos.importedAt)]);
    return query.watch().map((rows) => rows.map((row) => row.readTable(photos)).toList());
  }

  /// 按 tagId 查询照片
  Future<List<Photo>> getPhotosByTag(String tagId) async {
    final query = select(photos).join([
      innerJoin(photoTags, photoTags.photoId.equalsExp(photos.id)),
    ])
      ..where(photoTags.tagId.equals(tagId))
      ..orderBy([OrderingTerm.desc(photos.importedAt)]);
    final rows = await query.get();
    return rows.map((row) => row.readTable(photos)).toList();
  }

  /// 按标签名模糊搜索照片（与 watchPhotosByTagName 同语义，但是一次性查询）
  Future<List<Photo>> searchPhotosByTagName(String tagName) async {
    final escaped = _escapeLike(tagName);
    final query = select(photos).join([
      innerJoin(photoTags, photoTags.photoId.equalsExp(photos.id)),
      innerJoin(tags, tags.id.equalsExp(photoTags.tagId)),
    ])
      ..where(tags.name.like('%$escaped%', escapeChar: r'\'))
      ..orderBy([OrderingTerm.desc(photos.importedAt)]);
    final rows = await query.get();
    return rows.map((row) => row.readTable(photos)).toList();
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
