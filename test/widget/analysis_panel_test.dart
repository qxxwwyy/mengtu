// analysis_panel_test.dart — ToneInfoCard Widget 测试
//
// 注：AnalysisPanel 和 ColorCard 依赖 DB provider，需要完整的数据库 mock，
// 在 flutter_test 中有 timer/async 问题。这里只测 ToneInfoCard（纯 UI 组件）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/widgets/tone_info_card.dart';
import 'package:mengtu/models/tone_result.dart';

void main() {
  group('ToneInfoCard 渲染', () {
    ToneResult buildTone({
      String toneKey = 'mid',
      String toneRange = 'long',
      double blacks = 10,
      double shadows = 20,
      double midtones = 40,
      double highlights = 20,
      double whites = 10,
    }) {
      return ToneResult(
        mean: 128,
        median: 125,
        std: 45,
        minVal: 10,
        maxVal: 250,
        peakPosition: 125,
        blacks: blacks,
        shadows: shadows,
        midtones: midtones,
        highlights: highlights,
        whites: whites,
        toneKey: toneKey,
        toneRange: toneRange,
        confidence: 0.5,
      );
    }

    testWidgets('渲染基调标签', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToneInfoCard(tone: buildTone(toneKey: 'high')),
          ),
        ),
      );

      expect(find.text('高调'), findsOneWidget);
    });

    testWidgets('渲染五区域占比条', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToneInfoCard(tone: buildTone()),
          ),
        ),
      );

      expect(find.text('黑色'), findsOneWidget);
      expect(find.textContaining('中间调'), findsWidgets);
      expect(find.text('白色'), findsOneWidget);
    });

    testWidgets('渲染统计指标', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToneInfoCard(tone: buildTone()),
          ),
        ),
      );

      expect(find.text('均值'), findsOneWidget);
      expect(find.text('中位数'), findsOneWidget);
      expect(find.text('标准差'), findsOneWidget);
      expect(find.text('峰值'), findsOneWidget);
      expect(find.text('最暗'), findsOneWidget);
      expect(find.text('最亮'), findsOneWidget);
    });

    testWidgets('低调标签渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToneInfoCard(tone: buildTone(toneKey: 'low')),
          ),
        ),
      );

      expect(find.text('低调'), findsOneWidget);
    });

    testWidgets('全长调标签渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToneInfoCard(tone: buildTone(toneKey: 'full')),
          ),
        ),
      );

      expect(find.text('全长调'), findsOneWidget);
    });

    testWidgets('跨度标签渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToneInfoCard(
                tone: buildTone(toneKey: 'mid', toneRange: 'short')),
          ),
        ),
      );

      expect(find.textContaining('短跨度'), findsOneWidget);
    });
  });
}
