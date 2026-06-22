// style_profile_match.dart — 档案匹配结果（v3.5 PR4）
//
// 一张照片与一个风格档案的匹配结果，含相似度 + 样本数（用于分层置信度）。
// 由 styleProfileMatchProvider 产出，供 StageArchiveMatchCard 渲染。
import 'photo_fingerprint.dart';

/// 档案匹配结果
class StyleProfileMatch {
  /// 档案 ID
  final String profileId;

  /// 档案名称（如「王家卫港风」或内置「日系小清新」）
  final String profileName;

  /// 相似度 [0, 1]
  final double similarity;

  /// 档案样本数（用于分层置信度：N<5 定性，N>=5 显示 %）
  final int sampleCount;

  /// 是否为内置理论档案
  final bool isBuiltin;

  /// 内置档案的 key（japanese/hongkong/cinematic/chinoiserie）
  final String? builtinKey;

  /// 当前照片指纹（供 FingerprintRadar 对比用）
  final PhotoFingerprint currentFingerprint;

  const StyleProfileMatch({
    required this.profileId,
    required this.profileName,
    required this.similarity,
    required this.sampleCount,
    this.isBuiltin = false,
    this.builtinKey,
    required this.currentFingerprint,
  });

  /// 分层置信度文本（spec §3.9 O6）
  ///
  /// N<5：只显示定性（方向接近 / 差异较大）+ 置信度提示
  /// N>=5：显示 % 相似度
  String get similarityText {
    if (isBuiltin) {
      // 内置理论档案 n=0，始终显示 % 但标注「理论参照」
      return '${(similarity * 100).round()}% 相似（理论参照）';
    }
    if (sampleCount < 5) {
      return similarity > 0.7 ? '方向接近' : '差异较大';
    }
    return '${(similarity * 100).round()}% 相似';
  }

  /// 置信度提示（小样本时显示，否则 null）
  String? get confidenceHint {
    if (isBuiltin) return '基于理论推导值，非统计基准';
    if (sampleCount < 5) return '仅 $sampleCount 张样本，结果仅供参考';
    if (sampleCount < 15) return '基于 $sampleCount 张样本';
    return null;
  }
}
