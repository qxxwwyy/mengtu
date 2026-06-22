// fingerprint_service.dart — 照片指纹计算 + 档案匹配（v3.5 PR4）
//
// 解决 L1：不用多维高斯马氏距离（N=3 协方差矩阵奇异，数学硬伤），
// 改用各维度 {mean, std} 的标准化欧氏距离，稳定且可解释（gotcha #47）。
//
// 算法链：
// 1. computeFingerprint：从 DB 缓存的直方图 + toneJson 算 96 维直方图特征 +
//    9 维标量特征（Isolate 内纯内存操作，不重读图）
// 2. recomputeProfileStats：批量算档案内所有照片指纹，聚合各维度 {mean, std}
// 3. computeSimilarity：照片指纹 vs 档案统计 → 标准化欧氏距离 → 相似度 exp(-D²/2k)
//
// 距离融合（经验权重）：直方图卡方 60% + 标量标准化欧氏 40%
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/advanced_portrait_metrics.dart';
import '../models/photo_fingerprint.dart';
import '../models/tone_result.dart';
import '../services/database/app_database.dart';
import '../services/tone_service.dart' show calculateWarmToColdRatio;

/// Isolate 间传递的指纹计算参数（需可序列化）
class _FingerprintArgs {
  final String filePath;
  final Uint8List? rgbHistogram;
  final Uint8List? lumHistogram;
  final Uint8List? hueHistogram;
  final String? toneJson;

  const _FingerprintArgs(
    this.filePath,
    this.rgbHistogram,
    this.lumHistogram,
    this.hueHistogram,
    this.toneJson,
  );
}

/// 照片指纹计算 + 档案匹配服务
class FingerprintService {
  final AppDatabase _db;
  FingerprintService(this._db);

  /// 计算单张照片指纹（Isolate 内，复用 DB 缓存的直方图不重读图）
  Future<PhotoFingerprint> computeFingerprint(String photoId) async {
    final photo = await _db.photoDao.getPhotoById(photoId);
    if (photo == null) throw Exception('Photo not found');

    return compute(
      _computeFingerprintIsolate,
      _FingerprintArgs(
        photo.filePath,
        photo.rgbHistogram != null
            ? Uint8List.fromList(photo.rgbHistogram!)
            : null,
        photo.lumHistogram != null
            ? Uint8List.fromList(photo.lumHistogram!)
            : null,
        photo.hueHistogram != null
            ? Uint8List.fromList(photo.hueHistogram!)
            : null,
        photo.toneJson,
      ),
    );
  }

  /// 更新档案指纹统计（添加/移除照片后调用）
  ///
  /// 重新读取档案内所有照片的指纹，计算各维度 {mean, std}。
  /// 空档案清空 fingerprintStats。
  Future<void> recomputeProfileStats(String profileId) async {
    final photos = await _db.styleProfileDao.getProfilePhotos(profileId);
    if (photos.isEmpty) {
      await _db.styleProfileDao.updateFingerprintStats(profileId, null);
      return;
    }

    final fingerprints = <PhotoFingerprint>[];
    for (final photo in photos) {
      try {
        fingerprints.add(await computeFingerprint(photo.id));
      } catch (e) {
        // 单张失败不阻塞（照片文件缺失等），跳过
        debugPrint('Fingerprint failed for ${photo.id}: $e');
      }
    }

    if (fingerprints.isEmpty) {
      await _db.styleProfileDao.updateFingerprintStats(profileId, null);
      return;
    }

    final stats = computeStats(fingerprints);
    await _db.styleProfileDao.updateFingerprintStats(
        profileId, jsonEncode(stats));
  }

  /// 计算 N 个指纹的各维度统计（标准化欧氏用）
  ///
  /// 公开方法（测试用）：让单元测试能直接验证统计逻辑。
  Map<String, dynamic> computeStats(List<PhotoFingerprint> fingerprints) {
    final n = fingerprints.length;
    final histMeans = List.filled(96, 0.0);
    final histStds = List.filled(96, 0.0);
    final scalarMeans = List.filled(9, 0.0);
    final scalarStds = List.filled(9, 0.0);
    final scalarCounts = List.filled(9, 0);

    // 第一遍：求和（缺失标量维度不计入）
    for (final fp in fingerprints) {
      for (var i = 0; i < 96 && i < fp.histogramFeatures.length; i++) {
        histMeans[i] += fp.histogramFeatures[i];
      }
      for (var i = 0; i < fp.scalarFeatures.length && i < 9; i++) {
        final v = fp.scalarFeatures[i];
        if (!v.isNaN && v != PhotoFingerprint.missing) {
          scalarMeans[i] += v;
          scalarCounts[i]++;
        }
      }
    }

    // 求均值
    for (var i = 0; i < 96; i++) {
      histMeans[i] /= n;
    }
    for (var i = 0; i < 9; i++) {
      if (scalarCounts[i] > 0) scalarMeans[i] /= scalarCounts[i];
    }

    // 第二遍：求方差（标准差的平方）
    final histVarSums = List.filled(96, 0.0);
    final scalarVarSums = List.filled(9, 0.0);
    for (final fp in fingerprints) {
      for (var i = 0; i < 96 && i < fp.histogramFeatures.length; i++) {
        final d = fp.histogramFeatures[i] - histMeans[i];
        histVarSums[i] += d * d;
      }
      for (var i = 0; i < fp.scalarFeatures.length && i < 9; i++) {
        final v = fp.scalarFeatures[i];
        if (!v.isNaN && v != PhotoFingerprint.missing) {
          final d = v - scalarMeans[i];
          scalarVarSums[i] += d * d;
        }
      }
    }
    for (var i = 0; i < 96; i++) {
      histStds[i] = math.sqrt(histVarSums[i] / n);
    }
    for (var i = 0; i < 9; i++) {
      final count = scalarCounts[i] > 0 ? scalarCounts[i] : 1;
      scalarStds[i] = math.sqrt(scalarVarSums[i] / count);
    }

    return {
      'hist_means': histMeans,
      'hist_stds': histStds,
      'scalar_means': scalarMeans,
      'scalar_stds': scalarStds,
      'scalar_counts': scalarCounts,
      'n': n,
    };
  }

  /// 匹配：照片指纹 vs 档案 → 相似度 [0, 1]
  ///
  /// 标准化欧氏距离：D = sqrt(Σ((xᵢ−μᵢ)/σᵢ)²)
  /// 相似度：sim = exp(−D²/2)，D=0 → sim=1，D 大 → sim 趋近 0
  ///
  /// 融合（经验权重）：直方图卡方 60% + 标量标准化欧氏 40%
  Future<double> computeSimilarity(
      PhotoFingerprint fingerprint, String profileId) async {
    final profile = await _db.styleProfileDao.getProfileById(profileId);
    if (profile?.fingerprintStats == null ||
        profile!.fingerprintStats!.isEmpty) {
      return 0;
    }

    final Map<String, dynamic> stats;
    try {
      stats = jsonDecode(profile.fingerprintStats!) as Map<String, dynamic>;
    } catch (_) {
      return 0;
    }

    final histMeans = (stats['hist_means'] as List?)?.cast<double>() ?? [];
    final scalarMeans =
        (stats['scalar_means'] as List?)?.cast<double>() ?? [];
    final scalarStds = (stats['scalar_stds'] as List?)?.cast<double>() ?? [];

    // 1. 直方图卡方距离（每 bin: (a-b)²/(a+b)）
    double histDist = 0;
    var histDims = 0;
    for (var i = 0;
        i < 96 && i < histMeans.length && i < fingerprint.histogramFeatures.length;
        i++) {
      final a = fingerprint.histogramFeatures[i];
      final b = histMeans[i];
      final denom = a + b;
      if (denom > 1e-6) {
        final diff = a - b;
        histDist += diff * diff / denom;
        histDims++;
      }
    }
    if (histDims > 0) histDist = math.sqrt(histDist / histDims);

    // 2. 标量标准化欧氏距离
    double scalarDist = 0;
    var scalarDims = 0;
    for (var i = 0;
        i < 9 &&
            i < fingerprint.scalarFeatures.length &&
            i < scalarMeans.length;
        i++) {
      final v = fingerprint.scalarFeatures[i];
      // 缺失维度（-1 或 NaN）跳过（无脸照片的 STI/FLC 不影响其他维度匹配）
      if (v.isNaN || v == PhotoFingerprint.missing) continue;
      final std = (i < scalarStds.length && scalarStds[i] > 0.001)
          ? scalarStds[i]
          : 1.0;
      final diff = (v - scalarMeans[i]) / std;
      scalarDist += diff * diff;
      scalarDims++;
    }
    if (scalarDims > 0) scalarDist = math.sqrt(scalarDist / scalarDims);

    // 3. 融合（经验权重：直方图 60%，标量 40%）
    final combinedDist = 0.6 * histDist + 0.4 * scalarDist;
    return math.exp(-combinedDist * combinedDist / 2.0);
  }
}

/// Isolate：从直方图 bytes + toneJson 算指纹
///
/// 纯内存操作，不重新读图（复用 DB 缓存的直方图）。
PhotoFingerprint _computeFingerprintIsolate(_FingerprintArgs args) {
  // 1. 解析直方图（若缓存存在）
  HistogramData? hist;
  if (args.rgbHistogram != null && args.lumHistogram != null) {
    final combined = args.hueHistogram != null
        ? Uint8List.fromList(
            [...args.rgbHistogram!, ...args.lumHistogram!, ...args.hueHistogram!])
        : Uint8List.fromList([...args.rgbHistogram!, ...args.lumHistogram!]);
    hist = HistogramData.fromBytes(combined);
  }

  // 2. 解析 toneJson（ToneResult 扁平字段 + advanced 键）
  final tone = ToneResult.fromJsonString(args.toneJson);
  final adv = AdvancedPortraitMetrics.fromJsonString(args.toneJson);

  // 3. 直方图降维：256 bins → 32 bins/通道（每 8 bin 求和 + 归一化到 [0,1]）
  final histFeatures = List<double>.filled(96, 0.0);
  if (hist != null) {
    var idx = 0;
    for (final channel in [hist.r, hist.g, hist.b]) {
      final total = channel.fold<int>(0, (a, b) => a + b);
      for (var i = 0; i < 256; i += 8) {
        var sum = 0;
        for (var j = i; j < i + 8 && j < 256; j++) {
          sum += channel[j];
        }
        histFeatures[idx++] = total > 0 ? sum / total : 0.0;
      }
    }
  }

  // 4. 标量特征（顺序与 PhotoFingerprint.scalarLabels 一致）
  // [rms_contrast, warm_cold_ratio, black_point, white_point, entropy,
  //  scs, sls, sti, flc]
  final scalarFeatures = <double>[
    tone?.rmsContrast ?? PhotoFingerprint.missing,
    _warmColdRatio(hist),
    adv?.blackPointOffset ?? PhotoFingerprint.missing,
    adv?.whitePointCompression ?? PhotoFingerprint.missing,
    tone?.entropy ?? PhotoFingerprint.missing,
    tone?.scs ?? PhotoFingerprint.missing,
    tone?.sls ?? PhotoFingerprint.missing,
    adv?.skinSti ?? PhotoFingerprint.missing,
    adv?.faceLightingContrast ?? PhotoFingerprint.missing,
  ];

  return PhotoFingerprint(
      histogramFeatures: histFeatures, scalarFeatures: scalarFeatures);
}

double _warmColdRatio(HistogramData? hist) {
  if (hist?.hue == null) return PhotoFingerprint.missing;
  return calculateWarmToColdRatio(hist!.hue!);
}
