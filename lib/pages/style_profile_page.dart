// style_profile_page.dart — 风格档案管理页（v3.5 PR4）
//
// 列表所有档案（用户自定义 + 内置理论），支持：
// - 创建新档案：命名 → 选择照片 → 批量预计算 → 生成指纹统计
// - 档案详情：照片网格 + 删除/重算
// - 删除档案（事务清理关联，gotcha #40）
//
// 入口：「我的」Tab + 阶④卡片引导链接。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../providers/database_provider.dart';
import '../providers/photo_provider.dart';
import '../providers/style_profile_provider.dart';
import '../services/database/app_database.dart';
import '../theme/app_theme.dart';
import 'style_profile_detail_page.dart';

const _uuid = Uuid();

/// 风格档案管理页
class StyleProfilePage extends ConsumerWidget {
  const StyleProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(styleProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('风格档案')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (profiles) {
          if (profiles.isEmpty) {
            return _buildEmpty(context);
          }
          // 内置理论档案在前，用户档案按更新时间倒序
          final builtins = profiles.where((p) => p.isBuiltin).toList();
          final userProfiles =
              profiles.where((p) => !p.isBuiltin).toList();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (userProfiles.isNotEmpty) ...[
                const _SectionLabel('我的档案'),
                ...userProfiles.map((p) => _ProfileTile(profile: p)),
                const SizedBox(height: 12),
              ],
              if (builtins.isNotEmpty) ...[
                const _SectionLabel('理论参考档案'),
                ...builtins.map((p) => _ProfileTile(profile: p)),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '理论档案基于教材推导值，非统计基准。可作风格参照锚点。',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.style_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          const Text('还没有风格档案',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text(
            '导入样片创建档案后，可在详情页\n四阶卡片比对照片与档案的相似度',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          // empty 态的按钮仅占位提示（实际创建走 FAB，
          // 因为 _showCreateDialog 需要 ref，empty 态在 ConsumerWidget.build 内已有 ref）
          const Text(
            '点右下角 ＋ 创建',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef? ref) async {
    if (ref == null) return; // empty 态的占位按钮不响应（走 FAB）
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('创建风格档案'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '档案名称',
              hintText: '如：王家卫港风',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: const Text('下一步'),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty || !context.mounted) return;
    await _selectPhotosAndCreate(context, ref, name);
  }

  Future<void> _selectPhotosAndCreate(
      BuildContext context, WidgetRef ref, String name) async {
    // 选择照片：从全部照片列表让用户多选（复用现有 allPhotosProvider）
    final db = ref.read(appDatabaseProvider);
    final importService = await ref.read(importServiceProvider.future);
    final allPhotos = await ref.read(allPhotosProvider.future);

    if (!context.mounted) return;
    if (allPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无照片可导入档案')),
      );
      return;
    }

    final selected = await showDialog<List<Photo>>(
      context: context,
      builder: (ctx) => _PhotoSelectDialog(photos: allPhotos),
    );

    if (selected == null || selected.isEmpty || !context.mounted) return;

    // 1. 批量预计算（直方图 + 影调缓存）
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在预计算 ${selected.length} 张照片…')),
    );
    await importService.precomputeAnalysisForPhotos(
        selected.map((p) => p.id).toList());

    // 2. 创建档案（用 uuid 避免重名冲突）
    final profileId =
        await db.styleProfileDao.insertProfile(
      StyleProfilesCompanion.insert(id: _uuid.v4(), name: name),
    );

    // 3. 关联照片
    for (final photo in selected) {
      await db.styleProfileDao.addPhotoToProfile(profileId, photo.id);
    }

    // 4. 计算指纹统计
    final fpService = ref.read(fingerprintServiceProvider);
    await fpService.recomputeProfileStats(profileId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('档案「$name」已创建（${selected.length} 张样片）')),
      );
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Text(text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          )),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final StyleProfile profile;
  const _ProfileTile({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          profile.isBuiltin ? Icons.auto_awesome : Icons.style,
          color: AppColors.darkAccent,
        ),
        title: Text(profile.name),
        subtitle: Text(
          profile.isBuiltin
              ? (profile.builtinKey != null
                  ? '理论档案 · ${profile.description}'
                  : '理论档案')
              : (profile.description.isNotEmpty
                  ? profile.description
                  : '用户档案'),
          style: const TextStyle(fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: profile.isBuiltin
            ? const Icon(Icons.info_outline, size: 18, color: Colors.grey)
            : const Icon(Icons.chevron_right),
        onTap: () {
          if (profile.isBuiltin) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('「${profile.name}」是理论参考档案，'
                    '不可编辑。可在详情页四阶卡片中查看与它的相似度。'),
              ),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  StyleProfileDetailPage(profileId: profile.id),
            ),
          );
        },
      ),
    );
  }
}

/// 照片多选对话框（简化版：列表 + checkbox）
class _PhotoSelectDialog extends StatefulWidget {
  final List<Photo> photos;
  const _PhotoSelectDialog({required this.photos});

  @override
  State<_PhotoSelectDialog> createState() => _PhotoSelectDialogState();
}

class _PhotoSelectDialogState extends State<_PhotoSelectDialog> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('选择样片（已选 ${_selected.length}）'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.photos.length,
          itemBuilder: (_, i) {
            final photo = widget.photos[i];
            return ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: Text(photo.fileName,
                  style: const TextStyle(fontSize: 13)),
              trailing: Checkbox(
                value: _selected.contains(photo.id),
                onChanged: (v) => setState(() =>
                    v == true ? _selected.add(photo.id) : _selected.remove(photo.id)),
              ),
              onTap: () => setState(() => _selected.contains(photo.id)
                  ? _selected.remove(photo.id)
                  : _selected.add(photo.id)),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.photos.where((p) => _selected.contains(p.id)).toList()),
          child: Text('创建（${_selected.length}）'),
        ),
      ],
    );
  }
}
