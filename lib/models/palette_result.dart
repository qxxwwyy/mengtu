// palette_result.dart — 色卡提取结果模型
import 'dart:convert';

/// 单个主色（ARGB + 占比）
class PaletteColor {
  final int argb; // ARGB int（0xAARRGGBB）
  final double ratio; // 占比百分比 0-100

  const PaletteColor({required this.argb, required this.ratio});

  factory PaletteColor.fromJson(Map<String, dynamic> json) => PaletteColor(
        argb: json['argb'] as int,
        ratio: (json['ratio'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'argb': argb, 'ratio': ratio};

  int get r => (argb >> 16) & 0xFF;
  int get g => (argb >> 8) & 0xFF;
  int get b => argb & 0xFF;
}

/// 色卡提取结果（多个主色）
class PaletteResult {
  final List<PaletteColor> colors;

  const PaletteResult({required this.colors});

  factory PaletteResult.empty() => const PaletteResult(colors: []);

  factory PaletteResult.fromJson(List<dynamic> json) => PaletteResult(
        colors: json
            .map((e) => PaletteColor.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String toJsonString() => jsonEncode(colors.map((c) => c.toJson()).toList());

  static PaletteResult fromJsonString(String? json) {
    if (json == null || json.isEmpty) return PaletteResult.empty();
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return PaletteResult.fromJson(list);
    } catch (_) {
      return PaletteResult.empty();
    }
  }
}
