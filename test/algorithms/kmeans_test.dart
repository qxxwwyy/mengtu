// kmeans_test.dart — K-Means++ 算法单元测试
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/algorithms/kmeans.dart';

void main() {
  group('K-Means++', () {
    test('空列表返回空结果', () {
      final result = kmeansPlusPlus([], k: 5);
      expect(result.colors, isEmpty);
      expect(result.counts, isEmpty);
    });

    test('纯色图片返回一个颜色', () {
      final pixels = List.filled(100, 0xFF00FF00);
      final result = kmeansPlusPlus(pixels, k: 5);
      expect(result.colors.length, 1);
      final g = (result.colors[0] >> 8) & 0xFF;
      expect(g, 255);
    });

    test('两个聚类正确分配', () {
      final pixels = [
        ...List.filled(50, 0xFFFF0000),
        ...List.filled(50, 0xFF0000FF),
      ];
      final result = kmeansPlusPlus(pixels, k: 2);
      expect(result.colors.length, 2);
      final totalPixels = result.counts.fold<int>(0, (a, b) => a + b);
      expect(totalPixels, 100);
    });

    test('聚类数量不超过 k', () {
      final colors = [
        0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00,
        0xFFFF00FF, 0xFF00FFFF, 0xFF800000, 0xFF008000,
      ];
      final pixels = [
        for (final c in colors) ...List.filled(20, c),
      ];
      final result = kmeansPlusPlus(pixels, k: 3);
      expect(result.colors.length, lessThanOrEqualTo(3));
    });

    test('k 值大于像素数时退化', () {
      final pixels = [0xFFFF0000, 0xFF00FF00];
      final result = kmeansPlusPlus(pixels, k: 10);
      expect(result.colors.length, lessThanOrEqualTo(2));
    });

    test('固定种子保证可复现', () {
      final pixels = [
        ...List.filled(30, 0xFFAABBCC),
        ...List.filled(30, 0xFF112233),
        ...List.filled(30, 0xFFDDEEFF),
      ];
      final r1 = kmeansPlusPlus(pixels, k: 3);
      final r2 = kmeansPlusPlus(pixels, k: 3);
      // 固定种子(42) → 结果应该一致
      expect(r1.colors, r2.colors);
    });

    test('所有返回的色值都是有效 ARGB', () {
      final pixels = [
        ...List.filled(20, 0xFFAABBCC),
        ...List.filled(20, 0xFF112233),
      ];
      final result = kmeansPlusPlus(pixels, k: 2);
      for (final color in result.colors) {
        expect(color & 0xFF000000, 0xFF000000);
      }
    });
  });
}
