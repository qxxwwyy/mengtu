// main_shell.dart — 底部导航壳（v2.0 信息架构）
// 4 Tab：作品库 / 相册 / 策划 / 我的，用 NavigationBar + IndexedStack
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_page.dart';
import 'album_page.dart';
import 'plan_list_page.dart';
import 'profile_page.dart';

/// 当前选中的 Tab 索引（全局状态，让子页面能切换 Tab，如导入后跳策划）
final currentTabIndexProvider = NotifierProvider<_TabNotifier, int>(_TabNotifier.new);

class _TabNotifier extends Notifier<int> {
  @override
  int build() => 0; // 默认作品库

  void set(int index) => state = index;
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(currentTabIndexProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: tabIndex,
        children: const [
          HomePage(),
          AlbumPage(),
          PlanListPage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (i) => ref.read(currentTabIndexProvider.notifier).set(i),
        backgroundColor: theme.colorScheme.surface,
        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            selectedIcon: Icon(Icons.photo_library,
                color: theme.colorScheme.primary),
            label: '作品库',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_album_outlined,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            selectedIcon: Icon(Icons.photo_album,
                color: theme.colorScheme.primary),
            label: '相册',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            selectedIcon: Icon(Icons.assignment,
                color: theme.colorScheme.primary),
            label: '策划',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            selectedIcon: Icon(Icons.person,
                color: theme.colorScheme.primary),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
