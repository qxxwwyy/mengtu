// harmony_service_test.dart — 配色和谐度分析测试
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/harmony_service.dart';
import 'package:mengtu/models/palette_result.dart';

void main() {
  group('analyzeHarmony 空数据', () {
    test('空色卡 → unknown', () {
      final result = analyzeHarmony(PaletteResult(colors: []));
      expect(result.type, HarmonyType.unknown);
      expect(result.confidence, 0);
    });
  });

  group('analyzeHarmony 单色', () {
    test('纯灰度（无色相）→ monochromatic', () {
      final palette = PaletteResult(colors: [
        PaletteColor(argb: 0xFF808080, ratio: 1.0),
      ]);
      final result = analyzeHarmony(palette);
      expect(result.type, HarmonyType.monochromatic);
      expect(result.confidence, greaterThan(0.8));
    });

    test('单一彩色 → monochromatic', () {
      final palette = PaletteResult(colors: [
        PaletteColor(argb: 0xFFFF0000, ratio: 1.0), // 纯红 h=0
      ]);
      final result = analyzeHarmony(palette);
      expect(result.type, HarmonyType.monochromatic);
      expect(result.hues, [0]);
    });
  });

  group('analyzeHarmony 双色配色', () {
    test('邻近色（色相差 <30）→ analogous', () {
      // 红(0) + 橙(20) → 差 20 < 30
      final palette = PaletteResult(colors: [
        PaletteColor(argb: 0xFFFF0000, ratio: 0.5), // h=0
        PaletteColor(argb: 0xFFFF5500, ratio: 0.5), // h≈20
      ]);
      final result = analyzeHarmony(palette);
      expect(result.type, HarmonyType.analogous);
    });

    test('互补色（色相差 ~180）→ complementary', () {
      // 红(0) + 青(180)
      final palette = PaletteResult(colors: [
        PaletteColor(argb: 0xFFFF0000, ratio: 0.5), // h=0
        PaletteColor(argb: 0xFF00FFFF, ratio: 0.5), // h=180
      ]);
      final result = analyzeHarmony(palette);
      expect(result.type, HarmonyType.complementary);
    });

    test('三角色（色相差 ~120）→ triadic', () {
      // 红(0) + 绿(120)
      final palette = PaletteResult(colors: [
        PaletteColor(argb: 0xFFFF0000, ratio: 0.5), // h=0
        PaletteColor(argb: 0xFF00FF00, ratio: 0.5), // h=120
      ]);
      final result = analyzeHarmony(palette);
      expect(result.type, HarmonyType.triadic);
    });

    test('四角色（色相差 ~90）→ tetradic', () {
      // 红(0) + 黄绿(90)
      final palette = PaletteResult(colors: [
        PaletteColor(argb: 0xFFFF0000, ratio: 0.5), // h=0
        PaletteColor(argb: 0xFF80FF00, ratio: 0.5), // h≈90
      ]);
      final result = analyzeHarmony(palette);
      expect(result.type, HarmonyType.tetradic);
    });
  });

  group('analyzeHarmony 冷暖描述', () {
    test('暖色系邻近色描述含"暖色系"', () {
      // 红(0) + 橙(20)，avg=10 < 60 → 暖色
      final palette = PaletteResult(colors: [
        PaletteColor(argb: 0xFFFF0000, ratio: 0.5),
        PaletteColor(argb: 0xFFFF5500, ratio: 0.5),
      ]);
      final result = analyzeHarmony(palette);
      expect(result.description, contains('暖色系'));
    });

    test('冷色系邻近色 → analogous 类型', () {
      // 青(180) + 青蓝(190)，差 10 < 30 → analogous
      final palette = PaletteResult(colors: [
        PaletteColor(argb: 0xFF00FFFF, ratio: 0.5), // h=180
        PaletteColor(argb: 0xFF0099FF, ratio: 0.5), // h≈190
      ]);
      final result = analyzeHarmony(palette);
      expect(result.type, HarmonyType.analogous);
      // 冷色（avg hue 185 在 180-270 范围）
      expect(result.hues.every((h) => h >= 180 && h <= 270), isTrue);
    });
  });

  group('analyzeHarmony 置信度', () {
    test('所有结果的 confidence 在 0-1 范围', () {
      final cases = [
        PaletteResult(colors: []),
        PaletteResult(colors: [PaletteColor(argb: 0xFF808080, ratio: 1.0)]),
        PaletteResult(colors: [
          PaletteColor(argb: 0xFFFF0000, ratio: 0.5),
          PaletteColor(argb: 0xFF00FFFF, ratio: 0.5),
        ]),
      ];
      for (final p in cases) {
        final result = analyzeHarmony(p);
        expect(result.confidence, inInclusiveRange(0, 1));
      }
    });
  });
}
