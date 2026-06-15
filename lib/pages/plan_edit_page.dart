// plan_edit_page.dart — 策划创建/编辑（v2.0）
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/database_provider.dart';
import '../services/database/daos/plan_dao.dart';
import '../services/database/app_database.dart';

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

  @override
  void initState() {
    super.initState();
    _isEdit = widget.planId != null;
    if (_isEdit) {
      _loadPlan();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadPlan() async {
    final db = ref.read(appDatabaseProvider);
    final plan = await db.planDao.getPlanById(widget.planId!);
    if (plan != null && mounted) {
      _titleCtrl.text = plan.title;
      _themeCtrl.text = plan.theme;
      _styleCtrl.text = plan.style;
      _locationCtrl.text = plan.location;
      _plannedDate = plan.plannedDate;
      _status = plan.status;
      _shotList = db.planDao.parseShotList(plan.shotList);
      _gearList = db.planDao.parseGearList(plan.gearList);
      setState(() => _loading = false);
    }
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑策划' : '新建策划'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
          // 日期选择
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(_plannedDate == null
                ? '选择拍摄日期'
                : '拍摄日期：${_plannedDate!.year}/${_plannedDate!.month}/${_plannedDate!.day}'),
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
          // shot list 编辑器
          _SectionTitle(title: 'Shot List', count: _shotList.length),
          ..._shotList.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Checkbox(
                value: item.done,
                onChanged: (v) => setState(() => _shotList[i] =
                    ShotItem(desc: item.desc, done: v ?? false)),
              ),
              title: TextField(
                controller: TextEditingController(text: item.desc),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (text) => _shotList[i] =
                    ShotItem(desc: text, done: item.done),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => setState(() => _shotList.removeAt(i)),
              ),
            );
          }),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('添加 shot'),
            onPressed: () =>
                setState(() => _shotList.add(const ShotItem(desc: ''))),
          ),
          const SizedBox(height: 16),
          // 器材清单
          _SectionTitle(title: '器材清单', count: _gearList.length),
          ..._gearList.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: TextField(
                controller: TextEditingController(text: item.lens),
                decoration: const InputDecoration(
                  hintText: '如：85mm f/1.4',
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (text) => _gearList[i] =
                    GearItem(lens: text, note: item.note),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => setState(() => _gearList.removeAt(i)),
              ),
            );
          }),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('添加器材'),
            onPressed: () =>
                setState(() => _gearList.add(const GearItem(lens: ''))),
          ),
          const SizedBox(height: 32),
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
