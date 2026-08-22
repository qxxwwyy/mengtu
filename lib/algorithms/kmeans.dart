// kmeans.dart — K-Means++ 色彩量化算法
//
// K-Means++ 改进了初始中心点的选取：第一个中心随机选，后续中心
// 以"到已有中心的距离平方"为概率权重选取，使初始中心尽可能分散。
// 然后迭代执行 assign → update 直到收敛或达到最大迭代次数。
//
// 适用于摄影照片取色，比 MMCQ 更适合提取"感知均匀"的色块。

import 'dart:math' as math;

/// K-Means++ 提取结果
class KMeansResult {
  /// 聚类中心色（ARGB int）
  final List<int> colors;

  /// 每个聚类包含的像素数（用于占比计算）
  final List<int> counts;

  KMeansResult({required this.colors, required this.counts});
}

/// K-Means++ 算法入口
///
/// [pixels] ARGB int 列表（0xAARRGGBB）
/// [k] 聚类数量（3-8）
/// [maxIterations] 最大迭代次数
KMeansResult kmeansPlusPlus(
  List<int> pixels, {
  int k = 5,
  int maxIterations = 20,
}) {
  if (pixels.isEmpty || k <= 0) {
    return KMeansResult(colors: [], counts: []);
  }

  final n = pixels.length;
  k = math.min(k, n); // 不能超过像素数

  // --- RGB 提取 ---
  final r = List<int>.filled(n, 0);
  final g = List<int>.filled(n, 0);
  final b = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    r[i] = (pixels[i] >> 16) & 0xFF;
    g[i] = (pixels[i] >> 8) & 0xFF;
    b[i] = pixels[i] & 0xFF;
  }

  // --- K-Means++ 初始化 ---
  final rng = math.Random(42); // 固定种子保证可复现
  final centers = <int>[rng.nextInt(n)]; // 第一个中心随机选

  for (var c = 1; c < k; c++) {
    // 计算每个点到最近中心的距离平方
    final distSq = List<double>.filled(n, double.maxFinite);
    for (var i = 0; i < n; i++) {
      for (final ci in centers) {
        final dr = r[i] - r[ci];
        final dg = g[i] - g[ci];
        final db = b[i] - b[ci];
        final d = (dr * dr + dg * dg + db * db).toDouble();
        if (d < distSq[i]) distSq[i] = d;
      }
    }

    // 以距离平方为权重选取下一个中心
    final totalDist = distSq.fold<double>(0, (a, v) => a + v);
    if (totalDist == 0) break; // 所有点相同
    var target = rng.nextDouble() * totalDist;
    var selected = n - 1;
    for (var i = 0; i < n; i++) {
      target -= distSq[i];
      if (target <= 0) {
        selected = i;
        break;
      }
    }
    centers.add(selected);
  }

  // 当前聚类中心 RGB
  var cr = List<int>.filled(k, 0);
  var cg = List<int>.filled(k, 0);
  var cb = List<int>.filled(k, 0);
  for (var c = 0; c < centers.length; c++) {
    cr[c] = r[centers[c]];
    cg[c] = g[centers[c]];
    cb[c] = b[centers[c]];
  }

  // --- 迭代 ---
  final assignments = List<int>.filled(n, 0);
  final actualK = centers.length;

  for (var iter = 0; iter < maxIterations; iter++) {
    var changed = false;

    // Assign：每个点分到最近的中心
    for (var i = 0; i < n; i++) {
      var bestCluster = 0;
      var bestDist = double.maxFinite;
      for (var c = 0; c < actualK; c++) {
        final dr = r[i] - cr[c];
        final dg = g[i] - cg[c];
        final db = b[i] - cb[c];
        final d = (dr * dr + dg * dg + db * db).toDouble();
        if (d < bestDist) {
          bestDist = d;
          bestCluster = c;
        }
      }
      if (assignments[i] != bestCluster) {
        assignments[i] = bestCluster;
        changed = true;
      }
    }

    if (!changed && iter > 0) break; // 收敛

    // Update：重新计算中心
    final sumR = List<int>.filled(actualK, 0);
    final sumG = List<int>.filled(actualK, 0);
    final sumB = List<int>.filled(actualK, 0);
    final cnt = List<int>.filled(actualK, 0);
    for (var i = 0; i < n; i++) {
      final c = assignments[i];
      sumR[c] += r[i];
      sumG[c] += g[i];
      sumB[c] += b[i];
      cnt[c]++;
    }
    for (var c = 0; c < actualK; c++) {
      if (cnt[c] > 0) {
        cr[c] = sumR[c] ~/ cnt[c];
        cg[c] = sumG[c] ~/ cnt[c];
        cb[c] = sumB[c] ~/ cnt[c];
      }
    }
  }

  // --- 输出结果 ---
  final colors = <int>[];
  final counts = <int>[];
  for (var c = 0; c < actualK; c++) {
    final count = assignments.where((a) => a == c).length;
    if (count > 0) {
      colors.add(0xFF000000 | (cr[c] << 16) | (cg[c] << 8) | cb[c]);
      counts.add(count);
    }
  }

  return KMeansResult(colors: colors, counts: counts);
}
