// app_database.dart — drift 数据库核心
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables.dart';
import 'daos/photo_dao.dart';
import 'daos/tag_dao.dart';
import 'daos/color_pin_dao.dart';
import 'daos/album_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Photos, Tags, PhotoTags, ColorPins, Albums, AlbumPhotos],
  daos: [PhotoDao, TagDao, ColorPinDao, AlbumDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // v6: fileHash 唯一索引（全新安装也需创建，防并发导入重复）
          await m.database.customStatement(
            "CREATE UNIQUE INDEX IF NOT EXISTS photos_file_hash_unique "
            "ON photos (file_hash) WHERE file_hash != ''",
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v0.3.0: 新增 paletteJson + toneJson 列
            await m.addColumn(photos, photos.paletteJson);
            await m.addColumn(photos, photos.toneJson);
          }
          if (from < 3) {
            // v1.0.0: hueHistogram 列
            await m.addColumn(photos, photos.hueHistogram);
          }
          if (from < 4) {
            // v1.1.0: 取色点表
            await m.createTable(colorPins);
          }
          if (from < 5) {
            // v1.1.0: 相册表
            await m.createTable(albums);
            await m.createTable(albumPhotos);
          }
          if (from < 6) {
            // v1.2.0: fileHash 唯一约束（防止并发导入重复记录）
            // 先清理已存在的重复 hash（保留每组最早 id），排除空字符串默认值
            await m.database.customStatement(
              "DELETE FROM photos WHERE id NOT IN ("
              "SELECT MIN(id) FROM photos WHERE file_hash != '' GROUP BY file_hash"
              ") AND file_hash != ''",
            );
            // 部分唯一索引（仅对非空 hash 生效，避免空字符串默认值相互冲突）
            await m.database.customStatement(
              "CREATE UNIQUE INDEX photos_file_hash_unique "
              "ON photos (file_hash) WHERE file_hash != ''",
            );
          }
        },
      );
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'mengtu.db'));
    return NativeDatabase.createInBackground(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  });
}
