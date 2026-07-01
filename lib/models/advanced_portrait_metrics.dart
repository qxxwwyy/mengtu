// advanced_portrait_metrics.dart — v3.5 高级人像数理指标
//
// 序列化到 Photos.toneJson 的 'advanced' 键（与现有 ToneResult 的扁平字段共存）。
// 由 advancedMetricsProvider 合并写入（PR2 实现），直方图可算部分由 tone_service 计算。
//
// 重算策略（遵循 gotcha #39 模式）:
// - blackPointOffset / whitePointCompression / tenTonalType:
//   纯直方图可算 → 强制重算（缺字段抛 TypeError → fromJsonString try/catch 捕获返回 null
//   → provider 自动重算）
//
// v7.0：skinSti / faceLightingContrast 已移除（原依赖 MediaPipe Face Mesh 468 点网格，
// SCRFD 只给 5 点无法计算）。旧缓存含 skin_sti/face_lighting_contrast 键会被 fromJson
// 忽略（向前兼容）。
import 'dart:convert';

/// v3.5 高级人像数理指标
///
/// 序列化到 `Photos.toneJson` 的 `advanced` 键，与 [ToneResult] 的扁平字段
/// 共存于同一 toneJson 字符串（由 provider 合并读取）。
class AdvancedPortraitMetrics {
  /// 1% 累计暗部阶调位移 [0, 255]（强制重算，纯直方图可算）
  ///
  /// 在亮度直方图累计分布中，找累计像素占比达到 0.5%~2% 的灰度级，
  /// 取滑动平均作为黑点偏移。<4 表示死黑触底（电影调/港风标志）。
  final double blackPointOffset;

  /// 99% 累计高光阶调位移 [0, 255]（强制重算，纯直方图可算）
  ///
  /// 在亮度直方图累计分布中，找累计像素占比达到 98%~99.5% 的灰度级，
  /// 取滑动平均作为白点压缩。
  final double whitePointCompression;

  /// 十大影调（复用 toneKey×toneRange，基于像素分布）
  ///
  /// 例如："高长调" / "高短调" / "中长调" / "全长调"。
  /// 不引入 plan.md 的 mean/stdDev 阈值分类（与现有基于像素分布的基调+跨度判定冲突）。
  final String tenTonalType;

  const AdvancedPortraitMetrics({
    required this.blackPointOffset,
    required this.whitePointCompression,
    required this.tenTonalType,
  });

  Map<String, dynamic> toJson() => {
        'black_point_offset': blackPointOffset,
        'white_point_compression': whitePointCompression,
        'ten_tonal_type': tenTonalType,
      };

  factory AdvancedPortraitMetrics.fromJson(Map<String, dynamic> j) =>
      AdvancedPortraitMetrics(
        // 强制重算：纯直方图可算指标缺字段 → 强转抛 TypeError
        // → fromJsonString 的 try/catch 捕获返回 null → provider 自动重算
        blackPointOffset: (j['black_point_offset'] as num).toDouble(),
        whitePointCompression: (j['white_point_compression'] as num).toDouble(),
        tenTonalType: j['ten_tonal_type'] as String,
        // v7.0：skin_sti/face_lighting_contrast 键已废弃，旧缓存含则忽略
      );

  /// 从 toneJson 字符串解析 advanced 子对象
  ///
  /// - toneJson 为 null/空/非法 → 返回 null
  /// - toneJson 不含 advanced 键（旧缓存或 PR1 阶段）→ 返回 null（触发重算）
  /// - advanced 子对象缺强制字段 → fromJson 抛错 → try/catch 返回 null（触发重算）
  static AdvancedPortraitMetrics? fromJsonString(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final adv = decoded['advanced'];
      if (adv == null) return null; // 旧缓存无 advanced 键 → null → 触发重算
      return AdvancedPortraitMetrics.fromJson(adv as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 把本指标合并写入现有 toneJson 字符串的 'advanced' 键（只写不读，避免循环）
  ///
  /// 保留 toneJson 中其它键（ToneResult 扁平字段）不变，仅覆盖/新增 advanced。
  static String mergeIntoToneJson(String? existingToneJson, AdvancedPortraitMetrics metrics) {
    // 用可变 Map（const {} 不可写，base['advanced']=... 会抛 UnsupportedOperation）
    var base = <String, dynamic>{};
    if (existingToneJson != null && existingToneJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(existingToneJson);
        if (decoded is Map<String, dynamic>) {
          base = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // 旧 JSON 非法：丢弃，仅保留 advanced
      }
    }
    base['advanced'] = metrics.toJson();
    return jsonEncode(base);
  }
}
