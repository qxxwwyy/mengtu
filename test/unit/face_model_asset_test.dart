// face_model_asset_test.dart — 面部识别模型文件/打包完整性测试（v7.0）
//
// 目的：在 `flutter test` 能跑的范围内，验证 SCRFD NCNN
// 模型文件「存在、已声明」。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 插件内模型文件的物理路径与期望大小
  const models = <({String path, String name, int minBytes})>[
    (
      path: 'scrfd_ncnn_plugin/assets/scrfd_2.5g_kps-opt2.param',
      name: 'SCRFD param file',
      minBytes: 5 * 1024, // ~10KB
    ),
    (
      path: 'scrfd_ncnn_plugin/assets/scrfd_2.5g_kps-opt2.bin',
      name: 'SCRFD weights bin file',
      minBytes: 1000 * 1024, // ~1.6MB
    ),
  ];

  group('模型文件物理存在', () {
    for (final m in models) {
      test('${m.name}：文件存在且大小 >= ${m.minBytes ~/ 1024}KB', () {
        final file = File(m.path);
        expect(file.existsSync(), isTrue,
            reason: '${m.path} 不存在，模型未随仓库提交');
        final size = file.lengthSync();
        expect(size, greaterThanOrEqualTo(m.minBytes),
            reason: '${m.path} 大小 $size 字节 < ${m.minBytes}，疑似截断或占位文件');
      });
    }
  });

  group('pubspec.yaml asset 声明', () {
    test('插件 pubspec.yaml 声明了两个模型文件', () {
      final pubspec = File('scrfd_ncnn_plugin/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/scrfd_2.5g_kps-opt2.param'),
          reason: 'scrfd_ncnn_plugin/pubspec.yaml 未声明 param 文件');
      expect(pubspec, contains('assets/scrfd_2.5g_kps-opt2.bin'),
          reason: 'scrfd_ncnn_plugin/pubspec.yaml 未声明 bin 文件');
    });
  });

  group('模型文件非空/非损坏', () {
    test('两个文件头部字节非全零', () {
      for (final m in models) {
        final bytes = File(m.path).readAsBytesSync();
        final header = bytes.take(16).toList();
        final nonZeroInHeader = header.where((b) => b != 0).length;
        expect(nonZeroInHeader, greaterThan(0),
            reason: '${m.path} 头部 16 字节全零，疑似损坏的空文件');
      }
    });
  });
}
