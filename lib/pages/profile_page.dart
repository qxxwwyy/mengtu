// profile_page.dart — 我的页面（v2.0 整合统计 + 标签管理 + 设置入口）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tag_manage_page.dart';
import 'settings_page.dart';
import '../providers/database_provider.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  int _photoCount = 0;
  int _tagCount = 0;
  int _albumCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final db = ref.read(appDatabaseProvider);
    final photos = await db.photoDao.getAllPhotos();
    final tags = await db.tagDao.getAllTags();
    final albums = await db.albumDao.getAllAlbums();
    if (mounted) {
      setState(() {
        _photoCount = photos.length;
        _tagCount = tags.length;
        _albumCount = albums.length;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      _StatItem(
                          icon: Icons.photo_library, label: '照片', value: _photoCount),
                      _StatItem(
                          icon: Icons.local_offer, label: '标签', value: _tagCount),
                      _StatItem(
                          icon: Icons.photo_album, label: '相册', value: _albumCount),
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
            child: Text('萌图 Mengtu v2.0.0',
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
  final int value;

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
          Text('$value',
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
