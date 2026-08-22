// harmony_service.dart — 色彩和谐度分析
//
// 基于色卡主色的 HSV 色相差异，判定配色方案类型
import '../models/palette_result.dart';
import '../utils/color_utils.dart';

/// 配色方案类型
enum HarmonyType {
  monochromatic('单色系'),
  analogous('邻近色'),
  complementary('互补色'),
  triadic('三角色'),
  splitComplementary('分裂互补'),
  tetradic('四角色'),
  unknown('未分类');

  final String label;
  const HarmonyType(this.label);
}

/// 和谐度分析结果
class HarmonyResult {
  final HarmonyType type;
  final double confidence; // 0-1
  final String description;
  final List<int> hues; // 主色色相列表（0-359）

  const HarmonyResult({
    required this.type,
    required this.confidence,
    required this.description,
    required this.hues,
  });
}

/// 分析色彩和谐度
///
/// 输入 PaletteResult，输出配色方案判定
HarmonyResult analyzeHarmony(PaletteResult palette) {
  if (palette.colors.isEmpty) {
    return const HarmonyResult(
      type: HarmonyType.unknown,
      confidence: 0,
      description: '无可用色彩数据',
      hues: [],
    );
  }

  // 提取各主色的色相
  final hues = <int>[];
  for (final color in palette.colors) {
    final h = rgbToHue(color.r, color.g, color.b);
    if (h >= 0) hues.add(h);
  }

  if (hues.isEmpty) {
    return const HarmonyResult(
      type: HarmonyType.monochromatic,
      confidence: 0.9,
      description: '纯灰度照片，无色相差异',
      hues: [],
    );
  }

  if (hues.length == 1) {
    return HarmonyResult(
      type: HarmonyType.monochromatic,
      confidence: 0.95,
      description: '单色调，色彩统一',
      hues: hues,
    );
  }

  // 取前两个主色的色相差（环形距离）
  final hue1 = hues[0];
  final hue2 = hues.length > 1 ? hues[1] : hues[0];
  final diff = _hueDistance(hue1, hue2);

  // 判定逻辑
  if (diff < 30) {
    final avgHue = hues.reduce((a, b) => a + b) ~/ hues.length;
    return HarmonyResult(
      type: HarmonyType.analogous,
      confidence: 0.85,
      description: _warmColdDescription(avgHue, '邻近配色，视觉和谐统一'),
      hues: hues,
    );
  }

  // 检查互补色（~180°）
  if ((diff - 180).abs() < 30) {
    return HarmonyResult(
      type: HarmonyType.complementary,
      confidence: 0.85,
      description: '互补配色，对比强烈，视觉冲击力大',
      hues: hues,
    );
  }

  // 检查三角色（~120°）
  if ((diff - 120).abs() < 25) {
    return HarmonyResult(
      type: HarmonyType.triadic,
      confidence: 0.75,
      description: '三角色配色，色彩平衡且丰富',
      hues: hues,
    );
  }

  // 检查分裂互补（~150° 或 ~210°）
  if ((diff - 150).abs() < 20 || (diff - 210).abs() < 20) {
    return HarmonyResult(
      type: HarmonyType.splitComplementary,
      confidence: 0.7,
      description: '分裂互补配色，既有对比又不刺眼',
      hues: hues,
    );
  }

  // 检查四角色（~90°）
  if ((diff - 90).abs() < 20) {
    return HarmonyResult(
      type: HarmonyType.tetradic,
      confidence: 0.65,
      description: '四角色配色，色彩丰富但需谨慎平衡',
      hues: hues,
    );
  }

  return HarmonyResult(
    type: HarmonyType.unknown,
    confidence: 0.3,
    description: '混合配色，无明显的和谐度规律',
    hues: hues,
  );
}

/// 计算两个色相之间的环形最短距离（0-180）
int _hueDistance(int h1, int h2) {
  var diff = (h1 - h2).abs() % 360;
  if (diff > 180) diff = 360 - diff;
  return diff;
}

/// 根据平均色相描述冷暖
String _warmColdDescription(int avgHue, String base) {
  // 暖色：0-60, 300-360；冷色：180-270
  if (avgHue < 60 || avgHue > 300) {
    return '暖色系$base';
  } else if (avgHue > 180 && avgHue < 270) {
    return '冷色系$base';
  }
  return base;
}
