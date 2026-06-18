// detail_page.dart — 照片详情页（大图 + 分析面板 + 辅助工具）
//
// 暗房美学：全黑底让照片跳出来，毛玻璃工具栏
// v1.1.0: Clipping 警告 + 构图参考线 + 取色 + 对比度/曝光调节
// v2.1: 标签体系迁移到相册，本页不再有标签 UI（加入相册在底部面板「所属相册」/ ⋮ 菜单）
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/photo_provider.dart';
import '../providers/database_provider.dart';
import '../providers/analysis_provider.dart' show manualSkinSelectionProvider;
import '../providers/clipping_provider.dart';
import '../providers/exif_provider.dart' show colorPinsProvider;
import '../services/database/app_database.dart';
import 'compare_page.dart';
import '../widgets/detail_bottom_panel.dart';
import '../widgets/clipping_overlay.dart';
import '../widgets/composition_overlay.dart';
import '../widgets/color_picker_loupe.dart';
import '../services/pixel_picker_service.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';

class DetailPage extends ConsumerStatefulWidget {
  final String photoId;

  const DetailPage({super.key, required this.photoId});

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  final _imageKey = GlobalKey();
  bool _isBlackWhite = false;
  bool _showClipping = false;
  bool _showFocusPeaking = false; // v3.0: 峰值对焦蒙层
  CompositionMode _compositionMode = CompositionMode.none;
  double _contrast = 0; // -100 ~ +100
  double _exposure = 0; // -2.0 ~ +2.0 EV

  // 取色模式状态（取色标记直接从 DB 读取，不维护内存列表）
  bool _colorPickMode = false;
  ColorPickResult? _currentPick;
  Offset? _loupePosition;
  // v3.1: 会话级解码缓存，拖动期间纯内存取色（修原"每次 Isolate 解码全图"卡顿）
  ColorPickerSession? _pickerSession;
  bool _pickerLoading = false;
  // v3.1: 取色节流（限制到 ~30fps），避免高频 move 事件堆叠 setState
  DateTime? _lastPickAt;
  // 缓存当前照片尺寸，session.pick 时无需再 await provider
  int _sessionImgW = 0;
  int _sessionImgH = 0;

  @override
  void dispose() {
    // v3.1: 释放取色会话 + 清空全局手动肤色校准（避免泄漏到下一张照片）
    _pickerSession?.dispose();
    // manualSkinSelectionProvider 是全局 Notifier，离开详情页必须清空
    // （ref 在 dispose 后不可用，需在 super.dispose 之前访问）
    ref.read(manualSkinSelectionProvider.notifier).clear();
    super.dispose();
  }

  /// 处理取色手势 — 使用 globalPosition 与 _calculateImageDisplayRect 统一坐标系
  void _handleColorPickStart(LongPressStartDetails details) {
    if (!_colorPickMode || _pickerSession == null) return;
    _lastPickAt = null;
    _pickColorAtSync(details.globalPosition, details.localPosition);
  }

  void _handleColorPickUpdate(LongPressMoveUpdateDetails details) {
    if (!_colorPickMode || _pickerSession == null) return;
    // 节流：距上次取色 <33ms 则只更新放大镜位置，跳过像素查找
    final now = DateTime.now();
    final last = _lastPickAt;
    if (last != null && now.difference(last).inMilliseconds < 33) {
      // 仍跟随手指移动放大镜位置（轻量 setState）
      setState(() {
        _loupePosition = details.localPosition;
      });
      return;
    }
    _lastPickAt = now;
    _pickColorAtSync(details.globalPosition, details.localPosition);
  }

  Future<void> _handleColorPickEnd(LongPressEndDetails details) async {
    if (!_colorPickMode) return;
    final pick = _currentPick;
    if (pick == null) return;
    // 持久化取色点到数据库
    final pinId = const Uuid().v4();
    final pin = ColorPinsCompanion.insert(
      id: pinId,
      photoId: widget.photoId,
      x: pick.pixel.x,
      y: pick.pixel.y,
      r: pick.pixel.r,
      g: pick.pixel.g,
      b: pick.pixel.b,
    );
    // 写入 DB（colorPinsProvider 的 watch 会自动刷新 UI）
    ref.read(appDatabaseProvider).colorPinDao.insertPin(pin);

    if (mounted) {
      setState(() {
        _currentPick = null;
        _loupePosition = null;
      });
    }
  }

  /// 同步取色（基于会话级缓存，<1ms，无 Isolate）
  void _pickColorAtSync(Offset globalPosition, Offset localLoupe) {
    final session = _pickerSession;
    if (session == null) return;
    if (_sessionImgW == 0 || _sessionImgH == 0) return;

    final rect = _calculateImageDisplayRect();
    if (rect == null) return;

    // 全局坐标 → 图片像素坐标
    final imageX =
        ((globalPosition.dx - rect.left) / rect.width * _sessionImgW).round();
    final imageY =
        ((globalPosition.dy - rect.top) / rect.height * _sessionImgH).round();

    if (imageX < 0 ||
        imageX >= _sessionImgW ||
        imageY < 0 ||
        imageY >= _sessionImgH) {
      return;
    }

    final result = session.pick(imageX, imageY);
    if (!mounted) return;
    setState(() {
      _currentPick = result;
      _loupePosition = localLoupe;
    });
  }

  /// 进入取色模式时一次性解码全图（Isolate 内），完成后启用 session.pick
  Future<void> _enterColorPickMode(Photo photo) async {
    setState(() {
      _pickerLoading = true;
      _sessionImgW = photo.width;
      _sessionImgH = photo.height;
    });
    try {
      final session = await ColorPickerSession.begin(photo.filePath);
      if (!mounted) {
        session.dispose();
        return;
      }
      _pickerSession = session;
      setState(() => _pickerLoading = false);
    } catch (_) {
      if (mounted) {
        setState(() => _pickerLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('取色模式初始化失败，请重试')),
        );
      }
    }
  }

  void _exitColorPickMode() {
    _pickerSession?.dispose();
    _pickerSession = null;
    _pickerLoading = false;
    _lastPickAt = null;
    _currentPick = null;
    _loupePosition = null;
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除照片'),
        content: const Text('确定要删除这张照片吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final importService =
                  await ref.read(importServiceProvider.future);
              await importService.deletePhoto(widget.photoId);
              ref.invalidate(photoByIdProvider(widget.photoId));
              if (mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoAsync = ref.watch(photoByIdProvider(widget.photoId));

    return Scaffold(
      backgroundColor: DetailColors.background,
      body: photoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('错误: $e',
              style: const TextStyle(color: DetailColors.textPrimary)),
        ),
        data: (photo) {
          if (photo == null) {
            return const Center(
                child: Text('照片不存在',
                    style: TextStyle(color: DetailColors.textPrimary)));
          }
          return SafeArea(
            child: Column(
              children: [
                // 顶部毛玻璃工具栏（返回 + 文件名 + 删除 + 更多菜单）
                _buildTopBar(photo.fileName),
                // 图片区域
                Expanded(
                  flex: 2,
                  child: _buildImageViewer(photo),
                ),
                // 统一底部面板（高频工具行 + 展开 TabBarView）
                // 始终保留工具行（取色模式需通过"取色"按钮退出，不能整块隐藏）
                DetailBottomPanel(
                  photoId: photo.id,
                  isBlackWhite: _isBlackWhite,
                  showClipping: _showClipping,
                  isColorPickMode: _colorPickMode,
                  hasComposition: _compositionMode != CompositionMode.none,
                  showFocusPeaking: _showFocusPeaking,
                  // 取色模式强制收起（避免 TabBarView 与取色放大镜/pin 标记重叠争夺空间）
                  forceCollapsed: _colorPickMode,
                  onBlackWhiteToggle: () =>
                      setState(() => _isBlackWhite = !_isBlackWhite),
                  onClippingToggle: () =>
                      setState(() => _showClipping = !_showClipping),
                  onCompositionToggle: () => setState(() {
                    const modes = CompositionMode.values;
                    final nextIndex =
                        (modes.indexOf(_compositionMode) + 1) % modes.length;
                    _compositionMode = modes[nextIndex];
                  }),
                  onFocusPeakingToggle: () =>
                      setState(() => _showFocusPeaking = !_showFocusPeaking),
                  onColorPickToggle: () {
                    // 关闭取色：释放会话；开启取色：异步解码全图（v3.1 修复卡顿）
                    if (_colorPickMode) {
                      _exitColorPickMode();
                      setState(() => _colorPickMode = false);
                    } else {
                      setState(() => _colorPickMode = true);
                      _enterColorPickMode(photo);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageViewer(Photo photo) {
    final filePath = photo.filePath;
    final clippingAsync = _showClipping
        ? ref.watch(clippingProvider(widget.photoId))
        : null;

    // 基础 Image（始终挂在 _imageKey 上，用于坐标计算）
    // 注：_imageKey 只挂这一处（gotcha #29），避免条件分支让两个 Image 同时引用同一 GlobalKey。
    final imageWidget = Image.file(
      key: _imageKey,
      File(filePath),
      fit: BoxFit.contain,
      cacheWidth:
          (MediaQuery.of(context).size.width * 3).toInt().clamp(1, 4096),
      errorBuilder: (_, error, ___) => const Center(
        child: Icon(Icons.broken_image,
            color: DetailColors.textSecondary, size: 64),
      ),
    );

    // 黑白滤镜 + 对比度/曝光（包在 Image 外，仍受 InteractiveViewer 变换）
    Widget imageWithFilters = imageWidget;
    if (_isBlackWhite) {
      imageWithFilters = ColorFiltered(
        colorFilter: ColorFilter.matrix(_buildAdjustmentMatrix()),
        child: imageWithFilters,
      );
    }

    // 像素物理属性蒙层（仅 clipping）必须放在 InteractiveViewer 内部，
    // 与 Image 共享缩放/平移变换，否则放大检查溢出时斑点会错位（review 漏洞）
    // 注：v3.1 起"对焦"工具改为影调面板数据读数，不再叠加发光蒙层
    // （SharpnessOverlay 已移除，锐度数据在影调 Tab 的 SharpnessGuideCard 展示）
    final imageStackChildren = <Widget>[
      Center(child: imageWithFilters),
      if (_showClipping && clippingAsync != null)
        clippingAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (result) => ClippingOverlay(result: result),
        ),
    ];

    // 取色点标记也放在 InteractiveViewer 内部（共享变换，位置始终正确）
    // 注：仅在非取色模式分支由本 InteractiveViewer 渲染；
    // 取色模式分支单独构建一个带 pins 的 InteractiveViewer（见下方 if 块）。
    if (!_colorPickMode) {
      // 常规模式：单一 InteractiveViewer 包 Image + clipping
      return Stack(
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Stack(
              alignment: Alignment.center,
              children: imageStackChildren,
            ),
          ),
          // 构图参考线：屏幕坐标系（三分线/黄金分割不随缩放），保持外层
          if (_compositionMode != CompositionMode.none)
            IgnorePointer(
              child: CompositionOverlay(mode: _compositionMode),
            ),
        ],
      );
    }

    // 取色模式：pins 标记和 Image 都放在 InteractiveViewer 内部的 Stack，
    // 共享 InteractiveViewer 的缩放/平移变换。手势 GestureDetector 放外层（globalPosition 取色）。
    final pinsAsync = ref.watch(colorPinsProvider(widget.photoId));
    return GestureDetector(
      onLongPressStart: _handleColorPickStart,
      onLongPressMoveUpdate: _handleColorPickUpdate,
      onLongPressEnd: _handleColorPickEnd,
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 复用 imageStackChildren（含 Image + clipping）
                ...imageStackChildren,
                // 取色点标记（局部坐标，与 Image 共享 InteractiveViewer 变换）
                pinsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (pins) => _buildPinMarkers(pins, photo),
                ),
              ],
            ),
          ),
          // 构图参考线：屏幕坐标系，保持外层
          if (_compositionMode != CompositionMode.none)
            IgnorePointer(
              child: CompositionOverlay(mode: _compositionMode),
            ),
          // v3.1: 取色会话解码中（首次进入取色模式的一次性解码）
          if (_pickerLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x88000000),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          // 放大镜（不随缩放，始终跟随手指）
          if (_currentPick != null && _loupePosition != null)
            ColorPickerLoupe(
              result: _currentPick!,
              position: _loupePosition!,
            ),
          // 像素信息面板
          if (_currentPick != null)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: PixelInfoPanel(pixel: _currentPick!.pixel),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建取色点标记列表（局部坐标，基于 Image 的 RenderBox size）
  /// pin 存的是像素坐标，渲染时按 photo.width/height 比例映射到 Image 显示区域
  Widget _buildPinMarkers(List<ColorPin> pins, Photo photo) {
    final ctx = _imageKey.currentContext;
    if (ctx == null) return const SizedBox.shrink();
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const SizedBox.shrink();

    // Image 在 InteractiveViewer 内部，RenderBox 局部原点 (0,0) 即图片左上
    // pin 按 photo 像素尺寸比例映射到 box.size
    return Stack(
      children: pins.map((pin) {
        final px = pin.x / photo.width * box.size.width;
        final py = pin.y / photo.height * box.size.height;
        return ColorPinMarker(
          r: pin.r,
          g: pin.g,
          b: pin.b,
          position: Offset(px, py),
        );
      }).toList(),
    );
  }

  /// 构建调整矩阵（灰度 + 对比度 + 曝光）
  List<double> _buildAdjustmentMatrix() {
    // 曝光系数：2^EV
    final exposureMul = _exposure == 0 ? 1.0 : math.pow(2.0, _exposure).toDouble();

    // 对比度系数
    final contrastValue = _contrast;
    final contrastFactor =
        (259 * (contrastValue + 255)) / (255 * (259 - contrastValue));

    // 灰度系数 × 曝光 × 对比度
    final r = rec709R * exposureMul * contrastFactor;
    final g = rec709G * exposureMul * contrastFactor;
    final b = rec709B * exposureMul * contrastFactor;
    // 正确公式：offset = 128 * (1 - contrastFactor) * exposureMul
    final offset = 128 * (1 - contrastFactor) * exposureMul;

    return [
      r, g, b, 0, offset,
      r, g, b, 0, offset,
      r, g, b, 0, offset,
      0, 0, 0, 1, 0,
    ];
  }

  /// 计算图片在 InteractiveViewer 中的实际显示区域
  /// 使用 GlobalKey 获取图片渲染框的真实尺寸和位置
  Rect? _calculateImageDisplayRect() {
    final ctx = _imageKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 弹出底部列表选择第二张照片进行对比
  Future<void> _showComparePicker() async {
    final photos = await ref.read(allPhotosProvider.future);
    if (!mounted) return;
    // 排除当前照片，只列其余
    final candidates = photos.where((p) => p.id != widget.photoId).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要 2 张照片才能对比')),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('选择对比的照片',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    final p = candidates[i];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(File(p.thumbnailPath.isEmpty
                            ? p.filePath
                            : p.thumbnailPath),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 48,
                              height: 48,
                              color: DetailColors.divider,
                              child: const Icon(Icons.image, size: 24),
                            )),
                      ),
                      title: Text(p.filePath.split(Platform.pathSeparator).last,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(ctx, p.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ComparePage(
            photoId1: widget.photoId,
            photoId2: selected,
          ),
        ),
      );
    }
  }

  /// 毛玻璃顶栏（BackdropFilter + 渐变遮罩）
  /// 返回 + 文件名 + 删除 + ⋮更多菜单（加入相册/照片对比）
  Widget _buildTopBar(String fileName) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.5),
                Colors.black.withValues(alpha: 0.0),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第一行：返回 + 文件名 + 删除 + 更多菜单
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: DetailColors.textPrimary),
                    tooltip: '返回',
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: DetailColors.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: DetailColors.textSecondary),
                    tooltip: '删除照片',
                    onPressed: _confirmDelete,
                  ),
                  // ⋮ 更多菜单：低频功能（加入相册 / 照片对比）
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: DetailColors.textSecondary),
                    tooltip: '更多',
                    color: DetailColors.panelSurface,
                    onSelected: (value) {
                      if (value == 'album') {
                        _showAddToAlbumPicker();
                      } else if (value == 'compare') {
                        _showComparePicker();
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'album',
                        height: 44,
                        child: Row(
                          children: [
                            Icon(Icons.photo_album_outlined,
                                color: DetailColors.textPrimary, size: 20),
                            SizedBox(width: 12),
                            Text('加入相册'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'compare',
                        height: 44,
                        child: Row(
                          children: [
                            Icon(Icons.compare_outlined,
                                color: DetailColors.textPrimary, size: 20),
                            SizedBox(width: 12),
                            Text('照片对比'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 第二行：对比度/曝光滑块（仅黑白模式，黑白激活后的参数调节）
              if (_isBlackWhite) _buildAdjustmentSliders(),
            ],
          ),
        ),
      ),
    );
  }



  /// 把当前照片加入相册（弹出相册列表选择）
  Future<void> _showAddToAlbumPicker() async {
    final db = ref.read(appDatabaseProvider);
    final albums = await db.albumDao.getAllAlbums();
    if (!mounted) return;
    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有相册，请先在相册 Tab 创建')),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择相册',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: albums.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.photo_album_outlined),
                  title: Text(albums[i].name),
                  onTap: () => Navigator.pop(ctx, albums[i].id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await db.albumDao.addPhotoToAlbum(selected, widget.photoId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入相册')),
        );
      }
    }
  }

  /// 对比度/曝光调节滑块（黑白激活时显示）
  Widget _buildAdjustmentSliders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.contrast, size: 14, color: DetailColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _contrast,
                    min: -100,
                    max: 100,
                    onChanged: (v) => setState(() => _contrast = v),
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('${_contrast.round()}',
                    style: const TextStyle(color: DetailColors.textSecondary, fontSize: 10)),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.exposure, size: 14, color: DetailColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _exposure,
                    min: -2,
                    max: 2,
                    divisions: 40,
                    onChanged: (v) => setState(() => _exposure = v),
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('${_exposure.toStringAsFixed(1)}EV',
                    style: const TextStyle(color: DetailColors.textSecondary, fontSize: 10)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
