// tone_result_test.dart — HistogramData + ToneResult 数据模型测试
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/tone_result.dart';

void main() {
  group('HistogramData 构造', () {
    test('fromLists 正确分割 RGB 三通道', () {
      final rgb = List.generate(768, (i) => i);
      final lum = List.generate(256, (i) => i * 2);

      final data = HistogramData.fromLists(rgb, lum);

      expect(data.r.first, 0);
      expect(data.g.first, 256);
      expect(data.b.first, 512);
      expect(data.lum.first, 0);
      expect(data.lum.last, 510);
    });
  });

  group('HistogramData 序列化', () {
    test('toBytes → fromBytes 往返保持一致（Uint16List）', () {
      final r = List.generate(256, (i) => i * 100);
      final g = List.generate(256, (i) => 50000 - i * 50);
      final b = List.generate(256, (i) => i * 200);
      final lum = List.generate(256, (i) => i * 37);

      final original = HistogramData(r: r, g: g, b: b, lum: lum);
      final bytes = original.toBytes();

      // v1.0.0: 4 channels × 256 bins × 2 bytes + hue 360 × 2 = 2768 bytes
      expect(bytes.length, 2768);

      final restored = HistogramData.fromBytes(bytes);
      expect(restored.r, equals(r));
      expect(restored.g, equals(g));
      expect(restored.b, equals(b));
      expect(restored.lum, equals(lum));
    });

    test('Uint16List 不截断大值（回归保护，防退回 Uint8List）', () {
      final data = HistogramData(
        r: List.filled(256, 300),
        g: List.filled(256, 60000),
        b: List.filled(256, 65535),
        lum: List.filled(256, 12345),
      );

      final bytes = data.toBytes();
      final restored = HistogramData.fromBytes(bytes);

      expect(restored.r.first, 300);
      expect(restored.g.first, 60000);
      expect(restored.b.first, 65535);
      expect(restored.lum.first, 12345);
    });

    test('fromBytes 正确解析 Uint16List 视图（带 offset）', () {
      // 模拟 v1.0.0 新格式（含 hue 360 bins）
      final r = List.filled(256, 42);
      final g = List.filled(256, 84);
      final b = List.filled(256, 168);
      final lum = List.filled(256, 255);
      final hue = List.filled(360, 99);

      final u16 = Uint16List.fromList([...r, ...g, ...b, ...lum, ...hue]);
      final bytes = u16.buffer.asUint8List();

      final restored = HistogramData.fromBytes(bytes);
      expect(restored.r.first, 42);
      expect(restored.g.first, 84);
      expect(restored.b.first, 168);
      expect(restored.lum.first, 255);
      expect(restored.hue!.first, 99);
    });
  });

  group('HistogramData 边界值', () {
    test('全零直方图', () {
      final data = HistogramData(
        r: List.filled(256, 0),
        g: List.filled(256, 0),
        b: List.filled(256, 0),
        lum: List.filled(256, 0),
      );
      final bytes = data.toBytes();
      final restored = HistogramData.fromBytes(bytes);
      expect(restored.r.every((v) => v == 0), isTrue);
    });
  });

  group('ToneResult JSON 序列化', () {
    test('toJson 包含所有字段', () {
      final tone = ToneResult(
        mean: 100, median: 95, std: 30, minVal: 5, maxVal: 240,
        peakPosition: 90,
        blacks: 10, shadows: 20, midtones: 40, highlights: 20, whites: 10,
        toneKey: 'mid', toneRange: 'long', confidence: 0.5,
      );
      final json = tone.toJson();
      expect(json.containsKey('mean'), isTrue);
      expect(json.containsKey('toneKey'), isTrue);
      expect(json.containsKey('confidence'), isTrue);
      expect(json.containsKey('blacks'), isTrue);
      expect(json.containsKey('whites'), isTrue);
      // v3.0 新增 entropy/rmsContrast/skin 三键
      expect(json.containsKey('entropy'), isTrue);
      expect(json.containsKey('rmsContrast'), isTrue);
      expect(json.containsKey('skin'), isTrue);
      expect(json.length, 17);
    });

    test('v3.0 新增字段（entropy/rmsContrast/skin）默认值', () {
      final tone = ToneResult(
        mean: 100, median: 95, std: 30, minVal: 5, maxVal: 240,
        peakPosition: 90,
        blacks: 10, shadows: 20, midtones: 40, highlights: 20, whites: 10,
        toneKey: 'mid', toneRange: 'long', confidence: 0.5,
      );
      expect(tone.entropy, 0);
      expect(tone.rmsContrast, 0);
      expect(tone.hasSkin, isFalse);
      expect(tone.skinHueOffset, isNull);
    });

    test('含肤色分析的字段往返保持一致', () {
      final tone = ToneResult(
        mean: 100, median: 95, std: 30, minVal: 5, maxVal: 240,
        peakPosition: 90,
        blacks: 10, shadows: 20, midtones: 40, highlights: 20, whites: 10,
        toneKey: 'mid', toneRange: 'long', confidence: 0.5,
        entropy: 7.5,
        rmsContrast: 65.2,
        skin: const SkinAnalysis(
          hueOffset: 6.3,
          saturation: 42.0,
          luminanceSeparation: 18.5,
          colorSeparation: 145.0,
          skinLuminance: 68.0,
          bgLuminance: 49.5,
        ),
      );
      final restored = ToneResult.fromJsonString(tone.toJsonString());
      expect(restored, isNotNull);
      expect(restored!.entropy, 7.5);
      expect(restored.rmsContrast, 65.2);
      expect(restored.skinHueOffset, 6.3);
      expect(restored.skinSat, 42.0);
      expect(restored.sls, 18.5);
      expect(restored.scs, 145.0);
      expect(restored.skin.skinLuminance, 68.0);
      expect(restored.skin.bgLuminance, 49.5);
      expect(restored.hasSkin, isTrue);
    });

    test('SkinAnalysis.fromJson(null) 返回空', () {
      final s = SkinAnalysis.fromJson(null);
      expect(s.isEmpty, isTrue);
      expect(s.hueOffset, isNull);
    });
  });
}
