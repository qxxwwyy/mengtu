// tone_service_test.dart — 影调分析测试（三区域占比、基调判定、统计指标）
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/tone_service.dart';
import 'package:mengtu/models/tone_result.dart';

void main() {
  group('analyzeTone 暗调图片', () {
    test('大部分像素在 0-85 → 低调 + 暗部占比高', () {
      // 构造直方图：峰值在 bin 30，大部分在暗部
      final lumHist = List.filled(256, 0);
      lumHist[30] = 500;
      for (var i = 0; i <= 85; i++) {
        lumHist[i] += 10;
      }

      final tone = analyzeTone(lumHist);

      expect(tone.toneKey, 'low');
      expect(tone.shadows, greaterThan(50));
      expect(tone.peakPosition, 30);
      expect(tone.minVal, lessThanOrEqualTo(85));
      expect(tone.maxVal, lessThanOrEqualTo(85));
    });
  });

  group('analyzeTone 高调图片', () {
    test('大部分像素在 171-255 → 高调 + 亮部占比高', () {
      final lumHist = List.filled(256, 0);
      lumHist[220] = 500;
      for (var i = 171; i <= 255; i++) {
        lumHist[i] += 10;
      }

      final tone = analyzeTone(lumHist);

      expect(tone.toneKey, 'high');
      expect(tone.highlights, greaterThan(50));
      expect(tone.peakPosition, 220);
      expect(tone.minVal, greaterThanOrEqualTo(171));
    });
  });

  group('analyzeTone 中间调图片', () {
    test('大部分像素在 86-170 → 中间调', () {
      final lumHist = List.filled(256, 0);
      for (var i = 86; i <= 170; i++) {
        lumHist[i] = 20;
      }

      final tone = analyzeTone(lumHist);

      expect(tone.toneKey, 'mid');
      expect(tone.midtones, greaterThan(80));
      expect(tone.peakPosition, greaterThanOrEqualTo(86));
      expect(tone.peakPosition, lessThanOrEqualTo(170));
    });
  });

  group('analyzeTone 全长调图片', () {
    test('暗部和亮部都有显著占比（>15%）→ 全长调', () {
      final lumHist = List.filled(256, 0);
      // 暗部占 40%
      for (var i = 0; i <= 85; i++) {
        lumHist[i] = 10;
      }
      // 亮部占 40%
      for (var i = 171; i <= 255; i++) {
        lumHist[i] = 10;
      }

      final tone = analyzeTone(lumHist);

      expect(tone.toneKey, 'full');
      expect(tone.shadows, greaterThan(15));
      expect(tone.highlights, greaterThan(15));
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
        shadows: 15.3,
        midtones: 60.1,
        highlights: 24.6,
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
      expect(restored.toneKey, original.toneKey);
      expect(restored.confidence, original.confidence);
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
            peakPosition: 0, shadows: 0, midtones: 0, highlights: 0,
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
            peakPosition: 0, shadows: 0, midtones: 0, highlights: 0,
            toneKey: 'mid', toneRange: range, confidence: 0,
          );
      expect(makeTone('long').toneRangeLabel, '长跨度');
      expect(makeTone('medium').toneRangeLabel, '中跨度');
      expect(makeTone('short').toneRangeLabel, '短跨度');
    });
  });
}
