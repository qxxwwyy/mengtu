// color_utils.dart — RGB ↔ HSL ↔ HSV 转换、灰度计算
import 'dart:math';

/// Rec.709 亮度系数
const double rec709R = 0.2126;
const double rec709G = 0.7152;
const double rec709B = 0.0722;

/// Rec.709 灰度矩阵（用于 ColorFiltered 一键黑白）
const List<double> grayscaleMatrix = [
  rec709R, rec709G, rec709B, 0, 0, //
  rec709R, rec709G, rec709B, 0, 0, //
  rec709R, rec709G, rec709B, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// 计算亮度（Rec.709）
int luminance(int r, int g, int b) {
  return (rec709R * r + rec709G * g + rec709B * b).round().clamp(0, 255);
}

/// RGB → YCbCr（Rec.709 full-range，用于矢量示波器 Cb/Cr 平面）
///
/// 输入 R/G/B 为 0-255；返回 [Y] 在 0-255，[cb]/[cr] 在 -128~127。
/// 公式（Kb=0.0722, Kr=0.2126）：
///   Y  =  0.2126R + 0.7152G + 0.0722B
///   Cb = -0.1146R - 0.3854G + 0.5000B   (= (B−Y)/1.8556)
///   Cr =  0.5000R - 0.4542G - 0.0458B   (= (R−Y)/1.5748)
/// full-range 而非 studio-swing（16-235），让像素云直接用 Cb/Cr 映射到画布坐标，
/// 与示波器六色目标（BT.709 彩条）处于同一坐标系。
({double y, double cb, double cr}) rgbToYCbCr(int r, int g, int b) {
  final y = rec709R * r + rec709G * g + rec709B * b;
  return (
    y: y,
    cb: -0.1146 * r - 0.3854 * g + 0.5 * b,
    cr: 0.5 * r - 0.4542 * g - 0.0458 * b,
  );
}

/// RGB → HSL
({double h, double s, double l}) rgbToHsl(int r, int g, int b) {
  final rf = r / 255, gf = g / 255, bf = b / 255;
  final maxVal = [rf, gf, bf].reduce(max);
  final minVal = [rf, gf, bf].reduce(min);
  var h = 0.0, s = 0.0;
  final l = (maxVal + minVal) / 2;

  if (maxVal != minVal) {
    final d = maxVal - minVal;
    s = l > 0.5 ? d / (2 - maxVal - minVal) : d / (maxVal + minVal);
    switch (maxVal) {
      case final v when v == rf:
        h = (gf - bf) / d + (gf < bf ? 6 : 0);
      case final v when v == gf:
        h = (bf - rf) / d + 2;
      default:
        h = (rf - gf) / d + 4;
    }
    h /= 6;
  }

  return (h: h * 360, s: s * 100, l: l * 100);
}

/// RGB → HSV 的色相值（0-359°）
/// 饱和度为 0（灰色）时返回 -1 表示无色相
int rgbToHue(int r, int g, int b) {
  final rf = r / 255, gf = g / 255, bf = b / 255;
  final maxVal = [rf, gf, bf].reduce(max);
  final minVal = [rf, gf, bf].reduce(min);
  final delta = maxVal - minVal;

  if (delta == 0) return -1; // 灰度无色相

  double h;
  if (maxVal == rf) {
    h = ((gf - bf) / delta) % 6;
  } else if (maxVal == gf) {
    h = (bf - rf) / delta + 2;
  } else {
    h = (rf - gf) / delta + 4;
  }
  h *= 60;
  if (h < 0) h += 360;
  return h.round() % 360;
}

/// ARGB int → HEX 字符串
String argbToHex(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
}

/// ARGB int → RGB 字符串
String argbToRgbString(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 'rgb($r, $g, $b)';
}

/// ARGB int → HSL 字符串
String argbToHslString(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final hsl = rgbToHsl(r, g, b);
  return 'hsl(${hsl.h.round()}, ${hsl.s.round()}%, ${hsl.l.round()}%)';
}
