// photo_card.dart — 瀑布流缩略图卡片（带缩放动画 + 加载态）
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/database/app_database.dart';
import '../theme/app_theme.dart';

/// 照片卡片（瀑布流用）
///
/// 性能要点（v3.2 复核优化）：
/// - 不用 `AutomaticKeepAliveClientMixin`：依赖 `cacheExtent` + 全局 `ImageCache`
///   已足够（保活 1000 个 card state 反而占内存，且 Image 解码结果由 ImageCache
///   统一缓存，card 重建不会重新解码）。
/// - 不在 build() 里调 `File.existsSync()`（同步阻塞 I/O，瀑布流每帧每卡一次，
///   1000 张图滚动累计几十 ms 抖动）。改为：`thumbnailPath` 非空即认为缩略图存在，
///   极小概率的"文件丢失"由 `Image.file` 的 `errorBuilder` 兜底。
class PhotoCard extends StatefulWidget {
  final Photo photo;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress; // 长按进入多选
  final bool selectMode; // 是否处于多选模式
  final bool isSelected; // 多选模式下是否被选中
  final double aspectRatio;

  const PhotoCard({
    super.key,
    required this.photo,
    this.onTap,
    this.onLongPress,
    this.selectMode = false,
    this.isSelected = false,
    this.aspectRatio = 0.75,
  });

  @override
  State<PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<PhotoCard> {
  bool _isLoaded = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;

    final ratio = (photo.width > 0 && photo.height > 0)
        ? (photo.width / photo.height).clamp(0.5, 2.0)
        : widget.aspectRatio;

    // 缩略图缺失（清缓存后 thumbnailPath=''）→ 用原图兜底，cacheWidth 限制解码尺寸防 OOM。
    // 不调 existsSync（同步 I/O 拖慢滚动）；文件意外丢失由下方 errorBuilder 兜底。
    final thumbPath = photo.thumbnailPath;
    final useThumb = thumbPath.isNotEmpty;
    final imageFile = File(useThumb ? thumbPath : photo.filePath);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: Radii.legacy12Border,
          child: AspectRatio(
            aspectRatio: ratio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 加载占位
                if (!_isLoaded)
                  Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                // 缩略图（或原图兜底；原图用 cacheWidth 限制解码尺寸防 OOM）
                // Hero 共享元素转场（仅非多选模式包裹）
                Hero(
                  tag: widget.selectMode
                      ? 'noop_${widget.photo.id}'
                      : 'photo_${widget.photo.id}',
                  child: Image.file(
                  imageFile,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: useThumb ? null : 360,
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                    if (frame != null && !_isLoaded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isLoaded = true);
                      });
                    }
                    return AnimatedOpacity(
                      opacity: _isLoaded || wasSynchronouslyLoaded ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                  errorBuilder: (context, error, stack) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.3)),
                        const SizedBox(height: 4),
                        Text(
                          photo.fileName,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  ),
                ), // Hero 闭合
                // 右下角快速加标签按钮已在 v2.1 移除（标签迁移到相册）
                // 多选模式：选中蒙层 + 左上角勾
                if (widget.selectMode) ...[
                  if (widget.isSelected)
                    Container(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Icon(
                      widget.isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 24,
                      color: widget.isSelected
                          ? Theme.of(context).colorScheme.primary
                          : AppColors.onPhotoText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
