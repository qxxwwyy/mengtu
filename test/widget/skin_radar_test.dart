// skin_radar_test.dart — 肤色示波器（vectorscope）widget 测试（v6.2 / v8.0 改）
//
// v8.0 语气改造：判定文案从诊断式改为描述式
// - "对齐肤色线" → "贴近肤色线"
// - "轻微偏离/肤色偏色" → "暖偏移/冷偏移"（附场景提示）
//
// SkinRadar 是纯 StatelessWidget（CustomPaint），不需要 ProviderScope。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/widgets/grading/skin_radar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: child,
          ),
        ),
      );

  testWidgets('空 SkinAnalysis 显示「未检出肤色」占位', (tester) async {
    await tester.pumpWidget(wrap(const SkinRadar(skin: SkinAnalysis())));

    expect(find.text('肤色示波器'), findsOneWidget);
    expect(find.text('未检出肤色'), findsOneWidget);
    expect(
        find.textContaining('光点越靠近黄色「肤色线」'), findsOneWidget);
  });

  testWidgets('ΔH 贴近（5°）→ 「贴近肤色线」', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: 5, saturation: 40),
    )));

    expect(find.text('贴近肤色线'), findsOneWidget);
    expect(find.text('5°'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('ΔH 暖偏移（30°）→ 暖偏移标签', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: 30, saturation: 75),
    )));

    expect(find.textContaining('暖偏移'), findsOneWidget);
    expect(find.text('30°'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('ΔH 负值（冷偏移）→ 冷偏移标签', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: -12, saturation: 35),
    )));

    expect(find.textContaining('冷偏移'), findsOneWidget);
  });

  testWidgets('饱和度数值正常渲染', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: 5, saturation: 85),
    )));
    expect(find.text('85%'), findsOneWidget);
  });
}
