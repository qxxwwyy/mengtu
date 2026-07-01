// color_card_expanded_provider_test.dart — 色彩卡片展开状态 Notifier 测试（v6.2）
//
// 验证 Task A 的核心逻辑：人脸检测框可见性由本 provider 控制。
// - setExpanded → state = photoId
// - setCollapsed(同 photoId) → state = null
// - setCollapsed(异 photoId) → state 不变（防误清）
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/providers/analysis_provider.dart';

void main() {
  test('setExpanded 设置当前 photoId', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(colorCardExpandedProvider), isNull);

    container.read(colorCardExpandedProvider.notifier).setExpanded('p1');
    expect(container.read(colorCardExpandedProvider), 'p1');
  });

  test('setCollapsed 匹配当前 photoId → 清空', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(colorCardExpandedProvider.notifier).setExpanded('p1');
    container.read(colorCardExpandedProvider.notifier).setCollapsed('p1');
    expect(container.read(colorCardExpandedProvider), isNull);
  });

  test('setCollapsed 传异 photoId → 不清空（防误删他页展开态）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(colorCardExpandedProvider.notifier).setExpanded('p1');
    container.read(colorCardExpandedProvider.notifier).setCollapsed('other');
    expect(container.read(colorCardExpandedProvider), 'p1');
  });

  test('多次 setExpanded 切换 photoId', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(colorCardExpandedProvider.notifier).setExpanded('p1');
    container.read(colorCardExpandedProvider.notifier).setExpanded('p2');
    expect(container.read(colorCardExpandedProvider), 'p2');

    // 旧 photoId 折叠不应影响新的
    container.read(colorCardExpandedProvider.notifier).setCollapsed('p1');
    expect(container.read(colorCardExpandedProvider), 'p2');
  });
}
