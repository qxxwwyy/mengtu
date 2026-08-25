// profile_page.dart — 我的页面（v2.0 整合统计 + 标签管理 + 设置入口）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tag_manage_page.dart';
import 'settings_page.dart';
import '../providers/photo_provider.dart';
import '../providers/tag_provider.dart';
import '../providers/album_provider.dart';
import '../utils/app_info.dart';
import '../theme/app_theme.dart';
import '../widgets/common/animated_number.dart';
import '../widgets/common/page_transitions.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reactive 统计：watch 三个 stream，IndexedStack 常驻下也能随 DB 变化刷新。
    final photosAsync = ref.watch(allPhotosProvider);
    final tagsAsync = ref.watch(allTagsProvider);
    final albumsAsync = ref.watch(albumsProvider);

    final photoCount = photosAsync.maybeWhen(data: (l) => l.length, orElse: () => null);
    final tagCount = tagsAsync.maybeWhen(data: (l) => l.length, orElse: () => null);
    final albumCount = albumsAsync.maybeWhen(data: (l) => l.length, orElse: () => null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: ListView(
        children: [
          // 数据统计卡片网格（4 个统计卡片）
          Padding(
            padding: Spacing.all(Spacing.md),
            child: photoCount == null && tagCount == null && albumCount == null
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      _StatCard(
                        icon: Icons.photo_library,
                        label: '照片',
                        value: photoCount,
                      ),
                      SizedBox(width: Spacing.sm),
                      _StatCard(
                        icon: Icons.local_offer,
                        label: '标签',
                        value: tagCount,
                      ),
                      SizedBox(width: Spacing.sm),
                      _StatCard(
                        icon: Icons.photo_album,
                        label: '相册',
                        value: albumCount,
                      ),
                    ],
                  ),
          ),
          SizedBox(height: Spacing.sm),
          // 功能入口
          _MenuItem(
            icon: Icons.local_offer_outlined,
            title: '标签管理',
            subtitle: '管理相册标签（全局可复用）',
            onTap: () => Navigator.push(context,
                detailPageRoute(const TagManagePage())),
          ),
          _MenuItem(
            icon: Icons.settings_outlined,
            title: '设置',
            subtitle: '存储、缓存、关于',
            onTap: () => Navigator.push(context,
                detailPageRoute(const SettingsPage())),
          ),
          SizedBox(height: Spacing.xl),
          Center(
            child: Text(appVersionLabel, style: AppTypography.captionMuted),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: Spacing.all(Spacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
            ],
          ),
          borderRadius: Radii.lgBorder,
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.accent, size: 20),
            SizedBox(height: Spacing.sm),
            AnimatedNumber(
              value: value ?? 0,
              style: AppTypography.dataXl,
            ),
            SizedBox(height: 2),
            Text(label, style: AppTypography.captionMuted),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle, style: AppTypography.captionMuted),
      trailing: Icon(Icons.chevron_right,
          color: theme.colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
