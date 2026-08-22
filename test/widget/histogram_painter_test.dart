// histogram_painter_test.dart — HistogramPainter Widget 测试
//
// 测试 CustomPainter 的 shouldRepaint 逻辑和不同模式渲染
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/widgets/histogram_painter.dart';
import 'package:mengtu/models/tone_result.dart';

void main() {
  /// 构建测试直方图数据
  HistogramData buildHistogramData({
    List<int>? r,
    List<int>? g,
    List<int>? b,
    List<int>? lum,
  }) {
    return HistogramData(
      r: r ?? List.filled(256, 0),
      g: g ?? List.filled(256, 0),
      b: b ?? List.filled(256, 0),
      lum: lum ?? List.filled(256, 0),
    );
  }

  HistogramData buildSampleHistogram() {
    final r = List.filled(256, 0);
    final g = List.filled(256, 0);
    final b = List.filled(256, 0);
    final lum = List.filled(256, 0);
    // 在 bin 100 有峰值
    r[100] = 500;
    g[100] = 300;
    b[100] = 200;
    lum[100] = 400;
    return HistogramData(r: r, g: g, b: b, lum: lum);
  }

  group('HistogramPainter shouldRepaint', () {
    test('数据相同 → shouldRepaint = false', () {
      final data = buildSampleHistogram();
      final p1 = HistogramPainter(data: data, mode: HistogramMode.rgb);
      final p2 = HistogramPainter(data: data, mode: HistogramMode.rgb);

      expect(p1.shouldRepaint(p2), isFalse);
    });

    test('数据不同 → shouldRepaint = true', () {
      final p1 = HistogramPainter(
          data: buildSampleHistogram(), mode: HistogramMode.rgb);
      final p2 = HistogramPainter(
          data: buildHistogramData(), mode: HistogramMode.rgb);

      expect(p1.shouldRepaint(p2), isTrue);
    });

    test('模式不同 → shouldRepaint = true', () {
      final data = buildSampleHistogram();
      final p1 = HistogramPainter(data: data, mode: HistogramMode.rgb);
      final p2 = HistogramPainter(data: data, mode: HistogramMode.luminance);

      expect(p1.shouldRepaint(p2), isTrue);
    });
  });

  group('HistogramPainter 渲染', () {
    testWidgets('RGB 模式正常渲染', (tester) async {
      final data = buildSampleHistogram();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 100,
              child: CustomPaint(
                painter: HistogramPainter(data: data, mode: HistogramMode.rgb),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // MaterialApp 自身可能包含 CustomPaint，用 findsWidgets
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('亮度模式正常渲染', (tester) async {
      final data = buildSampleHistogram();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 100,
              child: CustomPaint(
                painter:
                    HistogramPainter(data: data, mode: HistogramMode.luminance),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('单通道 R 模式正常渲染', (tester) async {
      final data = buildSampleHistogram();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 100,
              child: CustomPaint(
                painter: HistogramPainter(data: data, mode: HistogramMode.r),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('全零数据不崩溃（空直方图）', (tester) async {
      final data = buildHistogramData(); // 全零
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 100,
              child: CustomPaint(
                painter: HistogramPainter(data: data, mode: HistogramMode.rgb),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('HistogramMode enum', () {
    test('包含 rgb/luminance/r/g/b/hue/rgbLum 七种模式', () {
      expect(HistogramMode.values.length, 7);
      expect(HistogramMode.values, contains(HistogramMode.rgb));
      expect(HistogramMode.values, contains(HistogramMode.luminance));
      expect(HistogramMode.values, contains(HistogramMode.r));
      expect(HistogramMode.values, contains(HistogramMode.g));
      expect(HistogramMode.values, contains(HistogramMode.b));
      expect(HistogramMode.values, contains(HistogramMode.rgbLum));
    });
  });
}
