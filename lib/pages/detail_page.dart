// detail_page.dart — 照片详情页（大图 + 分析面板 + 辅助工具）
//
// 暗房美学：全黑底让照片跳出来，毛玻璃工具栏
// v1.1.0: Clipping 警告 + 构图参考线 + 取色 + 对比度/曝光调节
// v2.1: 标签体系迁移到相册，本页不再有标签 UI（加入相册在底部面板「所属相册」/ ⋮ 菜单）
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/photo_provider.dart';
import '../providers/database_provider.dart';
import '../providers/analysis_provider.dart'
    show
        manualSkinSelectionProvider,
        detectedFaceProvider,
        colorCardExpandedProvider;
import '../providers/clipping_provider.dart';
import '../providers/sharpness_provider.dart';
import '../providers/exif_provider.dart' show colorPinsProvider;
import '../services/database/app_database.dart';
import 'compare_page.dart';
import '../widgets/detail_bottom_panel.dart';
import '../widgets/clipping_overlay.dart';
import '../widgets/face_bbox_overlay.dart';
import '../widgets/composition_overlay.dart';
import '../widgets/sharpness_overlay.dart';
import '../widgets/color_picker_loupe.dart';
import '../services/pixel_picker_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common/page_transitions.dart';
import '../utils/color_utils.dart';

class DetailPage extends ConsumerStatefulWidget {
  final String photoId;

  const DetailPage({super.key, required this.photoId});

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  final _imageKey = GlobalKey();
  // v6.1：取色 Stack 的 GlobalKey，用于把图片 global 坐标转成 Stack local 坐标
  // （统一取色放大镜/像素查找/pin 渲染的参考系，修复问题3 坐标错位）
  final _colorPickStackKey = GlobalKey();
  bool _isBlackWhite = false;
  bool _showClipping = false;
  bool _showFocusPeaking = false; // v3.0: 峰值对焦蒙层
  // v6.2：人脸检测框只在「色彩手法」卡片展开时显示（gotcha #62），
  // 由 colorCardExpandedProvider 控制（当前 photoId == state 时为 true）。
  // v6.1：顶部通知（替代底部 SnackBar，避免遮挡底部工具栏，问题2）
  String? _topNotice;
  bool _topNoticeVisible = false; // opacity 控制（widget 常驻，淡入/淡出才生效）
  Timer? _topNoticeTimer;
  CompositionMode _compositionMode = CompositionMode.none;
  double _contrast = 0; // -100 ~ +100
  double _exposure = 0; // -2.0 ~ +2.0 EV

  // 取色模式状态（取色标记直接从 DB 读取，不维护内存列表）
  bool _colorPickMode = false;
  // v3.2 卡顿修复：放大镜位置 + 当前取色结果改用 ValueNotifier，
  // 拖动时只重建放大镜/信息面板这两个小 widget，避免整棵 DetailPage（Image/
  // InteractiveViewer/pins）跟着 setState 重建导致的掉帧。
  final ValueNotifier<ColorPickResult?> _currentPickNotifier =
      ValueNotifier(null);
  final ValueNotifier<Offset?> _loupePositionNotifier = ValueNotifier(null);
  // v3.1: 会话级解码缓存，拖动期间纯内存取色（修原"每次 Isolate 解码全图"卡顿）
  // v6.0: 进一步降采样到长边 1200px + 进入详情页时后台预解码，
  // 用户点「取色」时零等待（_prefetchedSession 命中直接复用）。
  ColorPickerSession? _pickerSession;
  // 后台预解码的 session（initState 触发，用户点取色时优先取用）
  ColorPickerSession? _prefetchedSession;
  bool _pickerLoading = false;
  // v3.2: 取色节流提到 ~60fps（16ms），配合局部重建后成本可控，跟手感更好
  DateTime? _lastPickAt;
  // 缓存当前照片尺寸，session.pick 时无需再 await provider
  int _sessionImgW = 0;
  int _sessionImgH = 0;
  // 当前照片文件路径（initState 预解码 + Pin 菜单删除/校准复用）
  String? _photoFilePath;

  @override
  void dispose() {
    // v3.1: 释放取色会话 + 清空全局手动肤色校准（避免泄漏到下一张照片）
    _pickerSession?.dispose();
    _prefetchedSession?.dispose();
    _currentPickNotifier.dispose();
    _loupePositionNotifier.dispose();
    _topNoticeTimer?.cancel();
    // manualSkinSelectionProvider 是全局 Notifier，离开详情页必须清空
    // （ref 在 dispose 后不可用，需在 super.dispose 之前访问）
    ref.read(manualSkinSelectionProvider.notifier).clear();
    // v6.2：同步清空色彩卡片展开状态，避免下一张照片残留显示人脸框
    ref.read(colorCardExpandedProvider.notifier).setCollapsed(widget.photoId);
    super.dispose();
  }

  /// v6.0: 进入详情页时后台预解码取色 session（fire-and-forget）
  ///
  /// 用户大概率会点「取色」（这是详情页核心调色工具之一），提前在后台把全图
  /// 降采样解码好，点取色时直接复用 _prefetchedSession，零等待。
  /// 失败静默（取色按钮按下时再正常走 _enterColorPickMode 兜底）。
  void _prefetchPickerSession(Photo photo) {
    _photoFilePath = photo.filePath;
    _sessionImgW = photo.width;
    _sessionImgH = photo.height;
    ColorPickerSession.begin(photo.filePath, maxDim: 1200).then((session) {
      if (!mounted) {
        session.dispose();
        return;
      }
      // 已被取色模式消费或已退出则丢弃
      if (_pickerSession != null) {
        session.dispose();
        return;
      }
      _prefetchedSession = session;
    }).catchError((_) {
      // 预解码失败不打扰用户，按下取色再兜底
    });
  }

  /// v6.1：顶部浮出通知（替代底部 SnackBar）
  ///
  /// 问题2：底部 SnackBar 正好挡住底部工具行的操作按钮（黑白/构图/取色等）。
  /// 改在顶栏下方浮出通知，避开操作热区。3 秒后自动消失。
  ///
  /// v6.1 review 修复：原 AnimatedOpacity 配 `if(_topNotice!=null)` 条件渲染是死代码
  /// （widget 移除时来不及播淡出）。改为独立 `_topNoticeVisible` 控制 opacity，
  /// widget 常驻树，opacity 值变化才触发隐式动画（淡入/淡出都生效）。
  void _showTopNotice(String message, {Duration duration = const Duration(seconds: 3)}) {
    _topNoticeTimer?.cancel();
    setState(() {
      _topNotice = message;
      _topNoticeVisible = true;
    });
    _topNoticeTimer = Timer(duration, () {
      if (mounted) {
        // 先淡出（opacity→0），动画结束后再清空文本
        setState(() => _topNoticeVisible = false);
        _topNoticeTimer = Timer(const Duration(milliseconds: 220), () {
          if (mounted) setState(() => _topNotice = null);
        });
      }
    });
  }

  /// 处理取色手势
  ///
  /// v6.1 修复问题3：所有坐标统一用 localPosition（相对取色 Stack），
  /// 放大镜位置 / 像素查找 / pin 渲染都用同一个参考系，三者必然对齐。
  void _handleColorPickStart(LongPressStartDetails details) {
    if (!_colorPickMode || _pickerSession == null) return;
    _lastPickAt = null;
    _pickColorAtSync(details.localPosition);
  }

  void _handleColorPickUpdate(LongPressMoveUpdateDetails details) {
    if (!_colorPickMode || _pickerSession == null) return;
    // 节流：距上次取色 <16ms（~60fps）则只更新放大镜位置，跳过像素查找
    // 位置更新走 ValueNotifier，只重建放大镜（不触发整页 setState）
    final now = DateTime.now();
    final last = _lastPickAt;
    if (last != null && now.difference(last).inMilliseconds < 16) {
      _loupePositionNotifier.value = details.localPosition;
      return;
    }
    _lastPickAt = now;
    _pickColorAtSync(details.localPosition);
  }

  Future<void> _handleColorPickEnd(LongPressEndDetails details) async {
    if (!_colorPickMode) return;
    final pick = _currentPickNotifier.value;
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

    // v3.2: 清状态走 ValueNotifier（避免整页 setState）
    _currentPickNotifier.value = null;
    _loupePositionNotifier.value = null;
  }

  /// 同步取色（基于会话级缓存，<1ms，无 Isolate）
  ///
  /// v6.1：[localPos] 是相对【取色外层 Stack】的局部坐标（= 手指在 Stack 内位置）。
  /// 放大镜就用这个坐标定位 → 放大镜中心 = 手指位置。
  /// 像素查找把 localPos 映射到【图片在 Stack 内的实际矩形】→ 像素 = 手指下像素。
  void _pickColorAtSync(Offset localPos) {
    final session = _pickerSession;
    if (session == null) return;
    if (_sessionImgW == 0 || _sessionImgH == 0) return;

    // 图片在取色 Stack 内的实际矩形（local 坐标系，与 localPos 同参考系）
    final rect = _calculateImageRectInStack();
    if (rect == null) return;

    // localPos → 图片像素坐标
    final imageX =
        ((localPos.dx - rect.left) / rect.width * _sessionImgW).round();
    final imageY =
        ((localPos.dy - rect.top) / rect.height * _sessionImgH).round();

    if (imageX < 0 ||
        imageX >= _sessionImgW ||
        imageY < 0 ||
        imageY >= _sessionImgH) {
      return;
    }

    final result = session.pick(imageX, imageY);
    // 放大镜定位用 localPos（与取色 Stack 同参考系）→ 放大镜中心 = 手指位置
    _currentPickNotifier.value = result;
    _loupePositionNotifier.value = localPos;
  }

  /// 进入取色模式时一次性解码全图（Isolate 内），完成后启用 session.pick
  ///
  /// v6.0: 优先复用 initState 后台预解码的 _prefetchedSession（零等待）。
  /// 命中则直接启用；未命中（预解码未完成/失败）才显示 loading 等待解码。
  Future<void> _enterColorPickMode(Photo photo) async {
    _sessionImgW = photo.width;
    _sessionImgH = photo.height;

    // 命中预解码缓存 → 零等待启用
    final prefetched = _prefetchedSession;
    if (prefetched != null) {
      _prefetchedSession = null;
      _pickerSession = prefetched;
      return;
    }

    // 未命中 → 显示 loading，等待解码
    setState(() => _pickerLoading = true);
    try {
      final session =
          await ColorPickerSession.begin(photo.filePath, maxDim: 1200);
      if (!mounted) {
        session.dispose();
        return;
      }
      _pickerSession = session;
      setState(() => _pickerLoading = false);
    } catch (_) {
      if (mounted) {
        setState(() => _pickerLoading = false);
        _showTopNotice('取色模式初始化失败，请重试');
      }
    }
  }

  void _exitColorPickMode() {
    _pickerSession?.dispose();
    _pickerSession = null;
    _prefetchedSession?.dispose();
    _prefetchedSession = null;
    _pickerLoading = false;
    _lastPickAt = null;
    _currentPickNotifier.value = null;
    _loupePositionNotifier.value = null;
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
            style: TextButton.styleFrom(foregroundColor: StatusColors.error),
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
          // v6.0: 照片首次加载时后台预解码取色 session（用户点取色零等待）。
          // 用 _photoFilePath 做幂等 guard：同一张照片只触发一次（_prefetchPickerSession
          // 内部还会跳过 _pickerSession 已激活的情况）。
          if (_photoFilePath != photo.filePath &&
              _prefetchedSession == null &&
              _pickerSession == null) {
            _prefetchPickerSession(photo);
          }
          return SafeArea(
            child: Column(
              children: [
                // 顶部毛玻璃工具栏（返回 + 文件名 + 删除 + 更多菜单）
                _buildTopBar(photo.fileName),
                // 图片区域（含顶部通知浮层 + 取色放大镜等 overlays）
                Expanded(
                  flex: 2,
                  child: Stack(
                    children: [
                      _buildImageViewer(photo),
                      // v6.1：顶部通知浮层（常驻树，opacity 控制淡入淡出，避开操作按钮热区）
                      _buildTopNotice(),
                    ],
                  ),
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
      // M4 修复：num.clamp() 返回 num 不是 int。Flutter 的 cacheWidth 要求 int?，
      // 隐式赋值在部分编译器模式下会失败。显式 .toInt() 保证类型一致。
      cacheWidth: (MediaQuery.of(context).size.width * 3)
          .round()
          .clamp(1, 4096)
          .toInt(),
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

    // Hero 共享元素转场（从瀑布流缩略图放大）
    imageWithFilters = Hero(
      tag: 'photo_${widget.photoId}',
      child: imageWithFilters,
    );

    // 像素物理属性蒙层（clipping / sharpness / face bbox）必须放在 InteractiveViewer 内部，
    // 与 Image 共享缩放/平移变换，否则放大检查溢出/合焦时斑点会错位（gotcha #45）
    final clippingResult = clippingAsync?.asData?.value;
    final sharpnessAsync = _showFocusPeaking
        ? ref.watch(sharpnessProvider(widget.photoId))
        : null;
    final sharpnessMap = sharpnessAsync?.asData?.value;
    // v6.2：人脸检测框只在「色彩手法」卡片展开时显示（gotcha #62）。
    // watch colorCardExpandedProvider 建立依赖：卡片折叠/展开时本帧重建。
    final showFaceBox =
        ref.watch(colorCardExpandedProvider) == widget.photoId;
    final detectedFaceAsync = showFaceBox
        ? ref.watch(detectedFaceProvider(widget.photoId))
        : null;
    final detection = detectedFaceAsync?.asData?.value;
    final detectedFace = detection?.face;
    // 显示尺寸（EXIF 旋转后）—— 不能用 photo.width/height（存储尺寸未旋转），
    // 否则竖拍照片 overlay letterbox 算错、bbox 错位
    final displayW = detection?.displayWidth ?? photo.width;
    final displayH = detection?.displayHeight ?? photo.height;

    final imageStackChildren = <Widget>[
      Center(child: imageWithFilters),
      if (_showClipping && clippingResult != null)
        IgnorePointer(child: ClippingOverlay(result: clippingResult)),
      if (_showFocusPeaking && sharpnessMap != null)
        IgnorePointer(child: SharpnessOverlay(map: sharpnessMap)),
      // v6.2：取色模式/构图模式/卡片折叠时隐藏人脸框（避免视觉冲突/噪音）
      if (showFaceBox &&
          !_colorPickMode &&
          detectedFace != null &&
          _compositionMode == CompositionMode.none)
        FaceBBoxOverlay(
          face: detectedFace,
          imageWidth: displayW,
          imageHeight: displayH,
        ),
    ];

    // 取色点标记也放在 InteractiveViewer 内部（共享变换，位置始终正确）
    // 注：仅在非取色模式分支由本 InteractiveViewer 渲染；
    // 取色模式分支单独构建一个带 pins 的 InteractiveViewer（见下方 if 块）。
    if (!_colorPickMode) {
      // 常规模式：单一 InteractiveViewer 包 Image + clipping + sharpness
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
          // 构图参考线（v6.0：基于图片实际显示区域，letterbox 补偿，不溢出图片）
          if (_compositionMode != CompositionMode.none)
            IgnorePointer(
              child: CompositionOverlay(
                mode: _compositionMode,
                imageWidth: photo.width,
                imageHeight: photo.height,
              ),
            ),
        ],
      );
    }

    // 取色模式：v6.1 重构坐标系，统一用 Stack-local 坐标（修复问题3 错位）：
    // - InteractiveViewer 锁定 scale=1（取色无需缩放，坐标固定不漂移）
    // - pins 放外层 Stack（与放大镜/localPosition 同参考系）
    // - 放大镜位置 = localPosition → 中心对准手指
    // - 像素查找 = localPosition → 图片像素（手指下像素）
    // 三者必然对齐。
    final pinsAsync = ref.watch(colorPinsProvider(widget.photoId));
    return GestureDetector(
      onLongPressStart: _handleColorPickStart,
      onLongPressMoveUpdate: _handleColorPickUpdate,
      onLongPressEnd: _handleColorPickEnd,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        key: _colorPickStackKey,
        children: [
          // InteractiveViewer 锁定（取色期间禁止缩放/平移，保证坐标固定）
          InteractiveViewer(
            minScale: 1.0,
            maxScale: 1.0,
            panEnabled: false,
            scaleEnabled: false,
            child: Stack(
              alignment: Alignment.center,
              // 复用 imageStackChildren（含 Image + clipping + sharpness）
              children: imageStackChildren,
            ),
          ),
          // 构图参考线（v6.0：基于图片实际显示区域，letterbox 补偿）
          if (_compositionMode != CompositionMode.none)
            IgnorePointer(
              child: CompositionOverlay(
                mode: _compositionMode,
                imageWidth: photo.width,
                imageHeight: photo.height,
              ),
            ),
          // 取色点标记（Stack-local 坐标，与放大镜/localPosition 同参考系）
          pinsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (pins) => _buildPinMarkers(pins, photo),
          ),
          // v3.1: 取色会话解码中（首次进入取色模式的一次性解码）
          if (_pickerLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: AppColors.overlayScrim,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          // 放大镜（不随缩放，始终跟随手指；position = localPosition，Stack-local）
          // v3.2: 嵌套两层 ValueListenableBuilder，任一信号变化都重建放大镜，
          // 但仍只重建这一小块（Image/InteractiveViewer/pins 不受影响）。
          ValueListenableBuilder<ColorPickResult?>(
            valueListenable: _currentPickNotifier,
            builder: (context, pick, _) =>
                ValueListenableBuilder<Offset?>(
              valueListenable: _loupePositionNotifier,
              builder: (context, pos, _) {
                if (pos == null || pick == null) return const SizedBox.shrink();
                return ColorPickerLoupe(result: pick, position: pos);
              },
            ),
          ),
          // 像素信息面板
          ValueListenableBuilder<ColorPickResult?>(
            valueListenable: _currentPickNotifier,
            builder: (context, pick, _) {
              if (pick == null) return const SizedBox.shrink();
              return Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: PixelInfoPanel(pixel: pick.pixel),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// v6.1：顶部通知浮层（替代底部 SnackBar，问题2）
  ///
  /// 浮在顶栏下方，避开底部工具行的操作按钮。带淡入淡出动画 + 自动消失。
  /// v6.1 review 修复：widget 常驻树，用 `_topNoticeVisible` 切 opacity 触发动画
  /// （原 `if(_topNotice!=null)` 条件渲染导致淡出来不及播）。
  Widget _buildTopNotice() {
    // 无内容时不占空间（保留 widget 以便淡出动画，但视觉不可见）
    final hasContent = _topNotice != null;
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _topNoticeVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            // 无内容时缩小到 0 高度，避免占位阻挡
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: hasContent ? null : 0,
              child: hasContent
                  ? Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: Radii.xlBorder,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.overlayScrim,
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 16, color: AppColors.bgBase),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _topNotice ?? '',
                              style: AppTypography.caption.copyWith(color: AppColors.bgBase, fontWeight: FontWeight.w600,),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建取色点标记列表（Stack-local 坐标）
  ///
  /// pin 存的是【原图像素坐标】，渲染时映射到【图片在取色 Stack 内的实际矩形】
  /// （Stack-local，与放大镜/localPosition 同参考系）。
  ///
  /// v6.0：pin 可点击 → 弹出菜单（设为肤色基准 / 删除）。当前选为肤色基准的 pin
  /// 用 accent 描边高亮（与 [manualSkinSelectionProvider] 联动）。
  ///
  /// v6.1：改用 _calculateImageRectInStack（Stack-local），与放大镜/像素查找
  /// 同参考系 → pin 落点 = 取色时的放大镜中心（修复问题3 三者错位）。
  Widget _buildPinMarkers(List<ColorPin> pins, Photo photo) {
    final rect = _calculateImageRectInStack();
    if (rect == null) return const SizedBox.shrink();

    final manual = ref.read(manualSkinSelectionProvider);
    final isCurrentSkin = manual != null && manual.photoId == widget.photoId;

    return Stack(
      children: pins.map((pin) {
        // pin 原图像素坐标 → Stack-local 坐标（图片矩形内）
        final px = rect.left + pin.x / photo.width * rect.width;
        final py = rect.top + pin.y / photo.height * rect.height;
        // 命中当前肤色基准（RGB 三通道一致）→ accent 描边高亮
        // isCurrentSkin 为 true 时 manual 必非空（类型提升），无需 `!`
        final selected = isCurrentSkin &&
            (manual.rgb[0] - pin.r).abs() < 1 &&
            (manual.rgb[1] - pin.g).abs() < 1 &&
            (manual.rgb[2] - pin.b).abs() < 1;
        return ColorPinMarker(
          r: pin.r,
          g: pin.g,
          b: pin.b,
          position: Offset(px, py),
          selected: selected,
          onTap: () => _showPinMenu(pin, photo),
        );
      }).toList(),
    );
  }

  /// 取色点菜单：色值预览 / 设为肤色基准 / 删除（v6.0 问题4）
  void _showPinMenu(ColorPin pin, Photo photo) {
    final color = Color.fromARGB(0xFF, pin.r, pin.g, pin.b);
    final hsl = rgbToHsl(pin.r, pin.g, pin.b);
    final hue = hsl.h.round();
    final sat = hsl.s.round();
    final lum = hsl.l.round();
    final hex = argbToHex(0xFF000000 | (pin.r << 16) | (pin.g << 8) | pin.b);
    final manual = ref.read(manualSkinSelectionProvider);
    final isCurrentSkin = manual != null &&
        manual.photoId == widget.photoId &&
        (manual.rgb[0] - pin.r).abs() < 1 &&
        (manual.rgb[1] - pin.g).abs() < 1 &&
        (manual.rgb[2] - pin.b).abs() < 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: DetailColors.panelSurface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: Radii.mdBorder,
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hex,
                            style: AppTypography.label.copyWith(color: DetailColors.textPrimary, fontWeight: FontWeight.w600,
                                fontFamily: AppTypography.monoFontFamily)),
                        const SizedBox(height: 2),
                        Text('HSL $hue° / $sat% / $lum%',
                            style: AppTypography.caption.copyWith(color: DetailColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: DetailColors.divider),
            ListTile(
              leading: Icon(
                isCurrentSkin
                    ? Icons.check_circle
                    : Icons.face_retouching_natural,
                color: AppColors.accent,
              ),
              title: Text(isCurrentSkin ? '当前肤色基准' : '设为肤色基准',
                  style: const TextStyle(color: DetailColors.textPrimary)),
              subtitle: Text(
                  isCurrentSkin
                      ? '肤色卡片正以此色校准'
                      : '把此取色点作为肤色样本，重算 ΔH/饱和度等指标',
                  style: AppTypography.caption.copyWith(color: DetailColors.textMuted)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(manualSkinSelectionProvider.notifier).select(
                      widget.photoId,
                      pin.r,
                      pin.g,
                      pin.b,
                    );
                _showTopNotice('已设为肤色基准，肤色卡片已更新',
                    duration: const Duration(seconds: 2));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: DetailColors.warning),
              title: const Text('删除取色点',
                  style: TextStyle(color: DetailColors.warning)),
              onTap: () async {
                Navigator.pop(ctx);
                await ref
                    .read(appDatabaseProvider)
                    .colorPinDao
                    .deletePin(pin.id);
                // 若删的是当前肤色基准 → 清空校准（避免悬空引用）
                if (isCurrentSkin) {
                  ref.read(manualSkinSelectionProvider.notifier).clear();
                }
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
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

  /// 计算图片在取色 Stack 内的实际显示矩形（local 坐标系）
  ///
  /// v6.1 修复问题3：原 _calculateImageDisplayRect 用 global 坐标，但放大镜/pin 用
  /// local 坐标，两者参考系不一致 → 取色位置反直觉。现统一用 local 坐标：
  /// 把图片 RenderBox 的 global 位置，转换到取色 Stack（外层 GestureDetector 的 child）
  /// 的 local 坐标系，与 localPosition/localLoupe/pin 同参考系。
  ///
  /// 取色模式 InteractiveViewer 锁定 scale=1（见 _buildImageViewer 取色分支），
  /// rect 在取色期间固定不变，无需每次重算。
  Rect? _calculateImageRectInStack() {
    final imgCtx = _imageKey.currentContext;
    final stackCtx = _colorPickStackKey.currentContext;
    if (imgCtx == null || stackCtx == null) return null;
    final imgBox = imgCtx.findRenderObject() as RenderBox?;
    final stackBox = stackCtx.findRenderObject() as RenderBox?;
    if (imgBox == null || !imgBox.hasSize) return null;
    if (stackBox == null || !stackBox.hasSize) return null;
    // 图片左上角的 global 坐标 → 转 stack local
    final imgTopLeftGlobal = imgBox.localToGlobal(Offset.zero);
    final imgTopLeftInStack = stackBox.globalToLocal(imgTopLeftGlobal);
    return imgTopLeftInStack & imgBox.size;
  }

  /// 弹出底部列表选择第二张照片进行对比
  Future<void> _showComparePicker() async {
    final photos = await ref.read(allPhotosProvider.future);
    if (!mounted) return;
    // 排除当前照片，只列其余
    final candidates = photos.where((p) => p.id != widget.photoId).toList();
    if (candidates.isEmpty) {
      _showTopNotice('至少需要 2 张照片才能对比');
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text('选择对比的照片',
                    style: AppTypography.title.copyWith(fontWeight: FontWeight.w500)),
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
                        borderRadius: Radii.xsBorder,
                        // m8：thumbnailPath 空时原图兜底，加 cacheWidth 防列表滚动卡顿
                        child: Image.file(File(p.thumbnailPath.isEmpty
                            ? p.filePath
                            : p.thumbnailPath),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            cacheWidth: 96, // 48×2 retina，避免全分辨率原图进列表
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
        detailPageRoute(ComparePage(
          photoId1: widget.photoId,
          photoId2: selected,
        )),
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
                AppColors.overlayScrimStrong,
                Colors.transparent,
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
                      style: AppTypography.label.copyWith(color: DetailColors.textSecondary,),
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
      _showTopNotice('还没有相册，请先在相册 Tab 创建');
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择相册',
                  style: AppTypography.title.copyWith(fontWeight: FontWeight.w600)),
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
        _showTopNotice('已加入相册');
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
              // m7：固定宽度的 Text 可能被数值字符串撑溢（如 `-2.0EV`），
              // 改 ConstrainedBox + FittedBox 自适应缩放
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 44),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('${_contrast.round()}',
                      style: AppTypography.captionCompact.copyWith(color: DetailColors.textSecondary)),
                ),
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 44),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('${_exposure.toStringAsFixed(1)}EV',
                      style: AppTypography.captionCompact.copyWith(color: DetailColors.textSecondary)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
