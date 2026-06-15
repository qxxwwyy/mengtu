// file_hash.dart — SHA256 文件哈希计算（Isolate）
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// 计算文件 SHA256 哈希，在 Isolate 中执行
Future<String> computeFileHash(String filePath) {
  return compute(_hashFile, filePath);
}

/// 使用 Google 官方 crypto 包计算 SHA256
/// 替代之前手写实现（手写版多块消息累加有致命缺陷）
String _hashFile(String path) {
  final file = File(path);
  final bytes = file.readAsBytesSync();
  return sha256.convert(bytes).toString();
}
