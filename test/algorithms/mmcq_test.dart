// mmcq_test.dart — MMCQ 算法单元测试
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/algorithms/mmcq.dart';

void main() {
  group('MMCQ', () {
    test('空列表返回空结果', () {
      final result = mmcq([], colorCount: 5);
      expect(result.colors, isEmpty);
      expect(result.counts, isEmpty);
    });

    test('纯色图片返回一个颜色', () {
      // 100 个红色像素
      final pixels = List.filled(100, 0xFFFF0000);
      final result = mmcq(pixels, colorCount: 5);
      expect(result.colors.length, 1);
      expect(result.counts.length, 1);
      // 平均色应该接近红色
      final r = (result.colors[0] >> 16) & 0xFF;
      expect(r, 255);
    });

    test('两种颜色正确切分', () {
      final pixels = [
        ...List.filled(50, 0xFFFF0000), // 红
        ...List.filled(50, 0xFF0000FF), // 蓝
      ];
      final result = mmcq(pixels, colorCount: 2);
      expect(result.colors.length, 2);
      final totalPixels = result.counts.fold<int>(0, (a, b) => a + b);
      expect(totalPixels, 100);
    });

    test('colorCount 参数限制颜色数量', () {
      // 构造 8 种明显不同的颜色
      final colors8 = [
        0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00,
        0xFFFF00FF, 0xFF00FFFF, 0xFF800000, 0xFF008000,
      ];
      final pixels = [
        for (final c in colors8) ...List.filled(20, c),
      ];
      final result3 = mmcq(pixels, colorCount: 3);
      expect(result3.colors.length, lessThanOrEqualTo(3));
      final result5 = mmcq(pixels, colorCount: 5);
      expect(result5.colors.length, lessThanOrEqualTo(5));
    });

    test('count 和 colors 长度一致', () {
      final pixels = [
        ...List.filled(30, 0xFFFF0000),
        ...List.filled(30, 0xFF00FF00),
        ...List.filled(30, 0xFF0000FF),
      ];
      final result = mmcq(pixels, colorCount: 3);
      expect(result.colors.length, result.counts.length);
    });

    test('所有返回的色值都是有效 ARGB', () {
      final pixels = [
        ...List.filled(20, 0xFFAABBCC),
        ...List.filled(20, 0xFF112233),
        ...List.filled(20, 0xFFDDEEFF),
      ];
      final result = mmcq(pixels, colorCount: 3);
      for (final color in result.colors) {
        expect(color & 0xFF000000, 0xFF000000); // alpha = 255
      }
    });
  });
}
