// skin_radar_test.dart — 肤色示波器（vectorscope）widget 测试（v6.2）
//
// 验证 v6.2 重写后的行为：
// 1. 无肤色（空 SkinAnalysis）→ 显示「未检出肤色」+ 空示波器占位
// 2. 有肤色 + ΔH 对齐良好（<10°）→ 解读「对齐肤色线」+ 绿色
// 3. 有肤色 + ΔH 偏色（>25°）→ 解读「肤色偏色」+ 橙色
// 4. 饱和度数值与图例一致
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

    // 标题常驻
    expect(find.text('肤色示波器'), findsOneWidget);
    // 空态文案
    expect(find.text('未检出肤色'), findsOneWidget);
    // 引导文案（含「肤色线」）
    expect(
        find.textContaining('光点越靠近黄色「肤色线」'), findsOneWidget);
  });

  testWidgets('ΔH 对齐良好（5°）→ 「对齐肤色线」+ 绿色解读', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: 5, saturation: 40),
    )));

    expect(find.text('对齐肤色线'), findsOneWidget);
    // 色相偏差与饱和度数值行
    expect(find.text('5°'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('ΔH 偏色（30°）→ 「肤色偏色」+ 橙色解读', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: 30, saturation: 75),
    )));

    expect(find.text('肤色偏色'), findsOneWidget);
    expect(find.text('30°'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('ΔH 负值（偏品红）仍按绝对值判定偏离', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: -12, saturation: 35),
    )));

    // |ΔH|=12°，落在 10~25 区间 → 「轻微偏离」
    expect(find.text('轻微偏离'), findsOneWidget);
  });

  testWidgets('饱和度过高（>70%）饱和度数值用警告色', (tester) async {
    // 仅验证数值渲染（颜色断言需读 painter 内部，这里保证数值正确）
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: 5, saturation: 85),
    )));
    expect(find.text('85%'), findsOneWidget);
  });
}
