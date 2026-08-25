// plan_edit_page.dart — 策划创建/编辑（v2.0）
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/database_provider.dart';
import '../services/database/daos/plan_dao.dart';
import '../services/database/app_database.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';

class PlanEditPage extends ConsumerStatefulWidget {
  final String? planId; // 编辑模式传入，创建模式为 null

  const PlanEditPage({super.key, this.planId});

  @override
  ConsumerState<PlanEditPage> createState() => _PlanEditPageState();
}

class _PlanEditPageState extends ConsumerState<PlanEditPage> {
  final _titleCtrl = TextEditingController();
  final _themeCtrl = TextEditingController();
  final _styleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  DateTime? _plannedDate;
  List<ShotItem> _shotList = [];
  List<GearItem> _gearList = [];
  String _status = 'planning';
  bool _loading = true;
  bool _isEdit = false;

  // v3.0: 关联样片相册
  // null = 未关联；用 List<Album> 缓存供下拉选择，避免每次展开都查 DB
  String? _associatedAlbumId;
  List<Album> _albums = [];

  @override
  void initState() {
    super.initState();
    _isEdit = widget.planId != null;
    if (_isEdit) {
      _loadPlan();
    } else {
      _loading = false;
      _loadAlbums();
    }
  }

  Future<void> _loadAlbums() async {
    final db = ref.read(appDatabaseProvider);
    final albums = await db.albumDao.getAllAlbums();
    if (mounted) {
      setState(() {
        _albums = albums;
      });
    }
  }

  Future<void> _loadPlan() async {
    final db = ref.read(appDatabaseProvider);
    final plan = await db.planDao.getPlanById(widget.planId!);
    if (!mounted) return;
    if (plan == null) {
      // 策划已被删除：提示并返回，否则页面卡死在转圈
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('策划不存在或已被删除')),
      );
      Navigator.of(context).maybePop();
      return;
    }
    _titleCtrl.text = plan.title;
    _themeCtrl.text = plan.theme;
    _styleCtrl.text = plan.style;
    _locationCtrl.text = plan.location;
    _plannedDate = plan.plannedDate;
    _status = plan.status;
    _associatedAlbumId = plan.associatedAlbumId;
    _shotList = db.planDao.parseShotList(plan.shotList);
    _gearList = db.planDao.parseGearList(plan.gearList);
    setState(() => _loading = false);
    // 异步加载相册列表（不阻塞页面显示）
    _loadAlbums();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _themeCtrl.dispose();
    _styleCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入策划标题')),
      );
      return;
    }
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();

    if (_isEdit) {
      await db.planDao.updatePlan(ShootingPlansCompanion(
        id: Value(widget.planId!),
        title: Value(_titleCtrl.text.trim()),
        theme: Value(_themeCtrl.text.trim()),
        style: Value(_styleCtrl.text.trim()),
        location: Value(_locationCtrl.text.trim()),
        plannedDate: Value(_plannedDate),
        status: Value(_status),
        associatedAlbumId: Value(_associatedAlbumId),
        gearList: Value(db.planDao.encodeGearList(_gearList)),
        shotList: Value(db.planDao.encodeShotList(_shotList)),
        updatedAt: Value(now),
      ));
    } else {
      await db.planDao.insertPlan(ShootingPlansCompanion.insert(
        id: const Uuid().v4(),
        title: _titleCtrl.text.trim(),
        theme: Value(_themeCtrl.text.trim()),
        style: Value(_styleCtrl.text.trim()),
        location: Value(_locationCtrl.text.trim()),
        plannedDate: Value(_plannedDate),
        status: Value(_status),
        associatedAlbumId: Value(_associatedAlbumId),
        gearList: Value(db.planDao.encodeGearList(_gearList)),
        shotList: Value(db.planDao.encodeShotList(_shotList)),
      ));
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? '策划已更新' : '策划已创建')),
      );
    }
  }

  /// v3.0: 关联样片相册选择器
  /// 在拍摄现场可一键跳转浏览灵感样片；后期可做实拍/参考对比。
  Widget _buildAlbumSelector() {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: '关联样片相册',
        hintText: '可选：拍摄现场参考灵感样片',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.photo_album_outlined),
        suffixIcon: _associatedAlbumId != null
            ? IconButton(
                icon: const Icon(Icons.clear, size: 20),
                tooltip: '取消关联',
                onPressed: () =>
                    setState(() {
                  _associatedAlbumId = null;
                }),
              )
            : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _associatedAlbumId,
          isExpanded: true,
          isDense: true,
          hint: const Text('选择相册...'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('不关联相册',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            ..._albums.map((album) => DropdownMenuItem<String?>(
                  value: album.id,
                  child: Text(album.name,
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (value) => setState(() {
            _associatedAlbumId = value;
          }),
          dropdownColor: theme.colorScheme.surface,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑策划' : '新建策划'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
          // 基本信息
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '标题 *',
              hintText: '如：秋日公园人像',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _themeCtrl,
            decoration: const InputDecoration(
              labelText: '主题',
              hintText: '如：秋日、温暖',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _styleCtrl,
            decoration: const InputDecoration(
              labelText: '风格',
              hintText: '如：日系小清新',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationCtrl,
            decoration: const InputDecoration(
              labelText: '地点',
              hintText: '如：中山公园',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          // v3.0: 关联样片相册（拍摄现场可一键跳转灵感样片）
          _buildAlbumSelector(),
          const SizedBox(height: 12),
          // 日期选择
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(_plannedDate == null
                ? '选择拍摄日期'
                : '拍摄日期：${fmtDate(_plannedDate!)}'),
            trailing: _plannedDate != null
                ? IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _plannedDate = null),
                  )
                : null,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _plannedDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _plannedDate = picked);
            },
          ),
          // 状态选择
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: '状态'),
            items: const [
              DropdownMenuItem(value: 'planning', child: Text('策划中')),
              DropdownMenuItem(value: 'shooting', child: Text('拍摄中')),
              DropdownMenuItem(value: 'completed', child: Text('已完成')),
              DropdownMenuItem(value: 'archived', child: Text('已归档')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'planning'),
          ),
          const SizedBox(height: 24),
          // shot list 编辑器（子组件隔离，避免光标漂移）
          _SectionTitle(title: 'Shot List', count: _shotList.length),
          ..._shotList.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            // 用 item.id 作 ValueKey（而非 index），删除中间项时下方行
            // 不会因 index 变化被错误复用，避免 TextEditingController 文本错位。
            return EditableShotRow(
              key: ValueKey('shot_${item.id}'),
              initialDesc: item.desc,
              isDone: item.done,
              onDoneChanged: (v) => setState(() =>
                  _shotList[i] = ShotItem(id: item.id, desc: item.desc, done: v)),
              onDescChanged: (text) =>
                  _shotList[i] = ShotItem(id: item.id, desc: text, done: item.done),
              onDelete: () => setState(() => _shotList.removeAt(i)),
            );
          }),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('添加 shot'),
            onPressed: () =>
                setState(() => _shotList.add(ShotItem.create(''))),
          ),
          const SizedBox(height: 16),
          // 器材清单
          _SectionTitle(title: '器材清单', count: _gearList.length),
          ..._gearList.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return EditableGearRow(
              key: ValueKey('gear_${item.id}'),
              initialLens: item.lens,
              onChanged: (text) =>
                  _gearList[i] = GearItem(id: item.id, lens: text, note: item.note),
              onDelete: () => setState(() => _gearList.removeAt(i)),
            );
          }),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('添加器材'),
            onPressed: () =>
                setState(() => _gearList.add(GearItem.create(''))),
          ),
          const SizedBox(height: 32),
            ],
          ),
          // 吸底保存按钮（拇指热区 Easy 区）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                    Theme.of(context).colorScheme.surface,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: Radii.mdBorder),
                  ),
                  child: const Text('保存策划',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Shot list 可编辑行（独立 StatefulWidget，避免光标漂移）
/// 内部管理 TextEditingController + FocusNode，失焦时才回传数据
class EditableShotRow extends StatefulWidget {
  final String initialDesc;
  final bool isDone;
  final ValueChanged<bool> onDoneChanged;
  final ValueChanged<String> onDescChanged;
  final VoidCallback onDelete;

  const EditableShotRow({
    super.key,
    required this.initialDesc,
    required this.isDone,
    required this.onDoneChanged,
    required this.onDescChanged,
    required this.onDelete,
  });

  @override
  State<EditableShotRow> createState() => _EditableShotRowState();
}

class _EditableShotRowState extends State<EditableShotRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDesc);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.onDescChanged(_controller.text.trim());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: widget.isDone,
        onChanged: (v) => widget.onDoneChanged(v ?? false),
      ),
      title: TextField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: const InputDecoration(
          hintText: '描述构图、光影或参考...',
          border: InputBorder.none,
          isDense: true,
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (val) => widget.onDescChanged(val.trim()),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: widget.onDelete,
      ),
    );
  }
}

/// 器材清单可编辑行（同理，独立状态隔离）
class EditableGearRow extends StatefulWidget {
  final String initialLens;
  final ValueChanged<String> onChanged;
  final VoidCallback onDelete;

  const EditableGearRow({
    super.key,
    required this.initialLens,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<EditableGearRow> createState() => _EditableGearRowState();
}

class _EditableGearRowState extends State<EditableGearRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLens);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.onChanged(_controller.text.trim());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: TextField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: const InputDecoration(
          hintText: '如：85mm f/1.4',
          border: InputBorder.none,
          isDense: true,
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (val) => widget.onChanged(val.trim()),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: widget.onDelete,
      ),
    );
  }
}
