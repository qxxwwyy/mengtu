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
  Uint8List toBytes() {
    final all = <int>[...r, ...g, ...b, ...lum];
    // hue 可能为 null（旧缓存或无色相计算），存 360 个 0
    all.addAll(hue ?? List.filled(360, 0));
    final u16 = Uint16List.fromList(all);
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
  });

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
