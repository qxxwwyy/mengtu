// skin_radar_test.dart — 矢量示波器 widget 测试（v7.1 双模式改）
//
// v7.1：SkinRadar 改为 ConsumerWidget（watch scopeModeProvider/imageScopeProvider），
// 需要 ProviderScope。测试用 Override 跳过 imageScopeProvider 的文件 IO。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/widgets/grading/skin_radar.dart';
import 'package:mengtu/providers/analysis_provider.dart';

void main() {
  // 空 bins 作为 imageScopeProvider 的 override 返回值
  final emptyBins = List<int>.filled(
      SkinAnalysis.hueBinCount * SkinAnalysis.satBinCount, 0);

  Widget wrap(Widget child) => ProviderScope(
        overrides: [
          imageScopeProvider.overrideWith((ref, arg) async => emptyBins),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: child,
            ),
          ),
        ),
      );

  testWidgets('空 SkinAnalysis 显示「未检出肤色」占位', (tester) async {
    await tester.pumpWidget(wrap(
      const SkinRadar(skin: SkinAnalysis(), photoId: 'test'),
    ));

    expect(find.text('肤色示波器'), findsOneWidget);
    expect(find.text('未检出肤色'), findsOneWidget);
    expect(find.textContaining('肤色线'), findsOneWidget);
  });

  testWidgets('ΔH 贴近（5°）→ 「贴近肤色线」', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: 5, saturation: 40),
      photoId: 'test',
    )));

    expect(find.text('贴近肤色线'), findsOneWidget);
    expect(find.text('5°'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('ΔH 暖偏移（30°）→ 暖偏移标签', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: 30, saturation: 75),
      photoId: 'test',
    )));

    expect(find.textContaining('暖偏移'), findsOneWidget);
    expect(find.text('30°'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('ΔH 负值（冷偏移）→ 冷偏移标签', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: -12, saturation: 35),
      photoId: 'test',
    )));

    expect(find.textContaining('冷偏移'), findsOneWidget);
  });

  testWidgets('饱和度数值正常渲染', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(hueOffset: 5, saturation: 85),
      photoId: 'test',
    )));
    expect(find.text('85%'), findsOneWidget);
  });
}
