// mmcq.dart — Modified Median Cut Quantization (MMCQ)
//
// 参考 color-thief (MIT) 的 MMCQ 实现，独立编写。
// 算法核心：将 RGB 空间递归切分为色彩盒子，按最长轴中位数切分，
// 直到盒子数量达到目标色数或不可再分。
// 最终每个盒子取平均色作为主色，像素数作为权重。
//
// 参考: S. M. Smith, "Color quantization algorithms for digital images,"
//        based on Paul Heckbert's median-cut algorithm (1980).

/// RGB 像素（用于算法内部传递，避免 int 编解码开销）
class _Pixel {
  final int r, g, b;
  const _Pixel(this.r, this.g, this.b);
}

/// 色彩盒子（MMCQ 的核心数据结构）
class _ColorBox {
  final List<_Pixel> pixels;
  int _minR = 255, _maxR = 0;
  int _minG = 255, _maxG = 0;
  int _minB = 255, _maxB = 0;
  int _longestAxis = 0;

  _ColorBox(this.pixels) {
    _computeBounds();
  }

  void _computeBounds() {
    for (final p in pixels) {
      if (p.r < _minR) _minR = p.r;
      if (p.r > _maxR) _maxR = p.r;
      if (p.g < _minG) _minG = p.g;
      if (p.g > _maxG) _maxG = p.g;
      if (p.b < _minB) _minB = p.b;
      if (p.b > _maxB) _maxB = p.b;
    }
    final rangeR = _maxR - _minR;
    final rangeG = _maxG - _minG;
    final rangeB = _maxB - _minB;
    if (rangeR >= rangeG && rangeR >= rangeB) {
      _longestAxis = 0;
    } else if (rangeG >= rangeR && rangeG >= rangeB) {
      _longestAxis = 1;
    } else {
      _longestAxis = 2;
    }
  }

  /// 按最长轴的中位数切分，返回 [left, right]
  List<_ColorBox>? split() {
    if (pixels.length < 2) return null;

    // 按最长轴排序
    final sorted = List<_Pixel>.from(pixels);
    switch (_longestAxis) {
      case 0:
        sorted.sort((a, b) => a.r.compareTo(b.r));
      case 1:
        sorted.sort((a, b) => a.g.compareTo(b.g));
      case 2:
        sorted.sort((a, b) => a.b.compareTo(b.b));
    }

    final mid = sorted.length ~/ 2;
    return [_ColorBox(sorted.sublist(0, mid)), _ColorBox(sorted.sublist(mid))];
  }

  /// 求盒子平均色（返回 ARGB int）
  int averageColor() {
    var sumR = 0, sumG = 0, sumB = 0;
    for (final p in pixels) {
      sumR += p.r;
      sumG += p.g;
      sumB += p.b;
    }
    final n = pixels.length;
    return 0xFF000000 |
        ((sumR ~/ n) << 16) |
        ((sumG ~/ n) << 8) |
        (sumB ~/ n);
  }

  /// 盒子体积（用最长轴的范围作为优先级）
  int get volume {
    final rangeR = _maxR - _minR;
    final rangeG = _maxG - _minG;
    final rangeB = _maxB - _minB;
    return rangeR * rangeR + rangeG * rangeG + rangeB * rangeB;
  }

  int get count => pixels.length;
  bool get canSplit {
    if (pixels.length < 2) return false;
    // 所有像素同色则不可切分（切分无意义）
    return volume > 0;
  }
}

/// MMCQ 提取结果
class MmcqResult {
  /// 主色列表（ARGB int）
  final List<int> colors;

  /// 每个主色对应的像素数（用于占比计算）
  final List<int> counts;

  MmcqResult({required this.colors, required this.counts});
}

/// MMCQ 算法入口
///
/// [pixels] ARGB int 列表（0xAARRGGBB 格式）
/// [colorCount] 目标色数（3-8）
MmcqResult mmcq(List<int> pixels, {int colorCount = 5}) {
  if (pixels.isEmpty) {
    return MmcqResult(colors: [], counts: []);
  }

  // 转换为 _Pixel 列表
  final pixList = pixels.map((argb) {
    return _Pixel(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
    );
  }).toList();

  // 初始盒子（包含所有像素）
  var boxes = [_ColorBox(pixList)];

  // 递归切分：每次选体积最大的盒子切分
  while (boxes.length < colorCount) {
    // 按 volume 降序排列，优先切分体积大的盒子
    boxes.sort((a, b) => b.volume.compareTo(a.volume));

    var split = false;
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].canSplit) {
        final halves = boxes[i].split();
        if (halves != null) {
          boxes.removeAt(i);
          boxes.insert(i, halves[0]);
          boxes.insert(i + 1, halves[1]);
          split = true;
          break;
        }
      }
    }
    if (!split) break; // 无法继续切分
  }

  // 提取每个盒子的平均色 + 像素数
  final colors = <int>[];
  final counts = <int>[];
  for (final box in boxes) {
    if (box.count > 0) {
      colors.add(box.averageColor());
      counts.add(box.count);
    }
  }

  return MmcqResult(colors: colors, counts: counts);
}
