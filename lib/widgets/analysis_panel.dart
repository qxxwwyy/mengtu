// analysis_panel.dart — 底部分析面板（展开/收起式）
//
// v1.0.0 新增：色相直方图模式 + 色卡算法切换
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/analysis_provider.dart';
import '../providers/database_provider.dart';
import '../services/palette_service.dart';
import '../services/database/app_database.dart';
import 'histogram_painter.dart';
import 'color_card.dart';
import 'tone_info_card.dart';
import 'harmony_card.dart';

/// 取色点列表 Provider（监听变化，自动刷新）
final colorPinsProvider =
    StreamProvider.family<List<ColorPin>, String>((ref, photoId) {
  final db = ref.watch(appDatabaseProvider);
  return db.colorPinDao.watchPinsByPhotoId(photoId);
});

/// 分析面板（自管高度，不使用 DraggableScrollableSheet）
/// 通过回调通知父级黑白状态变化
class AnalysisPanel extends ConsumerStatefulWidget {
  final String photoId;
  final bool isBlackWhite;
  final ValueChanged<bool> onBlackWhiteChanged;

  const AnalysisPanel({
    super.key,
    required this.photoId,
    required this.isBlackWhite,
    required this.onBlackWhiteChanged,
  });

  @override
  ConsumerState<AnalysisPanel> createState() => _AnalysisPanelState();
}

class _AnalysisPanelState extends ConsumerState<AnalysisPanel> {
  bool _expanded = false;
  HistogramMode _histMode = HistogramMode.rgb;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        constraints: BoxConstraints(
          maxHeight: _expanded ? 380 : 52,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶栏：黑白开关 + 展开按钮
            _buildTopRow(),
            // 展开内容
            if (_expanded)
              SizedBox(
                height: 340,
                child: DefaultTabController(
                  length: 5,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: '直方图'),
                          Tab(text: '色卡'),
                          Tab(text: '影调'),
                          Tab(text: '和谐'),
                          Tab(text: '取色'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildHistogramTab(),
                            _buildPaletteTab(),
                            _buildToneTab(),
                            _buildHarmonyTab(),
                            _buildColorPinTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.brightness_6, size: 18,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text('黑白', style: Theme.of(context).textTheme.labelLarge),
          Switch(
            value: widget.isBlackWhite,
            onChanged: (v) {
              widget.onBlackWhiteChanged(v);
              setState(() {
                _histMode = v ? HistogramMode.luminance : HistogramMode.rgb;
              });
            },
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Text('分析', style: Theme.of(context).textTheme.labelMedium),
                Icon(_expanded ? Icons.expand_more : Icons.expand_less),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistogramTab() {
    final histAsync = ref.watch(histogramProvider(widget.photoId));
    return histAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('计算失败: $e')),
      data: (hist) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // 紧凑模式选择器：分段按钮 + 更多菜单
              _buildModeSelector(),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: CustomPaint(
                  painter: HistogramPainter(data: hist, mode: _histMode),
                  child: Container(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 紧凑模式选择器
  /// 三主模式分段按钮 + 更多下拉菜单（R/G/B/RGB+亮度）
  Widget _buildModeSelector() {
    final cs = Theme.of(context).colorScheme;
    final isBW = widget.isBlackWhite;

    // 主模式：RGB / 亮度 / 色相
    final mainModes = [
      (HistogramMode.rgb, 'RGB', Icons.palette_outlined),
      (HistogramMode.luminance, '亮度', Icons.tonality),
      (HistogramMode.hue, '色相', Icons.color_lens_outlined),
    ];

    // 次要模式（在"更多"菜单中）
    final moreModes = [
      (HistogramMode.r, 'R 通道'),
      (HistogramMode.g, 'G 通道'),
      (HistogramMode.b, 'B 通道'),
      (HistogramMode.rgbLum, 'RGB+亮度'),
    ];

    // 判断当前选中是否是主模式
    final isMainMode = mainModes.any((m) => m.$1 == _histMode);

    return Row(
      children: [
        // 分段按钮
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: mainModes.map((m) {
                final selected = _histMode == m.$1;
                return Expanded(
                  child: GestureDetector(
                    onTap: isBW && m.$1 != HistogramMode.luminance
                        ? null
                        : () => setState(() => _histMode = m.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primary.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(m.$3,
                              size: 14,
                              color: selected
                                  ? cs.primary
                                  : cs.onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text(m.$2,
                              style: TextStyle(
                                fontSize: 11,
                                color: selected
                                    ? cs.primary
                                    : cs.onSurface.withValues(alpha: 0.5),
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              )),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // 更多按钮
        if (!isBW)
          PopupMenuButton<HistogramMode>(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: !isMainMode
                    ? cs.primary.withValues(alpha: 0.2)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.more_horiz,
                      size: 14,
                      color: !isMainMode
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 2),
                  Text(
                    !isMainMode
                        ? moreModes.firstWhere((m) => m.$1 == _histMode).$2
                        : '更多',
                    style: TextStyle(
                      fontSize: 11,
                      color: !isMainMode
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            onSelected: (mode) => setState(() => _histMode = mode),
            itemBuilder: (context) => moreModes
                .map((m) => PopupMenuItem(
                      value: m.$1,
                      child: Row(
                        children: [
                          if (_histMode == m.$1)
                            Icon(Icons.check,
                                size: 16, color: cs.primary)
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Text(m.$2),
                        ],
                      ),
                    ))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildPaletteTab() {
    return ColorCard(photoId: widget.photoId);
  }

  Widget _buildToneTab() {
    final toneAsync = ref.watch(toneProvider(widget.photoId));
    return toneAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('影调分析失败: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 12),
              textAlign: TextAlign.center),
        ),
      ),
      data: (tone) => ToneInfoCard(tone: tone),
    );
  }

  Widget _buildHarmonyTab() {
    final paletteAsync = ref.watch(paletteProvider((
      photoId: widget.photoId,
      algorithm: PaletteAlgorithm.celebi,
      desired: 5,
    )));
    return paletteAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('色卡分析失败: $e',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                  fontSize: 12),
              textAlign: TextAlign.center),
        ),
      ),
      data: (palette) => HarmonyCard(palette: palette),
    );
  }

  /// 取色历史 Tab
  Widget _buildColorPinTab() {
    final pinsAsync = ref.watch(colorPinsProvider(widget.photoId));
    return pinsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('取色数据加载失败: $e',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                  fontSize: 12),
              textAlign: TextAlign.center),
        ),
      ),
      data: (pins) {
        if (pins.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.colorize,
                    size: 32,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                Text('还没有取色点',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                        fontSize: 12)),
                const SizedBox(height: 4),
                Text('在工具栏开启取色模式后长按图片',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.3),
                        fontSize: 10)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: pins.length,
          itemBuilder: (context, index) {
            final pin = pins[index];
            final color = Color.fromARGB(255, pin.r, pin.g, pin.b);
            return _ColorPinTile(
              pin: pin,
              color: color,
              onDelete: () {
                // 二次确认删除（符合 AGENTS.md 规范）
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除取色点'),
                    content: const Text('确定要删除这个取色点吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          ref
                              .read(appDatabaseProvider)
                              .colorPinDao
                              .deletePin(pin.id);
                        },
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// 取色点列表项
class _ColorPinTile extends StatelessWidget {
  final ColorPin pin;
  final Color color;
  final VoidCallback onDelete;

  const _ColorPinTile({
    required this.pin,
    required this.color,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 计算 HEX 和 HSV
    final hex =
        '#${pin.r.toRadixString(16).padLeft(2, '0')}${pin.g.toRadixString(16).padLeft(2, '0')}${pin.b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
    final hsv = HSVColor.fromColor(color);
    final hsvStr =
        'H:${hsv.hue.round()}° S:${(hsv.saturation * 100).round()}% V:${(hsv.value * 100).round()}%';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // 色块
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
            ),
            const SizedBox(width: 10),
            // 色值信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(hex,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '(${pin.x}, ${pin.y})',
                          style: TextStyle(
                              fontSize: 9, color: cs.onSurface.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('rgb(${pin.r}, ${pin.g}, ${pin.b})  $hsvStr',
                      style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurface.withValues(alpha: 0.4))),
                ],
              ),
            ),
            // 删除按钮
            GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
