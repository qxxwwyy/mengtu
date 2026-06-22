// replication_hints_test.dart — 复刻参数生成测试（v3.5 PR5）
//
// 覆盖 spec §5.4 测试列表：
// 1. 黑点 < 4 → 生成"保持触底"hint
// 2. 黑点 ≥ 4 → 生成"上提至 X%"hint
// 3. 白点 > 252 → "保持触顶"
// 4. ΔH > +5 → 生成"橙色色相左调"hint
// 5. 高饱和（>60）→ "橙色饱和度"hint
// 6. 无脸（skin null）→ 跳过色彩 hints，只生成影调 hints
// 7. 目标档案模板叠加
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/advanced_portrait_metrics.dart';
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/services/replication_hints_service.dart';

void main() {
  late ReplicationHintsService service;

  setUp(() {
    service = ReplicationHintsService();
  });

  /// 构造测试 ToneResult（复刻参数只用其中 skin 字段）
  ToneResult buildTone() => ToneResult(
        mean: 128,
        median: 125,
        std: 45,
        minVal: 10,
        maxVal: 250,
        peakPosition: 125,
        blacks: 10,
        shadows: 20,
        midtones: 40,
        highlights: 20,
        whites: 10,
        toneKey: 'mid',
        toneRange: 'long',
        confidence: 0.5,
        entropy: 6.5,
        rmsContrast: 50,
      );

  group('影调复刻参数', () {
    test('黑点 < 4 → "保持触底"', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 2.0,
        whitePointCompression: 250.0,
        tenTonalType: '低调',
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: null,
      );
      final blackHint = hints.firstWhere((h) => h.parameter == '黑点端点');
      expect(blackHint.value, contains('触底'));
      expect(blackHint.value, contains('0'));
    });

    test('黑点 ≥ 4 → "上提至 X%"', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 8.0,
        whitePointCompression: 248.0,
        tenTonalType: '高调',
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: null,
      );
      final blackHint = hints.firstWhere((h) => h.parameter == '黑点端点');
      expect(blackHint.value, contains('上提'));
      expect(blackHint.value, contains('8'));
    });

    test('白点 > 252 → "保持触顶"', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 5.0,
        whitePointCompression: 254.0,
        tenTonalType: '高调',
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: null,
      );
      final whiteHint = hints.firstWhere((h) => h.parameter == '白点端点');
      expect(whiteHint.value, contains('触顶'));
      expect(whiteHint.value, contains('255'));
    });

    test('白点 ≤ 252 → "压回 X"', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 5.0,
        whitePointCompression: 245.0,
        tenTonalType: '中调',
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: null,
      );
      final whiteHint = hints.firstWhere((h) => h.parameter == '白点端点');
      expect(whiteHint.value, contains('压回'));
      expect(whiteHint.value, contains('245'));
    });
  });

  group('色彩复刻参数', () {
    test('ΔH > +5 → "橙色色相左调"', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 5.0,
        whitePointCompression: 248.0,
        tenTonalType: '中调',
      );
      const skin = SkinAnalysis(
        hueOffset: 12.0,
        saturation: 40.0,
        skinLuminance: 65.0,
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: skin,
      );
      final hueHint = hints.firstWhere((h) => h.parameter == '橙色色相');
      expect(hueHint.value, contains('左调'));
      // 12 * 1.2 = 14.4 → round 14
      expect(hueHint.value, contains('14'));
    });

    test('ΔH < -5 → "橙色色相右调"', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 5.0,
        whitePointCompression: 248.0,
        tenTonalType: '中调',
      );
      const skin = SkinAnalysis(
        hueOffset: -8.0,
        saturation: 40.0,
        skinLuminance: 65.0,
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: skin,
      );
      final hueHint = hints.firstWhere((h) => h.parameter == '橙色色相');
      expect(hueHint.value, contains('右调'));
    });

    test('高饱和（>60）→ 生成"橙色饱和度"hint', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 5.0,
        whitePointCompression: 248.0,
        tenTonalType: '中调',
      );
      const skin = SkinAnalysis(
        hueOffset: 3.0, // ΔH < 5 不生成色相 hint
        saturation: 75.0,
        skinLuminance: 65.0,
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: skin,
      );
      final satHint = hints.firstWhere((h) => h.parameter == '橙色饱和度');
      expect(satHint.value, contains('-'));
    });

    test('无脸（skin null）→ 只生成影调 hints，无色彩 hints', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 5.0,
        whitePointCompression: 248.0,
        tenTonalType: '中调',
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: null,
      );
      // 只有影调 hints（黑点 + 白点），无色彩 hints（橙色色相/饱和度）
      expect(hints.any((h) => h.parameter == '黑点端点'), isTrue);
      expect(hints.any((h) => h.parameter == '白点端点'), isTrue);
      expect(hints.any((h) => h.parameter == '橙色色相'), isFalse);
      expect(hints.any((h) => h.parameter == '橙色饱和度'), isFalse);
    });

    test('ΔH 绝对值 ≤ 5 → 不生成色相 hint', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 5.0,
        whitePointCompression: 248.0,
        tenTonalType: '中调',
      );
      const skin = SkinAnalysis(
        hueOffset: 3.0,
        saturation: 40.0,
        skinLuminance: 65.0,
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: skin,
      );
      expect(hints.any((h) => h.parameter == '橙色色相'), isFalse);
    });
  });

  group('目标档案模板叠加', () {
    test('传入 targetTemplate → 追加到 hints 末尾', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 5.0,
        whitePointCompression: 248.0,
        tenTonalType: '中调',
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: null,
        targetStyleKey: 'japanese',
        targetTemplate: const [
          ReplicationHint(
              category: '曝光',
              parameter: '全局曝光',
              value: '+0.3 EV',
              note: '提亮'),
        ],
      );
      // 模板 hint 应在末尾
      final exposureHint = hints.lastWhere((h) => h.parameter == '全局曝光');
      expect(exposureHint.value, '+0.3 EV');
    });

    test('空 targetTemplate → 不追加', () {
      const advanced = AdvancedPortraitMetrics(
        blackPointOffset: 5.0,
        whitePointCompression: 248.0,
        tenTonalType: '中调',
      );
      final hints = service.generateHints(
        tone: buildTone(),
        advanced: advanced,
        skin: null,
        targetTemplate: const [],
      );
      // 只有影调 hints
      expect(hints.length, 2); // 黑点 + 白点
    });
  });
}
