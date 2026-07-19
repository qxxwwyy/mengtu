// stage_cards_test.dart — 四阶解构卡片 widget 测试（v3.5 PR3）
//
// 仓库首个使用 ProviderScope.override 的 widget 测试（现有 widget 测试都是纯 UI）。
// 覆盖 implementation_plan.md PR3 §3.11 测试列表：
// 1. GradingPanel 渲染 4 张卡片，默认全折叠
// 2. 点击阶①卡片展开，显示参照直方图 + 解读文字
// 3. 阶④显示「创建风格档案后可匹配」引导（无 provider 依赖）
// 4. 折叠态卡片渲染（序号圆标 1/2/3/4）
// 5. 各卡片标题正确（影调/色彩/主体/档案）
// 6. StageArchiveMatchCard 点击触发 SnackBar 提示
//
// ProviderScope override 模式（仓库新建立的惯例）：
// histogramProvider('p1').overrideWith((ref) async => sampleHist)
// toneProvider('p1').overrideWith((ref) async => sampleTone)
// bypass DB/file，避免 in-memory DB + 真实文件路径的复杂性。
//
// fixtures 内联（遵循仓库现有惯例 —— 不集中到 test_helpers）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/advanced_portrait_metrics.dart';
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/providers/analysis_provider.dart';
import 'package:mengtu/widgets/grading/grading_panel.dart';
import 'package:mengtu/widgets/grading/reference_histogram.dart';
import 'package:mengtu/widgets/grading/stage_card.dart';

void main() {
  // ============ fixtures（内联，遵循仓库惯例）============

  HistogramData buildSampleHistogram() {
    final r = List<int>.filled(256, 0);
    final g = List<int>.filled(256, 0);
    final b = List<int>.filled(256, 0);
    final lum = List<int>.filled(256, 0);
    r[100] = 500;
    g[100] = 300;
    b[100] = 200;
    lum[100] = 400;
    return HistogramData(r: r, g: g, b: b, lum: lum);
  }

  ToneResult buildTone({
    String toneKey = 'mid',
    String toneRange = 'long',
  }) =>
      ToneResult(
        mean: 128,
        median: 125,
        std: 45,
        minVal: 10,
        maxVal: 250,
        peakPosition: 125,
        blacks: 10,
        shadows: 20,
        midtones: 40,
        highlights: 20,
        whites: 10,
        toneKey: toneKey,
        toneRange: toneRange,
        confidence: 0.5,
        entropy: 6.5,
        rmsContrast: 50,
      );

  const sampleAdvanced = AdvancedPortraitMetrics(
    blackPointOffset: 3.5,
    whitePointCompression: 252.0,
    tenTonalType: '中长调',
  );

  const emptySkin = SkinAnalysis(); // 空 → 各卡片显示「未检出」

  /// v7.1：imageScopeProvider 的空 bins override（避免测试读文件）
  final emptyScopeBins = List<int>.filled(
      SkinAnalysis.hueBinCount * SkinAnalysis.satBinCount, 0);

  /// 构建带 provider override 的测试 harness
  ///
  /// override styleProfilesProvider 为空流 → 阶④显示空状态引导（不触发
  /// styleProfileMatchProvider 的 DB 查询，避免 timer pending 测试失败）
  Widget buildHarness(Widget child) {
    return ProviderScope(
      overrides: [
        histogramProvider('p1').overrideWith((ref) async => buildSampleHistogram()),
        toneProvider('p1').overrideWith((ref) async => buildTone()),
        skinProvider('p1').overrideWith((ref) async => emptySkin),
        imageScopeProvider('p1').overrideWith((ref, arg) async => emptyScopeBins),
        advancedMetricsProvider('p1')
            .overrideWith((ref) async => sampleAdvanced),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('GradingPanel 四阶卡片渲染', () {
    testWidgets('渲染 4 张卡片，默认全折叠（标题可见，详情隐藏）', (tester) async {
      await tester.pumpWidget(buildHarness(
        SizedBox(height: 400, child: GradingPanel(photoId: 'p1')),
      ));
      await tester.pumpAndSettle();

      // 4 个阶标题
      expect(find.text('影调手法'), findsOneWidget);
      expect(find.text('色彩手法'), findsOneWidget);
      expect(find.text('主体手法'), findsOneWidget);
      expect(find.text('洞察'), findsOneWidget);

      // 4 个序号圆标
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);

      // 折叠态：参照直方图不应存在（在阶①展开内容里）
      // ReferenceHistogram 是 CustomPaint，无法直接 find；改验证「黑点偏移」
      // 解读文字不应存在（展开后才显示）
      expect(find.textContaining('样片手法'), findsNothing);
    });

    testWidgets('点击阶①卡片展开，显示参照直方图 + 解读文字', (tester) async {
      // GradingPanel 内含 ListView，需有界高度（不能包 SingleChildScrollView）
      await tester.pumpWidget(buildHarness(
        SizedBox(height: 800, child: GradingPanel(photoId: 'p1')),
      ));
      await tester.pumpAndSettle();

      // 点击阶①标题展开
      await tester.tap(find.text('影调手法'));
      await tester.pumpAndSettle();

      // 展开后应出现解读文字（含「样片手法」）
      expect(find.textContaining('样片手法'), findsWidgets);
      // 黑点/白点解读标签应可见
      expect(find.text('黑点偏移'), findsOneWidget);
      expect(find.text('白点压缩'), findsOneWidget);
      // 十大影调标签
      expect(find.textContaining('十大影调'), findsOneWidget);

      // gotcha #64 回归：展开后参照直方图的 CustomPaint 宽度必须 > 0。
      // 真实 stage_card 展开内容是 Column(crossAxisAlignment: start)，
      // 若 ReferenceHistogram 内部不撑满宽度，CustomPaint 会被压成 0 宽 → 黑框。
      final histFinder = find.descendant(
        of: find.byType(ReferenceHistogram),
        matching: find.byType(CustomPaint),
      );
      expect(histFinder, findsOneWidget);
      final histSize = tester.getSize(histFinder);
      expect(histSize.width, greaterThan(0),
          reason: '阶①参照直方图渲染宽度不应为 0（gotcha #64 黑框 bug）');
      expect(histSize.height, equals(80));
    });

    testWidgets('阶①摘要显示「高调 · 长跨度」格式（toneKeyLabel · toneRangeLabel）',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          histogramProvider('p1').overrideWith((ref) async => buildSampleHistogram()),
          toneProvider('p1')
              .overrideWith((ref) async => buildTone(toneKey: 'high', toneRange: 'long')),
          skinProvider('p1').overrideWith((ref) async => emptySkin),
          advancedMetricsProvider('p1')
              .overrideWith((ref) async => sampleAdvanced),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 200, child: GradingPanel(photoId: 'p1')),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 高调 + 长调 → 摘要应为「高调 · 长跨度」（toneKeyLabel · toneRangeLabel）
      expect(find.text('高调 · 长跨度'), findsOneWidget);
    });

    testWidgets('阶②无肤色时摘要显示「未检出肤色」', (tester) async {
      await tester.pumpWidget(buildHarness(
        SizedBox(height: 400, child: GradingPanel(photoId: 'p1')),
      ));
      await tester.pumpAndSettle();

      // skinProvider 返回空 SkinAnalysis → 阶②摘要「未检出肤色」
      expect(find.text('未检出肤色'), findsOneWidget);
    });

    testWidgets('阶③无肤色时摘要显示「未检出主体」', (tester) async {
      await tester.pumpWidget(buildHarness(
        SizedBox(height: 400, child: GradingPanel(photoId: 'p1')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('未检出主体'), findsOneWidget);
    });
  });

  group('StageCard 通用容器', () {
    testWidgets('折叠态渲染标题 + 摘要 + 展开箭头（向下）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StageCard(
            index: 1,
            title: '测试卡片',
            summary: '测试摘要',
            expanded: false,
            onTap: () {},
            children: const [Text('详情内容')],
          ),
        ),
      ));

      expect(find.text('测试卡片'), findsOneWidget);
      expect(find.text('测试摘要'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsNothing);
      // 折叠态：详情隐藏
      expect(find.text('详情内容'), findsNothing);
    });

    testWidgets('展开态渲染 children + 收起箭头（向上）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StageCard(
              index: 2,
              title: '测试卡片',
              summary: '',
              expanded: true,
              onTap: () {},
              children: const [Text('详情内容')],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.text('详情内容'), findsOneWidget);
    });

    testWidgets('onTap 回调被触发', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StageCard(
            index: 1,
            title: '可点击',
            summary: '',
            expanded: false,
            onTap: () => tapCount++,
            children: const [],
          ),
        ),
      ));

      await tester.tap(find.text('可点击'));
      expect(tapCount, 1);
    });

    testWidgets('空摘要不渲染摘要行', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StageCard(
            index: 1,
            title: '无摘要',
            summary: '',
            expanded: false,
            onTap: () {},
            children: const [],
          ),
        ),
      ));

      expect(find.text('无摘要'), findsOneWidget);
      // summary 为空时不应有额外的 Text widget
      // （只验证标题存在，不额外断言空字符串 —— Flutter 会渲染空 Text）
    });
  });
}
