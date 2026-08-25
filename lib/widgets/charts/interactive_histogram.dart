// interactive_histogram.dart — 可交互直方图（触摸读数 + 入场动画）
//
// 图表规范（chart_animations.dart）：图表必须有入场动画 → ChartEnterBuilder
// 驱动 HistogramPainter.progress 从底部生长。
//
// 交互（暗房体验核心）：手指按住直方图任意位置 → 竖直游标线 + 浮层读数
// （亮度值 / 五区名称 / 该区间占比 / RGB 三通道分量），松手消失。
// 用 Listener（raw pointer）而非 GestureDetector：直方图常在 ListView 中，
// drag 手势会与滚动竞技场冲突，raw pointer 不参与竞技场、按下即读数。
//
// 读数计算抽成顶层纯函数（CustomPaint 不产生 Element，widget test 有盲区，
// gotcha #65 —— 纯函数可独立 unit test）。
import 'package:flutter/material.dart';

import '../../models/tone_result.dart';
import '../../theme/app_theme.dart';
import '../histogram_painter.dart';
import 'chart_animations.dart';

/// 直方图触摸读数（纯数据模型）
class HistogramProbe {
  /// 亮度 bin（0~255）
  final int bin;

  /// 五区名称（黑色/阴影/中间调/高光/白色，分界 51/102/153/204 与影调分析一致）
  final String zoneName;

  /// 该 bin 亮度像素占总像素比例（0~1）
  final double lumRatio;

  /// 该 bin R/G/B 通道计数占各自通道总量的比例（0~1，null = 通道无数据）
  final double? rRatio;
  final double? gRatio;
  final double? bRatio;

  const HistogramProbe({
    required this.bin,
    required this.zoneName,
    required this.lumRatio,
    this.rRatio,
    this.gRatio,
    this.bRatio,
  });
}

/// bin → 五区名称（分界与 tone_service 五段划分一致：51/102/153/204）
String zoneNameOfBin(int bin) {
  if (bin <= 51) return '黑色';
  if (bin <= 102) return '阴影';
  if (bin <= 153) return '中间调';
  if (bin <= 204) return '高光';
  return '白色';
}

int _totalOf(List<int> channel) {
  var sum = 0;
  for (final c in channel) {
    sum += c;
  }
  return sum;
}

double? _ratioAt(List<int>? channel, int bin) {
  if (channel == null || channel.isEmpty) return null;
  final total = _totalOf(channel);
  if (total == 0) return null;
  return channel[bin] / total;
}

/// 触摸 x 坐标 → 读数（纯函数）
///
/// [dx] 触摸点在直方图内的局部 x，[width] 直方图绘制宽度。
/// 亮度通道为空时返回 null（无可读数据）。
HistogramProbe? histogramProbeAt(HistogramData data, double dx, double width) {
  if (width <= 0) return null;
  final lum = data.lum;
  if (lum.isEmpty) return null;
  final totalLum = _totalOf(lum);
  if (totalLum == 0) return null;

  final bin = ((dx / width) * 256).clamp(0, 255).round();

  return HistogramProbe(
    bin: bin,
    zoneName: zoneNameOfBin(bin),
    lumRatio: lum[bin] / totalLum,
    rRatio: _ratioAt(data.r, bin),
    gRatio: _ratioAt(data.g, bin),
    bRatio: _ratioAt(data.b, bin),
  );
}

/// 可交互直方图：入场动画 + 按住读数
class InteractiveHistogram extends StatefulWidget {
  final HistogramData data;
  final HistogramMode mode;

  /// 直方图高度（画布高度，不含浮层溢出）
  final double height;

  const InteractiveHistogram({
    super.key,
    required this.data,
    this.mode = HistogramMode.rgbLum,
    this.height = 100,
  });

  @override
  State<InteractiveHistogram> createState() => _InteractiveHistogramState();
}

class _InteractiveHistogramState extends State<InteractiveHistogram> {
  HistogramProbe? _probe;
  double _probeX = 0;

  void _update(PointerEvent e, double width) {
    final probe = histogramProbeAt(widget.data, e.localPosition.dx, width);
    if (probe == null) {
      _clear();
      return;
    }
    setState(() {
      _probe = probe;
      _probeX = e.localPosition.dx.clamp(0.0, width);
    });
  }

  void _clear() {
    if (_probe == null) return;
    setState(() => _probe = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return ClipRect(
        // Listener（raw pointer）：不与外层 ListView 滚动手势竞技，
        // 按下即读数、移动即更新、抬起即消失
        child: Listener(
          onPointerDown: (e) => _update(e, width),
          onPointerMove: (e) => _update(e, width),
          onPointerUp: (_) => _clear(),
          onPointerCancel: (_) => _clear(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 图表主体：入场动画从底部生长
              ChartEnterBuilder(
                builder: (context, progress) => SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: HistogramPainter(
                      data: widget.data,
                      mode: widget.mode,
                      progress: progress,
                    ),
                  ),
                ),
              ),
              if (_probe != null) ...[
                // 游标线
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: _probeX,
                  child: Container(width: 1, color: ChartColors.probeCursor),
                ),
                // 读数浮层（跟随手指、clamp 防溢出）
                Positioned(
                  top: 2,
                  left: 0,
                  right: 0,
                  child: _ProbeBadge(
                    probe: _probe!,
                    anchorX: _probeX,
                    trackWidth: width,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

/// 读数浮层：亮度值 + 区域名 + 占比 + RGB 分量条
class _ProbeBadge extends StatelessWidget {
  final HistogramProbe probe;
  final double anchorX;
  final double trackWidth;

  const _ProbeBadge({
    required this.probe,
    required this.anchorX,
    required this.trackWidth,
  });

  @override
  Widget build(BuildContext context) {
    const badgeWidth = 148.0;
    // 浮层中心对准手指，clamp 在直方图范围内
    final left =
        (anchorX - badgeWidth / 2).clamp(0.0, trackWidth - badgeWidth);

    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.only(left: left),
        child: Container(
          width: badgeWidth,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: ChartColors.probeBadgeBg,
            borderRadius: Radii.smBorder,
            border: Border.all(color: ChartColors.gridLight, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('${probe.bin}',
                      style: AppTypography.monoWith(DetailColors.textPrimary)
                          .copyWith(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 5),
                  Text(probe.zoneName,
                      style: AppTypography.captionWith(DetailColors.accent)
                          .copyWith(fontSize: 10)),
                  const Spacer(),
                  Text('${(probe.lumRatio * 100).toStringAsFixed(1)}%',
                      style: AppTypography.mono
                          .copyWith(fontSize: 10)),
                ],
              ),
              const SizedBox(height: 4),
              _ChannelBars(probe: probe),
            ],
          ),
        ),
      ),
    );
  }
}

/// RGB 三通道在该 bin 的占比迷你条
class _ChannelBars extends StatelessWidget {
  final HistogramProbe probe;
  const _ChannelBars({required this.probe});

  @override
  Widget build(BuildContext context) {
    // 三通道中最大占比（≥0.5% 下限防全零条）
    final maxRatio = [
      probe.rRatio ?? 0,
      probe.gRatio ?? 0,
      probe.bRatio ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final scale = maxRatio > 0.005 ? maxRatio : 0.005;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _bar('R', probe.rRatio, ChartColors.channelR, scale),
        const SizedBox(height: 2),
        _bar('G', probe.gRatio, ChartColors.channelG, scale),
        const SizedBox(height: 2),
        _bar('B', probe.bRatio, ChartColors.channelB, scale),
      ],
    );
  }

  Widget _bar(String label, double? ratio, Color color, double scale) {
    return Row(
      children: [
        SizedBox(
          width: 8,
          child: Text(label,
              style: AppTypography.captionMuted.copyWith(fontSize: 8)),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: ClipRRect(
            borderRadius: Radii.pillBorder,
            child: LinearProgressIndicator(
              value: (ratio ?? 0) / scale,
              minHeight: 3,
              backgroundColor: ChartColors.gridFaint,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}
