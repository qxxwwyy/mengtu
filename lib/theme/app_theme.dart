// app_theme.dart — 萌图设计系统（暗房专业美学）
//
// 本文件是 theme/ 模块的统一导出入口 + ThemeData builder。
// 色彩/字体/间距/动效 token 分别在各自的文件中维护：
//   - app_colors.dart       → AppColors / DetailColors / StatusColors / ChartColors
//   - app_typography.dart   → AppTypography
//   - app_spacing.dart      → Spacing / Radii
//   - app_animations.dart   → Durations / Curves2 / AppAnimations
//
// 设计理念：深炭灰背景让照片色彩跳出来，
// 琥珀色（暗房安全灯）做点缀，专业摄影工具的质感。
// 暗色模式是核心场景，详情页永远是暗色（DetailColors 独立体系）。
library;

import 'package:flutter/material.dart';

// ── 导出全部 token 文件（单一导入入口）──
export 'app_colors.dart';
export 'app_typography.dart';
export 'app_spacing.dart';
export 'app_animations.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// 暗色主题（默认，也是核心场景）
ThemeData buildDarkTheme() {
  const accent = AppColors.accent;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.bgSurface,
    primary: accent,
    onPrimary: AppColors.bgBase,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.bgBase,
    textTheme: _buildTextTheme(AppColors.textPrimary),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.textPrimary,
      // 统一页头标题样式（消除各页手写 w600/20/primary）
      titleTextStyle: AppTypography.headline.copyWith(
        fontSize: 20,
        color: colorScheme.primary,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.bgSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.mdBorder,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.bgElevated,
      selectedColor: accent.withValues(alpha: 0.2),
      labelStyle: AppTypography.label.copyWith(color: AppColors.textPrimary),
      side: BorderSide(color: accent.withValues(alpha: 0.3), width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: Radii.smBorder),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: AppColors.bgBase,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: Radii.lgBorder),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.bgElevated,
      contentTextStyle: AppTypography.body.copyWith(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: Radii.smBorder),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 0.5,
    ),
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: accent.withValues(alpha: 0.15),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: accent.withValues(alpha: 0.2),
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: 0.2),
    ),
  );
}

/// 浅色主题（功能完整，视觉优先级低）
ThemeData buildLightTheme() {
  const accent = AppColors.lightAccent;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.light,
  ).copyWith(
    surface: AppColors.lightBgSurface,
    primary: accent,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.lightBgBase,
    textTheme: _buildTextTheme(AppColors.lightTextPrimary),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.lightTextPrimary,
      titleTextStyle: AppTypography.headline.copyWith(
        fontSize: 20,
        color: colorScheme.primary,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightBgSurface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: Radii.mdBorder),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.lightBgElevated,
      selectedColor: accent.withValues(alpha: 0.15),
      labelStyle: AppTypography.label.copyWith(color: AppColors.lightTextPrimary),
      side: BorderSide(color: accent.withValues(alpha: 0.3), width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: Radii.smBorder),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: AppColors.lightTextSecondary,
      indicatorColor: accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: Radii.lgBorder),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.lightTextPrimary,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: Radii.smBorder),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.lightDivider,
      thickness: 0.5,
    ),
    iconTheme: const IconThemeData(color: AppColors.lightTextSecondary),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: accent.withValues(alpha: 0.15),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: accent.withValues(alpha: 0.2),
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: 0.2),
    ),
  );
}

/// 构建 TextTheme（复用 AppTypography token，映射到 Material 3 槽位）
TextTheme _buildTextTheme(Color primaryColor) {
  return TextTheme(
    displayLarge: AppTypography.display.copyWith(color: primaryColor),
    displayMedium: AppTypography.dataXl.copyWith(color: primaryColor),
    headlineLarge: AppTypography.headline.copyWith(color: primaryColor),
    titleLarge: AppTypography.title.copyWith(color: primaryColor),
    bodyLarge: AppTypography.body.copyWith(color: primaryColor),
    bodyMedium: AppTypography.bodySecondary.copyWith(color: AppColors.textSecondary),
    labelLarge: AppTypography.label.copyWith(color: primaryColor),
    labelMedium: AppTypography.labelSecondary.copyWith(color: AppColors.textSecondary),
    bodySmall: AppTypography.caption.copyWith(color: AppColors.textSecondary),
    labelSmall: AppTypography.captionMuted.copyWith(color: AppColors.textMuted),
  );
}
