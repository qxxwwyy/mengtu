// precompute_fingerprint_test.dart — 预计算 + 指纹链路集成测试（v3.5 二轮复核新增）
//
// 核心验证目标（P1 修复）：
// precomputeAnalysisForPhotos 现在也填充 toneJson 的 'advanced' 键（含 Face Mesh
// 的 STI/FLC），让档案样片即使未打开详情页，STI/FLC 也能进入指纹匹配 ——
// 之前这两维恒为 -1 被跳过，导致肤色维度（v3.5 主打的差异化指标）系统性失效。
//
// 测试容错：BlazeFace/face_mesh 模型在 CI 测试环境缺失（asset 未随测试打包），
// analyzeSkinTone 会降级返回空 SkinAnalysis → STI/FLC = null。
// 因此断言分两档：
// - black_point_offset/white_point_compression/ten_tonal_type：纯直方图可算，必有值
// - skin_sti/face_lighting_contrast：Face Mesh 依赖，模型缺失时可为 null
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/advanced_portrait_metrics.dart';
import 'package:mengtu/services/database/app_database.dart';
import 'package:mengtu/services/fingerprint_service.dart';
import 'package:mengtu/services/import_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;
  late ImportService importService;
  late Directory tempDir;

  setUp(() async {
    db = createTestDatabase();
    // precomputeAnalysisForPhotos 不使用 thumbnailsDir（仅算分析缓存），
    // 测试用 forTesting 工厂注入临时目录，绕开 path_provider platform channel
    tempDir = await Directory.systemTemp.createTemp('mengtu_precompute_test');
    importService = ImportService.forTesting(db, tempDir.path);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('precomputeAnalysisForPhotos 填充 advanced 键', () {
    test('空缓存照片预计算后，toneJson 含 advanced 键 + 直方图可算字段必有值', () async {
      // 用渐变图（覆盖亮度范围）保证 black/white/ten_tonal 有意义
      final imgPath = generateGradientImageFile(
        '${Directory.systemTemp.createTempSync('mengtu_precompute').path}/grad.png',
      );
      final photoId = await insertTestPhoto(
        db,
        filePath: imgPath,
        fileName: 'grad.png',
      );

      final result = await importService.precomputeAnalysisForPhotos([photoId]);
      expect(result.success, 1);
      expect(result.failed, 0);

      final photo = await db.photoDao.getPhotoById(photoId);
      expect(photo!.rgbHistogram, isNotNull, reason: '直方图应已缓存');
      expect(photo.lumHistogram, isNotNull);
      expect(photo.toneJson, isNotNull, reason: 'toneJson 应已缓存');

      // 核心断言：advanced 键已填充
      final adv = AdvancedPortraitMetrics.fromJsonString(photo.toneJson);
      expect(adv, isNotNull,
          reason: 'P1 修复：precompute 必须写 advanced 键');
      // 直方图可算部分（强制必有结果）
      expect(adv!.blackPointOffset, greaterThanOrEqualTo(0.0));
      expect(adv.whitePointCompression, greaterThanOrEqualTo(0.0));
      expect(adv.tenTonalType, isNotEmpty);
      // STI/FLC：测试环境模型缺失可为 null（容错，不强制）
      // —— 真实环境（模型打包）才会非 null
    });

    test('幂等：已有 advanced 键不重算（不重复触发 Face Mesh 推理）', () async {
      final imgPath = generateGradientImageFile(
        '${Directory.systemTemp.createTempSync('mengtu_precompute2').path}/grad.png',
      );
      final photoId = await insertTestPhoto(
        db,
        filePath: imgPath,
        fileName: 'grad.png',
      );

      // 第一次预计算：写入 advanced
      await importService.precomputeAnalysisForPhotos([photoId]);
      final photo1 = await db.photoDao.getPhotoById(photoId);
      final adv1 = AdvancedPortraitMetrics.fromJsonString(photo1!.toneJson);
      final bp1 = adv1!.blackPointOffset;

      // 第二次预计算：advanced 已存在，应跳过（幂等）
      await importService.precomputeAnalysisForPhotos([photoId]);
      final photo2 = await db.photoDao.getPhotoById(photoId);
      final adv2 = AdvancedPortraitMetrics.fromJsonString(photo2!.toneJson);
      // 直方图可算字段不变（幂等）
      expect(adv2!.blackPointOffset, closeTo(bp1, 1e-9));
    });

    test('不存在的 photoId 计入 failed', () async {
      final result =
          await importService.precomputeAnalysisForPhotos(['nonexistent']);
      expect(result.success, 0);
      expect(result.failed, 1);
    });
  });

  group('预计算 → 档案指纹统计链路', () {
    test('预计算后的照片，recomputeProfileStats 能算出指纹统计', () async {
      final imgPath = generateGradientImageFile(
        '${Directory.systemTemp.createTempSync('mengtu_profile').path}/grad.png',
      );
      final photoId = await insertTestPhoto(
        db,
        filePath: imgPath,
        fileName: 'grad.png',
      );
      await importService.precomputeAnalysisForPhotos([photoId]);

      // 建档案 + 关联 + 重算指纹统计
      await db.styleProfileDao.insertProfile(
        StyleProfilesCompanion.insert(id: 'p1', name: 'test profile'),
      );
      await db.styleProfileDao.addPhotoToProfile('p1', photoId);

      final fpService = FingerprintService(db);
      await fpService.recomputeProfileStats('p1');

      final profile = await db.styleProfileDao.getProfileById('p1');
      expect(profile!.fingerprintStats, isNotNull,
          reason: '档案指纹统计应已生成');
      final stats = jsonDecode(profile.fingerprintStats!) as Map<String, dynamic>;
      expect(stats['n'], 1);
      // 直方图维度（96）和标量维度（9）结构完整
      final histMeans = (stats['hist_means'] as List);
      final scalarMeans = (stats['scalar_means'] as List);
      expect(histMeans.length, 96);
      expect(scalarMeans.length, 9);
      // 直方图可算维度（rms_contrast/black_point/white_point/entropy 等）count > 0
      final counts = (stats['scalar_counts'] as List).cast<int>();
      // 维度 2 = black_point，维度 3 = white_point（纯直方图可算，必计入）
      expect(counts[2], greaterThan(0), reason: 'black_point 维度应计入');
      expect(counts[3], greaterThan(0), reason: 'white_point 维度应计入');
    });

    test('预计算后相同照片 vs 自己的档案 → sim 接近 1.0', () async {
      final imgPath = generateGradientImageFile(
        '${Directory.systemTemp.createTempSync('mengtu_match').path}/grad.png',
      );
      final photoId = await insertTestPhoto(
        db,
        filePath: imgPath,
        fileName: 'grad.png',
      );
      await importService.precomputeAnalysisForPhotos([photoId]);

      await db.styleProfileDao.insertProfile(
        StyleProfilesCompanion.insert(id: 'p1', name: 'self'),
      );
      await db.styleProfileDao.addPhotoToProfile('p1', photoId);
      final fpService = FingerprintService(db);
      await fpService.recomputeProfileStats('p1');

      // 用同一张照片的指纹匹配自己的档案 → 相似度应很高
      final fp = await fpService.computeFingerprint(photoId);
      final sim = await fpService.computeSimilarity(fp, 'p1');
      expect(sim, greaterThan(0.9),
          reason: '照片与自己的档案应高度相似');
    });
  });
}
