// tone_service_test.dart — 影调分析测试（五区域占比、基调判定、统计指标）
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/tone_service.dart';
import 'package:mengtu/models/tone_result.dart';

void main() {
  group('analyzeTone 暗调图片', () {
    test('大部分像素在黑色区(0-51) → 低调 + 黑色占比高', () {
      // 构造直方图：峰值在 bin 30，大部分在黑色区
      final lumHist = List.filled(256, 0);
      lumHist[30] = 500;
      for (var i = 0; i <= 51; i++) {
        lumHist[i] += 10;
      }

      final tone = analyzeTone(lumHist);

      expect(tone.toneKey, 'low');
      expect(tone.blacks, greaterThan(50));
      expect(tone.peakPosition, 30);
      expect(tone.minVal, lessThanOrEqualTo(51));
      expect(tone.maxVal, lessThanOrEqualTo(51));
    });
  });

  group('analyzeTone 高调图片', () {
    test('大部分像素在白色区(205-255) → 高调 + 白色占比高', () {
      final lumHist = List.filled(256, 0);
      lumHist[220] = 500;
      for (var i = 205; i <= 255; i++) {
        lumHist[i] += 10;
      }

      final tone = analyzeTone(lumHist);

      expect(tone.toneKey, 'high');
      expect(tone.whites, greaterThan(50));
      expect(tone.peakPosition, 220);
      expect(tone.minVal, greaterThanOrEqualTo(205));
    });
  });

  group('analyzeTone 中间调图片', () {
    test('大部分像素在 103-153 → 中间调', () {
      final lumHist = List.filled(256, 0);
      for (var i = 103; i <= 153; i++) {
        lumHist[i] = 20;
      }

      final tone = analyzeTone(lumHist);

      expect(tone.toneKey, 'mid');
      expect(tone.midtones, greaterThan(80));
      expect(tone.peakPosition, greaterThanOrEqualTo(103));
      expect(tone.peakPosition, lessThanOrEqualTo(153));
    });
  });

  group('analyzeTone 全长调图片', () {
    test('阴影和高光都有显著占比（>15%）→ 全长调', () {
      final lumHist = List.filled(256, 0);
      // 阴影区(52-102) 占 ~40%
      for (var i = 52; i <= 102; i++) {
        lumHist[i] = 10;
      }
      // 高光区(154-204) 占 ~40%
      for (var i = 154; i <= 204; i++) {
        lumHist[i] = 10;
      }

      final tone = analyzeTone(lumHist);

      expect(tone.toneKey, 'full');
      expect(tone.shadows, greaterThan(15));
      expect(tone.highlights, greaterThan(15));
    });

    test('黑场+白场为主中间稀疏 → 全长调（回归：合并段判定）', () {
      // 典型高对比全长调：大量纯黑 + 大量纯白，中间段几乎没有
      // 旧逻辑只看 shadows/highlights（中间偏暗/偏亮段），会漏判成 mid
      // 新逻辑用 dark=blacks+shadows / light=highlights+whites，能正确判 full
      final lumHist = List.filled(256, 0);
      // 黑场（blacks 区 0-51）占 40%
      for (var i = 0; i <= 51; i++) {
        lumHist[i] = 8;
      }
      // 白场（whites 区 205-255）占 40%
      for (var i = 205; i <= 255; i++) {
        lumHist[i] = 8;
      }
      // 中间几乎无内容

      final tone = analyzeTone(lumHist);

      // dark = blacks+shadows，blacks 占大头；light = highlights+whites，whites 占大头
      expect(tone.toneKey, 'full');
    });
  });

  group('analyzeTone 五区域占比', () {
    test('各区域像素严格落入对应区间', () {
      // 每个区域各放 100 像素，验证分界点 51/102/153/204 正确
      final lumHist = List.filled(256, 0);
      lumHist[10] = 100; // 黑色区
      lumHist[80] = 100; // 阴影区
      lumHist[128] = 100; // 中间调区
      lumHist[180] = 100; // 高光区
      lumHist[240] = 100; // 白色区

      final tone = analyzeTone(lumHist);

      // 五段各占 20%
      expect(tone.blacks, closeTo(20, 0.1));
      expect(tone.shadows, closeTo(20, 0.1));
      expect(tone.midtones, closeTo(20, 0.1));
      expect(tone.highlights, closeTo(20, 0.1));
      expect(tone.whites, closeTo(20, 0.1));
    });

    test('分界点边界值归属正确（bin=51/102/153/204）', () {
      // bin 正好落在分界点上：51→黑色, 102→阴影, 153→中间调, 204→高光
      final lumHist = List.filled(256, 0);
      lumHist[51] = 100; // 边界：i<=51 → 黑色
      lumHist[102] = 100; // 边界：i<=102 → 阴影
      lumHist[153] = 100; // 边界：i<=153 → 中间调
      lumHist[204] = 100; // 边界：i<=204 → 高光

      final tone = analyzeTone(lumHist);

      // 四段各 25%，白色为 0
      expect(tone.blacks, closeTo(25, 0.1));
      expect(tone.shadows, closeTo(25, 0.1));
      expect(tone.midtones, closeTo(25, 0.1));
      expect(tone.highlights, closeTo(25, 0.1));
      expect(tone.whites, closeTo(0, 0.1));
    });

    test('五段占比之和恒等于 100%', () {
      // 用一张分布较散的图，验证不会漏算某段
      final lumHist = List.filled(256, 0);
      for (var i = 0; i < 256; i++) {
        lumHist[i] = (i * 7) % 50; // 伪随机分布
      }

      final tone = analyzeTone(lumHist);

      final sum = tone.blacks + tone.shadows + tone.midtones +
          tone.highlights + tone.whites;
      expect(sum, closeTo(100, 0.5));
    });
  });

  group('analyzeTone 统计指标', () {
    test('均值计算正确', () {
      // 全部像素集中在 bin 100，均值 = 100
      final lumHist = List.filled(256, 0);
      lumHist[100] = 1000;

      final tone = analyzeTone(lumHist);
      expect(tone.mean, closeTo(100, 0.1));
    });

    test('标准差为 0（所有像素同一亮度）', () {
      final lumHist = List.filled(256, 0);
      lumHist[100] = 1000;

      final tone = analyzeTone(lumHist);
      expect(tone.std, closeTo(0, 0.1));
    });

    test('标准差 > 0（像素分散）', () {
      final lumHist = List.filled(256, 0);
      lumHist[0] = 500;
      lumHist[255] = 500;

      final tone = analyzeTone(lumHist);
      expect(tone.std, greaterThan(100));
    });

    test('中位数计算正确', () {
      final lumHist = List.filled(256, 0);
      lumHist[50] = 100;
      lumHist[150] = 100;

      final tone = analyzeTone(lumHist);
      // 中位数应该在 50-150 之间
      expect(tone.median, greaterThanOrEqualTo(50));
      expect(tone.median, lessThanOrEqualTo(150));
    });

    test('峰值位置 = 像素数最多的 bin', () {
      final lumHist = List.filled(256, 0);
      lumHist[42] = 999;
      lumHist[100] = 10;

      final tone = analyzeTone(lumHist);
      expect(tone.peakPosition, 42);
    });
  });

  group('analyzeTone 跨度判定', () {
    test('全范围分布 → long', () {
      final lumHist = List.filled(256, 0);
      lumHist[0] = 100;
      lumHist[255] = 100;

      final tone = analyzeTone(lumHist);
      expect(tone.toneRange, 'long');
    });

    test('窄范围分布 → short', () {
      final lumHist = List.filled(256, 0);
      lumHist[100] = 100;
      lumHist[105] = 100;

      final tone = analyzeTone(lumHist);
      expect(tone.toneRange, 'short');
    });
  });

  group('analyzeTone 边界情况', () {
    test('空直方图（全 0）返回默认值', () {
      final lumHist = List.filled(256, 0);
      final tone = analyzeTone(lumHist);

      expect(tone.mean, 0);
      expect(tone.confidence, 0);
      expect(tone.toneKey, 'mid');
    });
  });

  group('ToneResult 序列化', () {
    test('toJsonString → fromJsonString 往返保持一致', () {
      final original = ToneResult(
        mean: 128.5,
        median: 130,
        std: 45.2,
        minVal: 10,
        maxVal: 250,
        peakPosition: 155,
        blacks: 10.0,
        shadows: 15.3,
        midtones: 60.1,
        highlights: 24.6,
        whites: 5.0,
        toneKey: 'mid',
        toneRange: 'long',
        confidence: 0.35,
      );

      final json = original.toJsonString();
      final restored = ToneResult.fromJsonString(json);

      expect(restored, isNotNull);
      expect(restored!.mean, original.mean);
      expect(restored.median, original.median);
      expect(restored.std, original.std);
      expect(restored.blacks, original.blacks);
      expect(restored.whites, original.whites);
      expect(restored.toneKey, original.toneKey);
      expect(restored.confidence, original.confidence);
    });

    test('旧三段缓存（缺 blacks/whites）读不出 → 返回 null 自动重算', () {
      // 模拟升级前的旧 JSON：只有 shadows/midtones/highlights
      const legacyJson =
          '{"mean":100,"median":95,"std":30,"minVal":5,"maxVal":240,'
          '"peakPosition":90,"shadows":20,"midtones":60,"highlights":20,'
          '"toneKey":"mid","toneRange":"long","confidence":0.5}';
      // 缺 blacks/whites → 强转抛 TypeError → try/catch 捕获 → 返回 null
      expect(ToneResult.fromJsonString(legacyJson), isNull);
    });

    test('fromJsonString(null) 返回 null', () {
      expect(ToneResult.fromJsonString(null), isNull);
    });

    test('fromJsonString("") 返回 null', () {
      expect(ToneResult.fromJsonString(''), isNull);
    });

    test('fromJsonString(非法JSON) 返回 null', () {
      expect(ToneResult.fromJsonString('not json'), isNull);
    });
  });

  group('ToneResult 标签', () {
    test('toneKeyLabel 中文映射', () {
      ToneResult makeTone(String key) => ToneResult(
            mean: 0, median: 0, std: 0, minVal: 0, maxVal: 0,
            peakPosition: 0,
            blacks: 0, shadows: 0, midtones: 0, highlights: 0, whites: 0,
            toneKey: key, toneRange: 'long', confidence: 0,
          );
      expect(makeTone('high').toneKeyLabel, '高调');
      expect(makeTone('low').toneKeyLabel, '低调');
      expect(makeTone('mid').toneKeyLabel, '中间调');
      expect(makeTone('full').toneKeyLabel, '全长调');
    });

    test('toneRangeLabel 中文映射', () {
      ToneResult makeTone(String range) => ToneResult(
            mean: 0, median: 0, std: 0, minVal: 0, maxVal: 0,
            peakPosition: 0,
            blacks: 0, shadows: 0, midtones: 0, highlights: 0, whites: 0,
            toneKey: 'mid', toneRange: range, confidence: 0,
          );
      expect(makeTone('long').toneRangeLabel, '长跨度');
      expect(makeTone('medium').toneRangeLabel, '中跨度');
      expect(makeTone('short').toneRangeLabel, '短跨度');
    });
  });
}
