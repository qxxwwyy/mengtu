// tone_result.dart — 影调分析结果模型
import 'dart:convert';
import 'dart:typed_data';

/// 直方图数据
class HistogramData {
  final List<int> r; // 256
  final List<int> g; // 256
  final List<int> b; // 256
  final List<int> lum; // 256
  final List<int>? hue; // 360 (nullable，RC 阶段新增)

  HistogramData({
    required this.r,
    required this.g,
    required this.b,
    required this.lum,
    this.hue,
  });

  /// 从 RGB + lum `List<int>` 构造
  factory HistogramData.fromLists(List<int> rgb, List<int> lum) {
    return HistogramData(
      r: rgb.sublist(0, 256),
      g: rgb.sublist(256, 512),
      b: rgb.sublist(512, 768),
      lum: lum,
    );
  }

  /// 序列化为 Uint16List bytes（每个 bin 2 字节，最大 65535）
  ///
  /// v1.0.0 布局：`[R(256×2) | G(256×2) | B(256×2) | Lum(256×2) | Hue(360×2)]` = 2768 bytes
  /// 旧格式（无 hue）：2048 bytes，fromBytes 会检测长度
  ///
  /// 注意：每个 bin 在序列化前 clamp 到 65535，防止大图降采样后单 bin 计数
  /// 超过 Uint16 范围（如纯色图 75 万像素集中在一个 bin）
  Uint8List toBytes() {
    final all = <int>[...r, ...g, ...b, ...lum];
    // hue 可能为 null（旧缓存或无色相计算），存 360 个 0
    all.addAll(hue ?? List.filled(360, 0));
    // clamp 到 Uint16 范围，避免极端单色图溢出
    final clamped = all.map((v) => v > 65535 ? 65535 : v).toList();
    final u16 = Uint16List.fromList(clamped);
    return u16.buffer.asUint8List();
  }

  /// 从 bytes 反序列化（Uint16List 格式）
  /// 兼容旧格式（2048 bytes，无 hue）和新格式（2768 bytes，含 hue）
  factory HistogramData.fromBytes(Uint8List bytes) {
    final u16 = Uint16List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 2);
    final all = u16.toList();
    final hasHue = all.length > 1024; // 旧格式 1024 bins，新格式 1384 bins（1024+360）
    return HistogramData(
      r: all.sublist(0, 256),
      g: all.sublist(256, 512),
      b: all.sublist(512, 768),
      lum: all.sublist(768, 1024),
      hue: hasHue ? all.sublist(1024, 1384) : null,
    );
  }
}

/// 人像肤色分析结果（v3.0 新增）
///
/// 当 [ToneService.analyzeTone] 完整版计算（含 ROI）时填充；
/// 当无脸检测、或仅基于直方图的纯内存计算时为 null。
/// 序列化到 toneJson 后，旧缓存缺这些字段 → null（不触发重算，由 Phase 2 按需补算）。
///
/// v7.0：STI/FLC 字段已移除（原依赖 MediaPipe Face Mesh 468 点网格，
/// SCRFD 只给 5 点无法计算）。旧缓存含 sti/flc 键会被 fromJson 忽略（向前兼容）。
class SkinAnalysis {
  /// 肤色色相偏差角 ΔH（相对 17° 达芬奇肤色线，-180~180）
  final double? hueOffset;

  /// 肤色平均饱和度（百分比 0~100）
  final double? saturation;

  /// 肤色-背景明度隔离度 SLS（百分比，皮肤 L − 背景 L）
  final double? luminanceSeparation;

  /// 肤色-背景色彩隔离度 SCS（色相环形最短距离，0~180）
  final double? colorSeparation;

  /// 肤色平均明度（百分比 0~100）
  final double? skinLuminance;

  /// 背景平均明度（百分比 0~100）
  final double? bgLuminance;

  /// 肤色像素分布 2D 直方图（hue×sat bins），用于矢量示波器像素云渲染。
  ///
  /// 扁平化一维数组：hueBins × satBins = 48 × 8 = 384 个 int。
  /// 索引 = hueBin * 8 + satBin，每 bin 存采样像素计数。
  /// null = 手动校准模式或旧缓存，示波器回退到单点渲染。
  final List<int>? hueSatBins;

  /// hueSatBins 的 hue 分 bin 数
  static const int hueBinCount = 48;

  /// hueSatBins 的 sat 分 bin 数
  static const int satBinCount = 8;

  const SkinAnalysis({
    this.hueOffset,
    this.saturation,
    this.luminanceSeparation,
    this.colorSeparation,
    this.skinLuminance,
    this.bgLuminance,
    this.hueSatBins,
  });

  bool get isEmpty =>
      hueOffset == null &&
      saturation == null &&
      luminanceSeparation == null &&
      colorSeparation == null;

  Map<String, dynamic> toJson() => {
        if (hueOffset != null) 'hueOffset': hueOffset,
        if (saturation != null) 'saturation': saturation,
        if (luminanceSeparation != null)
          'luminanceSeparation': luminanceSeparation,
        if (colorSeparation != null) 'colorSeparation': colorSeparation,
        if (skinLuminance != null) 'skinLuminance': skinLuminance,
        if (bgLuminance != null) 'bgLuminance': bgLuminance,
        if (hueSatBins != null) 'hueSatBins': hueSatBins,
      };

  factory SkinAnalysis.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const SkinAnalysis();
    double? numOrNull(Object? v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    List<int>? intListOrNull(Object? v) {
      if (v == null) return null;
      if (v is List) return v.map((e) => (e as num).toInt()).toList();
      return null;
    }
    return SkinAnalysis(
      hueOffset: numOrNull(j['hueOffset']),
      saturation: numOrNull(j['saturation']),
      luminanceSeparation: numOrNull(j['luminanceSeparation']),
      colorSeparation: numOrNull(j['colorSeparation']),
      skinLuminance: numOrNull(j['skinLuminance']),
      bgLuminance: numOrNull(j['bgLuminance']),
      hueSatBins: intListOrNull(j['hueSatBins']),
      // v7.0：sti/flc 键已废弃，旧缓存含则忽略（向前兼容）
    );
  }
}

/// 影调分析结果
class ToneResult {
  final double mean;
  final double median;
  final double std;
  final int minVal;
  final int maxVal;
  final double peakPosition;
  final double blacks;
  final double shadows;
  final double midtones;
  final double highlights;
  final double whites;
  final String toneKey; // high/mid/low/full
  final String toneRange; // long/medium/short
  final double confidence;

  // ============ v3.0 新增：数理审美指标 ============

  /// 一维信息熵（基于亮度直方图概率分布）
  /// 低熵 (<5.2) → 背景纯净；高熵 (>7.3) → 背景杂乱
  final double entropy;

  /// RMS 对比度（亮度标准差，0~255 区间）
  /// 与 [std] 同源，独立字段保留语义清晰（避免 UI 层混淆）
  final double rmsContrast;

  /// 肤色分析（无脸检测或纯直方图计算时为 [SkinAnalysis.empty]）
  /// 序列化到 toneJson，旧缓存不含 → null skin，由 Phase 2 按需补算
  final SkinAnalysis skin;

  ToneResult({
    required this.mean,
    required this.median,
    required this.std,
    required this.minVal,
    required this.maxVal,
    required this.peakPosition,
    required this.blacks,
    required this.shadows,
    required this.midtones,
    required this.highlights,
    required this.whites,
    required this.toneKey,
    required this.toneRange,
    required this.confidence,
    this.entropy = 0,
    this.rmsContrast = 0,
    this.skin = const SkinAnalysis(),
  });

  // 便捷访问肤色字段（null 安全）
  double? get skinHueOffset => skin.hueOffset;
  double? get skinSat => skin.saturation;
  double? get sls => skin.luminanceSeparation;
  double? get scs => skin.colorSeparation;
  bool get hasSkin => !skin.isEmpty;

  String get toneKeyLabel {
    switch (toneKey) {
      case 'high': return '高调';
      case 'low': return '低调';
      case 'mid': return '中间调';
      case 'full': return '全长调';
      default: return toneKey;
    }
  }

  String get toneRangeLabel {
    switch (toneRange) {
      case 'long':
        return '长跨度';
      case 'medium':
        return '中跨度';
      case 'short':
        return '短跨度';
      default:
        return toneRange;
    }
  }

  Map<String, dynamic> toJson() => {
        'mean': mean,
        'median': median,
        'std': std,
        'minVal': minVal,
        'maxVal': maxVal,
        'peakPosition': peakPosition,
        'blacks': blacks,
        'shadows': shadows,
        'midtones': midtones,
        'highlights': highlights,
        'whites': whites,
        'toneKey': toneKey,
        'toneRange': toneRange,
        'confidence': confidence,
        // v3.0 新增字段（旧缓存缺这些 → fromJson 抛错 → 触发重算）
        'entropy': entropy,
        'rmsContrast': rmsContrast,
        'skin': skin.toJson(),
      };

  factory ToneResult.fromJson(Map<String, dynamic> j) => ToneResult(
        mean: (j['mean'] as num).toDouble(),
        median: (j['median'] as num).toDouble(),
        std: (j['std'] as num).toDouble(),
        minVal: j['minVal'] as int,
        maxVal: j['maxVal'] as int,
        peakPosition: (j['peakPosition'] as num).toDouble(),
        // blacks/whites 不加默认值：旧缓存（3 段）缺这两键 → 强转抛 TypeError
        // → 被 fromJsonString 的 try/catch 捕获返回 null → provider 自动重算
        blacks: (j['blacks'] as num).toDouble(),
        shadows: (j['shadows'] as num).toDouble(),
        midtones: (j['midtones'] as num).toDouble(),
        highlights: (j['highlights'] as num).toDouble(),
        whites: (j['whites'] as num).toDouble(),
        toneKey: j['toneKey'] as String,
        toneRange: j['toneRange'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        // v3.0 新字段：旧缓存缺 entropy/rmsContrast → 强转抛错 → 触发重算
        // skin 字段缺则解析为空（不强制重算，等 Phase 2 按需补算）
        entropy: (j['entropy'] as num).toDouble(),
        rmsContrast: (j['rmsContrast'] as num).toDouble(),
        skin: SkinAnalysis.fromJson(j['skin'] as Map<String, dynamic>?),
      );

  String toJsonString() => jsonEncode(toJson());

  static ToneResult? fromJsonString(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return ToneResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
