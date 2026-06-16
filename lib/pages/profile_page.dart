// profile_page.dart — 我的页面（v2.0 整合统计 + 标签管理 + 设置入口）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tag_manage_page.dart';
import 'settings_page.dart';
import '../providers/photo_provider.dart';
import '../providers/tag_provider.dart';
import '../utils/app_info.dart';
import 'album_page.dart' show albumsProvider;

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Reactive 统计：watch 三个 stream，IndexedStack 常驻下也能随 DB 变化刷新。
    final photosAsync = ref.watch(allPhotosProvider);
    final tagsAsync = ref.watch(allTagsProvider);
    final albumsAsync = ref.watch(albumsProvider);

    final photoCount = photosAsync.maybeWhen(data: (l) => l.length, orElse: () => null);
    final tagCount = tagsAsync.maybeWhen(data: (l) => l.length, orElse: () => null);
    final albumCount = albumsAsync.maybeWhen(data: (l) => l.length, orElse: () => null);

    return Scaffold(
      appBar: AppBar(
        title: Text('我的',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: theme.colorScheme.primary)),
      ),
      body: ListView(
        children: [
          // 数据统计卡片
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: photoCount == null && tagCount == null && albumCount == null
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      _StatItem(
                          icon: Icons.photo_library,
                          label: '照片',
                          value: photoCount),
                      _StatItem(
                          icon: Icons.local_offer,
                          label: '标签',
                          value: tagCount),
                      _StatItem(
                          icon: Icons.photo_album,
                          label: '相册',
                          value: albumCount),
                    ],
                  ),
          ),
          // 功能入口
          _MenuItem(
            icon: Icons.local_offer_outlined,
            title: '标签管理',
            subtitle: '管理氛围、场景、情绪标签',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TagManagePage())),
          ),
          _MenuItem(
            icon: Icons.settings_outlined,
            title: '设置',
            subtitle: '存储、缓存、关于',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(appVersionLabel,
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.3))),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? value; // null 表示加载中

  const _StatItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 24),
          const SizedBox(height: 8),
          Text(value == null ? '—' : '$value',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        ],
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
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
      trailing: Icon(Icons.chevron_right,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
      onTap: onTap,
    );
  }
}
