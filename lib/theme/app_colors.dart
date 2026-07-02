// app_colors.dart — 萌图色彩 Token 系统（暗房专业美学）
//
// 设计理念：深邃的炭灰背景让照片色彩跳出来，
// 琥珀色（暗房安全灯）做主点缀，辅以冷/暖/成功/警告的语义色谱。
//
// 暗色模式是核心场景（专业摄影工具惯例），浅色模式保持功能完整。
// 详情页永远是暗色（DetailColors 独立体系），不随全局主题切换。
import 'package:flutter/material.dart';

/// 萌图设计系统色彩 Token
///
/// 暗色模式（默认）的色彩定义。浅色模式通过 `light*` 前缀覆盖。
/// 所有 Widget 应引用这些 token，禁止散落 `Color(0x...)` 或 `Colors.xxx`。
class AppColors {
  AppColors._();

  // ═══════════════════════════════════════════════
  // 暗色模式 — 背景层级（5 层深度体系）
  // ═══════════════════════════════════════════════

  /// 最深层 — 照片查看区（接近纯黑，带极微暖色调）
  static const bgVoid = Color(0xFF08080A);

  /// 页面底色（比纯黑略亮，建立空间深度）
  static const bgBase = Color(0xFF0F0F12);

  /// 卡片底色（第一层浮起）
  static const bgSurface = Color(0xFF16161A);

  /// 浮层/弹窗背景（第二层浮起）
  static const bgElevated = Color(0xFF1E1E24);

  /// hover / 选中态背景
  static const bgHover = Color(0xFF26262E);

  // ═══════════════════════════════════════════════
  // 暗色模式 — 强调色体系（从单一琥珀升级为色温光谱）
  // ═══════════════════════════════════════════════

  /// 主品牌色 — 暗房安全灯（琥珀色）
  static const accent = Color(0xFFE8A838);

  /// 主品牌色弱化态
  static const accentDim = Color(0xFF8C6818);

  /// 数据/图表辅色（冷色系分析）
  static const accentCyan = Color(0xFF4ECDC4);

  /// 警告/溢出（暖色系警告）
  static const accentCoral = Color(0xFFFF6B6B);

  /// 成功/确认
  static const accentSage = Color(0xFF95E1A3);

  /// 文字高亮（暖白，比纯白柔和）
  static const textGlow = Color(0xFFF0E6D2);

  // ═══════════════════════════════════════════════
  // 暗色模式 — 文字层级
  // ═══════════════════════════════════════════════

  /// 主文字色（高对比度）
  static const textPrimary = Color(0xFFE8E6E3);

  /// 次要文字色（图标、辅助标签）
  static const textSecondary = Color(0xFFA0A0A8);

  /// 弱化文字色（占位、提示）
  static const textMuted = Color(0xFF6A6A72);

  /// 数据数值色（暖金色，区分文字和数据）
  static const textData = Color(0xFFC8B87A);

  // ═══════════════════════════════════════════════
  // 暗色模式 — 特殊/功能色
  // ═══════════════════════════════════════════════

  /// 图表网格线（白色 6% alpha）
  static const chartGrid = Color(0x0FFFFFFF);

  /// 分隔线
  static const divider = Color(0xFF2A2A2E);

  /// 蒙层（黑色 40% alpha）
  static const overlayScrim = Color(0x66000000);

  /// 蒙层强（黑色 60% alpha）
  static const overlayScrimStrong = Color(0x99000000);

  // ═══════════════════════════════════════════════
  // 照片覆盖层文字（不论主题始终浅色，因为叠在照片上）
  // ═══════════════════════════════════════════════

  /// 照片上的主文字（白色 70%）
  static const onPhotoText = Color(0xB3FFFFFF);

  /// 照片上次要文字（白色 30%）
  static const onPhotoTextDim = Color(0x4DFFFFFF);

  /// 照片覆盖暗角（黑色 75%）
  static const onPhotoScrim = Color(0xBF000000);

  // ═══════════════════════════════════════════════
  // 浅色模式（功能完整但视觉优先级低）
  // ═══════════════════════════════════════════════

  static const lightBgBase = Color(0xFFFAFAFA);
  static const lightBgSurface = Color(0xFFFFFFFF);
  static const lightBgElevated = Color(0xFFF5F5F5);
  static const lightAccent = Color(0xFFC8881C);
  static const lightAccentDim = Color(0xFFE8D5B0);
  static const lightTextPrimary = Color(0xFF1A1A1A);
  static const lightTextSecondary = Color(0xFF666666);
  static const lightTextMuted = Color(0xFF999999);
  static const lightDivider = Color(0xFFE5E5E5);
}

/// 详情页专用暗色 Token（独立体系）
///
/// 详情页作为图片查看/调色场景，无论全局主题如何都使用暗色背景，
/// 让照片色彩最准确（gotcha #26）。
/// 集中维护详情页所有颜色，替代散落的 Colors.white54 / Colors.black 硬编码。
class DetailColors {
  DetailColors._();

  /// 详情页底色（最深层，最大化照片对比度）
  static const background = Color(0xFF08080A);

  /// 底部面板不透明背景（surface 角色）
  static const panelSurface = Color(0xFF16161A);

  /// 卡片/列表项背景
  static const cardSurface = Color(0xFF1E1E24);

  /// 嵌套控件背景（分段选择器、chips 容器）
  static const controlSurface = Color(0xFF26262E);

  /// 小标签/chip 背景
  static const chipSurface = Color(0xFF2E2E36);

  /// 主文字色
  static const textPrimary = Color(0xFFE8E6E3);

  /// 次要文字色（白色 ~55%）
  static const textSecondary = Color(0x8CFFFFFF);

  /// 弱化文字色（白色 ~35%）
  static const textMuted = Color(0x59FFFFFF);

  /// 分隔线（白色 6%）
  static const divider = Color(0x0FFFFFFF);

  /// 错误/警告色（溢出警告高亮）
  static const warning = Color(0xFFFF6B6B);

  /// 强调色（与全局 accent 一致）
  static const accent = Color(0xFFE8A838);

  /// 蒙层（黑色 40%）
  static const scrim = Color(0x66000000);

  /// 人脸框非高亮色（白色 67%）
  static const faceBoxNormal = Color(0xAAFFFFFF);
}

/// 语义状态色（跨主题通用）
///
/// 用于 InterpretationStatus、SharpnessGuide、PlanStatus 等场景。
/// 这些颜色不随暗/浅主题变化（状态语义是绝对的）。
class StatusColors {
  StatusColors._();

  /// 错误/危险/删除
  static const error = Color(0xFFEF5350);

  /// 成功/良好
  static const success = Color(0xFF4CAF50);

  /// 警告/注意
  static const warning = Color(0xFFFF9800);

  /// 信息/偏低
  static const info = Color(0xFF42A5F5);

  /// 中性/已完成/归档
  static const neutral = Color(0xFF9E9E9E);

  /// 冷灰蓝（归档状态专用）
  static const neutralCool = Color(0xFF607D8B);
}

/// 图表/数据可视化专用色
///
/// 直方图通道色、影调分区色、肤色示波器色等。
/// 这些颜色表达数据语义，不随主题变化。
class ChartColors {
  ChartColors._();

  // ── 直方图 RGB 通道 ──
  static const channelR = Color(0xFFF44336);
  static const channelG = Color(0xFF4CAF50);
  static const channelB = Color(0xFF2196F3);

  /// 亮度通道
  static const channelLum = Color(0xFFE0E0E0);

  // ── 影调五区域（tone zones）──
  static const toneBlacks = Color(0xFF42424F);
  static const toneShadows = Color(0xFF37474F);
  static const toneMidtones = Color(0xFF78909C);
  static const toneHighlights = Color(0xFFB0BEC5);
  static const toneWhites = Color(0xFFECEFF1);

  // ── 肤色示波器 ──
  /// 肤色参考线（暖黄）
  static const skinToneLine = Color(0xFFFFD54F);

  /// 肤色光点（暖橙）
  static const skinTonePoint = Color(0xFFFF8A65);

  /// 肤色光点外晕
  static const skinToneHalo = Color(0xFFFF7043);

  // ── 网格/辅助线 ──
  /// 浅网格线（白色 15%）
  static const gridLight = Color(0x26FFFFFF);

  /// 更浅网格线（白色 10%）
  static const gridFaint = Color(0x1AFFFFFF);
}
