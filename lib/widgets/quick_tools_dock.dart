// quick_tools_dock.dart — 详情页悬浮毛玻璃工具 Dock（v2.0 拇指热区优化）
// 放在图片区域底部，Easy 区一键操作，替代原来的"更多"BottomSheet
import 'dart:ui';
import 'package:flutter/material.dart';

class QuickToolsDock extends StatelessWidget {
  final bool isBlackWhite;
  final bool showClipping;
  final bool isColorPickMode;
  final bool hasComposition;
  final VoidCallback onBlackWhiteToggle;
  final VoidCallback onClippingToggle;
  final VoidCallback onCompositionToggle;
  final VoidCallback onColorPickToggle;
  final VoidCallback onCompareTap;

  const QuickToolsDock({
    super.key,
    required this.isBlackWhite,
    required this.showClipping,
    required this.isColorPickMode,
    required this.hasComposition,
    required this.onBlackWhiteToggle,
    required this.onClippingToggle,
    required this.onCompositionToggle,
    required this.onColorPickToggle,
    required this.onCompareTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDockItem(
                  icon: Icons.brightness_6_outlined,
                  label: '黑白',
                  isActive: isBlackWhite,
                  accentColor: accent,
                  onTap: onBlackWhiteToggle,
                ),
                _buildDockItem(
                  icon: Icons.remove_red_eye_outlined,
                  label: '溢出',
                  isActive: showClipping,
                  accentColor: accent,
                  onTap: onClippingToggle,
                ),
                _buildDockItem(
                  icon: Icons.grid_on_outlined,
                  label: '构图',
                  isActive: hasComposition,
                  accentColor: accent,
                  onTap: onCompositionToggle,
                ),
                _buildDockItem(
                  icon: Icons.colorize_outlined,
                  label: '取色',
                  isActive: isColorPickMode,
                  accentColor: accent,
                  onTap: onColorPickToggle,
                ),
                _buildDockItem(
                  icon: Icons.compare_outlined,
                  label: '对比',
                  isActive: false,
                  accentColor: accent,
                  onTap: onCompareTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isActive ? accentColor : Colors.white60,
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isActive ? 12 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
