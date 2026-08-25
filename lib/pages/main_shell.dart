// main_shell.dart — 底部导航壳（v2.0 信息架构，v2.0 UI 暗房美学 blur）
// 4 Tab：作品库 / 相册 / 策划 / 我的，用 NavigationBar + IndexedStack
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import 'home_page.dart';
import 'album_page.dart';
import 'plan_list_page.dart';
import 'profile_page.dart';

/// 当前选中的 Tab 索引（全局状态，让子页面能切换 Tab，如导入后跳策划）
final currentTabIndexProvider =
    NotifierProvider<_TabNotifier, int>(_TabNotifier.new);

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
      // extendBody 让内容延伸到导航栏下方，配合 blur 效果
      extendBody: true,
      body: IndexedStack(
        index: tabIndex,
        children: const [
          HomePage(),
          AlbumPage(),
          PlanListPage(),
          ProfilePage(),
        ],
      ),
      // 自定义 blur 底部导航栏
      bottomNavigationBar: _BlurNavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (i) =>
            ref.read(currentTabIndexProvider.notifier).set(i),
        items: const [
          _NavItem(
            icon: Icons.photo_library_outlined,
            selectedIcon: Icons.photo_library,
            label: '作品库',
          ),
          _NavItem(
            icon: Icons.photo_album_outlined,
            selectedIcon: Icons.photo_album,
            label: '相册',
          ),
          _NavItem(
            icon: Icons.assignment_outlined,
            selectedIcon: Icons.assignment,
            label: '策划',
          ),
          _NavItem(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: '我的',
          ),
        ],
        primaryColor: theme.colorScheme.primary,
        onSurfaceColor: theme.colorScheme.onSurface,
      ),
    );
  }
}

/// 导航项数据
class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 毛玻璃底部导航栏
class _BlurNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_NavItem> items;
  final Color primaryColor;
  final Color onSurfaceColor;

  const _BlurNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
    required this.primaryColor,
    required this.onSurfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgBase.withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(color: AppColors.divider, width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _NavTile(
                      item: items[i],
                      isSelected: i == selectedIndex,
                      onTap: () {
                HapticFeedback.selectionClick();
                onDestinationSelected(i);
              },
                      primaryColor: primaryColor,
                      mutedColor: onSurfaceColor.withValues(alpha: 0.5),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个导航项（带选中态弹性动画）
class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final Color primaryColor;
  final Color mutedColor;

  const _NavTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.primaryColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppAnimations.pressDuration,
        curve: AppAnimations.pressCurve,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: Radii.pillBorder,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? item.selectedIcon : item.icon,
              size: 22,
              color: isSelected ? primaryColor : mutedColor,
            ),
            // 选中时 label 从右侧展开
            AnimatedSize(
              duration: AppAnimations.pressDuration,
              curve: AppAnimations.pressCurve,
              child: isSelected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        item.label,
                        style: AppTypography.label.copyWith(fontWeight: FontWeight.w600,
                          color: primaryColor,),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
