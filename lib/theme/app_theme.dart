// app_theme.dart — 萌图设计系统（暗房美学）
//
// 设计理念：深炭灰背景让照片色彩跳出来，
// 琥珀色（暗房安全灯）做点缀，专业摄影工具的质感。
import 'package:flutter/material.dart';

/// 全局设计 Token（替代 Colors.grey.shadeXXX 硬编码）
class AppColors {
  AppColors._();

  // --- 暗色模式 ---
  static const darkBgBase = Color(0xFF0F0F0F);
  static const darkBgSurface = Color(0xFF1A1A1A);
  static const darkBgElevated = Color(0xFF242424);
  static const darkAccent = Color(0xFFE8A838);
  static const darkAccentDim = Color(0xFF8C6818);
  static const darkTextPrimary = Color(0xFFE8E8E8);
  static const darkTextSecondary = Color(0xFF9A9A9A);
  static const darkTextMuted = Color(0xFF6A6A6A);

  // --- 浅色模式 ---
  static const lightBgBase = Color(0xFFFAFAFA);
  static const lightBgSurface = Color(0xFFFFFFFF);
  static const lightBgElevated = Color(0xFFF5F5F5);
  static const lightAccent = Color(0xFFC8881C);
  static const lightAccentDim = Color(0xFFE8D5B0);
  static const lightTextPrimary = Color(0xFF1A1A1A);
  static const lightTextSecondary = Color(0xFF666666);
  static const lightTextMuted = Color(0xFF999999);
}

/// 暗色主题（默认）
ThemeData buildDarkTheme() {
  const accent = AppColors.darkAccent;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.darkBgSurface,
    primary: accent,
    onPrimary: AppColors.darkBgBase,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.darkBgBase,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.darkTextPrimary,
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkBgSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.darkBgElevated,
      selectedColor: accent.withValues(alpha: 0.2),
      labelStyle: const TextStyle(fontSize: 12, color: AppColors.darkTextPrimary),
      side: BorderSide(color: accent.withValues(alpha: 0.3), width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: AppColors.darkTextSecondary,
      indicatorColor: accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: AppColors.darkBgBase,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkBgElevated,
      contentTextStyle: const TextStyle(color: AppColors.darkTextPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF2A2A2A),
      thickness: 0.5,
    ),
    iconTheme: const IconThemeData(color: AppColors.darkTextSecondary),
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

/// 浅色主题
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
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.lightTextPrimary,
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightBgSurface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.lightBgElevated,
      selectedColor: accent.withValues(alpha: 0.15),
      labelStyle: const TextStyle(fontSize: 12, color: AppColors.lightTextPrimary),
      side: BorderSide(color: accent.withValues(alpha: 0.3), width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.lightTextPrimary,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE5E5E5),
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
