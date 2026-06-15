// photo_card.dart — 瀑布流缩略图卡片（带缩放动画 + 加载态）
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/database/app_database.dart';

/// 照片卡片（瀑布流用）
class PhotoCard extends StatefulWidget {
  final Photo photo;
  final VoidCallback? onTap;
  final double aspectRatio;

  const PhotoCard({
    super.key,
    required this.photo,
    this.onTap,
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

    return GestureDetector(
      onTap: widget.onTap,
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
                // 缩略图
                Image.file(
                  File(photo.thumbnailPath),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
