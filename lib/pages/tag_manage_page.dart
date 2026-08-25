// tag_manage_page.dart — 标签管理页
//
// v2.1：标签是相册的子系统（全局定义、关联到相册）。本页管理全局标签，
// 每个 chip 旁显示被多少个相册使用。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tag_provider.dart';
import '../providers/database_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common/async_views.dart';
import '../widgets/common/empty_state.dart';

class TagManagePage extends ConsumerStatefulWidget {
  const TagManagePage({super.key});

  @override
  ConsumerState<TagManagePage> createState() => _TagManagePageState();
}

class _TagManagePageState extends ConsumerState<TagManagePage> {
  final _newTagController = TextEditingController();
  String _selectedGroup = 'custom';

  static const _groupLabels = {
    'atmosphere': '氛围',
    'scene': '场景',
    'emotion': '情绪',
    'custom': '自定义',
  };

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    ref
        .read(tagActionsProvider.notifier)
        .createTag(name, group: _selectedGroup);
    _newTagController.clear();
  }

  void _deleteTag(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定要删除标签 "$name" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(tagActionsProvider.notifier).deleteTag(id);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: StatusColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(allTagsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('标签管理')),
      body: Column(
        children: [
          // 新建标签区域
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('新建标签',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newTagController,
                          decoration: const InputDecoration(
                            hintText: '输入标签名',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addTag(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.add),
                        onPressed: _addTag,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 分组选择
                  Text('选择分组：',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: _groupLabels.entries.map((entry) {
                      return ChoiceChip(
                        label: Text(entry.value),
                        selected: _selectedGroup == entry.key,
                        onSelected: (_) =>
                            setState(() => _selectedGroup = entry.key),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          // 标签列表（按分组显示）
          Expanded(
            child: tagsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => AsyncErrorView(
                message: '标签加载失败',
                onRetry: () => ref.invalidate(allTagsProvider),
              ),
              data: (tags) {
                if (tags.isEmpty) {
                  return const EmptyState(
                    icon: Icons.local_offer_outlined,
                    title: '暂无标签',
                    subtitle: '在相册详情页可以给相册挂标签',
                  );
                }
                // 按分组归类
                final grouped = <String, List<({String id, String name})>>{};
                for (final tag in tags) {
                  final g = tag.group;
                  grouped.putIfAbsent(g, () => []);
                  grouped[g]!.add((id: tag.id, name: tag.name));
                }

                return ListView(
                  children: [
                    for (final groupKey in _groupLabels.keys)
                      if (grouped.containsKey(groupKey)) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            _groupLabels[groupKey]!,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            children: grouped[groupKey]!.map((tag) {
                            return _TagChipWithCount(
                              id: tag.id,
                              name: tag.name,
                              onDelete: () => _deleteTag(tag.id, tag.name),
                            );
                          }).toList(),
                          ),
                        ),
                      ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 标签 chip + 相册使用计数（异步查 getAlbumCountByTag）
class _TagChipWithCount extends ConsumerWidget {
  final String id;
  final String name;
  final VoidCallback onDelete;

  const _TagChipWithCount({
    required this.id,
    required this.name,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return FutureBuilder<int>(
      future: db.albumDao.getAlbumCountByTag(id),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Chip(
          label: Text(count > 0 ? '$name · $count' : name),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: onDelete,
        );
      },
    );
  }
}
