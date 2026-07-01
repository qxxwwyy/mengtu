// color_picker_loupe.dart — 取色放大镜组件
//
// 长按图片时显示的放大镜：局部像素网格 + 中心十字准星 + 色值标签。
//
// v6.0 易用性优化（问题5）：
// - 放大镜从 80px → 130px（cell 11.8px，比原 7.2px 更清晰，看得清单格颜色）
// - 中心格 accent 描边高亮，明确「就取这一格」
// - 放大镜下方直接显示 HEX + HSV，所见即所得判断是否肤色（不用再找底部面板）
//
// 取色点标记 ColorPinMarker（问题4）：支持 onTap 弹出菜单 + selected 高亮
// （当前肤色基准用 accent 描边）。
import 'package:flutter/material.dart';
import '../services/pixel_picker_service.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';

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
    const loupeSize = 130.0;
    const gridSize = 11; // 与 ColorPickerSession 的 regionRgb 11×11 保持一致
    const cellSize = loupeSize / gridSize;
    final pixel = result.pixel;
    final color = Color.fromARGB(0xFF, pixel.r, pixel.g, pixel.b);
    final hsl = rgbToHsl(pixel.r, pixel.g, pixel.b);

    return Positioned(
      left: position.dx - loupeSize / 2,
      top: position.dy - loupeSize - 20, // 在手指上方
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 放大镜圆圈（像素网格）
          Container(
            width: loupeSize,
            height: loupeSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
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
          // v6.0：放大镜下方直接显示色值 + HSV（所见即所得判断肤色）
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: Colors.white, width: 1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  pixel.hex,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'H${hsl.h.round()}° S${hsl.s.round()}%',
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
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

    // v6.0：中心格 accent 描边高亮（明确「就取这一格」）
    final centerRect = Rect.fromLTWH(
      centerX - cellSize / 2,
      centerY - cellSize / 2,
      cellSize,
      cellSize,
    );
    final highlightPaint = Paint()
      ..color = AppColors.darkAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(centerRect, highlightPaint);

    // 中心十字准星
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 水平线
    canvas.drawLine(
      Offset(centerX - 10, centerY),
      Offset(centerX + 10, centerY),
      crossPaint,
    );
    // 垂直线
    canvas.drawLine(
      Offset(centerX, centerY - 10),
      Offset(centerX, centerY + 10),
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
///
/// v6.0（问题4）：
/// - [onTap] 弹出菜单（设为肤色基准 / 删除）
/// - [selected] 为 true 时用 accent 描边高亮（当前肤色基准）
///
/// v6.1：[position] 是【取色 Stack 的 local 坐标】（显示空间，非像素，也非
/// Image-box 局部）—— 与放大镜/localPosition 同参考系（修复问题3 三者错位）。
class ColorPinMarker extends StatelessWidget {
  final int r;
  final int g;
  final int b;
  final Offset position; // 相对取色 Stack 的局部坐标（显示空间）
  final VoidCallback? onTap;
  final bool selected;

  const ColorPinMarker({
    super.key,
    required this.r,
    required this.g,
    required this.b,
    required this.position,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 10,
      top: position.dy - 10,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.fromARGB(0xFF, r, g, b),
            border: Border.all(
              color: selected ? AppColors.darkAccent : Colors.white,
              width: selected ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 4,
              ),
              if (selected)
                BoxShadow(
                  color: AppColors.darkAccent.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: selected
              ? const Icon(Icons.face, size: 11, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
