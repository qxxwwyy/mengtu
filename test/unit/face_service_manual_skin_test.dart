// face_service_manual_skin_test.dart — 手动肤色校准测试（v3.1）
//
// 验证 analyzeSkinTone 的手动覆盖路径（manualSkinRgb）：
// 即使 TFLite 模型不可用（不传 modelPath），手动模式也能算出色相偏差/饱和度。
// 这是修复"未检测到面部时无路可走"的关键降级通路。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mengtu/services/face_service.dart';

void main() {
  late Directory tempDir;
  late String imagePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('manual_skin_test');
    // 任意内容图（手动模式不关心像素，只用传入的 RGB 算色相）
    final image = img.Image(width: 50, height: 50);
    for (var y = 0; y < 50; y++) {
      for (var x = 0; x < 50; x++) {
        image.setPixelRgb(x, y, 200, 150, 120);
      }
    }
    imagePath = '${tempDir.path}/skin.png';
    File(imagePath).writeAsBytesSync(img.encodePng(image));
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('analyzeSkinTone 手动覆盖', () {
    test('传入健康肤色（暖橙）→ hueOffset 接近 0，饱和度在合理区间', () async {
      // RGB(225, 170, 130) ≈ 健康肤色，色相 ~25°（达芬奇线 17° 附近）
      final result = await analyzeSkinTone(
        imagePath,
        manualSkinRgb: [225, 170, 130],
      );
      expect(result.hueOffset, isNotNull);
      expect(result.hueOffset!.abs(), lessThan(20),
          reason: '健康暖橙肤色 ΔH 应接近达芬奇线（17°）');
      expect(result.saturation, isNotNull);
      // HSL 饱和度（max-min)/(1-|2L-1|)，该 RGB 实算 ~61%，落在肤色合理区间
      expect(result.saturation, inInclusiveRange(20.0, 70.0));
      expect(result.skinLuminance, isNotNull);
    });

    test('手动模式跳过人脸检测：SLS/SCS 置 null（无背景统计）', () async {
      final result = await analyzeSkinTone(
        imagePath,
        manualSkinRgb: [225, 170, 130],
      );
      expect(result.luminanceSeparation, isNull);
      expect(result.colorSeparation, isNull);
      expect(result.bgLuminance, isNull);
    });

    test('不传 modelPath 也能工作（降级通路，不依赖 TFLite）', () async {
      // 关键：未检测到脸/模型缺失时，用户仍可通过取色点手动校准
      final result = await analyzeSkinTone(
        imagePath,
        // 不传 shortModelPath / fullModelPath → 模型路径为空 → 但 manual 优先跳过检测
        manualSkinRgb: [200, 100, 100],
      );
      expect(result.hueOffset, isNotNull);
      expect(result.saturation, isNotNull);
    });

    test('偏黄绿肤色 → hueOffset 明显偏正（>5°）', () async {
      // RGB(180, 200, 80) ≈ 黄绿色，色相远离 17°
      final result = await analyzeSkinTone(
        imagePath,
        manualSkinRgb: [180, 200, 80],
      );
      // 黄绿色相 ~60°，ΔH ≈ 60-17 = 43°（或环形最短距离）
      expect(result.hueOffset!.abs(), greaterThan(5));
    });

    test('manualSkinRgb null 且模型路径空 → 返回空 SkinAnalysis', () async {
      final result = await analyzeSkinTone(imagePath);
      expect(result.isEmpty, isTrue);
    });
  });
}
