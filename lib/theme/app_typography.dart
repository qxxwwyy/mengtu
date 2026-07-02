// app_typography.dart — 萌图字体层级 Token
//
// 9 级 typography scale，参考 Material 3 但针对摄影工具场景调优：
// 数据数值用暖金色+细体大号，与普通文字视觉区分。
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 字体层级 Token
///
/// 用法：`AppTypography.display` / `AppTypography.dataXl` 等。
/// 所有 Widget 应引用这些 token，禁止散落 `FontWeight.w500` 硬编码。
class AppTypography {
  AppTypography._();

  // ═══════════════════════════════════════════════
  // 文字层级
  // ═══════════════════════════════════════════════

  /// 数据仪表盘大数字
  static const display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  /// 页面标题
  static const headline = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  /// 卡片标题、section 标题
  static const title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  /// 正文
  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// 标签、按钮文字
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// 标注、辅助信息
  static const caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  // ═══════════════════════════════════════════════
  // 数据数值层级（暖金色 textData，区分文字和数据）
  // ═══════════════════════════════════════════════

  /// 大数值展示（细体大数字，更优雅）
  static const dataXl = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w300,
    letterSpacing: 0,
    color: AppColors.textData,
    height: 1.2,
  );

  /// 中等数值
  static const dataMd = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textData,
    height: 1.3,
  );

  /// 色值/坐标（等宽字体）
  static const mono = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    color: AppColors.textData,
    fontFamily: 'monospace',
    height: 1.4,
  );

  // ═══════════════════════════════════════════════
  // 次要文字层级（textSecondary 颜色）
  // ═══════════════════════════════════════════════

  /// 次要正文
  static const bodySecondary = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  /// 次要标签
  static const labelSecondary = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  /// 弱化标注
  static const captionMuted = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    color: AppColors.textMuted,
    height: 1.4,
  );

  // ═══════════════════════════════════════════════
  // 便捷工厂方法 — 传入颜色覆盖默认
  // ═══════════════════════════════════════════════

  /// [display] 带指定颜色
  static TextStyle displayWith(Color color) => display.copyWith(color: color);

  /// [headline] 带指定颜色
  static TextStyle headlineWith(Color color) => headline.copyWith(color: color);

  /// [title] 带指定颜色
  static TextStyle titleWith(Color color) => title.copyWith(color: color);

  /// [body] 带指定颜色
  static TextStyle bodyWith(Color color) => body.copyWith(color: color);

  /// [label] 带指定颜色
  static TextStyle labelWith(Color color) => label.copyWith(color: color);

  /// [caption] 带指定颜色
  static TextStyle captionWith(Color color) => caption.copyWith(color: color);

  /// [dataXl] 带指定颜色
  static TextStyle dataXlWith(Color color) => dataXl.copyWith(color: color);

  /// [dataMd] 带指定颜色
  static TextStyle dataMdWith(Color color) => dataMd.copyWith(color: color);

  /// [mono] 带指定颜色
  static TextStyle monoWith(Color color) => mono.copyWith(color: color);
}
