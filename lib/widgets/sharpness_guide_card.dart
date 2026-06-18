// sharpness_guide_card.dart — 锐度/合焦数据读数卡片（v3.1）
//
// 替代原峰值对焦发光蒙层（SharpnessOverlay）：
// - 原蒙层分辨率低（240×160）且与图片对齐错位（letterbox 未补偿）
// - 用户反馈视觉干扰大，改为"影调面板"内的纯数据读数
//
// 读数来源（SharpnessMap）：
// - foregroundScore：图像中心区域（主体）拉普拉斯方差
// - backgroundScore：图像边缘区域（背景）拉普拉斯方差
// - overallScore：全图方差
//
// 摄影学翻译：
// - 主体锐度高 + 背景锐度低 = 典型糖水人像（主体突出、背景虚化）
// - 主体锐度低 = 可能跑焦（建议检查对焦点）
// - 主体≈背景锐度 = 全画面清晰（风光/纪实），人像则背景干扰大
import 'package:flutter/material.dart';
import '../services/sharpness_service.dart';
import '../theme/app_theme.dart';

/// 锐度/合焦数据读数卡片
class SharpnessGuideCard extends StatelessWidget {
  final SharpnessMap map;

  /// 该照片的宽高比（用于判定是否人像构图，影响建议文案）
  /// 为 null 时按通用建议展示
  final double? photoAspectRatio;

  const SharpnessGuideCard({
    super.key,
    required this.map,
    this.photoAspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    final fg = map.foregroundScore;
    final bg = map.backgroundScore;
    final fgGuide = _SharpnessGuide.classifyForeground(fg);
    final bgGuide = _SharpnessGuide.classifyBackground(bg);
    final separation = fg - bg;
    final sepGuide = _SharpnessGuide.classifySeparation(separation);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DetailColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.darkAccent.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.center_focus_strong,
                  size: 14, color: AppColors.darkAccent),
              const SizedBox(width: 6),
              const Text(
                '合焦读数',
                style: TextStyle(
                  color: AppColors.darkAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SharpnessRow(
            icon: Icons.face,
            label: '主体锐度',
            value: 'σ = ${fg.toStringAsFixed(1)}',
            statusColor: fgGuide.color,
            tip: fgGuide.tip,
          ),
          const SizedBox(height: 8),
          _SharpnessRow(
            icon: Icons.blur_on,
            label: '背景锐度',
            value: 'σ = ${bg.toStringAsFixed(1)}',
            statusColor: bgGuide.color,
            tip: bgGuide.tip,
          ),
          const SizedBox(height: 8),
          _SharpnessRow(
            icon: Icons.layers,
            label: '主体隔离度',
            value: 'Δ = ${separation.toStringAsFixed(1)}',
            statusColor: sepGuide.color,
            tip: sepGuide.tip,
          ),
        ],
      ),
    );
  }
}

class _SharpnessRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color statusColor;
  final String tip;

  const _SharpnessRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.statusColor,
    required this.tip,
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
                tip,
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

// ============ 阈值分类器 ============

class _SharpnessGuide {
  final Color color;
  final String tip;
  const _SharpnessGuide(this.color, this.tip);

  /// 主体锐度（中心区域拉普拉斯方差）：
  /// >150 高（合焦清晰）/ 50~150 中等 / <50 低（可能跑焦）
  static _SharpnessGuide classifyForeground(double v) {
    if (v < 50) {
      return const _SharpnessGuide(Color(0xFFEF5350),
          '主体模糊，可能跑焦。检查对焦点是否落在人脸/眼睛，必要时放大查看锐度。');
    }
    if (v > 150) {
      return const _SharpnessGuide(Color(0xFF4CAF50),
          '主体清晰合焦，细节锐利。注意女性/儿童柔和人像可略降清晰度避免毛孔过显。');
    }
    return const _SharpnessGuide(Color(0xFFFF9800),
        '主体锐度适中。若需更"刀锐奶滑"效果，可对主体做局部锐化。');
  }

  /// 背景锐度（边缘区域拉普拉斯方差）：
  /// <30 低（虚化强，人像理想）/ 30~80 中 / >80 高（背景清晰，干扰主体）
  static _SharpnessGuide classifyBackground(double v) {
    if (v < 30) {
      return const _SharpnessGuide(Color(0xFF4CAF50),
          '背景虚化纯净，主体剥离感强，典型大光圈人像效果。');
    }
    if (v > 80) {
      return const _SharpnessGuide(Color(0xFFFF9800),
          '背景清晰、细节繁杂，易喧宾夺主。建议后期压暗背景或冷调化以突出主体。');
    }
    return const _SharpnessGuide(AppColors.darkAccent,
        '背景虚化适中，层次自然。');
  }

  /// 主体隔离度（主体σ − 背景σ）：
  /// >80 强隔离（理想糖水人像）/ 0~80 一般 / <0 反转（背景比主体清晰 → 跑焦）
  static _SharpnessGuide classifySeparation(double v) {
    if (v < 0) {
      return const _SharpnessGuide(Color(0xFFEF5350),
          '背景比主体更清晰——主体严重跑焦，或对焦点落在背景上。请重新对焦。');
    }
    if (v > 80) {
      return const _SharpnessGuide(Color(0xFF4CAF50),
          '主体突出、背景虚化强烈，糖水人像典型特征，焦点汇聚到位。');
    }
    return const _SharpnessGuide(AppColors.darkAccent,
        '主体与背景锐度接近，画面整体清晰（风光/纪实适用）。人像可考虑增大光圈或拉近距离增强虚化。');
  }
}
