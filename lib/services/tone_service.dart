// tone_service.dart — 影调分析服务
//
// 复用直方图的亮度数据计算影调统计，不重新读图。
// 五区域划分：blacks(0-51) / shadows(52-102) / midtones(103-153) / highlights(154-204) / whites(205-255)
// 基调判定：基于峰值位置 + 区域占比
// 跨度判定：基于最值分布范围
//
// v3.0：新增数理审美指标（一维信息熵 + RMS 对比度），仍为纯内存计算。
// 肤色 ROI 指标由 face_service + tone_service.analyzeToneFull 协同计算（Phase 2）。
//
// 参考取色卡 tone_analysis.py 的影调分类规则（仅功能设计参考，独立实现）
import 'dart:math' as math;
import '../models/tone_result.dart';

/// 从亮度直方图（256 bins）计算影调分析结果（纯内存版，不含肤色 ROI）
///
/// [lumHist] 是 Rec.709 亮度直方图，来自 HistogramData.lum
/// 这是纯内存计算（遍历 256 个 bin），极快，不需要 Isolate
ToneResult analyzeTone(List<int> lumHist) {
  final total = lumHist.fold<int>(0, (a, b) => a + b);
  if (total == 0) {
    return ToneResult(
      mean: 0,
      median: 0,
      std: 0,
      minVal: 0,
      maxVal: 0,
      peakPosition: 0,
      blacks: 0,
      shadows: 0,
      midtones: 0,
      highlights: 0,
      whites: 0,
      toneKey: 'mid',
      toneRange: 'short',
      confidence: 0,
      entropy: 0,
      rmsContrast: 0,
    );
  }

  // 均值
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * lumHist[i];
  }
  final mean = sum / total;

  // 中位数
  var cumulative = 0;
  var median = 0;
  final half = total ~/ 2;
  for (var i = 0; i < 256; i++) {
    cumulative += lumHist[i];
    if (cumulative >= half) {
      median = i;
      break;
    }
  }

  // 标准差
  var varianceSum = 0.0;
  for (var i = 0; i < 256; i++) {
    if (lumHist[i] > 0) {
      final d = i - mean;
      varianceSum += d * d * lumHist[i];
    }
  }
  final std = math.sqrt(varianceSum / total);

  // 最小/最大值（有像素的最暗/最亮 bin）
  var minVal = 255;
  var maxVal = 0;
  for (var i = 0; i < 256; i++) {
    if (lumHist[i] > 0) {
      if (i < minVal) minVal = i;
      if (i > maxVal) maxVal = i;
    }
  }

  // 峰值位置（像素数最多的 bin）
  var peakPosition = 0.0;
  var peakCount = 0;
  for (var i = 0; i < 256; i++) {
    if (lumHist[i] > peakCount) {
      peakCount = lumHist[i];
      peakPosition = i.toDouble();
    }
  }

  // 五区域占比（按像素数，分界点 51/102/153/204 与直方图视觉分界线对齐）
  var blacksCount = 0;
  var shadowsCount = 0;
  var midtonesCount = 0;
  var highlightsCount = 0;
  var whitesCount = 0;
  for (var i = 0; i < 256; i++) {
    if (i <= 51) {
      blacksCount += lumHist[i];
    } else if (i <= 102) {
      shadowsCount += lumHist[i];
    } else if (i <= 153) {
      midtonesCount += lumHist[i];
    } else if (i <= 204) {
      highlightsCount += lumHist[i];
    } else {
      whitesCount += lumHist[i];
    }
  }
  final blacks = blacksCount / total * 100;
  final shadows = shadowsCount / total * 100;
  final midtones = midtonesCount / total * 100;
  final highlights = highlightsCount / total * 100;
  final whites = whitesCount / total * 100;

  // 基调判定：用合并段（暗部=blacks+shadows，亮部=highlights+whites）判定全长调
  final toneKey = _classifyToneKey(peakPosition, blacks, shadows, highlights, whites);
  final toneRange = _classifyToneRange(minVal, maxVal);
  final confidence = _calcConfidence(toneKey, peakCount, total);

  // ============ v3.0 新增：信息熵 + RMS 对比度 ============
  final entropy = _calculateEntropy(lumHist, total);
  // RMS 对比度 = 亮度标准差，与 std 同源（保留语义独立字段）
  final rmsContrast = std;

  return ToneResult(
    mean: mean,
    median: median.toDouble(),
    std: std,
    minVal: minVal,
    maxVal: maxVal,
    peakPosition: peakPosition,
    blacks: blacks,
    shadows: shadows,
    midtones: midtones,
    highlights: highlights,
    whites: whites,
    toneKey: toneKey,
    toneRange: toneRange,
    confidence: confidence,
    entropy: entropy,
    rmsContrast: rmsContrast,
  );
}

/// 基调判定（参考取色卡 tone_analysis.py 分类规则）
///
/// 全长调用合并段判定：暗部 = blacks + shadows，亮部 = highlights + whites，
/// 两端都有显著占比（>15%）即为全长调。这样能正确识别"黑场+白场为主、
/// 中间稀疏"的高对比图（单看 shadows/highlights 会漏判）。
///
/// peak 阈值 85/171 沿用旧值（bin 索引），与 5 段分界 51/102/153/204 独立，
/// 用于判定峰值偏向暗端还是亮端。
String _classifyToneKey(
    double peak, double blacks, double shadows, double highlights, double whites) {
  final dark = blacks + shadows;
  final light = highlights + whites;
  // 全长调：暗部和亮部都有显著占比（>15%）
  if (dark > 15 && light > 15) return 'full';
  // 按峰值位置判定
  if (peak <= 85) return 'low'; // 低调（峰值偏暗端）
  if (peak >= 171) return 'high'; // 高调（峰值偏亮端）
  return 'mid'; // 中间调
}

/// 跨度判定（基于最值分布范围）
String _classifyToneRange(int minVal, int maxVal) {
  final range = maxVal - minVal;
  if (range >= 200) return 'long'; // 长跨度（几乎覆盖全范围）
  if (range >= 100) return 'medium'; // 中跨度
  return 'short'; // 短跨度（低对比度）
}

/// 置信度：峰值的显著程度
double _calcConfidence(String toneKey, int peakCount, int total) {
  if (total == 0) return 0;
  final peakRatio = peakCount / total;
  // 峰值越集中，置信度越高（0-1）
  return peakRatio.clamp(0.0, 1.0);
}

/// 一维信息熵（基于亮度直方图概率分布）
///
/// E = -Σ p_i · log2(p_i)
/// 低熵 (<5.2) → 背景纯净；高熵 (>7.3) → 背景杂乱
double _calculateEntropy(List<int> lumHist, int total) {
  if (total == 0) return 0.0;
  double entropy = 0.0;
  for (var i = 0; i < 256; i++) {
    final count = lumHist[i];
    if (count > 0) {
      final p = count / total;
      entropy -= p * (math.log(p) / math.ln2);
    }
  }
  return entropy;
}

// ============ v3.0 色彩空间对齐（Display P3 / Adobe RGB → sRGB 补偿）============

/// Display P3 → sRGB 的 3×3 线性变换矩阵补偿
///
/// 用于 RAW 导出的广色域照片：未补偿时肤色 HSL 会被误报为偏黄，
/// 在 HSL 肤色分析前对像素做此变换，让结果与 sRGB 调色软件一致。
/// 参考 W3C CSS Color 4 色彩转换数学（chromatic adaptation）。
List<int> convertP3ToSrgb(int rP3, int gP3, int bP3) {
  final rNorm = rP3 / 255.0;
  final gNorm = gP3 / 255.0;
  final bNorm = bP3 / 255.0;

  // Display P3 → sRGB 变换矩阵（线性化后的精确推导）
  final rSrgb = 1.2249 * rNorm - 0.2247 * gNorm;
  final gSrgb = -0.0420 * rNorm + 1.0420 * gNorm;
  final bSrgb = -0.0197 * rNorm - 0.0786 * gNorm + 1.0983 * bNorm;

  return [
    (rSrgb * 255.0).round().clamp(0, 255),
    (gSrgb * 255.0).round().clamp(0, 255),
    (bSrgb * 255.0).round().clamp(0, 255),
  ];
}

/// 计算肤色色相偏差角 ΔH（相对达芬奇肤色线 17°）
///
/// 返回 -180~180 的环形最短距离：
/// - ΔH > +5° → 偏黄绿（蜡黄病态）
/// - ΔH < -5° → 偏紫红（充血醉酒）
double skinHueOffset(double avgSkinHue) {
  const target = 17.0;
  var diff = avgSkinHue - target;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return diff;
}

/// 冷暖比例计算（HSL 色相直方图 360 bins）
///
/// 暖色：H∈[0°,60°]∪[300°,360°]；冷色：H∈[150°,250°]
/// Ratio = warm / cold
double calculateWarmToColdRatio(List<int> hueHist) {
  var warmCount = 0;
  var coldCount = 0;
  for (var h = 0; h < 360; h++) {
    final count = hueHist[h];
    if (h <= 60 || h >= 300) {
      warmCount += count;
    } else if (h >= 150 && h <= 250) {
      coldCount += count;
    }
  }
  if (coldCount == 0) return warmCount.toDouble();
  return warmCount / coldCount;
}
