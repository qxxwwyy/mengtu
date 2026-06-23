// replication_hints_service.dart — 复刻参数生成（v3.5 PR5）
//
// 语境：解读式（「若想复刻此样片影调，可尝试：…」），非诊断命令式。
// plan.md §4.3 的 ExpertDiagnosisEngine 已弃用（诊断修复语境冲突）。
//
// 输出可折叠的复刻参数附录，数据来源：tone/advanced/skin 量化指标 →
// 映射到 Lightroom/CaptureOne 风格的调整参数（曲线/HSL/色调分离）。
import 'package:flutter/foundation.dart';

import '../models/advanced_portrait_metrics.dart';
import '../models/tone_result.dart';

/// 单条复刻参数
@immutable
class ReplicationHint {
  /// 类别（曲线/HSL/曝光/色调分离）
  final String category;

  /// 参数名（如「黑点端点」「橙色色相」）
  final String parameter;

  /// 调整值（如「+0.3 ~ +0.7 EV」「左调 -5」）
  final String value;

  /// 说明（为什么这样调）
  final String note;

  const ReplicationHint({
    required this.category,
    required this.parameter,
    required this.value,
    required this.note,
  });
}

/// 复刻参数生成器
class ReplicationHintsService {
  // 阈值常量（提取自原内联魔数，便于校准 + 文档化）
  // 黑点 < 此值视为死黑触底（电影调/港风标志）
  static const _blackPointFloor = 4.0;
  // 白点 > 此值视为高光触顶（高反差标志）
  static const _whitePointCeil = 252.0;
  // ΔH 绝对值 > 此值才生成色相调整建议（5° 内属于自然波动）
  static const _hueOffsetThreshold = 5.0;
  // 饱和度 > 此值视为高饱和（需降饱和）
  static const _highSaturationCeil = 60.0;
  // ΔH(deg) → LR HSL 调整量经验增益（肤色线偏移放大，因 HSL 滑块量纲不同）
  static const _hueToHslGain = 1.2;
  // 过饱和部分按 30% 折减（不直接拉满，保留风格余地）
  static const _satReduceGain = 0.3;

  /// 根据样片指标生成复刻参数列表
  ///
  /// [tone] 当前未使用（预留：未来可加 RMS/entropy 复刻建议）。传 null 即可。
  /// [targetStyleKey] 内置档案 key（japanese/hongkong/cinematic/chinoiserie），
  /// 用于叠加该风格的复刻模板（仅 isRefined 的档案有完整模板）。
  List<ReplicationHint> generateHints({
    ToneResult? tone,
    required AdvancedPortraitMetrics? advanced,
    required SkinAnalysis? skin,
    String? targetStyleKey,
    List<ReplicationHint> targetTemplate = const [],
  }) {
    final hints = <ReplicationHint>[];

    // 1. 影调复刻（来自 advanced）
    if (advanced != null) {
      if (advanced.blackPointOffset < _blackPointFloor) {
        hints.add(const ReplicationHint(
          category: '曲线',
          parameter: '黑点端点',
          value: '保持触底 (0)',
          note: '样片用暗部死黑换对比度冲击，复刻时曲线左下角不抬起',
        ));
      } else {
        hints.add(ReplicationHint(
          category: '曲线',
          parameter: '黑点端点',
          value: '上提至 ${advanced.blackPointOffset.toStringAsFixed(0)}% 灰阶',
          note: '样片保留了暗部层次，复刻时曲线左下角上提',
        ));
      }

      if (advanced.whitePointCompression > _whitePointCeil) {
        hints.add(const ReplicationHint(
          category: '曲线',
          parameter: '白点端点',
          value: '保持触顶 (255)',
          note: '高光溢出换冲击力，复刻时曲线右上角不压回',
        ));
      } else {
        hints.add(ReplicationHint(
          category: '曲线',
          parameter: '白点端点',
          value: '压回 ${advanced.whitePointCompression.toStringAsFixed(0)}',
          note: '保留高光细节，复刻时曲线右上角下压',
        ));
      }
    }

    // 2. 色彩复刻（来自 skin）
    if (skin != null && !skin.isEmpty && skin.hueOffset != null) {
      if (skin.hueOffset!.abs() > _hueOffsetThreshold) {
        final adjust =
            (skin.hueOffset!.abs() * _hueToHslGain).round();
        hints.add(ReplicationHint(
          category: 'HSL',
          parameter: '橙色色相',
          value: skin.hueOffset! > 0 ? '左调 -$adjust' : '右调 +$adjust',
          note:
              '样片肤色 ΔH=${skin.hueOffset!.toStringAsFixed(1)}°，复刻此色调需微调',
        ));
      }
      if (skin.saturation != null && skin.saturation! > _highSaturationCeil) {
        hints.add(ReplicationHint(
          category: 'HSL',
          parameter: '橙色饱和度',
          value: '-${((skin.saturation! - 50) * _satReduceGain).round()}',
          note: '样片肤色饱和度 ${skin.saturation!.toStringAsFixed(0)}% 偏高，复刻可略降',
        ));
      }
    }

    // 3. 目标档案的复刻模板（仅 isRefined 的内置档案，由调用方传入）
    if (targetTemplate.isNotEmpty) {
      hints.addAll(targetTemplate);
    }

    return hints;
  }
}
