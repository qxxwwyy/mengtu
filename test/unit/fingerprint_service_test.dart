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
  });
}
