// vectorscope_probe_test.dart — 示波器长按查询纯函数测试
//
// 覆盖：canvasToChroma 逆变换（与 painter 几何互逆、clamp）、
// chromaToHueName 色相命名（含中心无彩区）。painter 盲区 → 纯函数可测（gotcha #65）。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/widgets/grading/skin_radar.dart';

void main() {
  // 与 painter 一致的几何：size 200×200 → cx=cy=100, radius=84
  const size = Size(200, 200);

  group('canvasToChroma（画布 → Cb/Cr 逆变换）', () {
    test('中心 → Cb=0 Cr=0', () {
      final c = canvasToChroma(const Offset(100, 100), size);
      expect(c.cb, closeTo(0, 0.01));
      expect(c.cr, closeTo(0, 0.01));
    });

    test('+Cb 方向（右）→ cb 正、cr 0', () {
      // radius=84 → 右端点 x=184
      final c = canvasToChroma(const Offset(184, 100), size);
      expect(c.cb, closeTo(127.5, 0.5));
      expect(c.cr, closeTo(0, 0.5));
    });

    test('+Cr 方向（上）→ cr 正（y 翻转校验）', () {
      // 画布 y 向下，上端点 y=16 → Cr 应为正
      final c = canvasToChroma(const Offset(100, 16), size);
      expect(c.cb, closeTo(0, 0.5));
      expect(c.cr, closeTo(127.5, 0.5));
    });

    test('超出满量程圆 clamp 到 ±128', () {
      final c = canvasToChroma(const Offset(-500, 500), size);
      expect(c.cb, -128.0);
      expect(c.cr, -128.0);
    });
  });

  group('chromaToHueName（Cb/Cr → 色相名）', () {
    test('中心（近无彩）→ 无彩', () {
      expect(chromaToHueName(0, 0), '无彩');
      expect(chromaToHueName(2, -2), '无彩');
    });

    test('肤色线方向（Cb≈-41, Cr≈+63）→ 橙区（肤色落在橙）', () {
      // I-axis 123° 幅度 75 的点，反算 RGB 是暖肤色 → 橙
      final name = chromaToHueName(-40.9, 62.9);
      expect(name, anyOf('橙', '黄'));
    });

    test('红方向（Cr 主导）→ 红', () {
      // 纯红 Cb/Cr（Rec.709 full-range 191,0,0 → Cb≈-20 Cr≈+75）
      final name = chromaToHueName(-20.3, 75.2);
      expect(name, anyOf('红', '橙'));
    });

    test('蓝方向（Cb 主导）→ 蓝', () {
      final name = chromaToHueName(105.9, -35.1);
      expect(name, anyOf('蓝', '青'));
    });
  });
}
