// interpretation_row.dart — 解读行（共享组件，v3.5 PR3）
//
// 抽取自 tone_guide_card.dart 的私有 _GuideRow，供四阶解构卡片复用。
// 布局：[图标(状态色)] [Expanded: 标签 + 单色等宽值(状态色) / 解读文字(弱化色)]
//
// 解读措辞约定（spec §3.5/3.7）：用「样片手法：…」式，描述样片为什么这样布阶调/色彩，
// 而非命令式「你应该…」。教学定位 = 解构而非指挥。
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 解读行的状态色（与 tone_guide_card 阈值分类器对齐）
class InterpretationStatus {
  InterpretationStatus._();

  /// 好（绿）—— 指标落在理想区间
  static const Color good = Color(0xFF4CAF50);

  /// 注意（橙）—— 指标偏离，需关注
  static const Color warn = Color(0xFFFF9800);

  /// 低/平（蓝）—— 指标偏低，效果平淡
  static const Color low = Color(0xFF42A5F5);

  /// 差（红）—— 指标明显异常
  static const Color bad = Color(0xFFEF5350);

  /// 中性（accent）—— 无好坏之分的客观描述
  static const Color neutral = AppColors.darkAccent;
}

/// 解读行：图标 + 标签 + 单色等宽值 + 解读文字
///
/// 各 stage 卡片（stage_tonal_card / stage_color_card / stage_isolation_card）
/// 在展开态用它呈现单个指标的解读。折叠态不显示（由 StageCard 控制）。
class InterpretationRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color statusColor;
  final String interpretation;

  const InterpretationRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.statusColor,
    required this.interpretation,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: statusColor),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: DetailColors.textSecondary, fontSize: 11)),
                  const Spacer(),
                  Text(value,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      )),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                interpretation,
                style: const TextStyle(
                    color: DetailColors.textMuted,
                    fontSize: 11,
                    height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
