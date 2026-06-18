// color_picker_loupe.dart — 取色放大镜组件
//
// 长按图片时显示的放大镜，中心十字准星 + 局部像素网格
import 'package:flutter/material.dart';
import '../services/pixel_picker_service.dart';

/// 取色放大镜
class ColorPickerLoupe extends StatelessWidget {
  final ColorPickResult result;
  final Offset position; // 放大镜中心位置（相对于父组件）

  const ColorPickerLoupe({
    super.key,
    required this.result,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    const loupeSize = 80.0;
    const cellSize = loupeSize / 11; // 11x11 网格

    return Positioned(
      left: position.dx - loupeSize / 2,
      top: position.dy - loupeSize - 20, // 在手指上方
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 放大镜圆圈
          Container(
            width: loupeSize,
            height: loupeSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ClipOval(
              child: CustomPaint(
                painter: _LoupePainter(
                  regionRgb: result.regionRgb,
                  cellSize: cellSize,
                ),
                size: const Size(loupeSize, loupeSize),
              ),
            ),
          ),
          // 颜色预览小块
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Color.fromARGB(
                0xFF,
                result.pixel.r,
                result.pixel.g,
                result.pixel.b,
              ),
              border: Border.all(color: Colors.white, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoupePainter extends CustomPainter {
  final List<List<int>> regionRgb;
  final double cellSize;

  _LoupePainter({required this.regionRgb, required this.cellSize});

  // v3.2 卡顿修复：复用单个 Paint，循环里只改 .color（原实现每帧每格
  // 新建 Paint，11×11=121 次 Paint 分配/frame）。Color 是 Paint 上的值字段，
  // 改它不影响正在绘制的其他画笔（绘制是同步的，paint 调用瞬间完成）。
  final Paint _cellPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (regionRgb.isEmpty) return;

    final half = regionRgb.length ~/ 2;
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // 绘制像素网格（复用 _cellPaint，只改 color）
    for (var y = 0; y < regionRgb.length; y++) {
      for (var x = 0; x < regionRgb[y].length; x++) {
        _cellPaint.color = Color(regionRgb[y][x]);
        final rect = Rect.fromLTWH(
          centerX + (x - half) * cellSize - cellSize / 2,
          centerY + (y - half) * cellSize - cellSize / 2,
          cellSize,
          cellSize,
        );
        canvas.drawRect(rect, _cellPaint);
      }
    }

    // 中心十字准星
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 水平线
    canvas.drawLine(
      Offset(centerX - 8, centerY),
      Offset(centerX + 8, centerY),
      crossPaint,
    );
    // 垂直线
    canvas.drawLine(
      Offset(centerX, centerY - 8),
      Offset(centerX, centerY + 8),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LoupePainter oldDelegate) {
    // v3.2: ColorPickerSession 复用同一个 regionRgb 缓冲（原地填充避免每帧
    // 121 次 List 分配），引用相等会误判为"未变化"。改为始终重绘：
    // painter 仅在 ColorPickerLoupe 被重建时创建（由 _currentPickNotifier
    // ValueListenableBuilder 驱动，频率 ≤ 取色节流 60fps），重绘成本可控。
    return true;
  }
}

/// 像素信息面板（底部浮出条）
class PixelInfoPanel extends StatelessWidget {
  final PixelInfo pixel;

  const PixelInfoPanel({super.key, required this.pixel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 颜色预览
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Color.fromARGB(0xFF, pixel.r, pixel.g, pixel.b),
              border: Border.all(color: Colors.white38),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          // 色值信息
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pixel.hex,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${pixel.rgbString}  L:${pixel.luminance}',
                style: const TextStyle(color: Colors.white60, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // 坐标
          Text(
            '(${pixel.x}, ${pixel.y})',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// 取色点标记（图片上的小圆点）
class ColorPinMarker extends StatelessWidget {
  final int r;
  final int g;
  final int b;
  final Offset position; // 归一化坐标 (0-1)
  final VoidCallback? onTap;

  const ColorPinMarker({
    super.key,
    required this.r,
    required this.g,
    required this.b,
    required this.position,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 8,
      top: position.dy - 8,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.fromARGB(0xFF, r, g, b),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
