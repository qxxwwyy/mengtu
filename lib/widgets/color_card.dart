// color_card.dart — 色卡组件（横向色块条 + 占比 + 色值展示）
//
// v1.0.0 新增：算法切换（Celebi/MMCQ/K-Means）+ 提取数量调节（3-8）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/palette_result.dart';
import '../utils/color_utils.dart';
import '../services/palette_service.dart';
import '../providers/analysis_provider.dart';

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

  /// 便捷构造 PaletteParams
  PaletteParams get _params =>
      (photoId: widget.photoId, algorithm: _algorithm, desired: _desired);

  @override
  Widget build(BuildContext context) {
    final paletteAsync = ref.watch(paletteProvider(_params));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildControls(),
          const SizedBox(height: 8),
          paletteAsync.when(
            loading: () => const SizedBox(
              height: 56,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('色卡提取失败: $e',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 12),
                  textAlign: TextAlign.center),
            ),
            data: (palette) {
              if (palette.colors.isEmpty) {
                return SizedBox(
                  height: 56,
                  child: Center(
                    child: Text('无法提取色卡',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4))),
                  ),
                );
              }
              return Column(
                children: [
                  _buildColorBar(palette),
                  const SizedBox(height: 12),
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
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final algo in PaletteAlgorithm.values)
          ChoiceChip(
            label: Text(_algorithmLabel(algo)),
            selected: _algorithm == algo,
            onSelected: (_) {
              setState(() {
                _algorithm = algo;
                _selectedIndex = -1;
              });
            },
          ),
        const SizedBox(width: 4),
        // 数量调节
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_desired', style: const TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(
              width: 120,
              child: Slider(
                value: _desired.toDouble(),
                min: 3,
                max: 8,
                divisions: 5,
                label: '$_desired',
                onChanged: (v) {
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
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            for (var i = 0; i < palette.colors.length; i++)
              Expanded(
                flex: _getFlex(palette.colors[i].ratio),
                child: _ColorBlock(
                  color: Color(palette.colors[i].argb),
                  ratio: palette.colors[i].ratio,
                  isSelected: _selectedIndex == i,
                  onTap: () {
                    setState(() {
                      _selectedIndex = _selectedIndex == i ? -1 : i;
                    });
                  },
                  onLongPress: () =>
                      _copyToClipboard(argbToHex(palette.colors[i].argb)),
                ),
              ),
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
        padding: const EdgeInsets.all(12),
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
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('占比 ${c.ratio.toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(argbToHex(argb),
                          style: TextStyle(
                              fontFamily: 'monospace',
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ColorValueRow(label: 'RGB', value: argbToRgbString(argb)),
            _ColorValueRow(label: 'HSL', value: argbToHslString(argb)),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
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

/// 单个色块
class _ColorBlock extends StatelessWidget {
  final Color color;
  final double ratio;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ColorBlock({
    required this.color,
    required this.ratio,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 3,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${ratio.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 10,
                color: _getContrastColor(color),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 根据背景色亮度选择文字颜色
  Color _getContrastColor(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70;
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
