// photo_card.dart — 瀑布流缩略图卡片（带缩放动画 + 加载态）
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/database/app_database.dart';

/// 照片卡片（瀑布流用）
class PhotoCard extends StatefulWidget {
  final Photo photo;
  final VoidCallback? onTap;
  final VoidCallback? onTagTap; // 快速加标签（右下角图标）
  final VoidCallback? onLongPress; // 长按进入多选
  final bool selectMode; // 是否处于多选模式
  final bool isSelected; // 多选模式下是否被选中
  final double aspectRatio;

  const PhotoCard({
    super.key,
    required this.photo,
    this.onTap,
    this.onTagTap,
    this.onLongPress,
    this.selectMode = false,
    this.isSelected = false,
    this.aspectRatio = 0.75,
  });

  @override
  State<PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<PhotoCard>
    with AutomaticKeepAliveClientMixin {
  bool _isLoaded = false;
  bool _isPressed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final photo = widget.photo;

    final ratio = (photo.width > 0 && photo.height > 0)
        ? (photo.width / photo.height).clamp(0.5, 2.0)
        : widget.aspectRatio;

    // 缩略图可能被清缓存清空（thumbnailPath=''）或文件丢失，用原图兜底
    // 原图兜底时用 cacheWidth 限制解码尺寸，避免大图 OOM
    final thumbPath = photo.thumbnailPath;
    final thumbExists = thumbPath.isNotEmpty && File(thumbPath).existsSync();
    final imageFile = File(thumbExists ? thumbPath : photo.filePath);

    return GestureDetector(
      onTap: widget.selectMode ? widget.onTap : widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
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
                Image.file(
                  imageFile,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: thumbExists ? null : 360,
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
                // 右下角快速加标签按钮（渐进式披露：不进详情就能加标签）
                // 多选模式下隐藏标签按钮
                if (widget.onTagTap != null && !widget.selectMode)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: GestureDetector(
                      onTap: widget.onTagTap,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.local_offer_outlined,
                            color: Colors.white.withValues(alpha: 0.9), size: 16),
                      ),
                    ),
                  ),
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
                          : Colors.white.withValues(alpha: 0.7),
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
