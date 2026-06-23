// face_model_asset_test.dart — 面部识别模型文件/打包完整性测试（v3.5）
//
// 目的：在 `flutter test`（主机 dart 运行时）能跑的范围内，验证三个 TFLite
// 模型文件「存在、已声明、能被 rootBundle 读取」。这是 CI 可覆盖的上限。
//
// 不能验证的（需真机）：TFLite 推理本身。tflite_flutter 用 dart:ffi 加载
// 编译进 APK 的原生库（libtensorflowlite_jni.so），该库只在真实 Flutter 引擎
// 环境存在，`flutter test` 下 Interpreter.fromFile 会失败。推理正确性请用
// `flutter test integration_test` 连真机/模拟器验证。
//
// 验证内容：
// 1. assets/models/ 下三个 .tflite 文件存在且大小合理（非空、非截断）
// 2. pubspec.yaml 的 flutter.assets 声明了这三个文件（否则打包后读不到）
// 3. rootBundle.load 能读到完整 bytes（验证 asset → bundle 链路）
// 4. 文件是合法 TFLite flatbuffer（非零、头部字节符合预期）
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // rootBundle.load 依赖 ServicesBinding，测试 main 首行显式初始化 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 三个模型文件的 asset key + 期望最小大小（防截断/占位文件）
  const models = <({String key, String name, int minBytes})>[
    (
      key: 'assets/models/face_detection_short_range.tflite',
      name: 'BlazeFace short_range（近距人脸检测，主力）',
      minBytes: 200 * 1024, // 实际 ~229KB，阈值留余量
    ),
    (
      key: 'assets/models/face_detection_full_range_sparse.tflite',
      name: 'BlazeFace full_range_sparse（远景回退）',
      minBytes: 600 * 1024, // 实际 ~676KB
    ),
    (
      key: 'assets/models/face_mesh.tflite',
      name: 'Face Mesh（468 landmarks，STI/FLC 依赖）',
      minBytes: 1100 * 1024, // 实际 ~1.2MB
    ),
  ];

  group('模型文件物理存在', () {
    for (final m in models) {
      test('${m.name}：文件存在且大小 >= ${m.minBytes ~/ 1024}KB', () {
        final file = File(m.key);
        expect(file.existsSync(), isTrue,
            reason: '${m.key} 不存在，模型未随仓库提交');
        final size = file.lengthSync();
        expect(size, greaterThanOrEqualTo(m.minBytes),
            reason: '${m.key} 大小 $size 字节 < ${m.minBytes}，疑似截断或占位文件');
      });
    }
  });

  group('pubspec.yaml asset 声明', () {
    test('flutter.assets 段声明了全部三个模型文件', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final m in models) {
        expect(pubspec, contains(m.key),
            reason: 'pubspec.yaml 未声明 ${m.key}，打包后 rootBundle 读不到');
      }
    });
  });

  group('rootBundle 读取链路（验证 asset → bundle）', () {
    for (final m in models) {
      test('${m.name}：rootBundle.load 读取完整 bytes', () async {
        final bytes = await rootBundle.load(m.key);
        final data = bytes.buffer.asUint8List();
        expect(data.length, greaterThanOrEqualTo(m.minBytes),
            reason: 'rootBundle 读到的 ${m.key} 仅 ${data.length} 字节，'
                '与磁盘文件大小不符（asset 打包可能有问题）');
        // TFLite flatbuffer 文件头：首个字节非零（合法 flatbuffer 的 size prefix
        // 或 file identifier）。全零 = 文件损坏。
        expect(data.every((b) => b == 0), isFalse,
            reason: '${m.key} 内容全零，文件损坏');
      });
    }
  });

  group('模型文件非空/非损坏', () {
    test('三个文件头部字节非全零（flatbuffer 合法性粗检）', () {
      for (final m in models) {
        final bytes = File(m.key).readAsBytesSync();
        final header = bytes.take(16).toList();
        // flatbuffer 文件不应以连续零开头（size prefix 通常是小端整数）
        final nonZeroInHeader = header.where((b) => b != 0).length;
        expect(nonZeroInHeader, greaterThan(0),
            reason: '${m.key} 头部 16 字节全零，疑似损坏的空文件');
      }
    });
  });
}
