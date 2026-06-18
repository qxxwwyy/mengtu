// detail_bottom_panel.dart — 详情页统一底部面板（v2.0 重构）
//
// 融合原 QuickToolsDock + AnalysisPanel 为单一组件，解决两套割裂工具系统的问题：
// - 常驻工具行：高频调色工具（黑白/溢出/构图/取色）始终可见 + 展开把手
// - 展开内容：TabBarView（信息 / 直方图 / 色卡 / 影调 / 和谐 / 取色）
//
// 黑白控制统一为此处一个入口（删除原顶栏快捷栏 + AnalysisPanel Switch 的重复）
// 标签管理移入"信息"Tab，释放底部拇指热区
// 对比/加入相册等低频功能移到 detail_page 顶栏更多菜单
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/exif_info.dart';
import '../pages/album_detail_page.dart';
import '../providers/album_provider.dart';
import '../providers/analysis_provider.dart';
import '../providers/database_provider.dart';
import '../providers/exif_provider.dart';
import '../providers/photo_provider.dart';
import '../services/database/app_database.dart';
import '../services/palette_service.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';
import 'color_card.dart';
import 'harmony_card.dart';
import 'histogram_painter.dart';
import 'tone_info_card.dart';
import 'tone_guide_card.dart';
import 'sharpness_guide_card.dart';
import '../providers/sharpness_provider.dart';

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

  /// 强制收起（取色模式时为 true）：保留工具行可见，但禁止展开 TabBarView
  /// 避免 TabBarView 与取色放大镜/pin 标记重叠争夺空间
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

class _DetailBottomPanelState extends ConsumerState<DetailBottomPanel>
    with TickerProviderStateMixin {
  bool _expanded = false;
  HistogramMode _histMode = HistogramMode.rgb;
  // 自管 TabController：DefaultTabController 会随展开/收起被卸载重建，
  // 导致每次展开回到"信息"tab。hoist 后 tab 索引跨展开/收起保留。
  late final TabController _tabController =
      TabController(length: 6, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 实际是否展开（forceCollapsed 时强制 false）
  bool get _effectiveExpanded => _expanded && !widget.forceCollapsed;

  void _toggleExpand() {
    if (widget.forceCollapsed) return; // 取色模式禁止展开
    setState(() => _expanded = !_expanded);
    widget.onExpandChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: const BoxDecoration(
          color: DetailColors.panelSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: DetailColors.divider, width: 0.5),
          ),
        ),
        constraints: BoxConstraints(
          maxHeight: _effectiveExpanded ? 380 : 72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 常驻工具行（始终可见，取色模式也保留以供退出）
            _buildToolRow(),
            // 展开内容（取色模式 forceCollapsed 时不显示）
            if (_effectiveExpanded)
              SizedBox(
                height: 308,
                child: Column(
                  children: [
                    _buildTabBar(),
                    Expanded(child: _buildTabBarView()),
                  ],
                ),
              ),
          ],
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
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
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
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  // ============ TabBar ============

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: AppColors.darkAccent,
      unselectedLabelColor: DetailColors.textSecondary,
      indicatorColor: AppColors.darkAccent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      tabs: const [
        Tab(text: '信息'),
        Tab(text: '直方图'),
        Tab(text: '色卡'),
        Tab(text: '影调'),
        Tab(text: '和谐'),
        Tab(text: '取色'),
      ],
    );
  }

  Widget _buildTabBarView() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildInfoTab(),
        _buildHistogramTab(),
        _buildPaletteTab(),
        _buildToneTab(),
        _buildHarmonyTab(),
        _buildColorPinTab(),
      ],
    );
  }

  // ============ 信息 Tab（新增：EXIF + 文件信息 + 所属相册）============

  Widget _buildInfoTab() {
    final photoAsync = ref.watch(photoByIdProvider(widget.photoId));
    final exifAsync = ref.watch(exifInfoProvider(widget.photoId));
    final albumsAsync = ref.watch(photoAlbumsProvider(widget.photoId));

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      children: [
        // 拍摄参数（EXIF）
        exifAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (exif) => _ExifSection(
            photoId: widget.photoId,
            exif: exif,
            // 同时 invalidate photoByIdProvider：exifInfoProvider 依赖它，
            // 而 photoByIdProvider 是 FutureProvider（非 stream）会缓存旧 Photo，
            // 不 invalidate 它的话拿到的仍是 exifJson=null 的旧对象
            onReread: () {
              ref.invalidate(photoByIdProvider(widget.photoId));
              ref.invalidate(exifInfoProvider(widget.photoId));
            },
          ),
        ),
        const SizedBox(height: 10),
        // 文件信息
        photoAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => _buildErrorText('文件信息加载失败'),
          data: (photo) =>
              photo == null ? const SizedBox.shrink() : _FileInfoSection(photo: photo),
        ),
        const SizedBox(height: 10),
        // 所属相册（v2.1：照片不再有标签，标签是相册的子系统）
        albumsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => _buildErrorText('相册加载失败'),
          data: (albums) => _AlbumsSection(
            photoId: widget.photoId,
            albums: albums,
          ),
        ),
      ],
    );
  }

  // ============ 直方图 Tab ============

  Widget _buildHistogramTab() {
    final histAsync = ref.watch(histogramProvider(widget.photoId));
    // 色相模式时联动标注取色点（灰点 r==g==b → 无色相，过滤掉）
    final pinHues = _histMode == HistogramMode.hue
        ? ref.watch(colorPinsProvider(widget.photoId)).maybeWhen(
              data: (pins) => pins
                  .map((p) => rgbToHue(p.r, p.g, p.b))
                  .where((h) => h >= 0)
                  .toList(),
              orElse: () => const <int>[],
            )
        : const <int>[];
    return histAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorText('计算失败: $e'),
      data: (hist) {
        // 影调分析复用直方图亮度数据，与直方图共享缓存生命周期
        final toneAsync = ref.watch(toneProvider(widget.photoId));
        // v3.0：肤色分析（BlazeFace ROI）独立异步，不阻塞直方图渲染
        final skinAsync = ref.watch(skinProvider(widget.photoId));
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _buildModeSelector(),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: CustomPaint(
                  painter: HistogramPainter(
                    data: hist,
                    mode: _histMode,
                    colorPinHues: _histMode == HistogramMode.hue
                        ? pinHues
                        : null,
                  ),
                  child: Container(),
                ),
              ),
              // v3.0: 信息熵 + RMS 对比度 + 肤色 → 调色指引
              // 嵌入直方图下方，复用同一缓存（不重新读图）
              toneAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (tone) => ToneGuideCard(
                  tone: tone,
                  showSkin: true,
                  skin: skinAsync.maybeWhen(
                    data: (s) => s,
                    orElse: () => null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 直方图模式选择器（分段按钮 + 更多下拉菜单）
  Widget _buildModeSelector() {
    const accent = AppColors.darkAccent;
    final isBW = widget.isBlackWhite;

    final mainModes = [
      (HistogramMode.rgb, 'RGB', Icons.palette_outlined),
      (HistogramMode.luminance, '亮度', Icons.tonality),
      (HistogramMode.hue, '色相', Icons.color_lens_outlined),
    ];

    final moreModes = [
      (HistogramMode.r, 'R 通道'),
      (HistogramMode.g, 'G 通道'),
      (HistogramMode.b, 'B 通道'),
      (HistogramMode.rgbLum, 'RGB+亮度'),
    ];

    final isMainMode = mainModes.any((m) => m.$1 == _histMode);

    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: DetailColors.controlSurface,
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
                            ? accent.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(m.$3,
                              size: 14,
                              color: selected
                                  ? accent
                                  : DetailColors.textMuted),
                          const SizedBox(width: 4),
                          Text(m.$2,
                              style: TextStyle(
                                fontSize: 11,
                                color: selected
                                    ? accent
                                    : DetailColors.textMuted,
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
        if (!isBW)
          PopupMenuButton<HistogramMode>(
            icon: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: !isMainMode
                    ? accent.withValues(alpha: 0.2)
                    : DetailColors.controlSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.more_horiz,
                      size: 14,
                      color: !isMainMode
                          ? accent
                          : DetailColors.textMuted),
                  const SizedBox(width: 2),
                  Text(
                    !isMainMode
                        ? moreModes.firstWhere((m) => m.$1 == _histMode).$2
                        : '更多',
                    style: TextStyle(
                      fontSize: 11,
                      color: !isMainMode
                          ? accent
                          : DetailColors.textMuted,
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
                            const Icon(Icons.check, size: 16, color: accent)
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

  // ============ 色卡 / 影调 / 和谐 Tab ============

  Widget _buildPaletteTab() => ColorCard(photoId: widget.photoId);

  Widget _buildToneTab() {
    final toneAsync = ref.watch(toneProvider(widget.photoId));
    // v3.0：肤色分析独立异步，ToneGuideCard 按需展示
    final skinAsync = ref.watch(skinProvider(widget.photoId));
    // v3.1：「对焦」工具开启时计算锐度读数（替代原发光蒙层）
    final sharpAsync = widget.showFocusPeaking
        ? ref.watch(sharpnessProvider(widget.photoId))
        : null;
    return toneAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorText('影调分析失败: $e'),
      data: (tone) => SingleChildScrollView(
        // 嵌套滚动容器：ToneInfoCard（明度分区 + 统计指标）+ 调色指引卡片
        // ToneInfoCard 自身不再包含 SingleChildScrollView，统一由本层滚动
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ToneInfoCard(tone: tone),
            // v3.0: 影调调色指引（信息熵 + RMS + 肤色 4 维度）
            // 单独 horizontal padding（与 ToneInfoCard 的 12px 对齐）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ToneGuideCard(
                tone: tone,
                showSkin: true,
                skin: skinAsync.maybeWhen(
                  data: (s) => s,
                  orElse: () => null,
                ),
              ),
            ),
            // v3.1: 「对焦」工具开启时显示合焦读数卡片（数据读数，无蒙层）
            if (sharpAsync != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: sharpAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (map) =>
                      SharpnessGuideCard(map: map, photoAspectRatio: 1.5),
                ),
              ),
          ],
        ),
      ),
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
      error: (e, _) => _buildErrorText('色卡分析失败: $e'),
      data: (palette) => HarmonyCard(palette: palette),
    );
  }

  // ============ 取色点 Tab ============

  Widget _buildColorPinTab() {
    final pinsAsync = ref.watch(colorPinsProvider(widget.photoId));
    // v3.1：当前手动校准选中的 pin（高亮 + 提供切换）
    final manualSel = ref.watch(manualSkinSelectionProvider);
    final manualSelectedId = <String>{};
    if (manualSel != null && manualSel.photoId == widget.photoId) {
      // 找到与选中 RGB 匹配的 pin（手动选择基于 RGB，pin 表无独立选中态）
      manualSelectedId.add(
          '${manualSel.rgb[0].round()},${manualSel.rgb[1].round()},${manualSel.rgb[2].round()}');
    }
    return pinsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorText('取色数据加载失败: $e'),
      data: (pins) {
        if (pins.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.colorize,
                    size: 32, color: AppColors.darkAccentDim),
                const SizedBox(height: 8),
                const Text('还没有取色点',
                    style: TextStyle(
                        color: DetailColors.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('在工具栏开启取色模式后长按图片',
                    style: TextStyle(
                        color: DetailColors.textMuted, fontSize: 10)),
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
            final isManualSelected =
                manualSelectedId.contains('$pin.r,$pin.g,$pin.b');
            return _ColorPinTile(
              pin: pin,
              color: color,
              isManualSelected: isManualSelected,
              onCalibrate: () {
                // v3.1：把该 pin 作为肤色校准基准
                ref
                    .read(manualSkinSelectionProvider.notifier)
                    .select(widget.photoId, pin.r, pin.g, pin.b);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已用作肤色校准，查看影调 Tab 的肤色指引'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              onClearCalibration: () => ref
                  .read(manualSkinSelectionProvider.notifier)
                  .clear(),
              onDelete: () {
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
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.red),
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

  Widget _buildErrorText(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message,
            style: const TextStyle(
                color: DetailColors.textMuted, fontSize: 12),
            textAlign: TextAlign.center),
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
    const accent = AppColors.darkAccent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: isActive ? accent : DetailColors.textSecondary),
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

// ============ 信息 Tab 子组件 ============

/// 拍摄参数区（EXIF）
class _ExifSection extends ConsumerStatefulWidget {
  final String photoId;
  final ExifInfo? exif;
  final VoidCallback onReread;

  const _ExifSection({
    required this.photoId,
    required this.exif,
    required this.onReread,
  });

  @override
  ConsumerState<_ExifSection> createState() => _ExifSectionState();
}

class _ExifSectionState extends ConsumerState<_ExifSection> {
  bool _reading = false;

  Future<void> _reread() async {
    setState(() => _reading = true);
    final importService = await ref.read(importServiceProvider.future);
    final ok = await importService.readExifForExistingPhoto(widget.photoId);
    if (mounted) {
      setState(() => _reading = false);
      widget.onReread();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '已读取拍摄参数' : '本照片无 EXIF 拍摄参数'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final exif = widget.exif;

    if (exif == null || exif.isEmpty) {
      // 无 EXIF：显示占位 + 重新读取按钮（历史照片补全）
      return _InfoCard(
        icon: Icons.camera_outlined,
        title: '拍摄参数',
        child: Row(
          children: [
            const Expanded(
              child: Text('本照片无拍摄参数',
                  style: TextStyle(
                      color: DetailColors.textMuted, fontSize: 12)),
            ),
            TextButton.icon(
              onPressed: _reading ? null : _reread,
              icon: _reading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 16),
              label: const Text('重新读取', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.darkAccent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      );
    }

    return _InfoCard(
      icon: Icons.camera_outlined,
      title: '拍摄参数',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：相机 + 镜头
          if (exif.cameraDisplay != null || exif.lensModel != null)
            _InfoLine(children: [
              if (exif.cameraDisplay != null)
                _InfoChip(label: exif.cameraDisplay!),
              if (exif.lensModel != null)
                _InfoChip(label: exif.lensModel!),
            ]),
          if (exif.exposureTriple.isNotEmpty) ...[
            const SizedBox(height: 4),
            _InfoLine(children: [
              Text(exif.exposureTriple,
                  style: const TextStyle(
                      color: DetailColors.textPrimary,
                      fontSize: 13,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5)),
            ]),
          ],
          if (exif.takenAt != null) ...[
            const SizedBox(height: 4),
            _InfoLine(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 12, color: DetailColors.textMuted),
              const SizedBox(width: 4),
              Text(_formatDate(exif.takenAt!),
                  style: const TextStyle(
                      color: DetailColors.textSecondary, fontSize: 11)),
            ]),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

/// 文件信息区
class _FileInfoSection extends StatelessWidget {
  final Photo photo;

  const _FileInfoSection({required this.photo});

  @override
  Widget build(BuildContext context) {
    final sizeMb = (photo.fileSize / 1024 / 1024).toStringAsFixed(1);
    return _InfoCard(
      icon: Icons.description_outlined,
      title: '文件信息',
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          _InfoChip(label: '${photo.width}×${photo.height}'),
          _InfoChip(label: '$sizeMb MB'),
          _InfoChip(label: '导入于 ${_formatDate(photo.importedAt)}'),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }
}

/// 所属相册区（v2.1：照片不再有标签，标签是相册的子系统）
///
/// 列出该照片所在的所有相册，点击跳转相册详情；末尾「加入相册」ActionChip
/// 弹出相册选择器（支持新建）。
class _AlbumsSection extends ConsumerWidget {
  final String photoId;
  final List<Album> albums;

  const _AlbumsSection({required this.photoId, required this.albums});

  Future<void> _addToAlbum(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final allAlbums = await db.albumDao.getAllAlbums();
    if (!context.mounted) return;

    final controller = TextEditingController();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('加入相册',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建相册'),
                    onPressed: () async {
                      final name = await showDialog<String>(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: const Text('新建相册'),
                          content: TextField(
                            controller: controller,
                            autofocus: true,
                            decoration: const InputDecoration(
                                hintText: '相册名称',
                                border: OutlineInputBorder()),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(dctx),
                                child: const Text('取消')),
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(dctx, controller.text.trim()),
                                child: const Text('创建')),
                          ],
                        ),
                      );
                      if (name != null && name.isNotEmpty) {
                        final albumId = const Uuid().v4();
                        await db.albumDao.insertAlbum(
                          AlbumsCompanion.insert(id: albumId, name: name),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, albumId);
                      }
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (allAlbums.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('没有相册，请点击右上角新建'),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: allAlbums.length,
                  itemBuilder: (_, i) {
                    final album = allAlbums[i];
                    return ListTile(
                      leading: const Icon(Icons.photo_album_outlined),
                      title: Text(album.name),
                      onTap: () => Navigator.pop(ctx, album.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );

    if (selected != null) {
      await db.albumDao.addPhotoToAlbum(selected, photoId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _InfoCard(
      icon: Icons.photo_album_outlined,
      title: '所属相册',
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          ...albums.map((album) => ActionChip(
                avatar:
                    const Icon(Icons.photo_album_outlined, size: 14),
                label: Text(album.name,
                    style: const TextStyle(fontSize: 11)),
                onPressed: () {
                  // 切换到相册详情页
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AlbumDetailPage(albumId: album.id),
                    ),
                  );
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )),
          if (albums.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('未加入任何相册',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 14),
            label: const Text('加入相册', style: TextStyle(fontSize: 11)),
            onPressed: () => _addToAlbum(context, ref),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

/// 信息卡片容器（统一标题 + 图标 + 内容样式）
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DetailColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.darkAccent),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                    color: DetailColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final List<Widget> children;

  const _InfoLine({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: children,
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DetailColors.chipSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: const TextStyle(
            color: DetailColors.textPrimary,
            fontSize: 11,
          )),
    );
  }
}

// ============ 取色点列表项（从 analysis_panel 迁移）============

class _ColorPinTile extends StatelessWidget {
  final ColorPin pin;
  final Color color;
  final bool isManualSelected;
  final VoidCallback onCalibrate;
  final VoidCallback onClearCalibration;
  final VoidCallback onDelete;

  const _ColorPinTile({
    required this.pin,
    required this.color,
    required this.isManualSelected,
    required this.onCalibrate,
    required this.onClearCalibration,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${pin.r.toRadixString(16).padLeft(2, '0')}${pin.g.toRadixString(16).padLeft(2, '0')}${pin.b.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();
    final hsv = HSVColor.fromColor(color);
    final hsvStr =
        'H:${hsv.hue.round()}° S:${(hsv.saturation * 100).round()}% V:${(hsv.value * 100).round()}%';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: isManualSelected
          ? AppColors.darkAccent.withValues(alpha: 0.12)
          : DetailColors.cardSurface,
      elevation: 0,
      shape: isManualSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color: AppColors.darkAccent.withValues(alpha: 0.5),
                  width: 1),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.darkAccent.withValues(alpha: 0.3)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(hex,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DetailColors.textPrimary)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: DetailColors.chipSurface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '(${pin.x}, ${pin.y})',
                          style: const TextStyle(
                              fontSize: 9, color: DetailColors.textMuted),
                        ),
                      ),
                      if (isManualSelected) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.darkAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('肤色基准',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.darkAccent,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('rgb(${pin.r}, ${pin.g}, ${pin.b})  $hsvStr',
                      style: const TextStyle(
                          fontSize: 10, color: DetailColors.textMuted)),
                ],
              ),
            ),
            // v3.1：用作肤色校准基准（点击切换）
            GestureDetector(
              onTap: isManualSelected ? onClearCalibration : onCalibrate,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isManualSelected
                      ? Icons.face_retouching_natural
                      : Icons.face_retouching_natural_outlined,
                  size: 18,
                  color: isManualSelected
                      ? AppColors.darkAccent
                      : DetailColors.textMuted,
                ),
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 16, color: DetailColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
