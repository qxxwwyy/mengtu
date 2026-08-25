// color_card.dart — 色卡组件（暗房专业美学 v2）
//
// v1.0.0: 算法切换（Celebi/MMCQ/K-Means）+ 提取数量调节（3-8）
// v2.0.0: segmented control + staggered 入场动画 + 1px 间隙 + haptic 反馈
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/palette_result.dart';
import '../utils/color_utils.dart';
import '../services/palette_service.dart';
import '../providers/analysis_provider.dart';
import '../theme/app_theme.dart';

/// 色卡组件：横向色块条 + 算法切换 + 数量调节 + 点击查看色值 + 长按复制
class ColorCard extends ConsumerStatefulWidget {
  final String photoId;

  const ColorCard({super.key, required this.photoId});

  @override
  ConsumerState<ColorCard> createState() => _ColorCardState();
}

class _ColorCardState extends ConsumerState<ColorCard> {
  int _selectedIndex = -1;
  PaletteAlgorithm _algorithm = PaletteAlgorithm.celebi;
  int _desired = 5;

  PaletteParams get _params =>
      (photoId: widget.photoId, algorithm: _algorithm, desired: _desired);

  @override
  Widget build(BuildContext context) {
    final paletteAsync = ref.watch(paletteProvider(_params));

    return SingleChildScrollView(
      padding: Spacing.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildControls(),
          SizedBox(height: Spacing.sm),
          paletteAsync.when(
            loading: () => SizedBox(
              height: 56,
              child: Center(
                child: CircularProgressIndicator(
                  color: DetailColors.accent,
                ),
              ),
            ),
            error: (e, _) => Padding(
              padding: Spacing.all(Spacing.lg),
              child: Text(
                '色卡提取失败: $e',
                style: AppTypography.captionMuted,
                textAlign: TextAlign.center,
              ),
            ),
            data: (palette) {
              if (palette.colors.isEmpty) {
                return SizedBox(
                  height: 56,
                  child: Center(
                    child: Text('无法提取色卡', style: AppTypography.captionMuted),
                  ),
                );
              }
              return Column(
                children: [
                  _buildColorBar(palette),
                  SizedBox(height: Spacing.md),
                  if (_selectedIndex >= 0 &&
                      _selectedIndex < palette.colors.length)
                    _buildColorDetail(palette.colors[_selectedIndex]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 算法切换 + 数量调节控件
  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 算法 segmented control ──
        Container(
          decoration: BoxDecoration(
            color: DetailColors.controlSurface,
            borderRadius: Radii.smBorder,
          ),
          child: Row(
            children: [
              for (final algo in PaletteAlgorithm.values)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _algorithm = algo;
                        _selectedIndex = -1;
                      });
                    },
                    child: Container(
                      padding: Spacing.v(Spacing.sm),
                      decoration: BoxDecoration(
                        color: _algorithm == algo
                            ? DetailColors.accent
                            : Colors.transparent,
                        borderRadius: Radii.smBorder,
                      ),
                      child: Text(
                        _algorithmLabel(algo),
                        textAlign: TextAlign.center,
                        style: _algorithm == algo
                            ? AppTypography.label.copyWith(
                                color: DetailColors.background,
                              )
                            : AppTypography.labelSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: Spacing.sm),
        // ── 数量 slider ──
        Row(
          children: [
            Text('$_desired', style: AppTypography.dataMd),
            SizedBox(width: Spacing.sm),
            Expanded(
              child: Slider(
                value: _desired.toDouble(),
                min: 3,
                max: 8,
                divisions: 5,
                label: '$_desired',
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _desired = v.round();
                    _selectedIndex = -1;
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _algorithmLabel(PaletteAlgorithm algo) {
    switch (algo) {
      case PaletteAlgorithm.celebi:
        return 'Celebi';
      case PaletteAlgorithm.mmcq:
        return 'MMCQ';
      case PaletteAlgorithm.kmeans:
        return 'K-Means';
    }
  }

  Widget _buildColorBar(PaletteResult palette) {
    return ClipRRect(
      borderRadius: Radii.mdBorder,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            for (var i = 0; i < palette.colors.length; i++) ...[
              if (i > 0)
                Container(width: 1, color: AppColors.bgBase),
              Expanded(
                flex: _getFlex(palette.colors[i].ratio),
                child: _AnimatedColorBlock(
                  color: Color(palette.colors[i].argb),
                  ratio: palette.colors[i].ratio,
                  isSelected: _selectedIndex == i,
                  delay: Duration(milliseconds: i * 50),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedIndex = _selectedIndex == i ? -1 : i;
                    });
                  },
                  onLongPress: () =>
                      _copyToClipboard(argbToHex(palette.colors[i].argb)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 占比转 flex 权重（最小 15% 保证可点击）
  int _getFlex(double ratio) {
    final clamped = ratio.clamp(15.0, 100.0);
    return (clamped * 10).round();
  }

  Widget _buildColorDetail(PaletteColor c) {
    final argb = c.argb;
    return Card(
      child: Padding(
        padding: Spacing.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color(argb),
                    borderRadius: Radii.mdBorder,
                    border: Border.all(color: ChartColors.gridLight),
                  ),
                ),
                SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('占比 ${c.ratio.toStringAsFixed(1)}%',
                          style: AppTypography.title),
                      SizedBox(height: Spacing.xs),
                      Text(argbToHex(argb), style: AppTypography.mono),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: Spacing.sm),
            _ColorValueRow(label: 'RGB', value: argbToRgbString(argb)),
            _ColorValueRow(label: 'HSL', value: argbToHslString(argb)),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已复制: $text'),
          duration: const Duration(milliseconds: 800),
        ),
      );
    }
  }
}

/// 带 staggered 入场动画的色块
class _AnimatedColorBlock extends StatefulWidget {
  final Color color;
  final double ratio;
  final bool isSelected;
  final Duration delay;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AnimatedColorBlock({
    required this.color,
    required this.ratio,
    required this.isSelected,
    required this.delay,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_AnimatedColorBlock> createState() => _AnimatedColorBlockState();
}

class _AnimatedColorBlockState extends State<_AnimatedColorBlock>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.chartEnterDuration,
    );
    _scale = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.chartEnterCurve),
    );
    // staggered 延迟入场
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          return Transform.scale(
            scaleX: _scale.value,
            alignment: Alignment.center,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            border: Border.all(
              color: widget.isSelected
                  ? DetailColors.textPrimary
                  : Colors.transparent,
              width: 3,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: Spacing.bottom(Spacing.xs),
              child: Text(
                '${widget.ratio.toStringAsFixed(0)}%',
                style: AppTypography.captionCompact.copyWith(color: _getContrastColor(widget.color),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 根据背景色亮度选择文字颜色
  Color _getContrastColor(Color bg) {
    return bg.computeLuminance() > 0.5
        ? AppColors.lightTextPrimary
        : DetailColors.textPrimary;
  }
}

/// 色值行
class _ColorValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _ColorValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: Spacing.v(2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(label, style: AppTypography.captionMuted),
          ),
          Expanded(
            child: Text(value, style: AppTypography.mono),
          ),
        ],
      ),
    );
  }
}
