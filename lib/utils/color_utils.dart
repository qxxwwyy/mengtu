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
