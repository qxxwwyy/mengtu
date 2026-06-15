// file_hash_test.dart — SHA256 文件哈希测试
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/utils/file_hash.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mengtu_hash_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('computeFileHash 一致性', () {
    test('相同内容 → 相同哈希', () async {
      final file1 = File('${tempDir.path}/a.txt');
      final file2 = File('${tempDir.path}/b.txt');
      await file1.writeAsString('hello world');
      await file2.writeAsString('hello world');

      final hash1 = await computeFileHash(file1.path);
      final hash2 = await computeFileHash(file2.path);

      expect(hash1, hash2);
    });

    test('不同内容 → 不同哈希', () async {
      final file1 = File('${tempDir.path}/a.txt');
      final file2 = File('${tempDir.path}/b.txt');
      await file1.writeAsString('hello');
      await file2.writeAsString('world');

      final hash1 = await computeFileHash(file1.path);
      final hash2 = await computeFileHash(file2.path);

      expect(hash1, isNot(hash2));
    });

    test('哈希长度为 64（SHA256 hex）', () async {
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('test');
      final hash = await computeFileHash(file.path);
      expect(hash.length, 64);
    });

    test('已知内容的哈希值正确（crypto 包正确性）', () async {
      // "abc" 的 SHA256 标准值
      final file = File('${tempDir.path}/abc.txt');
      await file.writeAsString('abc');
      final hash = await computeFileHash(file.path);
      expect(hash,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('computeFileHash 边界情况', () {
    test('空文件哈希正确', () async {
      final file = File('${tempDir.path}/empty.txt');
      await file.writeAsString('');
      final hash = await computeFileHash(file.path);
      // 空字符串的 SHA256 标准值
      expect(hash,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('大文件哈希正确（> 1MB，跨多块）', () async {
      final file = File('${tempDir.path}/big.txt');
      // 2MB 的重复数据
      final bigContent = 'A' * (2 * 1024 * 1024);
      await file.writeAsString(bigContent);
      final hash = await computeFileHash(file.path);
      expect(hash.length, 64);
      // 相同大文件两次哈希应一致
      final hash2 = await computeFileHash(file.path);
      expect(hash, hash2);
    });

    test('二进制文件哈希正确', () async {
      final file = File('${tempDir.path}/bin.dat');
      await file.writeAsBytes(List.generate(1000, (i) => i % 256));
      final hash = await computeFileHash(file.path);
      expect(hash.length, 64);
    });
  });
}
