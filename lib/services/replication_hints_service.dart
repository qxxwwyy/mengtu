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
  /// 根据样片指标生成复刻参数列表
  ///
  /// [targetStyleKey] 内置档案 key（japanese/hongkong/cinematic/chinoiserie），
  /// 用于叠加该风格的复刻模板（仅 isRefined 的档案有完整模板）。
  List<ReplicationHint> generateHints({
    required ToneResult? tone,
    required AdvancedPortraitMetrics? advanced,
    required SkinAnalysis? skin,
    String? targetStyleKey,
    List<ReplicationHint> targetTemplate = const [],
  }) {
    final hints = <ReplicationHint>[];

    // 1. 影调复刻（来自 advanced）
    if (advanced != null) {
      if (advanced.blackPointOffset < 4) {
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

      if (advanced.whitePointCompression > 252) {
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
      if (skin.hueOffset!.abs() > 5) {
        final adjust = (skin.hueOffset!.abs() * 1.2).round();
        hints.add(ReplicationHint(
          category: 'HSL',
          parameter: '橙色色相',
          value: skin.hueOffset! > 0 ? '左调 -$adjust' : '右调 +$adjust',
          note:
              '样片肤色 ΔH=${skin.hueOffset!.toStringAsFixed(1)}°，复刻此色调需微调',
        ));
      }
      if (skin.saturation != null && skin.saturation! > 60) {
        hints.add(ReplicationHint(
          category: 'HSL',
          parameter: '橙色饱和度',
          value: '-${((skin.saturation! - 50) * 0.3).round()}',
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
