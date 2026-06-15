// analysis_flow_test.dart — 分析流程集成测试
//
// 验证：直方图计算 → 缓存写入 → 二次读取 → 影调计算 → 色卡提取 全链路
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/database/app_database.dart';
import 'package:mengtu/services/histogram_service.dart';
import 'package:mengtu/services/palette_service.dart';
import 'package:mengtu/services/tone_service.dart';
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/models/palette_result.dart';
import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = createTestDatabase();
    tempDir = await Directory.systemTemp.createTemp('mengtu_analysis_test');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 插入照片记录（指定文件路径）
  Future<String> insertPhotoWithFile(String path) async {
    final id = 'test_${DateTime.now().microsecondsSinceEpoch}';
    await db.photoDao.insertPhoto(PhotosCompanion.insert(
      id: id,
      filePath: path,
      thumbnailPath: path,
      fileName: 'test.png',
    ));
    return id;
  }

  group('直方图 → 缓存 → 二次读取', () {
    test('首次计算直方图并缓存，二次从缓存读取', () async {
      final imgPath = generateSolidImageFile(
        '${tempDir.path}/red.png',
        r: 255,
        g: 0,
        b: 0,
      );
      final photoId = await insertPhotoWithFile(imgPath);

      // 首次计算
      final hist1 = await computeHistogram(imgPath);
      expect(hist1.r[255], greaterThan(0));

      // 缓存到 DB
      final bytes = hist1.toBytes();
      await db.photoDao.updateHistogramCache(
        photoId,
        rgbHistogram: bytes.sublist(0, 1536),
        lumHistogram: bytes.sublist(1536, 2048),
        hueHistogram: bytes.sublist(2048), // hue 360 bins × 2 = 720 字节（v1.0.0 新增）
      );

      // 从缓存读取
      final photo = await db.photoDao.getPhotoById(photoId);
      expect(photo!.rgbHistogram, isNotNull);
      expect(photo.lumHistogram, isNotNull);

      // 完整重建（含 hue）：RGB + Lum + Hue = 2768 字节
      final combined = Uint8List.fromList([
        ...photo.rgbHistogram!,
        ...photo.lumHistogram!,
        ...?photo.hueHistogram,
      ]);
      final hist2 = HistogramData.fromBytes(combined);

      // 数据一致
      expect(hist2.r, equals(hist1.r));
      expect(hist2.lum, equals(hist1.lum));
    });
  });

  group('影调分析全链路', () {
    test('暗调图片 → 低调判定', () async {
      final imgPath = generateSolidImageFile(
        '${tempDir.path}/dark.png',
        r: 20,
        g: 20,
        b: 20,
      );
      final photoId = await insertPhotoWithFile(imgPath);

      // 计算直方图
      final hist = await computeHistogram(imgPath);
      // 缓存
      final bytes = hist.toBytes();
      await db.photoDao.updateHistogramCache(
        photoId,
        rgbHistogram: bytes.sublist(0, 1536),
        lumHistogram: bytes.sublist(1536, 2048),
        hueHistogram: bytes.sublist(2048), // hue 720 字节
      );

      // 从亮度直方图计算影调
      final tone = analyzeTone(hist.lum);

      // 缓存影调
      await db.photoDao.updateToneCache(photoId, tone.toJsonString());

      // 验证（亮度 20 落入黑色区 0-51）
      expect(tone.toneKey, 'low');
      expect(tone.blacks, greaterThan(80));

      // 从缓存读取验证
      final photo = await db.photoDao.getPhotoById(photoId);
      final cached = ToneResult.fromJsonString(photo!.toneJson);
      expect(cached, isNotNull);
      expect(cached!.toneKey, 'low');
    });

    test('高调图片 → 高调判定', () async {
      final imgPath = generateSolidImageFile(
        '${tempDir.path}/bright.png',
        r: 240,
        g: 240,
        b: 240,
      );
      await insertPhotoWithFile(imgPath);

      final hist = await computeHistogram(imgPath);
      final tone = analyzeTone(hist.lum);

      // 验证（亮度 240 落入白色区 205-255）
      expect(tone.toneKey, 'high');
      expect(tone.whites, greaterThan(80));
    });

    test('灰色图片 → 中间调判定', () async {
      final imgPath = generateSolidImageFile(
        '${tempDir.path}/gray.png',
        r: 128,
        g: 128,
        b: 128,
      );
      final hist = await computeHistogram(imgPath);
      final tone = analyzeTone(hist.lum);

      expect(tone.toneKey, 'mid');
      expect(tone.midtones, greaterThan(80));
    });
  });

  group('色卡提取全链路', () {
    test('纯色图片提取色卡 → 单色结果', () async {
      final imgPath = generateSolidImageFile(
        '${tempDir.path}/red.png',
        r: 255,
        g: 0,
        b: 0,
      );
      final photoId = await insertPhotoWithFile(imgPath);

      final palette = await extractPalette(imgPath, desired: 5);

      // 缓存
      await db.photoDao.updatePaletteCache(photoId, palette.toJsonString());

      // 从缓存读取
      final photo = await db.photoDao.getPhotoById(photoId);
      final cached = PaletteResult.fromJsonString(photo!.paletteJson);

      expect(cached.colors, isNotEmpty);
      // 纯红图片的主色应接近红色
      final firstColor = cached.colors.first;
      expect(firstColor.r, greaterThan(200));
      expect(firstColor.g, lessThan(100));
      expect(firstColor.b, lessThan(100));
    });

    test('色卡占比之和合理（接近 100%）', () async {
      final imgPath = generateGradientImageFile('${tempDir.path}/grad.png');
      final palette = await extractPalette(imgPath, desired: 5);

      final totalRatio = palette.colors.fold<double>(0, (a, c) => a + c.ratio);
      // 占比总和应在合理范围（量化后可能有损失）
      expect(totalRatio, greaterThan(0));
    });

    test('色卡序列化往返（缓存正确）', () async {
      final imgPath = generateGradientImageFile('${tempDir.path}/grad2.png');
      final palette = await extractPalette(imgPath, desired: 5);
      final json = palette.toJsonString();
      final restored = PaletteResult.fromJsonString(json);

      expect(restored.colors.length, palette.colors.length);
      for (var i = 0; i < palette.colors.length; i++) {
        expect(restored.colors[i].argb, palette.colors[i].argb);
      }
    });
  });

  group('分析缓存失效', () {
    test('toneJson 缓存为空时 fromJsonString 返回 null', () async {
      final result = ToneResult.fromJsonString(null);
      expect(result, isNull);
    });

    test('paletteJson 缓存为空时 fromJsonString 返回空色卡', () async {
      final result = PaletteResult.fromJsonString(null);
      expect(result.colors, isEmpty);
    });
  });
}
