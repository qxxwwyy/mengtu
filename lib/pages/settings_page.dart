// settings_page.dart — 设置页（版本信息 + 存储统计 + 清理缓存 + 关于）
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/database_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isClearing = false;
  Future<({int count, int size})>? _storageFuture;

  @override
  void initState() {
    super.initState();
    _storageFuture = _getStorageInfo();
  }

  void _refreshStorage() {
    setState(() {
      _storageFuture = _getStorageInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _buildStorageSection(),
          _buildCacheSection(),
          _buildAboutSection(),
        ],
      ),
    );
  }

  Widget _buildStorageSection() {
    return FutureBuilder<({int count, int size})>(
      future: _storageFuture,
      builder: (context, snapshot) {
        final count = snapshot.data?.count ?? 0;
        final size = snapshot.data?.size ?? 0;
        return _SectionCard(
          title: '存储',
          children: [
            _InfoRow(label: '照片数量', value: '$count 张'),
            _InfoRow(label: '占用空间', value: _formatBytes(size)),
          ],
        );
      },
    );
  }

  Widget _buildCacheSection() {
    return _SectionCard(
      title: '缓存',
      children: [
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('清理缩略图缓存'),
          subtitle: const Text('下次打开会重新生成缩略图'),
          trailing: _isClearing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chevron_right),
          onTap: _isClearing ? null : _clearThumbnailCache,
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return _SectionCard(
      title: '关于',
      children: [
        const _InfoRow(label: '应用名称', value: '萌图'),
        const _InfoRow(label: '版本', value: 'v1.2.0'),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('开源协议'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showLicenses(context),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('关于萌图'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAbout(context),
        ),
      ],
    );
  }

  Future<void> _clearThumbnailCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缩略图缓存'),
        content: const Text('将删除所有缩略图文件，下次打开照片时会重新生成。\n\n'
            '注意：照片原图和数据库记录不会受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清理')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isClearing = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final thumbDir = Directory('${appDir.path}/thumbnails');
      if (await thumbDir.exists()) {
        await thumbDir.delete(recursive: true);
        await thumbDir.create(recursive: true);
      }
      // 清空 DB 中所有照片的缩略图路径（避免指向已删文件导致碎图）
      // 下次浏览时 photo_card 会按需重生成（ImportService.regenerateThumbnail）
      await ref.read(appDatabaseProvider).photoDao.clearAllThumbnails();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缩略图缓存已清理，浏览时将自动重建')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
      _refreshStorage();
    }
  }

  Future<({int count, int size})> _getStorageInfo() async {
    final db = ref.read(appDatabaseProvider);
    final count = await db.photoDao.getPhotoCount();
    final size = await db.photoDao.getTotalStorageUsed();
    return (count: count, size: size);
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: '萌图',
      applicationVersion: '1.2.0',
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于萌图'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('萌图 Mengtu v1.2.0'),
            SizedBox(height: 12),
            Text(
              '面向摄影爱好者的照片灵感收集与调色参考工具。\n\n'
              '功能：照片管理、直方图/色相分析、色卡提取（MMCQ/K-Means/Celebi三算法）、影调分析、一键黑白。\n\n'
              '纯本地应用，不联网，不收集用户数据。',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

/// 分区卡片
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 0, 4),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600)),
          ),
          Card(
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// 信息行
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
