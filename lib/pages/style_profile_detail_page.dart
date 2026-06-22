// style_profile_detail_page.dart — 档案详情页（v3.5 PR4）
//
// 展示档案内照片网格 + 元信息，支持：
// - 移除照片（事务清理后重算指纹统计）
// - 重算指纹（手动触发 recomputeProfileStats）
// - 删除档案（事务清理关联，gotcha #40）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_provider.dart';
import '../providers/style_profile_provider.dart';
import '../services/database/app_database.dart';
import '../theme/app_theme.dart';

/// 单个档案的详情页
class StyleProfileDetailPage extends ConsumerStatefulWidget {
  final String profileId;

  const StyleProfileDetailPage({super.key, required this.profileId});

  @override
  ConsumerState<StyleProfileDetailPage> createState() =>
      _StyleProfileDetailPageState();
}

class _StyleProfileDetailPageState
    extends ConsumerState<StyleProfileDetailPage> {
  bool _computing = false;

  Future<void> _recompute() async {
    setState(() => _computing = true);
    try {
      final fpService = ref.read(fingerprintServiceProvider);
      await fpService.recomputeProfileStats(widget.profileId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('指纹统计已重新计算')),
        );
      }
    } finally {
      if (mounted) setState(() => _computing = false);
    }
  }

  Future<void> _removePhoto(String photoId) async {
    final db = ref.read(appDatabaseProvider);
    await db.styleProfileDao
        .removePhotoFromProfile(widget.profileId, photoId);
    // 重算指纹统计
    final fpService = ref.read(fingerprintServiceProvider);
    await fpService.recomputeProfileStats(widget.profileId);
  }

  Future<void> _deleteProfile(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除档案'),
        content: const Text('删除后不可恢复，关联照片本身不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final db = ref.read(appDatabaseProvider);
    await db.styleProfileDao.deleteProfile(widget.profileId);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync =
        ref.watch(styleProfilesProvider);
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('档案详情'),
        actions: [
          IconButton(
            onPressed: _computing ? null : _recompute,
            icon: _computing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            tooltip: '重算指纹',
          ),
          IconButton(
            onPressed: () => _deleteProfile(context),
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除档案',
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (profiles) {
          StyleProfile? profileMatch;
          for (final p in profiles) {
            if (p.id == widget.profileId) {
              profileMatch = p;
              break;
            }
          }
          if (profileMatch == null) {
            return const Center(child: Text('档案不存在'));
          }
          // 提升为非空（跨 FutureBuilder 闭包不能用类型提升）
          final profile = profileMatch;
          return FutureBuilder(
            future: db.styleProfileDao.getProfilePhotos(widget.profileId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final photos = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.style, color: AppColors.darkAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(profile.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ]),
                          if (profile.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(profile.description,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                          const SizedBox(height: 8),
                          Text('${photos.length} 张样片',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500)),
                          if (profile.fingerprintStats != null &&
                              profile.fingerprintStats!.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text('指纹统计已生成',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.green)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (photos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text('档案内无照片',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ...photos.map((photo) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.photo_outlined),
                            title: Text(photo.fileName,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                '${photo.width}×${photo.height}',
                                style: const TextStyle(fontSize: 11)),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 20),
                              onPressed: () => _removePhoto(photo.id),
                            ),
                          ),
                        )),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
