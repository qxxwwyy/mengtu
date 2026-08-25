// face_bbox_overlay.dart — 人脸检测框可视化（v6.1 问题1）
//
// 在图片上绘制 ML Kit 检测到的主脸 bbox（归一化 0~1），让用户直观看到
// 「肤色识别落到脸部哪个区域」—— 解决「不知识别到哪 + 不信任检测结果」。
// 配合小标签「肤色 ROI」提示这是肤色采样区，建立用户安全感。
//
// 坐标：bbox 是归一化 0~1（相对原图），需按 BoxFit.contain 的 letterbox
// 映射到图片实际显示矩形（与 ClippingOverlay/CompositionOverlay 同款逻辑）。
import 'package:flutter/material.dart';
import '../services/face_service.dart' show DetectedFace;
import '../theme/app_theme.dart';
import '../utils/letterbox.dart';

/// 人脸检测框可视化蒙层
class FaceBBoxOverlay extends StatelessWidget {
  /// 检测到的主脸（归一化 bbox）；null 时不绘制
  final DetectedFace? face;

  /// 原图像素宽（算 letterbox 用）
  final int imageWidth;

  /// 原图像素高（算 letterbox 用）
  final int imageHeight;

  /// 是否高亮（肤色采样进行中时 accent 色，否则中性灰）
  final bool highlight;

  const FaceBBoxOverlay({
    super.key,
    required this.face,
    required this.imageWidth,
    required this.imageHeight,
    this.highlight = true,
  });

  @override
  Widget build(BuildContext context) {
    if (face == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _FaceBBoxPainter(
          face: face!,
          imageAspect: imageWidth / imageHeight,
          highlight: highlight,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// 按 BoxFit.contain 在 [size] 内计算图片实际显示矩形（与其它蒙层一致）

class _FaceBBoxPainter extends CustomPainter {
  final DetectedFace face;
  final double imageAspect;
  final bool highlight;

  _FaceBBoxPainter({
    required this.face,
    required this.imageAspect,
    required this.highlight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = imageRectInContainer(size, imageAspect);
    final color = highlight ? AppColors.accent : DetailColors.faceBoxNormal;

    // bbox 归一化 0~1 → 图片矩形内像素坐标
    final bbox = Rect.fromLTWH(
      rect.left + face.left * rect.width,
      rect.top + face.top * rect.height,
      face.width * rect.width,
      face.height * rect.height,
    );

    // 半透明填充（极淡，标识 ROI 区域）
    final fillPaint = Paint()..color = color.withValues(alpha: 0.08);
    canvas.drawRect(bbox, fillPaint);

    // 描边（虚线效果用角点 + 实线边框；这里用实线边框更清晰）
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(bbox, strokePaint);

    // 四角强化标记（像取景框，专业感）
    final cornerLen = (bbox.width * 0.12).clamp(8.0, 24.0);
    final cornerPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // 左上
    canvas.drawLine(bbox.topLeft, bbox.topLeft + Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(bbox.topLeft, bbox.topLeft + Offset(0, cornerLen), cornerPaint);
    // 右上
    canvas.drawLine(bbox.topRight, bbox.topRight + Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(bbox.topRight, bbox.topRight + Offset(0, cornerLen), cornerPaint);
    // 左下
    canvas.drawLine(bbox.bottomLeft, bbox.bottomLeft + Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(bbox.bottomLeft, bbox.bottomLeft + Offset(0, -cornerLen), cornerPaint);
    // 右下
    canvas.drawLine(bbox.bottomRight, bbox.bottomRight + Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(bbox.bottomRight, bbox.bottomRight + Offset(0, -cornerLen), cornerPaint);

    // 标签「肤色采样区」
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: '肤色采样区',
        style: AppTypography.captionCompact.copyWith(color: AppColors.bgBase, fontWeight: FontWeight.w600,),
      );
    tp.layout();
    final labelW = tp.width + 10;
    final labelH = tp.height + 4;
    final labelRect = Rect.fromLTWH(
      bbox.left,
      (bbox.top - labelH - 2).clamp(0, size.height - labelH),
      labelW,
      labelH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(3)),
      Paint()..color = AppColors.accent,
    );
    tp.paint(canvas, Offset(labelRect.left + 5, labelRect.top + 2));
  }

  @override
  bool shouldRepaint(covariant _FaceBBoxPainter old) =>
      old.face != face || old.highlight != highlight;
}
