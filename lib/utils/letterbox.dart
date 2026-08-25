// letterbox.dart — BoxFit.contain letterbox 几何统一计算
//
// `Image(fit: BoxFit.contain)` 在任意容器内是 letterboxed（上下/左右留黑），
// 蒙层（溢出/锐度/构图/人脸框）必须只在图片实际矩形内绘制，否则斑点/线条
// 会溢出到黑边区域（gotcha #52）。
// 此前该计算在 4 个蒙层文件里各复制一份 —— 现统一为单一实现。
import 'dart:ui';

/// 按 BoxFit.contain 在 [size] 内计算图片实际显示矩形（居中 letterbox）
///
/// [imageAspect] 图片宽高比（width / height）。返回图片在容器内的显示矩形。
Rect imageRectInContainer(Size size, double imageAspect) {
  final containerAspect = size.width / size.height;
  if (imageAspect > containerAspect) {
    // 图片更宽 → 以宽度为准，上下留白
    final drawHeight = size.width / imageAspect;
    final offsetY = (size.height - drawHeight) / 2;
    return Offset(0, offsetY) & Size(size.width, drawHeight);
  }
  // 图片更高 → 以高度为准，左右留白
  final drawWidth = size.height * imageAspect;
  final offsetX = (size.width - drawWidth) / 2;
  return Offset(offsetX, 0) & Size(drawWidth, size.height);
}
