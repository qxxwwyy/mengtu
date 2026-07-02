// insight_service.dart — 样片洞察规则引擎（v8.0）
//
// 替代已删除的 FingerprintService + BuiltinProfiles 匹配系统。
// 不做伪精确的"相似度 %"，而是用简单 if-else 规则将照片的影调/色彩/手法
// 指标归类为一个整体风格标签，并生成解读式文字。
//
// 设计原则：
// - 只描述，不诊断（不说"蜡黄病态""死亡暗脸"）
// - 规则匹配就是规则匹配，不假装是统计相似度
// - 每个风格标签附带教学性解读文案
import '../models/advanced_portrait_metrics.dart';
import '../models/tone_result.dart';
import '../services/tone_service.dart' show calculateWarmToColdRatio;

/// 样片洞察结果
class PhotoInsight {
  /// 风格标签（如"日系高调""港风怀旧"等），null = 无法归类
  final String? styleLabel;

  /// 影调维度解读
  final String tonalInsight;

  /// 色彩维度解读
  final String colorInsight;

  /// 手法维度解读
  final String techniqueInsight;

  /// 一句话总结
  final String summary;

  const PhotoInsight({
    this.styleLabel,
    required this.tonalInsight,
    required this.colorInsight,
    required this.techniqueInsight,
    required this.summary,
  });
}

/// 洞察规则引擎
class InsightService {
  /// 根据照片各项指标生成洞察
  ///
  /// [tone] 影调分析（mean/rmsContrast/entropy/toneKey/blacks 等）
  /// [advanced] 高级指标（黑点/白点）
  /// [skin] 肤色分析（可空，无脸检测时为空 SkinAnalysis）
  /// [hueHistogram] 色相直方图（360 bins，用于冷暖比计算，可空）
  PhotoInsight generate({
    required ToneResult? tone,
    required AdvancedPortraitMetrics? advanced,
    required SkinAnalysis skin,
    List<int>? hueHistogram,
  }) {
    if (tone == null) {
      return const PhotoInsight(
        tonalInsight: '影调分析中…',
        colorInsight: '',
        techniqueInsight: '',
        summary: '',
      );
    }

    final warmCold =
        hueHistogram != null ? calculateWarmToColdRatio(hueHistogram) : null;
    final styleLabel = _classifyStyle(tone, advanced, skin, warmCold);
    final tonalInsight = _buildTonalInsight(tone, advanced);
    final colorInsight = _buildColorInsight(tone, advanced, skin, warmCold);
    final techniqueInsight = _buildTechniqueInsight(tone, skin);
    final summary = _buildSummary(styleLabel, tone, skin);

    return PhotoInsight(
      styleLabel: styleLabel,
      tonalInsight: tonalInsight,
      colorInsight: colorInsight,
      techniqueInsight: techniqueInsight,
      summary: summary,
    );
  }

  /// 风格归类（简单 if-else，非统计匹配）
  ///
  /// 阈值基于摄影教材 + 调色理论的经验值，不做伪精确。
  /// 如果同时满足多个风格条件，取匹配度最高的。
  String? _classifyStyle(
    ToneResult tone,
    AdvancedPortraitMetrics? adv,
    SkinAnalysis skin,
    double? warmCold,
  ) {
    final rms = tone.rmsContrast;
    final mean = tone.mean;
    final bp = adv?.blackPointOffset ?? 8;
    final sat = skin.saturation;

    // 日系高调：高调（mean > 130）+ 低对比（RMS < 35）+ 黑点上提（> 6）
    if (mean > 130 && rms < 35 && bp > 6) {
      return '日系高调';
    }

    // 港风怀旧：中低调（mean < 120）+ 高对比（RMS > 50）+ 黑点低（< 6）
    if (mean < 120 && rms > 50 && bp < 6) {
      return '港风怀旧';
    }

    // 电影青橙：全长调（toneKey == 'full'）+ 高对比（RMS > 55）+ 暖冷比 < 0.9
    if (tone.toneKey == 'full' && rms > 55 && (warmCold != null && warmCold < 0.9)) {
      return '电影青橙';
    }

    // 中式古典：中间调（120 < mean < 150）+ 低对比（RMS < 30）+ 低饱和
    if (mean > 115 && mean < 155 && rms < 30 && sat != null && sat < 30) {
      return '中式古典';
    }

    // 低调人像：低调（mean < 100）
    if (mean < 100) {
      return '低调人像';
    }

    // 高调人像：高调（mean > 150）但对比不低（排除日系）
    if (mean > 150) {
      return '高调人像';
    }

    return null;
  }

  String _buildTonalInsight(ToneResult tone, AdvancedPortraitMetrics? adv) {
    final parts = <String>[];

    // 基调
    parts.add(tone.toneKeyLabel);

    // 对比度
    if (tone.rmsContrast > 55) {
      parts.add('高对比（RMS ${tone.rmsContrast.toStringAsFixed(0)}），明暗反差强烈');
    } else if (tone.rmsContrast < 30) {
      parts.add('低对比（RMS ${tone.rmsContrast.toStringAsFixed(0)}），柔和过渡');
    } else {
      parts.add('中等对比（RMS ${tone.rmsContrast.toStringAsFixed(0)}），明暗均衡');
    }

    // 黑点/白点
    if (adv != null) {
      if (adv.blackPointOffset < 4) {
        parts.add('暗部死黑触底');
      } else {
        parts.add('黑点上提 ${adv.blackPointOffset.toStringAsFixed(0)} 保留层次');
      }
      if (adv.whitePointCompression > 252) {
        parts.add('高光微溢出');
      }
    }

    // 熵 → 背景纯净度
    if (tone.entropy < 5.5) {
      parts.add('背景纯净');
    } else if (tone.entropy > 7.0) {
      parts.add('背景层次丰富');
    }

    return '${parts.join('，')}。';
  }

  String _buildColorInsight(
    ToneResult tone,
    AdvancedPortraitMetrics? adv,
    SkinAnalysis skin,
    double? warmCold,
  ) {
    final parts = <String>[];

    // 冷暖偏向
    if (warmCold != null) {
      if (warmCold < 0.9) {
        parts.add('冷调偏移');
      } else if (warmCold > 1.2) {
        parts.add('暖调偏移');
      } else {
        parts.add('冷暖均衡');
      }
    }

    // 肤色描述
    if (!skin.isEmpty && skin.hueOffset != null) {
      final dh = skin.hueOffset!;
      if (dh.abs() < 8) {
        parts.add('肤色贴近标准线');
      } else if (dh > 0) {
        parts.add('肤色暖偏（ΔH +${dh.toStringAsFixed(0)}°）');
      } else {
        parts.add('肤色冷偏（ΔH ${dh.toStringAsFixed(0)}°）');
      }
      if (skin.saturation != null) {
        if (skin.saturation! < 25) {
          parts.add('低饱和通透');
        } else if (skin.saturation! > 55) {
          parts.add('高饱和浓郁');
        }
      }
    }

    if (parts.isEmpty) parts.add('色彩中性自然');
    return '${parts.join('，')}。';
  }

  String _buildTechniqueInsight(ToneResult tone, SkinAnalysis skin) {
    final parts = <String>[];

    // 明度隔离
    final sls = skin.luminanceSeparation;
    if (sls != null) {
      if (sls > 15) {
        parts.add('主体显著提亮（SLS +${sls.toStringAsFixed(0)}%），视觉焦点汇聚');
      } else if (sls < -15) {
        parts.add('主体压暗（SLS ${sls.toStringAsFixed(0)}%），低调叙事');
      } else {
        parts.add('主体融入环境（SLS ${sls.toStringAsFixed(0)}%），平等叙事');
      }
    }

    // 色彩隔离
    final scs = skin.colorSeparation;
    if (scs != null) {
      if (scs > 60) {
        parts.add('色彩分离强（SCS ${scs.toStringAsFixed(0)}°）');
      } else if (scs < 30) {
        parts.add('色彩同源统一（SCS ${scs.toStringAsFixed(0)}°）');
      }
    }

    // 背景纯净度
    if (tone.entropy < 5.5) {
      parts.add('背景纯净（熵 ${tone.entropy.toStringAsFixed(1)}），虚化或大色块');
    } else if (tone.entropy > 7.0) {
      parts.add('背景复杂（熵 ${tone.entropy.toStringAsFixed(1)}），环境叙事丰富');
    }

    if (parts.isEmpty) parts.add('手法均衡');
    return '${parts.join('；')}。';
  }

  String _buildSummary(String? label, ToneResult tone, SkinAnalysis skin) {
    if (label == null) {
      // 无法归类 → 纯描述性总结
      return '${tone.toneKeyLabel}${tone.toneRangeLabel}，'
          'RMS ${tone.rmsContrast.toStringAsFixed(0)}，'
          '熵 ${tone.entropy.toStringAsFixed(1)}。';
    }

    // 根据风格标签生成一句话总结
    switch (label) {
      case '日系高调':
        return '高调 + 低对比 + 白皙肤色 = 日系小清新的典型语汇。';
      case '港风怀旧':
        return '中低调 + 高对比 + 死黑触底 + 暖黄肤色 = 港风怀旧的经典配方。';
      case '电影青橙':
        return '全长调 + 高对比 + 冷暖分裂 = 电影青橙调的视觉张力。';
      case '中式古典':
        return '中间调 + 低对比 + 低饱和 = 中式古典的含蓄内敛。';
      case '低调人像':
        return '低调画面，暗部主导，氛围感强。';
      case '高调人像':
        return '高调画面，亮部主导，通透明快。';
      default:
        return '${tone.toneKeyLabel}${tone.toneRangeLabel}影调。';
    }
  }
}
