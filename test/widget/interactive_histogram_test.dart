// interactive_histogram_test.dart — 可交互直方图 widget 测试
//
// 覆盖验收 2 行为：按住直方图 → 读数浮层出现（亮度值/区域名/占比），
// 移动手指 → 读数跟新，松手 → 浮层消失。
// Listener（raw pointer）在 widget test 用 TestGesture down/move/up 模拟。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/widgets/charts/interactive_histogram.dart';

void main() {
  HistogramData makeData() {
    final ch = List<int>.filled(256, 10);
    return HistogramData(r: ch, g: ch, b: ch, lum: List<int>.from(ch));
  }

  Future<void> pumpHistogram(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 256,
            height: 100,
            child: InteractiveHistogram(data: makeData()),
          ),
        ),
      ),
    ));
    // 入场动画播完
    await tester.pumpAndSettle();
  }

  testWidgets('按住直方图显示读数浮层（亮度值 + 区域名 + 占比）', (tester) async {
    await pumpHistogram(tester);

    expect(find.byType(InteractiveHistogram), findsOneWidget);
    // 初始无浮层
    expect(find.text('中间调'), findsNothing);

    // 按住组件中间（组件在 800×600 视口内居中，先取实际左上角）
    final tl = tester.getTopLeft(find.byType(InteractiveHistogram));
    final gesture = await tester.startGesture(tl + const Offset(128, 50));
    await tester.pump();

    expect(find.text('中间调'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    // 均匀分布单 bin 占比 = 10/2560 ≈ 0.4%
    expect(find.text('0.4%'), findsOneWidget);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('移动手指读数跟新到新区间', (tester) async {
    await pumpHistogram(tester);

    final tl = tester.getTopLeft(find.byType(InteractiveHistogram));
    final gesture = await tester.startGesture(tl + const Offset(128, 50));
    await tester.pump();
    expect(find.text('中间调'), findsOneWidget);

    // 移到最右（bin 255 → 白色区）
    await gesture.moveBy(const Offset(127, 0));
    await tester.pump();
    expect(find.text('白色'), findsOneWidget);
    expect(find.text('中间调'), findsNothing);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('松手浮层消失', (tester) async {
    await pumpHistogram(tester);

    final tl = tester.getTopLeft(find.byType(InteractiveHistogram));
    final gesture = await tester.startGesture(tl + const Offset(64, 50));
    await tester.pump();
    expect(find.text('阴影'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(find.text('阴影'), findsNothing);
  });

  testWidgets('RGB 三通道迷你条存在', (tester) async {
    await pumpHistogram(tester);

    final tl = tester.getTopLeft(find.byType(InteractiveHistogram));
    final gesture = await tester.startGesture(tl + const Offset(128, 50));
    await tester.pump();

    // R/G/B 三个通道标签
    expect(find.text('R'), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    await gesture.up();
    await tester.pump();
  });
}
