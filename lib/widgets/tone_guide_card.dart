// tone_guide_card.dart — 数理审美调色指引卡片（v3.0）
//
// 把图像的数学特征翻译为具体的摄影调色参数与避坑动作，为"缺乏直觉审美"
// 的程序员群体提供"仪表盘式"的精准数据校准。
//
// 指标来源（详见 implementation_plan.md）：
// 1. 一维信息熵 E（背景杂乱度 / 虚化纯净度）
// 2. 全局对比度 RMS（光影立体感）
// 3. 肤色色相偏差角 ΔH（达芬奇肤色线对齐）—— Phase 2 才有数据
// 4. 肤色饱和度 / 通透感 —— Phase 2 才有数据
// 5. 肤色-背景明度/色彩隔离度 SLS / SCS —— Phase 2 才有数据
//
// 设计原则：纯文字展示，最纯粹直观，避免视觉噪音。
import 'package:flutter/material.dart';
import '../models/tone_result.dart';
import '../theme/app_theme.dart';

/// 数理审美调色指引卡片
///
/// 用于嵌入 [DetailBottomPanel] 的直方图 / 影调 / 色卡 Tab，
/// 根据可用指标动态展示调色建议（无脸检测时只显示熵/对比度部分）。
class ToneGuideCard extends StatelessWidget {
  final ToneResult tone;

  /// 肤色分析（来自 skinProvider，可空）
  /// 为空时仅展示熵/RMS 部分；非空则追加肤色 4 维度指引。
  final SkinAnalysis? skin;

  /// 是否展示肤色相关指标（Phase 1 关闭，Phase 2 由 face_service 提供 ROI 后开启）
  final bool showSkin;

  const ToneGuideCard({
    super.key,
    required this.tone,
    this.skin,
    this.showSkin = false,
  });

  @override
  Widget build(BuildContext context) {
    // 合并 skin：优先用传入的 skin，否则回退到 tone.skin
    final effectiveSkin = skin ?? tone.skin;
    final hasSkin = showSkin && !effectiveSkin.isEmpty;
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
              Icon(Icons.tips_and_updates_outlined,
                  size: 14, color: AppColors.darkAccent),
              const SizedBox(width: 6),
              const Text(
                '调色指引',
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
          _buildEntropyGuide(),
          const SizedBox(height: 8),
          _buildContrastGuide(),
          if (hasSkin) ...[
            const SizedBox(height: 8),
            _buildSkinHueGuide(effectiveSkin),
            const SizedBox(height: 8),
            _buildSkinSatGuide(effectiveSkin),
            const SizedBox(height: 8),
            _buildSlsguide(effectiveSkin),
          ] else if (showSkin) ...[
            // Phase 2 但本图无脸 → 引导用户用取色器手动校准
            const SizedBox(height: 8),
            _buildNoSkinHint(),
          ],
        ],
      ),
    );
  }

  /// 信息熵 → 背景杂乱度 / 虚化纯净度
  Widget _buildEntropyGuide() {
    final e = tone.entropy;
    final guide = _EntropyGuide.classify(e);
    return _GuideRow(
      icon: Icons.blur_on,
      label: '背景纯净度',
      value: 'E = ${e.toStringAsFixed(2)}',
      statusColor: guide.color,
      tip: guide.tip,
    );
  }

  /// RMS 对比度 → 光影立体感
  Widget _buildContrastGuide() {
    final r = tone.rmsContrast;
    final guide = _ContrastGuide.classify(r);
    return _GuideRow(
      icon: Icons.contrast,
      label: '光影立体感',
      value: 'σ = ${r.toStringAsFixed(1)}',
      statusColor: guide.color,
      tip: guide.tip,
    );
  }

  /// 肤色色相偏差角 ΔH → 达芬奇肤色线对齐
  Widget _buildSkinHueGuide(SkinAnalysis s) {
    final dh = s.hueOffset!;
    final guide = _SkinHueGuide.classify(dh);
    return _GuideRow(
      icon: Icons.face_retouching_natural,
      label: '肤色色相 ΔH',
      value: '${dh > 0 ? '+' : ''}${dh.toStringAsFixed(1)}°',
      statusColor: guide.color,
      tip: guide.tip,
    );
  }

  /// 肤色饱和度 → 通透感
  Widget _buildSkinSatGuide(SkinAnalysis s) {
    final sat = s.saturation!;
    final guide = _SkinSatGuide.classify(sat);
    return _GuideRow(
      icon: Icons.opacity,
      label: '肤色饱和度',
      value: '${sat.toStringAsFixed(0)}%',
      statusColor: guide.color,
      tip: guide.tip,
    );
  }

  /// SLS / SCS → 主体隔离度
  Widget _buildSlsguide(SkinAnalysis s) {
    final sls = s.luminanceSeparation ?? 0;
    final scs = s.colorSeparation ?? 0;
    final slsGuide = _SlsGuide.classify(sls);
    return _GuideRow(
      icon: Icons.center_focus_strong,
      label: '主体明度隔离',
      value: 'SLS ${sls.toStringAsFixed(0)}%',
      statusColor: slsGuide.color,
      tip: '${slsGuide.tip}（色彩隔离 SCS = ${scs.toStringAsFixed(0)}°）',
    );
  }

  /// 无脸检测占位提示（引导用户用取色器手动校准）
  Widget _buildNoSkinHint() {
    return _GuideRow(
      icon: Icons.touch_app,
      label: '肤色校准',
      value: '未检测',
      statusColor: DetailColors.textMuted,
      tip: '未检测到面部。可开启取色工具并长按皮肤，进行手动校准。',
    );
  }
}

/// 指引行：图标 + 指标名 + 数值 + 文字建议
class _GuideRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color statusColor;
  final String tip;

  const _GuideRow({
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

// ============ 阈值分类器（颜色 + 文字建议）============

class _EntropyGuide {
  final Color color;
  final String tip;
  const _EntropyGuide(this.color, this.tip);

  /// 低熵 (<5.2) → 背景纯净；高熵 (>7.3) → 杂乱
  static _EntropyGuide classify(double e) {
    if (e < 5.2) {
      return const _EntropyGuide(Color(0xFF4CAF50),
          '背景纯净，可放心拉大整体对比度，突出主体轮廓。');
    }
    if (e > 7.3) {
      return const _EntropyGuide(Color(0xFFFF9800),
          '背景杂乱喧宾夺主。建议降低背景清晰度、压暗背景亮度或冷调化。');
    }
    return const _EntropyGuide(AppColors.darkAccent,
        '背景层次适中。保持当前节奏，按需做局部压暗。');
  }
}

class _ContrastGuide {
  final Color color;
  final String tip;
  const _ContrastGuide(this.color, this.tip);

  /// RMS 对比度（亮度标准差）：>75 高 / <35 低
  static _ContrastGuide classify(double r) {
    if (r > 75) {
      return const _ContrastGuide(Color(0xFFFF9800),
          '全局对比度强烈、边缘锐利。女性/儿童柔和人像请降低纹理清晰度以避免毛孔被放大。');
    }
    if (r < 35) {
      return const _ContrastGuide(Color(0xFF42A5F5),
          '画面偏平。可拉高对比度增加立体感，或靠局部光影塑造层次。');
    }
    return const _ContrastGuide(Color(0xFF4CAF50),
        '对比度适中，立体感与柔和度均衡。');
  }
}

class _SkinHueGuide {
  final Color color;
  final String tip;
  const _SkinHueGuide(this.color, this.tip);

  /// ΔH 偏差角：±2° 健康 / >+5° 偏黄 / <-5° 偏红
  static _SkinHueGuide classify(double dh) {
    if (dh > 5) {
      return const _SkinHueGuide(Color(0xFFFF9800),
          '面部偏黄绿（蜡黄病态）。HSL 黄/橙通道色相左调（往橙偏），直至 ΔH 回到 ±2°。');
    }
    if (dh < -5) {
      return const _SkinHueGuide(Color(0xFFEF5350),
          '面部偏紫红（充血醉酒）。HSL 红色通道色相右调（往橙偏）。');
    }
    return const _SkinHueGuide(Color(0xFF4CAF50),
      '肤色色相对齐达芬奇线，健康暖橙调，无需调整。',
    );
  }
}

class _SkinSatGuide {
  final Color color;
  final String tip;
  const _SkinSatGuide(this.color, this.tip);

  /// 健康区间 30~50% / >55% 过饱和 / <25% 苍白
  static _SkinSatGuide classify(double s) {
    if (s > 55) {
      return const _SkinSatGuide(Color(0xFFFF9800),
          '皮肤过饱和（塑料蜡质感）。降低橙色饱和度，提高橙色明度，恢复"白里透红"。');
    }
    if (s < 25) {
      return const _SkinSatGuide(Color(0xFF42A5F5),
          '面部苍白贫血。HSL 微量提升橙色饱和度。');
    }
    return const _SkinSatGuide(Color(0xFF4CAF50),
        '皮肤通透自然，饱和度落在健康区间。');
  }
}

class _SlsGuide {
  final Color color;
  final String tip;
  const _SlsGuide(this.color, this.tip);

  /// SLS >15% 主体亮背景暗（理想）/ <0% 死亡暗脸
  static _SlsGuide classify(double sls) {
    if (sls < 0) {
      return const _SlsGuide(Color(0xFFEF5350),
          '死亡暗脸：主体被亮背景吞噬。面部局部蒙版提亮 0.3~0.7 档，背景压暗 0.2~0.5 档。');
    }
    if (sls < 15) {
      return const _SlsGuide(Color(0xFFFF9800),
          '主体与背景明度相近，焦点不够汇聚。轻度压暗背景，或对面部做径向提亮。');
    }
    return const _SlsGuide(Color(0xFF4CAF50),
        '主体剥离感强，视觉焦点稳稳汇聚在面部。');
  }
}
