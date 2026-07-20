// skin_radar_test.dart — 矢量示波器 widget 测试（v7.2 Cb/Cr 平面重构）
//
// v7.2：imageScopeProvider 现在返回 64×64 Cb/Cr bins（替代旧 48×8 hue×sat）。
// 测试 override 也要匹配新维度。SkinAnalysis 新增 chromaBins/chromaCb/chromaCr
// 可选字段，旧测试构造的 SkinAnalysis() 自动带 null chroma 字段，painter 走回退。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/widgets/grading/skin_radar.dart';
import 'package:mengtu/providers/analysis_provider.dart';

void main() {
  // 空 bins 作为 imageScopeProvider 的 override 返回值（64×64 Cb/Cr）
  final emptyBins = List<int>.filled(
      SkinAnalysis.cbBinCount * SkinAnalysis.crBinCount, 0);

  Widget wrap(Widget child, {List<int>? scopeBins}) => ProviderScope(
        overrides: [
          imageScopeProvider.overrideWith(
              (ref, arg) => Future.value(scopeBins ?? emptyBins)),
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

  // v7.2 新增：非空 chromaBins 时像素云能渲染（不抛异常）
  testWidgets('非空 Cb/Cr bins 像素云正常渲染', (tester) async {
    final nonEmptyBins = List<int>.filled(
        SkinAnalysis.cbBinCount * SkinAnalysis.crBinCount, 0);
    // 在中心 bin（Cb≈0, Cr≈0 附近）放一些计数，模拟有色彩信号
    final centerCb = SkinAnalysis.cbBinCount ~/ 2;
    final centerCr = SkinAnalysis.crBinCount ~/ 2;
    nonEmptyBins[centerCb * SkinAnalysis.crBinCount + centerCr] = 100;
    nonEmptyBins[(centerCb + 1) * SkinAnalysis.crBinCount + centerCr + 1] = 50;

    await tester.pumpWidget(wrap(
      SkinRadar(
        skin: const SkinAnalysis(hueOffset: 5, saturation: 40),
        photoId: 'test',
      ),
      scopeBins: nonEmptyBins,
    ));

    // 能找到示波器标题 + 不抛异常即通过（CustomPaint 渲染不产生可 find 的 widget）
    expect(find.text('肤色示波器'), findsOneWidget);
  });

  // v7.2 新增：chromaCb/chromaCr 提供时肤色光点走精确路径
  testWidgets('chromaCb/Cr 提供时光点走精确路径', (tester) async {
    await tester.pumpWidget(wrap(SkinRadar(
      skin: const SkinAnalysis(
        hueOffset: 5,
        saturation: 40,
        chromaCb: 16,
        chromaCr: 22,
      ),
      photoId: 'test',
    )));

    // 只要不抛异常、文案正常即通过
    expect(find.text('贴近肤色线'), findsOneWidget);
  });
}

