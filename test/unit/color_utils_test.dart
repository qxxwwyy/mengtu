// color_utils_test.dart — RGB↔HSL 转换、Rec.709 灰度、色值格式化测试
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/utils/color_utils.dart';

void main() {
  group('luminance Rec.709', () {
    test('纯红亮度 = 0.2126 × 255 ≈ 54', () {
      expect(luminance(255, 0, 0), closeTo(54, 1));
    });

    test('纯绿亮度 = 0.7152 × 255 ≈ 182', () {
      expect(luminance(0, 255, 0), closeTo(182, 1));
    });

    test('纯蓝亮度 = 0.0722 × 255 ≈ 18', () {
      expect(luminance(0, 0, 255), closeTo(18, 1));
    });

    test('白色 = 255，黑色 = 0', () {
      expect(luminance(255, 255, 255), 255);
      expect(luminance(0, 0, 0), 0);
    });

    test('灰色 128 ≈ 128', () {
      expect(luminance(128, 128, 128), closeTo(128, 1));
    });
  });

  group('rgbToHsl', () {
    test('红色 H=0 S=100 L=50', () {
      final hsl = rgbToHsl(255, 0, 0);
      expect(hsl.h, closeTo(0, 1));
      expect(hsl.s, closeTo(100, 1));
      expect(hsl.l, closeTo(50, 1));
    });

    test('绿色 H=120', () {
      expect(rgbToHsl(0, 255, 0).h, closeTo(120, 1));
    });

    test('蓝色 H=240', () {
      expect(rgbToHsl(0, 0, 255).h, closeTo(240, 1));
    });

    test('灰色饱和度为 0', () {
      expect(rgbToHsl(128, 128, 128).s, closeTo(0, 1));
    });

    test('白色和黑色饱和度为 0', () {
      expect(rgbToHsl(255, 255, 255).s, closeTo(0, 1));
      expect(rgbToHsl(0, 0, 0).s, closeTo(0, 1));
    });

    test('黄色 H=60', () {
      expect(rgbToHsl(255, 255, 0).h, closeTo(60, 1));
    });

    test('青色 H=180', () {
      expect(rgbToHsl(0, 255, 255).h, closeTo(180, 1));
    });

    test('品红 H=300', () {
      expect(rgbToHsl(255, 0, 255).h, closeTo(300, 1));
    });
  });

  group('argbToHex', () {
    test('纯红 → #FF0000', () {
      expect(argbToHex(0xFFFF0000), '#FF0000');
    });

    test('纯绿 → #00FF00', () {
      expect(argbToHex(0xFF00FF00), '#00FF00');
    });

    test('纯蓝 → #0000FF', () {
      expect(argbToHex(0xFF0000FF), '#0000FF');
    });

    test('黑色 → #000000', () {
      expect(argbToHex(0xFF000000), '#000000');
    });

    test('白色 → #FFFFFF', () {
      expect(argbToHex(0xFFFFFFFF), '#FFFFFF');
    });

    test('忽略 Alpha 通道', () {
      expect(argbToHex(0x80FF0000), '#FF0000');
    });
  });

  group('argbToRgbString', () {
    test('格式为 rgb(r, g, b)', () {
      expect(argbToRgbString(0xFFFF8800), 'rgb(255, 136, 0)');
    });
  });

  group('argbToHslString', () {
    test('格式为 hsl(h, s%, l%)', () {
      final result = argbToHslString(0xFFFF0000);
      expect(result, contains('hsl('));
      expect(result, contains('%'));
    });
  });

  group('grayscaleMatrix', () {
    test('20 元素（4×5 矩阵）', () {
      expect(grayscaleMatrix.length, 20);
    });

    test('Rec.709 系数正确', () {
      // R 行
      expect(grayscaleMatrix[0], rec709R);
      expect(grayscaleMatrix[1], rec709G);
      expect(grayscaleMatrix[2], rec709B);
      // G 行（与 R 行相同系数）
      expect(grayscaleMatrix[5], rec709R);
      expect(grayscaleMatrix[6], rec709G);
      expect(grayscaleMatrix[7], rec709B);
      // B 行
      expect(grayscaleMatrix[10], rec709R);
      expect(grayscaleMatrix[11], rec709G);
      expect(grayscaleMatrix[12], rec709B);
      // Alpha 行保留
      expect(grayscaleMatrix[18], 1);
    });
  });
}
