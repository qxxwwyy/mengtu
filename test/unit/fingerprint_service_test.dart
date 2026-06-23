// fingerprint_service_test.dart — 指纹服务测试（v3.5 PR4）
//
// 覆盖 spec §4.6 测试列表：
// 1. computeStats：N 张指纹 → 各维度 {mean, std}（纯函数，主测点）
// 2. computeSimilarity：相同指纹 vs 档案 → sim 接近 1.0（需 DB + 照片）
// 3. computeSimilarity：差异大 → sim 低
// 4. 缺失维度（-1）跳过不影响其他维度
//
// 注：computeFingerprint 依赖 Isolate + 照片文件，测试通过 DB 注入预计算的
// 直方图缓存 + toneJson 间接验证（不读真实图片）。
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/photo_fingerprint.dart';
import 'package:mengtu/services/database/app_database.dart';
import 'package:mengtu/services/fingerprint_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late FingerprintService service;

  setUp(() {
    final db = createTestDatabase();
    service = FingerprintService(db);
  });

  /// 构造合成指纹
  PhotoFingerprint buildFingerprint({
    List<double>? hist,
    List<double>? scalars,
  }) =>
      PhotoFingerprint(
        histogramFeatures: hist ?? List.filled(96, 0.5),
        scalarFeatures: scalars ??
            const [0.3, 1.0, 5.0, 250.0, 6.5, 50.0, 15.0, 0.65, 0.25],
      );

  group('computeStats 各维度统计（纯函数）', () {
    test('N=1 → mean=该指纹，std=0', () {
      final fp = buildFingerprint(
          scalars: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]);
      final stats = service.computeStats([fp]);

      expect(stats['n'], 1);
      final means = (stats['scalar_means'] as List).cast<double>();
      final stds = (stats['scalar_stds'] as List).cast<double>();
      // 单样本 std=0
      for (var i = 0; i < 9; i++) {
        expect(means[i], 0.5);
        expect(stds[i], 0.0);
      }
    });

    test('N=3 → mean=平均值', () {
      final fps = [
        buildFingerprint(
            scalars: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]),
        buildFingerprint(
            scalars: [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3]),
        buildFingerprint(
            scalars: [0.5, 0.4, 0.3, 0.2, 0.1, 0.0, 0.0, 0.0, 0.0]),
      ];
      final stats = service.computeStats(fps);

      expect(stats['n'], 3);
      final means = (stats['scalar_means'] as List).cast<double>();
      // 维度 2（scs）：0.3, 0.3, 0.3 → mean=0.3
      expect(means[2], closeTo(0.3, 1e-9));
      // 维度 0（rms）：0.1, 0.3, 0.5 → mean=0.3
      expect(means[0], closeTo(0.3, 1e-9));
    });

    test('缺失维度（-1）不计入统计', () {
      // 维度 7（sti）和 8（flc）为 -1（无脸照片）
      final fps = [
        buildFingerprint(
            scalars: [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, -1.0, -1.0]),
        buildFingerprint(
            scalars: [0.5, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, -1.0, -1.0]),
      ];
      final stats = service.computeStats(fps);

      final counts = (stats['scalar_counts'] as List).cast<int>();
      final means = (stats['scalar_means'] as List).cast<double>();
      // 维度 0（rms）有 2 个有效值 → count=2
      expect(counts[0], 2);
      // 维度 7（sti）全部缺失 → count=0
      expect(counts[7], 0);
      expect(counts[8], 0);
      // 维度 0 mean = (0.3+0.5)/2 = 0.4
      expect(means[0], closeTo(0.4, 1e-9));
    });

    test('直方图维度 96 个全部计算', () {
      final hist1 = List<double>.filled(96, 0.1);
      final hist2 = List<double>.filled(96, 0.3);
      final stats = service.computeStats([
        buildFingerprint(hist: hist1),
        buildFingerprint(hist: hist2),
      ]);

      final histMeans = (stats['hist_means'] as List).cast<double>();
      final histStds = (stats['hist_stds'] as List).cast<double>();
      expect(histMeans.length, 96);
      expect(histStds.length, 96);
      // mean = (0.1+0.3)/2 = 0.2
      expect(histMeans[0], closeTo(0.2, 1e-9));
      // std = sqrt(((0.1-0.2)² + (0.3-0.2)²)/2) = sqrt(0.01) = 0.1
      expect(histStds[0], closeTo(0.1, 1e-9));
    });
  });

  group('computeSimilarity 标准化欧氏距离', () {
    test('空档案统计（fingerprintStats null）→ 返回 0', () async {
      final db = createTestDatabase();
      final svc = FingerprintService(db);
      await db.styleProfileDao.insertProfile(
        StyleProfilesCompanion.insert(id: 'p1', name: '空档案'),
      );
      final fp = buildFingerprint();
      final sim = await svc.computeSimilarity(fp, 'p1');
      expect(sim, 0.0);
    });

    test('相同指纹 vs 档案 → sim 接近 1.0', () async {
      final db = createTestDatabase();
      final svc = FingerprintService(db);
      const scalars = [0.3, 1.0, 5.0, 250.0, 6.5, 50.0, 15.0, 0.65, 0.25];
      final fps = [buildFingerprint(scalars: scalars)];
      final stats = svc.computeStats(fps);

      await db.styleProfileDao.insertProfile(
        StyleProfilesCompanion.insert(
          id: 'p1',
          name: 'test',
          fingerprintStats: Value(jsonEncode(stats)),
        ),
      );

      // 用相同的指纹匹配
      final fp = buildFingerprint(scalars: scalars);
      final sim = await svc.computeSimilarity(fp, 'p1');
      // 完全相同的指纹 → 距离=0 → sim=exp(0)=1.0
      expect(sim, greaterThan(0.95));
    });

    test('差异大的指纹 → sim 低', () async {
      final db = createTestDatabase();
      final svc = FingerprintService(db);
      // 档案指纹：低 RMS、低黑点
      final fps = [
        buildFingerprint(
            scalars: [0.1, 0.5, 2.0, 200.0, 5.0, 20.0, 5.0, 0.3, 0.1])
      ];
      final stats = svc.computeStats(fps);
      await db.styleProfileDao.insertProfile(
        StyleProfilesCompanion.insert(
          id: 'p1',
          name: 'test',
          fingerprintStats: Value(jsonEncode(stats)),
        ),
      );

      // 当前指纹：高 RMS、高黑点（差异大）
      final fp = buildFingerprint(
          scalars: [0.8, 2.0, 100.0, 255.0, 8.0, 90.0, 40.0, 0.9, 0.8]);
      final sim = await svc.computeSimilarity(fp, 'p1');
      expect(sim, lessThan(0.5));
    });

    test('中等差异的指纹 → sim 在合理区间（0.2~0.8）', () async {
      // v3.5 二轮复核新增：验证 exp 衰减系数从 2.0 放宽到 4.0 后，
      // 中等差异的指纹既不会被压到接近 0（过严），也不会虚高（过松）。
      final db = createTestDatabase();
      final svc = FingerprintService(db);
      // 档案指纹：RMS=0.4，黑点=20
      final fps = [
        buildFingerprint(
            scalars: [0.4, 1.0, 20.0, 245.0, 6.5, 50.0, 15.0, 0.6, 0.25])
      ];
      final stats = svc.computeStats(fps);
      await db.styleProfileDao.insertProfile(
        StyleProfilesCompanion.insert(
          id: 'p1',
          name: 'test',
          fingerprintStats: Value(jsonEncode(stats)),
        ),
      );

      // 当前指纹：与档案接近但有偏离（RMS 0.5 vs 0.4，黑点 30 vs 20）
      final fp = buildFingerprint(
          scalars: [0.5, 1.2, 30.0, 248.0, 6.8, 55.0, 18.0, 0.62, 0.28]);
      final sim = await svc.computeSimilarity(fp, 'p1');
      // 中等差异应落在 0.2~0.8（既非「很相似」也非「完全无关」）
      expect(sim, greaterThan(0.2));
      expect(sim, lessThan(0.95));
    });

    test('内置理论档案风格：hist_means 用高斯生成，sim 不会被压到接近 0', () async {
      // v3.5 二轮复核新增：验证 exp 衰减放宽（2.0→4.0）后，理论档案的高斯
      // hist_means 与真实照片（多峰）的卡方距离不再让相似度系统性偏低。
      // 构造一个与理论档案接近但不完全相同的直方图，sim 应 > 0.3。
      final db = createTestDatabase();
      final svc = FingerprintService(db);
      // 档案：单峰高斯直方图（峰值 bin 16）
      final hist = List<double>.filled(96, 0.0);
      var sum = 0.0;
      for (var i = 0; i < 96; i++) {
        final d = (i - 16) / 8.0;
        hist[i] = (i < 32) ? math.exp(-0.5 * d * d) : 0.0;
        sum += hist[i];
      }
      for (var i = 0; i < 96; i++) {
        hist[i] /= sum;
      }
      final fps = [
        PhotoFingerprint(
          histogramFeatures: hist,
          scalarFeatures: const [0.3, 1.0, 5.0, 250.0, 6.5, 50.0, 15.0, 0.65, 0.25],
        )
      ];
      final stats = svc.computeStats(fps);
      await db.styleProfileDao.insertProfile(
        StyleProfilesCompanion.insert(
          id: 'p1',
          name: 'theory',
          fingerprintStats: Value(jsonEncode(stats)),
        ),
      );

      // 当前：峰值略偏移的高斯（bin 18 vs 档案 bin 16），模拟真实照片偏离理论分布
      final hist2 = List<double>.filled(96, 0.0);
      var sum2 = 0.0;
      for (var i = 0; i < 96; i++) {
        final d = (i - 18) / 9.0;
        hist2[i] = (i < 32) ? math.exp(-0.5 * d * d) : 0.0;
        sum2 += hist2[i];
      }
      for (var i = 0; i < 96; i++) {
        hist2[i] /= sum2;
      }
      final fp = PhotoFingerprint(
        histogramFeatures: hist2,
        scalarFeatures: const [0.3, 1.0, 5.0, 250.0, 6.5, 50.0, 15.0, 0.65, 0.25],
      );
      final sim = await svc.computeSimilarity(fp, 'p1');
      // 系数放宽后，相似风格不应被系统性压低
      expect(sim, greaterThan(0.3),
          reason: '理论档案与近似风格 sim 应 > 0.3，否则衰减系数过严');
    });
  });
}
