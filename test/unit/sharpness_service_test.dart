// sharpness_service_test.dart — 锐度服务测试（v3.1）
//
// 验证主体（中心区域）/ 背景（边缘）锐度评分：
// 中心清晰、背景模糊的合成图 → foregroundScore > backgroundScore
// 这是"对焦工具改为数据读数"的核心指标。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mengtu/services/sharpness_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sharpness_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  img.Image makeSubjectSharpBgBlurImage() {
    // 120×80：中心 60×40 是高对比黑白棋盘（锐），四周是平滑渐变（糊）
    final image = img.Image(width: 120, height: 80);
    for (var y = 0; y < 80; y++) {
      for (var x = 0; x < 120; x++) {
        final inCenter = x >= 30 && x < 90 && y >= 20 && y < 60;
        if (inCenter) {
          // 高频棋盘（4px 周期）→ 拉普拉斯响应强
          final v = (((x ~/ 4) + (y ~/ 4)) % 2 == 0) ? 255 : 0;
          image.setPixelRgb(x, y, v, v, v);
        } else {
          // 平滑横向渐变 → 拉普拉斯响应弱
          final v = ((x / 120) * 255).round();
          image.setPixelRgb(x, y, v, v, v);
        }
      }
    }
    return image;
  }

  img.Image makeUniformImage() {
    // 全图均匀（无边缘）→ 主体/背景锐度都接近 0
    final image = img.Image(width: 120, height: 80);
    for (var y = 0; y < 80; y++) {
      for (var x = 0; x < 120; x++) {
        image.setPixelRgb(x, y, 128, 128, 128);
      }
    }
    return image;
  }

  group('computeSharpness', () {
    test('主体清晰 + 背景虚化 → foregroundScore > backgroundScore', () async {
      final path = '${tempDir.path}/sharp.png';
      File(path).writeAsBytesSync(
          img.encodePng(makeSubjectSharpBgBlurImage()));

      final map = await computeSharpness(path);
      expect(map.cols, greaterThan(0));
      expect(map.rows, greaterThan(0));
      expect(map.foregroundScore, greaterThan(map.backgroundScore),
          reason: '中心棋盘锐利，应使主体锐度高于背景');
    });

    test('主体/背景区域评分 >= 0', () async {
      final path = '${tempDir.path}/uniform.png';
      File(path).writeAsBytesSync(img.encodePng(makeUniformImage()));

      final map = await computeSharpness(path);
      expect(map.foregroundScore, greaterThanOrEqualTo(0));
      expect(map.backgroundScore, greaterThanOrEqualTo(0));
      expect(map.overallScore, greaterThanOrEqualTo(0));
    });

    test('原图宽高比被正确记录', () async {
      final path = '${tempDir.path}/sharp.png';
      File(path).writeAsBytesSync(
          img.encodePng(makeSubjectSharpBgBlurImage()));

      final map = await computeSharpness(path);
      // 120/80 = 1.5
      expect(map.aspectRatio, closeTo(1.5, 0.01));
    });

    test('响应矩阵归一化到 0~1', () async {
      final path = '${tempDir.path}/sharp.png';
      File(path).writeAsBytesSync(
          img.encodePng(makeSubjectSharpBgBlurImage()));

      final map = await computeSharpness(path);
      for (final v in map.response) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
