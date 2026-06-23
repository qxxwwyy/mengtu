// builtin_profiles.dart — 内置理论参考档案（v3.5 PR5）
//
// 4 个数据结构（日系/港风/青橙/中式），其中日系 + 港风的复刻参数已做精（isRefined），
// 青橙 + 中式待校准（spec §5.2 冲突 1 折中）。
//
// 数据来源：摄影教材 + 调色理论的数理推导。明确标注：理论推导值，非统计基准。
// 启动时 ensureSeeded 插入（幂等，已存在不重复插入）。
//
// gotcha #50（PR5 复核新增）：标量单位必须与 _computeFingerprintIsolate 一致。
// scalar_means/scalar_stds 是 RAW 值（非归一化）：
//   [rms_contrast(0~128), warm_cold_ratio(0.5~2), black_point(0~255),
//    white_point(0~255), entropy(0~8), scs(0~180), sls(-100~100), sti(0~1), flc(0~1)]
import 'dart:convert';
import 'dart:math' as math;

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
  final List<ReplicationHint> replicationTemplates;

  const BuiltinProfileData({
    required this.key,
    required this.name,
    required this.description,
    required this.isRefined,
    required this.note,
    required this.fingerprintStats,
    required this.replicationTemplates,
  });
}

/// 生成单通道（32 bins）归一化高斯分布
List<double> _gaussianChannel(int peakBin, double spread) {
  final raw = List<double>.filled(32, 0.0);
  var sum = 0.0;
  for (var i = 0; i < 32; i++) {
    final d = (i - peakBin) / spread;
    raw[i] = math.exp(-0.5 * d * d);
    sum += raw[i];
  }
  if (sum > 0) {
    for (var i = 0; i < 32; i++) {
      raw[i] /= sum;
    }
  }
  return raw;
}

/// 生成 96 维直方图（R32+G32+B32，每通道独立归一化）
List<double> _buildHistogram({
  int rPeak = 16,
  int gPeak = 16,
  int bPeak = 16,
  double spread = 6,
}) {
  return [
    ..._gaussianChannel(rPeak, spread),
    ..._gaussianChannel(gPeak, spread),
    ..._gaussianChannel(bPeak, spread),
  ];
}

/// 生成全 0.03 的 std 数组（理论档案：假定各 bin 的离散度为均值 3%）
List<double> _uniformStd(int length, double value) =>
    List<double>.filled(length, value);

/// 内置理论档案
class BuiltinProfiles {
  BuiltinProfiles._();

  static const _theoreticalNote = '理论推导值，非统计基准';

  // profiles 不能是 const —— fingerprintStats 的 hist_means 由运行时函数生成。
  static final List<BuiltinProfileData> profiles = [
    // 日系小清新（复刻参数已做精）
    // 高调低对比：RMS 低（~25）、黑点上提（~12）、白点不触顶（~242）
    // 肤色白皙通透：SCS 低（柔和）、SLS 弱（融入背景）、STI 高、FLC 低（平光）
    BuiltinProfileData(
      key: 'japanese',
      name: '日系小清新',
      description: '高调低对比，肤色白皙通透',
      isRefined: true,
      note: _theoreticalNote,
      fingerprintStats: {
        // RAW 单位（与 _computeFingerprintIsolate 一致，gotcha #50）
        'scalar_means': [25.0, 1.1, 12.0, 242.0, 6.5, 30.0, 8.0, 0.72, 0.12],
        'scalar_stds': [8.0, 0.3, 4.0, 6.0, 0.4, 12.0, 8.0, 0.08, 0.05],
        // 直方图：高调右偏（峰值在 bin 20-24，对应亮度 160-192）
        'hist_means': _buildHistogram(rPeak: 22, gPeak: 20, bPeak: 18, spread: 7),
        'hist_stds': _uniformStd(96, 0.03),
        'n': 0,
      },
      replicationTemplates: const [
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
    // 中低调中高对比：RMS 中（~45）、黑点低（~6）、白点触顶（~250）
    // 肤色暖黄：SCS 高、SLS 中、FLC 高（侧光立体）
    BuiltinProfileData(
      key: 'hongkong',
      name: '港风怀旧',
      description: '中低调中高对比，肤色暖黄',
      isRefined: true,
      note: _theoreticalNote,
      fingerprintStats: {
        'scalar_means': [45.0, 1.3, 6.0, 250.0, 6.8, 45.0, 18.0, 0.55, 0.35],
        'scalar_stds': [10.0, 0.4, 3.0, 4.0, 0.5, 12.0, 10.0, 0.1, 0.1],
        // 直方图：中低调左偏（峰值在 bin 8-14，对应亮度 64-112）
        'hist_means': _buildHistogram(rPeak: 12, gPeak: 10, bPeak: 8, spread: 6),
        'hist_stds': _uniformStd(96, 0.03),
        'n': 0,
      },
      replicationTemplates: const [
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
    // 全长调高对比：RMS 高（~60）、黑点触底（~2）、白点触顶（~252）
    // 青橙分裂：SCS 高、SLS 中、FLC 高
    BuiltinProfileData(
      key: 'cinematic',
      name: '电影青橙调',
      description: '全长调高对比，青橙分裂',
      isRefined: false,
      note: '$_theoreticalNote（待校准）',
      fingerprintStats: {
        'scalar_means': [60.0, 0.8, 2.0, 252.0, 7.0, 70.0, 22.0, 0.6, 0.4],
        'scalar_stds': [12.0, 0.3, 2.0, 3.0, 0.4, 10.0, 8.0, 0.1, 0.1],
        // 直方图：全长调 U 型（两端高，中调低）—— 近似双峰
        'hist_means': _buildUShapeHistogram(),
        'hist_stds': _uniformStd(96, 0.03),
        'n': 0,
      },
      replicationTemplates: const [],
    ),
    // 中式古典（复刻参数待校准）
    // 中调中对比：RMS 低（~22）、黑点提（~8）、白点不触顶（~244）
    // 低饱和稳重：SCS 低、SLS 弱、FLC 低
    BuiltinProfileData(
      key: 'chinoiserie',
      name: '中式古典',
      description: '中调中对比，低饱和稳重',
      isRefined: false,
      note: '$_theoreticalNote（待校准）',
      fingerprintStats: {
        'scalar_means': [22.0, 1.0, 8.0, 244.0, 6.6, 35.0, 10.0, 0.65, 0.18],
        'scalar_stds': [7.0, 0.3, 3.0, 5.0, 0.4, 12.0, 8.0, 0.1, 0.07],
        // 直方图：中间调中央（峰值在 bin 15-17，对应亮度 120-136）
        'hist_means': _buildHistogram(rPeak: 16, gPeak: 16, bPeak: 16, spread: 8),
        'hist_stds': _uniformStd(96, 0.03),
        'n': 0,
      },
      replicationTemplates: const [],
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

/// 生成 U 型直方图（全长调参照：两端高、中间低）
List<double> _buildUShapeHistogram() {
  final hist = List<double>.filled(96, 0.0);
  // 每通道独立 U 型
  for (final offset in [0, 32, 64]) {
    var sum = 0.0;
    final raw = List<double>.filled(32, 0.0);
    for (var i = 0; i < 32; i++) {
      // 距离中心 16 的归一化距离（0~1），两端为 1
      final dist = (i - 16).abs() / 16.0;
      raw[i] = 0.3 + 0.7 * dist * dist; // 中心 0.3，两端 1.0
      sum += raw[i];
    }
    if (sum > 0) {
      for (var i = 0; i < 32; i++) {
        hist[offset + i] = raw[i] / sum;
      }
    }
  }
  return hist;
}
