// histogram_service_test.dart — 直方图计算测试（真实图片）
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mengtu/services/histogram_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mengtu_hist_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 生成纯色图片并返回路径
  String makeSolidImage(String name, int r, int g, int b,
      {int size = 40}) {
    final image = img.Image(width: size, height: size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    final path = '${tempDir.path}/$name.png';
    File(path).writeAsBytesSync(img.encodePng(image));
    return path;
  }

  /// 找到 List<int> 中最大值的索引
  int maxIndex(List<int> list) {
    var maxVal = list[0];
    var maxIdx = 0;
    for (var i = 1; i < list.length; i++) {
      if (list[i] > maxVal) {
        maxVal = list[i];
        maxIdx = i;
      }
    }
    return maxIdx;
  }

  group('computeHistogram 纯色图片', () {
    test('纯红图片：R 通道峰值在 255', () async {
      final path = makeSolidImage('red', 255, 0, 0);
      final hist = await computeHistogram(path);

      expect(maxIndex(hist.r), 255);
      expect(maxIndex(hist.g), 0);
      expect(maxIndex(hist.b), 0);
    });

    test('纯绿图片：G 通道峰值在 255', () async {
      final path = makeSolidImage('green', 0, 255, 0);
      final hist = await computeHistogram(path);

      expect(maxIndex(hist.g), 255);
    });

    test('纯蓝图片：B 通道峰值在 255', () async {
      final path = makeSolidImage('blue', 0, 0, 255);
      final hist = await computeHistogram(path);

      expect(maxIndex(hist.b), 255);
    });

    test('白色图片：所有通道峰值在 255', () async {
      final path = makeSolidImage('white', 255, 255, 255);
      final hist = await computeHistogram(path);

      expect(maxIndex(hist.r), 255);
      expect(maxIndex(hist.g), 255);
      expect(maxIndex(hist.b), 255);
    });

    test('黑色图片：所有通道峰值在 0', () async {
      final path = makeSolidImage('black', 0, 0, 0);
      final hist = await computeHistogram(path);

      expect(maxIndex(hist.r), 0);
      expect(maxIndex(hist.g), 0);
      expect(maxIndex(hist.b), 0);
    });
  });

  group('computeHistogram 亮度通道', () {
    test('白色亮度峰值在 255', () async {
      final path = makeSolidImage('white', 255, 255, 255);
      final hist = await computeHistogram(path);
      expect(maxIndex(hist.lum), 255);
    });

    test('黑色亮度峰值在 0', () async {
      final path = makeSolidImage('black', 0, 0, 0);
      final hist = await computeHistogram(path);
      expect(maxIndex(hist.lum), 0);
    });

    test('纯红亮度 ≈ 54（Rec.709）', () async {
      final path = makeSolidImage('red', 255, 0, 0);
      final hist = await computeHistogram(path);
      expect(maxIndex(hist.lum), closeTo(54, 1));
    });

    test('纯绿亮度 ≈ 182（Rec.709）', () async {
      final path = makeSolidImage('green', 0, 255, 0);
      final hist = await computeHistogram(path);
      expect(maxIndex(hist.lum), closeTo(182, 1));
    });
  });

  group('computeHistogram 降采样', () {
    test('100×100 图片 step=4 → 采样约 625 像素', () async {
      final path = makeSolidImage('gray', 128, 128, 128, size: 100);
      final hist = await computeHistogram(path);

      // step=4: ceil(100/4)=25 → 25×25=625
      final totalCount = hist.lum.reduce((a, b) => a + b);
      expect(totalCount, closeTo(625, 25));
    });
  });

  group('computeHistogram 错误处理', () {
    test('损坏文件抛出异常', () async {
      final path = '${tempDir.path}/corrupt.png';
      File(path).writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]); // 不完整 PNG

      // 损坏文件会抛 RangeError 或 Exception，用通用匹配
      await expectLater(
        computeHistogram(path),
        throwsA(isA<Object>()),
      );
    });

    test('不存在的文件抛出异常', () async {
      await expectLater(
        computeHistogram('${tempDir.path}/nonexistent.png'),
        throwsA(isA<Object>()),
      );
    });
  });

  group('computeHistogram 一致性', () {
    test('同一图片两次计算结果相同', () async {
      final path = makeSolidImage('multi', 100, 150, 200);
      final hist1 = await computeHistogram(path);
      final hist2 = await computeHistogram(path);

      expect(hist1.r, equals(hist2.r));
      expect(hist1.g, equals(hist2.g));
      expect(hist1.b, equals(hist2.b));
      expect(hist1.lum, equals(hist2.lum));
    });
  });
}
