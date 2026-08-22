// hue_test.dart — 色相转换 (rgbToHue) 单元测试
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/utils/color_utils.dart';

void main() {
  group('rgbToHue', () {
    test('红色 = 0°', () {
      expect(rgbToHue(255, 0, 0), 0);
    });

    test('绿色 = 120°', () {
      expect(rgbToHue(0, 255, 0), 120);
    });

    test('蓝色 = 240°', () {
      expect(rgbToHue(0, 0, 255), 240);
    });

    test('黄色 = 60°', () {
      expect(rgbToHue(255, 255, 0), 60);
    });

    test('青色 = 180°', () {
      expect(rgbToHue(0, 255, 255), 180);
    });

    test('品红 = 300°', () {
      expect(rgbToHue(255, 0, 255), 300);
    });

    test('灰色返回 -1（无色相）', () {
      expect(rgbToHue(128, 128, 128), -1);
    });

    test('白色返回 -1（无色相）', () {
      expect(rgbToHue(255, 255, 255), -1);
    });

    test('黑色返回 -1（无色相）', () {
      expect(rgbToHue(0, 0, 0), -1);
    });

    test('橙色 ≈ 30°', () {
      final hue = rgbToHue(255, 127, 0);
      expect(hue, inInclusiveRange(20, 40));
    });
  });
}
