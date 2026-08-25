// insight_service_test.dart — 洞察引擎 v2 测试（通透度诊断 + 风格判定 + 词典文案）
//
// v8.1 新增覆盖：
// - clarityInsight 四档（通透/空气感/偏闷/硬朗）—— 调研最大痛点母题的翻译
// - 风格判定（日系清透/胶片感灰调/港风怀旧/电影感/古典等，用户叫法）
// - 文案含调研词典锚点（"发灰不通透"/数值锚点）
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/advanced_portrait_metrics.dart';
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/services/insight_service.dart';

ToneResult _tone({
  double mean = 128,
  double rms = 45,
  String toneKey = 'mid',
  String toneRange = 'medium',
  double entropy = 6.0,
}) {
  return ToneResult(
    mean: mean,
    median: mean,
    std: rms,
    minVal: 0,
    maxVal: 255,
    peakPosition: mean,
    blacks: 10,
    shadows: 20,
    midtones: 40,
    highlights: 20,
    whites: 10,
    toneKey: toneKey,
    toneRange: toneRange,
    confidence: 0.8,
    entropy: entropy,
    rmsContrast: rms,
  );
}

AdvancedPortraitMetrics _adv({double bp = 8, double wp = 250}) {
  return AdvancedPortraitMetrics(
    blackPointOffset: bp,
    whitePointCompression: wp,
    tenTonalType: '中中调',
  );
}

void main() {
  final service = InsightService();

  group('通透度诊断（clarityInsight）', () {
    test('黑位上提 + 低对比 → 偏闷（含"发灰不通透"用户语言）', () {
      final insight = service.generate(
        tone: _tone(rms: 25),
        advanced: _adv(bp: 18),
        skin: const SkinAnalysis(),
      );
      expect(insight.clarityInsight, contains('偏闷'));
      expect(insight.clarityInsight, contains('发灰'));
      // 数值锚点
      expect(insight.clarityInsight, contains('18'));
      expect(insight.clarityInsight, contains('25'));
    });

    test('黑位上提 + 对比适中 → 空气感（胶片/电影手法）', () {
      final insight = service.generate(
        tone: _tone(rms: 45),
        advanced: _adv(bp: 14),
        skin: const SkinAnalysis(),
      );
      expect(insight.clarityInsight, contains('空气感'));
    });

    test('黑位触底 + 高对比 → 硬朗', () {
      final insight = service.generate(
        tone: _tone(rms: 60),
        advanced: _adv(bp: 1),
        skin: const SkinAnalysis(),
      );
      expect(insight.clarityInsight, contains('硬朗'));
    });

    test('黑位扎实 + 对比足够 → 通透（默认良好区间）', () {
      final insight = service.generate(
        tone: _tone(rms: 45),
        advanced: _adv(bp: 8),
        skin: const SkinAnalysis(),
      );
      expect(insight.clarityInsight, contains('通透'));
    });

    test('tone 为 null → 影调分析中，不抛异常', () {
      final insight = service.generate(
        tone: null,
        advanced: null,
        skin: const SkinAnalysis(),
      );
      expect(insight.tonalInsight, '影调分析中…');
      expect(insight.clarityInsight, '');
    });
  });

  group('风格判定（v8.1 用户叫法）', () {
    test('高调 + 低对比 + 黑位上提 → 日系清透', () {
      final insight = service.generate(
        tone: _tone(mean: 145, rms: 28),
        advanced: _adv(bp: 10),
        skin: const SkinAnalysis(),
      );
      expect(insight.styleLabel, '日系清透');
      expect(insight.summary, contains('日系清透'));
    });

    test('中低调 + 低对比 + 黑位明显上提 → 胶片感灰调（v8.1 新增）', () {
      final insight = service.generate(
        tone: _tone(mean: 115, rms: 30),
        advanced: _adv(bp: 15),
        skin: const SkinAnalysis(),
      );
      expect(insight.styleLabel, '胶片感灰调');
      expect(insight.summary, contains('手法不是事故'));
    });

    test('中低调 + 高对比 + 黑点低 → 港风怀旧', () {
      final insight = service.generate(
        tone: _tone(mean: 105, rms: 55),
        advanced: _adv(bp: 3),
        skin: const SkinAnalysis(),
      );
      expect(insight.styleLabel, '港风怀旧');
    });

    test('全长调 + 高对比 → 电影感（青橙向）', () {
      final insight = service.generate(
        tone: _tone(rms: 60, toneKey: 'full', toneRange: 'long'),
        advanced: _adv(bp: 8),
        skin: const SkinAnalysis(),
      );
      expect(insight.styleLabel, '电影感（青橙向）');
    });

    test('中间调 + 低对比 + 低饱和肤色 → 中式古典', () {
      final insight = service.generate(
        tone: _tone(mean: 130, rms: 25),
        advanced: _adv(bp: 8),
        skin: const SkinAnalysis(hueOffset: 5, saturation: 20),
      );
      expect(insight.styleLabel, '中式古典');
    });
  });

  group('调研词典文案', () {
    test('肤色暖偏 → "偏黄气"', () {
      final insight = service.generate(
        tone: _tone(),
        advanced: _adv(),
        skin: const SkinAnalysis(hueOffset: 15, saturation: 45),
      );
      expect(insight.colorInsight, contains('偏黄气'));
    });

    test('肤色冷偏 → "偏粉气"', () {
      final insight = service.generate(
        tone: _tone(),
        advanced: _adv(),
        skin: const SkinAnalysis(hueOffset: -15, saturation: 45),
      );
      expect(insight.colorInsight, contains('偏粉气'));
    });

    test('高明度低饱和肤色 → "奶油感方向"', () {
      final insight = service.generate(
        tone: _tone(),
        advanced: _adv(),
        skin: const SkinAnalysis(
            hueOffset: 5, saturation: 30, skinLuminance: 68),
      );
      expect(insight.colorInsight, contains('奶油感'));
    });

    test('主体亮隔离 → "跳出来"人话', () {
      final insight = service.generate(
        tone: _tone(),
        advanced: _adv(),
        skin: const SkinAnalysis(
            hueOffset: 5, saturation: 40, luminanceSeparation: 22),
      );
      expect(insight.techniqueInsight, contains('跳出来'));
    });
  });
}
