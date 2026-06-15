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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
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
