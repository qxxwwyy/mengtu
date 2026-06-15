// clipping_service_test.dart — Clipping 区域检测测试
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mengtu/services/clipping_service.dart';
import '../helpers/test_helpers.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('clipping_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('detectClipping 纯黑图', () {
    test('全黑图 → darkRatio 高，hasDarkClipping 为 true', () async {
      final path = '${tempDir.path}/black.png';
      generateSolidImageFile(path, r: 0, g: 0, b: 0);

      final result = await detectClipping(path);

      expect(result.hasDarkClipping, isTrue);
      expect(result.darkRatio, greaterThan(0.5));
      expect(result.brightRatio, equals(0));
      expect(result.darkPoints, isNotEmpty);
    });
  });

  group('detectClipping 纯白图', () {
    test('全白图 → brightRatio 高，hasBrightClipping 为 true', () async {
      final path = '${tempDir.path}/white.png';
      generateSolidImageFile(path, r: 255, g: 255, b: 255);

      final result = await detectClipping(path);

      expect(result.hasBrightClipping, isTrue);
      expect(result.brightRatio, greaterThan(0.5));
      expect(result.darkRatio, equals(0));
      expect(result.brightPoints, isNotEmpty);
    });
  });

  group('detectClipping 中灰图', () {
    test('中灰图 → 无 clipping', () async {
      final path = '${tempDir.path}/gray.png';
      generateSolidImageFile(path, r: 128, g: 128, b: 128);

      final result = await detectClipping(path);

      expect(result.hasAnyClipping, isFalse);
      expect(result.darkPoints, isEmpty);
      expect(result.brightPoints, isEmpty);
    });
  });

  group('detectClipping 尺寸', () {
    test('返回的 width/height 与图片一致', () async {
      final path = '${tempDir.path}/sized.png';
      generateSolidImageFile(path, width: 120, height: 80, r: 0, g: 0, b: 0);

      final result = await detectClipping(path);

      expect(result.width, 120);
      expect(result.height, 80);
    });
  });

  group('detectClipping 混合图', () {
    test('半黑半白图 → 两端都有 clipping', () async {
      // 左半黑、右半白
      final path = '${tempDir.path}/mixed.png';
      generateMixedImageFile(path);

      final result = await detectClipping(path);

      expect(result.hasAnyClipping, isTrue);
      // 左半黑 → darkRatio 约 0.5，右半白 → brightRatio 约 0.5
      expect(result.darkRatio, greaterThan(0.3));
      expect(result.brightRatio, greaterThan(0.3));
    });
  });
}

/// 生成左黑右白的图片
void generateMixedImageFile(String path, {int width = 100, int height = 100}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (x < width ~/ 2) {
        image.setPixelRgb(x, y, 0, 0, 0);
      } else {
        image.setPixelRgb(x, y, 255, 255, 255);
      }
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}
