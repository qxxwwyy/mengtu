// palette_result_test.dart — 色卡数据模型序列化测试
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/palette_result.dart';

void main() {
  group('PaletteColor', () {
    test('r/g/b 从 ARGB 正确提取', () {
      const c = PaletteColor(argb: 0xFFFF8800, ratio: 35.5);
      expect(c.r, 255);
      expect(c.g, 136);
      expect(c.b, 0);
    });

    test('toJson / fromJson 往返', () {
      const original = PaletteColor(argb: 0xFFAABBCC, ratio: 42.3);
      final json = original.toJson();
      final restored = PaletteColor.fromJson(json);

      expect(restored.argb, original.argb);
      expect(restored.ratio, original.ratio);
    });
  });

  group('PaletteResult', () {
    test('toJsonString / fromJsonString 往返', () {
      final palette = PaletteResult(colors: [
        const PaletteColor(argb: 0xFFFF0000, ratio: 40.0),
        const PaletteColor(argb: 0xFF00FF00, ratio: 35.0),
        const PaletteColor(argb: 0xFF0000FF, ratio: 25.0),
      ]);

      final json = palette.toJsonString();
      final restored = PaletteResult.fromJsonString(json);

      expect(restored.colors.length, 3);
      expect(restored.colors[0].argb, 0xFFFF0000);
      expect(restored.colors[0].ratio, 40.0);
      expect(restored.colors[2].argb, 0xFF0000FF);
    });

    test('fromJsonString(null) 返回空色卡', () {
      final result = PaletteResult.fromJsonString(null);
      expect(result.colors, isEmpty);
    });

    test('fromJsonString("") 返回空色卡', () {
      final result = PaletteResult.fromJsonString('');
      expect(result.colors, isEmpty);
    });

    test('fromJsonString(非法JSON) 返回空色卡', () {
      final result = PaletteResult.fromJsonString('garbage');
      expect(result.colors, isEmpty);
    });

    test('empty() 工厂返回空列表', () {
      final empty = PaletteResult.empty();
      expect(empty.colors, isEmpty);
    });
  });
}
