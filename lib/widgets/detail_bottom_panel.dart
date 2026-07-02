// detail_bottom_panel.dart — 详情页统一底部面板（v2.0 重构，v3.5 PR3 四阶解构改造）
//
// 融合原 QuickToolsDock + AnalysisPanel 为单一组件，解决两套割裂工具系统的问题：
// - 常驻工具行：高频调色工具（黑白/溢出/构图/锐度/取色/数据）始终可见 + 展开把手
// - 展开内容：GradingPanel（四阶解构卡片：影调/色彩/主体/档案），替代原 6 Tab
//
// v3.5 PR3 改造：
// - 删除 TabController（不再需要 TabBar）
// - 展开内容从 TabBarView 替换为 GradingPanel（滚动四阶卡片）
// - 工具行末尾新增「数据」按钮 → push 到 RawDataDashboard 全屏页
// - 原 6 Tab 内容（信息/直方图/色卡/影调/和谐/取色）迁入 RawDataDashboard
//
// 黑白控制统一为此处一个入口。取色模式由 forceCollapsed 控制（保留工具行可见）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'grading/grading_panel.dart';
import 'grading/raw_data_dashboard.dart';

/// 详情页底部统一面板
///
/// 工具状态（黑白/溢出/构图/取色）由父组件 [DetailPage] 管理，
/// 通过构造参数传入当前值 + 回调。面板自管展开状态。
class DetailBottomPanel extends ConsumerStatefulWidget {
  final String photoId;

  // 工具状态（父组件持有，因 overlays 在图片区渲染）
  final bool isBlackWhite;
  final bool showClipping;
  final bool isColorPickMode;
  final bool hasComposition;
  final bool showFocusPeaking;

  // 工具回调
  final VoidCallback onBlackWhiteToggle;
  final VoidCallback onClippingToggle;
  final VoidCallback onCompositionToggle;
  final VoidCallback onColorPickToggle;
  final VoidCallback onFocusPeakingToggle;

  /// 展开/收起变化回调（父组件可借此在收起时让图片获得更多空间）
  final ValueChanged<bool>? onExpandChanged;

  /// 强制收起（取色模式时为 true）：保留工具行可见，但禁止展开 GradingPanel
  /// 避免 GradingPanel 与取色放大镜/pin 标记重叠争夺空间
  final bool forceCollapsed;

  const DetailBottomPanel({
    super.key,
    required this.photoId,
    required this.isBlackWhite,
    required this.showClipping,
    required this.isColorPickMode,
    required this.hasComposition,
    required this.showFocusPeaking,
    required this.onBlackWhiteToggle,
    required this.onClippingToggle,
    required this.onCompositionToggle,
    required this.onColorPickToggle,
    required this.onFocusPeakingToggle,
    this.onExpandChanged,
    this.forceCollapsed = false,
  });

  @override
  ConsumerState<DetailBottomPanel> createState() => _DetailBottomPanelState();
}

class _DetailBottomPanelState extends ConsumerState<DetailBottomPanel> {
  bool _expanded = false;

  /// 实际是否展开（forceCollapsed 时强制 false）
  bool get _effectiveExpanded => _expanded && !widget.forceCollapsed;

  void _toggleExpand() {
    if (widget.forceCollapsed) return; // 取色模式禁止展开
    setState(() => _expanded = !_expanded);
    widget.onExpandChanged?.call(_expanded);
  }

  void _openDataDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RawDataDashboard(photoId: widget.photoId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v6.1：用固定 height 约束（原 maxHeight:380 留余量 → Column(min) 居中 →
    // 工具行与卡片之间出现暗色空隙，用户看成「顶部大黑框」，问题4）。
    // 收起态 72（工具行），展开态 = 工具行(60) + GradingPanel(308) = 368。
    final height = _effectiveExpanded ? 368.0 : 80.0;
    return AnimatedContainer(
      duration: AppAnimations.expandDuration,
      curve: AppAnimations.expandCurve,
      height: height,
      decoration: const BoxDecoration(
        color: DetailColors.panelSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        border: Border(
          top: BorderSide(color: DetailColors.divider, width: 0.5),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // grab handle 拖拽指示器（非取色模式显示）
          if (!widget.forceCollapsed) _buildGrabHandle(),
          // 常驻工具行（始终可见，取色模式也保留以供退出）
          _buildToolRow(),
          // 展开内容（取色模式 forceCollapsed 时不显示）—— Expanded 填满剩余高度
          // 紧贴工具行下方，无间隙
          if (_effectiveExpanded)
            Expanded(
              child: GradingPanel(photoId: widget.photoId),
            ),
        ],
      ),
    );
  }

  // ============ Grab Handle ============

  Widget _buildGrabHandle() {
    return GestureDetector(
      onTap: _toggleExpand,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: AppAnimations.expandDuration,
          width: _effectiveExpanded ? 28 : 36,
          height: 4,
          decoration: BoxDecoration(
            color: _effectiveExpanded
                ? AppColors.accent.withValues(alpha: 0.6)
                : DetailColors.textMuted,
            borderRadius: Radii.pillBorder,
          ),
        ),
      ),
    );
  }

  // ============ 常驻工具行 ============

  Widget _buildToolRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _ToolButton(
            icon: Icons.brightness_6_outlined,
            label: '黑白',
            isActive: widget.isBlackWhite,
            onTap: widget.onBlackWhiteToggle,
          ),
          _ToolButton(
            icon: Icons.remove_red_eye_outlined,
            label: '溢出',
            isActive: widget.showClipping,
            onTap: widget.onClippingToggle,
          ),
          _ToolButton(
            icon: Icons.grid_on_outlined,
            label: '构图',
            isActive: widget.hasComposition,
            onTap: widget.onCompositionToggle,
          ),
          _ToolButton(
            icon: Icons.center_focus_strong_outlined,
            label: '锐度',
            isActive: widget.showFocusPeaking,
            onTap: widget.onFocusPeakingToggle,
          ),
          _ToolButton(
            icon: Icons.colorize_outlined,
            label: '取色',
            isActive: widget.isColorPickMode,
            onTap: widget.onColorPickToggle,
          ),
          // v3.5 PR3：数据仪表盘入口（全屏页，承载原 6 Tab 的原始读数）
          _ToolButton(
            icon: Icons.bar_chart,
            label: '数据',
            isActive: false,
            onTap: _openDataDashboard,
          ),
          const SizedBox(width: 4),
          // 分隔线
          Container(
            width: 1,
            height: 28,
            color: DetailColors.divider,
          ),
          // 右侧：展开把手（取色模式时显示取色提示，不可展开）
          Expanded(
            child: widget.forceCollapsed
                ? // 取色模式：提示长按取点，不可点展开
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app,
                              size: 14, color: DetailColors.textMuted),
                          SizedBox(width: 4),
                          Text('长按图片取色点',
                              style: TextStyle(
                                fontSize: 11,
                                color: DetailColors.textMuted,
                              )),
                        ],
                      ),
                    )
                : GestureDetector(
                    onTap: _toggleExpand,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _effectiveExpanded ? '收起' : '分析 / 信息',
                            style: const TextStyle(
                              fontSize: 12,
                              color: DetailColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // 展开时向上（可收起），收起时向下（可展开）
                          Icon(
                            _effectiveExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: DetailColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============ 常驻工具行按钮 ============

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.legacy12Border,
      child: Container(
        decoration: isActive
            ? BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: Radii.legacy12Border,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 22,
                color: isActive ? accent : DetailColors.textSecondary),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? accent : DetailColors.textMuted,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}
