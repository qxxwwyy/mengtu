// pixel_picker_session_test.dart — 取色会话测试（v3.1）
//
// 验证 ColorPickerSession 一次性解码后，pick() 返回的像素与直接 img 读一致。
// 这是修复"取色卡顿"的核心：拖动期间不再重复解码。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mengtu/services/pixel_picker_service.dart';
import 'package:mengtu/utils/color_utils.dart';

void main() {
  late Directory tempDir;
  late String imagePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('picker_session_test');
    // 生成一张有渐变 + 已知像素点的图，便于验证取色正确性
    final image = img.Image(width: 60, height: 40);
    for (var y = 0; y < 40; y++) {
      for (var x = 0; x < 60; x++) {
        // 横向 R 渐变 + 纵向 G 渐变，B 固定
        image.setPixelRgb(x, y, (x * 4).clamp(0, 255), (y * 6).clamp(0, 255),
            100);
      }
    }
    imagePath = '${tempDir.path}/grad.png';
    File(imagePath).writeAsBytesSync(img.encodePng(image));
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('ColorPickerSession', () {
    test('begin() 一次性解码，pick() 像素值与 img 直接读一致', () async {
      final session = await ColorPickerSession.begin(imagePath);
      expect(session.width, 60);
      expect(session.height, 40);

      // 取几个点对照
      for (final p in [
        [0, 0],
        [30, 20],
        [59, 39],
        [10, 5],
      ]) {
        final result = session.pick(p[0], p[1]);
        // 与 img 直接读对照
        final bytes = File(imagePath).readAsBytesSync();
        final decoded = img.decodeImage(bytes)!;
        final ref = decoded.getPixel(p[0], p[1]);
        expect(result.pixel.r, ref.r.toInt());
        expect(result.pixel.g, ref.g.toInt());
        expect(result.pixel.b, ref.b.toInt());
      }
      session.dispose();
    });

    test('pick() 越界坐标自动 clamp 不抛错', () async {
      final session = await ColorPickerSession.begin(imagePath);
      // 负坐标
      final neg = session.pick(-10, -10);
      expect(neg.pixel.x, 0);
      expect(neg.pixel.y, 0);
      // 超界
      final over = session.pick(1000, 1000);
      expect(over.pixel.x, 59);
      expect(over.pixel.y, 39);
      session.dispose();
    });

    test('pick() 返回 11×11 regionRgb 与中心点一致', () async {
      final session = await ColorPickerSession.begin(imagePath);
      final result = session.pick(30, 20);
      expect(result.regionRgb.length, 11);
      for (final row in result.regionRgb) {
        expect(row.length, 11);
      }
      // region 中心应与 pixel 一致
      final centerArgb = result.regionRgb[5][5];
      final centerR = (centerArgb >> 16) & 0xFF;
      expect(centerR, result.pixel.r);
      session.dispose();
    });

    test('pick() 是同步调用（无 Isolate 通信开销）', () async {
      final session = await ColorPickerSession.begin(imagePath);
      // 连续取 100 个点应极快（纯内存查找）
      final sw = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        session.pick(i % 60, (i * 7) % 40);
      }
      sw.stop();
      // 100 次纯内存取色应远小于 100ms（宽松阈值，防 CI 慢机）
      expect(sw.elapsedMilliseconds, lessThan(100),
          reason: 'pick() 应为纯内存查找，100 次应 <100ms');
      session.dispose();
    });

    test('PixelInfo 衍生字段（hex/luminance）正确', () async {
      final session = await ColorPickerSession.begin(imagePath);
      final result = session.pick(10, 5);
      final lum = luminance(result.pixel.r, result.pixel.g, result.pixel.b);
      expect(result.pixel.luminance, lum);
      // hex 应包含 #
      expect(result.pixel.hex, startsWith('#'));
      session.dispose();
    });
  });
}
