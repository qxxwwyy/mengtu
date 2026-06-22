// builtin_profiles.dart — 内置理论参考档案（v3.5 PR5）
//
// 4 个数据结构（日系/港风/青橙/中式），其中日系 + 港风的复刻参数已做精（isRefined），
// 青橙 + 中式待校准（spec §5.2 冲突 1 折中）。
//
// 数据来源：摄影教材 + 调色理论的数理推导。明确标注：理论推导值，非统计基准。
// 启动时 ensureSeeded 插入（幂等，已存在不重复插入）。
import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../services/database/app_database.dart';
import 'replication_hints_service.dart';

/// 单个内置档案的元数据 + 理论指纹统计 + 复刻模板
class BuiltinProfileData {
  final String key;
  final String name;
  final String description;
  final bool isRefined;
  final String note;
  final Map<String, dynamic> fingerprintStats;
  final List<ReplicationHint> replicationTemplate;

  const BuiltinProfileData({
    required this.key,
    required this.name,
    required this.description,
    required this.isRefined,
    required this.note,
    required this.fingerprintStats,
    required this.replicationTemplate,
  });
}

/// 内置理论档案
class BuiltinProfiles {
  BuiltinProfiles._();

  static const _theoreticalNote = '理论推导值，非统计基准';

  static const profiles = [
    // 日系小清新（复刻参数已做精）
    BuiltinProfileData(
      key: 'japanese',
      name: '日系小清新',
      description: '高调低对比，肤色白皙通透',
      isRefined: true,
      note: _theoreticalNote,
      fingerprintStats: {
        'scalar_means': [0.15, 0.9, 12.0, 245.0, 6.5, 30.0, 20.0, 0.7, 0.15],
        'scalar_stds': [0.05, 0.2, 4.0, 5.0, 0.5, 10.0, 8.0, 0.1, 0.05],
        'n': 0,
      },
      replicationTemplate: [
        ReplicationHint(
            category: '曝光',
            parameter: '全局曝光',
            value: '+0.3 ~ +0.7 EV',
            note: '整体提亮营造高调'),
        ReplicationHint(
            category: '曲线',
            parameter: '黑点',
            value: '上提至 4-8% 灰阶',
            note: '去除死黑，营造空气感'),
        ReplicationHint(
            category: 'HSL',
            parameter: '橙色明度',
            value: '+10 ~ +15',
            note: '肤色提亮白皙'),
        ReplicationHint(
            category: 'HSL',
            parameter: '绿色色相',
            value: '右调 +5 ~ +10',
            note: '植物偏黄绿'),
        ReplicationHint(
            category: '色调分离',
            parameter: '阴影',
            value: '少量青绿',
            note: '暗部冷调化'),
      ],
    ),
    // 港风怀旧（复刻参数已做精）
    BuiltinProfileData(
      key: 'hongkong',
      name: '港风怀旧',
      description: '中低调中高对比，肤色暖黄',
      isRefined: true,
      note: _theoreticalNote,
      fingerprintStats: {
        'scalar_means': [0.35, 1.3, 8.0, 248.0, 6.8, 45.0, 15.0, 0.55, 0.35],
        'scalar_stds': [0.08, 0.3, 3.0, 4.0, 0.6, 12.0, 10.0, 0.1, 0.1],
        'n': 0,
      },
      replicationTemplate: [
        ReplicationHint(
            category: '曲线',
            parameter: '黑点',
            value: '保持低位 (2-8)',
            note: '保留暗部厚重感'),
        ReplicationHint(
            category: 'HSL',
            parameter: '橙色色相',
            value: '左调 -3 ~ -8',
            note: '肤色偏暖黄'),
        ReplicationHint(
            category: 'HSL',
            parameter: '橙色饱和度',
            value: '+5 ~ +10',
            note: '强化暖调'),
        ReplicationHint(
            category: '色调分离',
            parameter: '高光',
            value: '少量橙黄',
            note: '亮部暖化'),
        ReplicationHint(
            category: '色调分离',
            parameter: '阴影',
            value: '少量青蓝',
            note: '暗部冷调对比'),
      ],
    ),
    // 电影青橙调（复刻参数待校准）
    BuiltinProfileData(
      key: 'cinematic',
      name: '电影青橙调',
      description: '全长调高对比，青橙分裂',
      isRefined: false,
      note: '$_theoreticalNote（待校准）',
      fingerprintStats: {
        'scalar_means': [0.28, 0.7, 0.0, 250.0, 7.0, 70.0, 18.0, 0.6, 0.4],
        'scalar_stds': [0.07, 0.25, 2.0, 3.0, 0.5, 8.0, 6.0, 0.1, 0.1],
        'n': 0,
      },
      replicationTemplate: [],
    ),
    // 中式古典（复刻参数待校准）
    BuiltinProfileData(
      key: 'chinoiserie',
      name: '中式古典',
      description: '中调中对比，低饱和稳重',
      isRefined: false,
      note: '$_theoreticalNote（待校准）',
      fingerprintStats: {
        'scalar_means': [0.22, 1.0, 4.0, 246.0, 6.6, 65.0, 12.0, 0.65, 0.22],
        'scalar_stds': [0.06, 0.2, 3.0, 4.0, 0.5, 10.0, 8.0, 0.1, 0.08],
        'n': 0,
      },
      replicationTemplate: [],
    ),
  ];

  /// 应用启动时插入内置档案（幂等，已存在不重复插入）
  static Future<void> ensureSeeded(AppDatabase db) async {
    for (final p in profiles) {
      final id = 'builtin_${p.key}';
      final existing = await db.styleProfileDao.getProfileById(id);
      if (existing == null) {
        await db.styleProfileDao.insertProfile(
          StyleProfilesCompanion.insert(
            id: id,
            name: p.name,
            description: Value(p.description),
            isBuiltin: const Value(true),
            builtinKey: Value(p.key),
            fingerprintStats: Value(jsonEncode(p.fingerprintStats)),
          ),
        );
      }
    }
  }

  /// 按 key 取内置档案数据（供复刻参数模板查询）
  static BuiltinProfileData? getByKey(String? key) {
    if (key == null) return null;
    for (final p in profiles) {
      if (p.key == key) return p;
    }
    return null;
  }
}
