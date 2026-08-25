// insight_service.dart — 样片洞察规则引擎（v8.0；v8.1 调研词典升级）
//
// 替代已删除的 FingerprintService + BuiltinProfiles 匹配系统。
// 不做伪精确的"相似度 %"，而是用简单 if-else 规则将照片的影调/色彩/手法
// 指标归类为一个整体风格标签，并生成解读式文字。
//
// 设计原则：
// - 只描述，不诊断（不说"蜡黄病态""死亡暗脸"）
// - 规则匹配就是规则匹配，不假装是统计相似度
// - 每个风格标签附带教学性解读文案
//
// v8.1（小红书调研 2026-08 驱动，见 docs/xhs-research-2026-08.md）：
// - 新增通透度诊断（clarityInsight）——"通透/闷/发灰"是调研中最大的
//   用户痛点母题（8.7 万赞《为什么你调色越来越脏？》+ 12 篇发灰笔记），
//   黑位/RMS 数据第一次翻译成用户语言，并附数值锚点
// - 风格名对齐用户叫法（日系高调→日系清透），新增胶片感灰调判定
// - 文案全面采用调研词典：通透/发灰/闷/层次/氛围感/空气感/质感
import '../models/advanced_portrait_metrics.dart';
import '../models/tone_result.dart';
import '../services/tone_service.dart' show calculateWarmToColdRatio;

/// 样片洞察结果
class PhotoInsight {
  /// 风格标签（如"日系清透""港风怀旧"等），null = 无法归类
  final String? styleLabel;

  /// 通透度诊断（v8.1）：黑位/白位/RMS 的组合翻译成"通透/闷/发灰"用户语言
  final String clarityInsight;

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
    this.clarityInsight = '',
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
    final clarityInsight = _buildClarityInsight(tone, advanced);
    final tonalInsight = _buildTonalInsight(tone, advanced);
    final colorInsight = _buildColorInsight(tone, advanced, skin, warmCold);
    final techniqueInsight = _buildTechniqueInsight(tone, skin);
    final summary = _buildSummary(styleLabel, tone, skin);

    return PhotoInsight(
      styleLabel: styleLabel,
      clarityInsight: clarityInsight,
      tonalInsight: tonalInsight,
      colorInsight: colorInsight,
      techniqueInsight: techniqueInsight,
      summary: summary,
    );
  }

  /// 通透度诊断（v8.1 调研核心洞察）
  ///
  /// 调研发现"通透 ↔ 灰/闷"是用户心中最大的一对反义词（22 篇笔记用"通透"，
  /// 12+ 篇抱怨"发灰"），但无人给出可操作定义。这里把黑位/对比度组合翻译
  /// 成用户语言 + 数值锚点：
  /// - 通透 = 黑位扎实（不抬灰）+ 对比足够 + 白位干净
  /// - 闷/灰 = 黑位上提 + 对比偏低（全局灰雾）
  /// - 空气感 = 有意的黑位上提但对比仍在（胶片/电影手法）
  String _buildClarityInsight(ToneResult tone, AdvancedPortraitMetrics? adv) {
    final bp = adv?.blackPointOffset ?? 8;
    final rms = tone.rmsContrast;
    final bpStr = bp.toStringAsFixed(0);
    final rmsStr = rms.toStringAsFixed(0);

    // 发闷：黑位明显上提 + 对比偏低
    if (bp > 13 && rms < 32) {
      return '通透度：偏闷。黑位上提 $bpStr 且对比偏低（RMS $rmsStr），'
          '暗部没沉下去、明暗拉不开 —— 这就是小红书说的"发灰不通透"。'
          '想更通透：压黑位、加对比。';
    }
    // 空气感：黑位上提但对比仍在（有意手法）
    if (bp > 10) {
      return '通透度：空气感。黑位上提 $bpStr（暗部不贴死黑），'
          '对比 RMS $rmsStr 仍在 —— 胶片感/电影感的典型手法，'
          '"灰"得有目的。';
    }
    // 死黑
    if (bp < 3 && rms > 50) {
      return '通透度：硬朗。黑位触底 + 高对比（RMS $rmsStr），'
          '暗部死黑换冲击力 —— 港风/电影调的取舍。';
    }
    // 通透（默认良好区间）
    return '通透度：通透。黑位扎实（偏移 $bpStr）、对比 RMS $rmsStr、'
        '明暗分离清晰 —— "通透"第一次有了数值锚点。';
  }

  /// 风格归类（简单 if-else，非统计匹配）
  ///
  /// 阈值基于摄影教材 + 调色理论 + 2026-08 小红书调研的风格特征表。
  /// 如果同时满足多个风格条件，取匹配度最高的。
  /// 风格名对齐用户叫法（调研词典）。
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

    // 日系清透：高调（mean > 130）+ 低对比（RMS < 35）+ 黑点上提（> 6）
    if (mean > 130 && rms < 35 && bp > 6) {
      return '日系清透';
    }

    // 胶片感灰调：中低调 + 低对比 + 黑位明显上提（v8.1 新增，调研：
    // "故意发灰是胶片感核心手法"，与"无意发灰"的区分在黑位是否可控）
    if (mean > 95 && mean <= 135 && rms < 35 && bp > 11) {
      return '胶片感灰调';
    }

    // 港风怀旧：中低调（mean < 120）+ 高对比（RMS > 50）+ 黑点低（< 6）
    if (mean < 120 && rms > 50 && bp < 6) {
      return '港风怀旧';
    }

    // 电影青橙：全长调（toneKey == 'full'）+ 高对比（RMS > 55）
    if (tone.toneKey == 'full' && rms > 55) {
      return '电影感（青橙向）';
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

    // 对比度（词典：层次 = 明度分离度）
    if (tone.rmsContrast > 55) {
      parts.add('高对比（RMS ${tone.rmsContrast.toStringAsFixed(0)}），层次拉开、明暗反差强烈');
    } else if (tone.rmsContrast < 30) {
      parts.add('低对比（RMS ${tone.rmsContrast.toStringAsFixed(0)}），柔和过渡，层次靠得很近');
    } else {
      parts.add('中等对比（RMS ${tone.rmsContrast.toStringAsFixed(0)}），明暗均衡');
    }

    // 黑点/白点
    if (adv != null) {
      if (adv.blackPointOffset < 4) {
        parts.add('暗部死黑触底');
      } else {
        parts.add('黑点上提 ${adv.blackPointOffset.toStringAsFixed(0)} 保留层次（空气感来源）');
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
        parts.add('冷调偏移（青蓝倾向，日系/阴影场景常见）');
      } else if (warmCold > 1.2) {
        parts.add('暖调偏移（橙黄倾向，黄金时段/港风常见）');
      } else {
        parts.add('冷暖均衡');
      }
    }

    // 肤色描述（词典：奶油感 = 高明度低饱和微暖）
    if (!skin.isEmpty && skin.hueOffset != null) {
      final dh = skin.hueOffset!;
      if (dh.abs() < 8) {
        parts.add('肤色贴近标准线');
      } else if (dh > 0) {
        parts.add('肤色暖偏（ΔH +${dh.toStringAsFixed(0)}°），偏黄气');
      } else {
        parts.add('肤色冷偏（ΔH ${dh.toStringAsFixed(0)}°），偏粉气');
      }
      if (skin.saturation != null && skin.skinLuminance != null) {
        final sat = skin.saturation!;
        final lum = skin.skinLuminance!;
        if (lum > 60 && sat < 40) {
          parts.add('肤色白净低饱和（奶油感方向）');
        } else if (sat > 55) {
          parts.add('高饱和浓郁');
        } else if (sat < 25) {
          parts.add('低饱和克制');
        }
      } else if (skin.saturation != null) {
        if (skin.saturation! < 25) {
          parts.add('低饱和克制');
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

    // 明度隔离（词典翻译：明度差 → "主体跳出来"）
    final sls = skin.luminanceSeparation;
    if (sls != null) {
      if (sls > 15) {
        parts.add('主体比背景亮（明度差 +${sls.toStringAsFixed(0)}%），'
            '人脸从环境里跳出来 —— 这就是为什么要单独提亮人物');
      } else if (sls < -15) {
        parts.add('主体比背景暗（明度差 ${sls.toStringAsFixed(0)}%），低调叙事');
      } else {
        parts.add('主体与背景明度接近（明度差 ${sls.toStringAsFixed(0)}%），人融进环境，平等叙事');
      }
    }

    // 色彩隔离
    final scs = skin.colorSeparation;
    if (scs != null) {
      if (scs > 60) {
        parts.add('肤色与背景色相分离大（色相差 ${scs.toStringAsFixed(0)}°），主体色彩独立');
      } else if (scs < 30) {
        parts.add('肤色与背景色相同源（色相差 ${scs.toStringAsFixed(0)}°），画面色调统一');
      }
    }

    // 背景纯净度（词典：质感 = 细节保留 + 层次）
    if (tone.entropy < 5.5) {
      parts.add('背景纯净（熵 ${tone.entropy.toStringAsFixed(1)}），虚化或大色块，主体质感突出');
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

    // 根据风格标签生成一句话总结（文案对齐调研词典）
    switch (label) {
      case '日系清透':
        return '高调 + 低对比 + 白皙肤色 —— 日系清透的典型语汇，'
            '通透感来自黑位控制而非一味降对比。';
      case '胶片感灰调':
        return '中低调 + 黑位有意上提 + 低对比 —— 胶片感的"灰"是手法不是事故，'
            '配颗粒更完整。';
      case '港风怀旧':
        return '中低调 + 高对比 + 死黑触底 —— 港风怀旧的经典配方，加颗粒和青橙分离更接近。';
      case '电影感（青橙向）':
        return '全长调 + 高对比 —— 电影感的骨架；高光染暖、阴影加青就是青橙调色。';
      case '中式古典':
        return '中间调 + 低对比 + 低饱和 —— 中式古典的含蓄内敛，克制的灰度美学。';
      case '低调人像':
        return '低调画面，暗部主导，氛围感强。';
      case '高调人像':
        return '高调画面，亮部主导，通透明快。';
      default:
        return '${tone.toneKeyLabel}${tone.toneRangeLabel}影调。';
    }
  }
}
