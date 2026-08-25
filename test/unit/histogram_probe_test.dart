// histogram_probe_test.dart — 直方图触摸读数纯函数测试
//
// 覆盖：bin 换算、五区命名（分界 51/102/153/204）、占比、RGB 分量、
// 空数据/零总量守卫、越界 clamp（gotcha #65：painter 盲区 → 纯函数可测）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/widgets/charts/interactive_histogram.dart';

HistogramData _uniform() {
  // 全 256 bin 每 bin 10 个像素（总量 2560），ratio 可预测
  final ch = List<int>.filled(256, 10);
  return HistogramData(r: ch, g: ch, b: ch, lum: List<int>.from(ch));
}

void main() {
  group('zoneNameOfBin 五区命名', () {
    test('分界点 51/102/153/204 与影调分析一致', () {
      expect(zoneNameOfBin(0), '黑色');
      expect(zoneNameOfBin(51), '黑色');
      expect(zoneNameOfBin(52), '阴影');
      expect(zoneNameOfBin(102), '阴影');
      expect(zoneNameOfBin(103), '中间调');
      expect(zoneNameOfBin(153), '中间调');
      expect(zoneNameOfBin(154), '高光');
      expect(zoneNameOfBin(204), '高光');
      expect(zoneNameOfBin(205), '白色');
      expect(zoneNameOfBin(255), '白色');
    });
  });

  group('histogramProbeAt', () {
    test('x → bin 换算（左端/中间/右端）', () {
      final data = _uniform();
      final probe1 = histogramProbeAt(data, 0, 256);
      final probe2 = histogramProbeAt(data, 128, 256);
      final probe3 = histogramProbeAt(data, 255.9, 256);
      expect(probe1!.bin, 0);
      expect(probe2!.bin, 128);
      expect(probe3!.bin, 255);
    });

    test('均匀分布占比 = 1/256 ≈ 0.39%', () {
      final probe = histogramProbeAt(_uniform(), 128, 256)!;
      expect(probe.lumRatio, closeTo(10 / 2560, 1e-9));
      expect(probe.zoneName, '中间调');
    });

    test('RGB 分量比例正确', () {
      final data = _uniform();
      // R 通道 bin 100 改成 20（总量 2570）→ rRatio = 20/2570
      final r = List<int>.from(data.r);
      r[100] = 20;
      final d2 = HistogramData(r: r, g: data.g, b: data.b, lum: data.lum);
      final probe = histogramProbeAt(d2, 100, 256)!;
      expect(probe.rRatio, closeTo(20 / 2570, 1e-9));
      expect(probe.gRatio, closeTo(10 / 2560, 1e-9));
    });

    test('亮度全零 → null（无有效数据）', () {
      final zero = HistogramData(
          r: List<int>.filled(256, 0),
          g: List<int>.filled(256, 0),
          b: List<int>.filled(256, 0),
          lum: List<int>.filled(256, 0));
      expect(histogramProbeAt(zero, 100, 256), isNull);
    });

    test('宽度 0 → null 守卫', () {
      expect(histogramProbeAt(_uniform(), 100, 0), isNull);
    });

    test('越界触摸 clamp 到 0~255', () {
      final data = _uniform();
      expect(histogramProbeAt(data, -50, 256)!.bin, 0);
      expect(histogramProbeAt(data, 9999, 256)!.bin, 255);
    });
  });
}
