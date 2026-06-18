// face_service_anchor_test.dart — BlazeFace anchor 生成与解码测试（v3.1）
//
// 防 v3.0 回归：原 _buildAnchors 只生成 640 个（与 896 输出不匹配 → RangeError
// 被 try/catch 吞掉 → 永远检测不到脸）。本测试固化 896 这个不变量。
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/services/face_service.dart';

void main() {
  group('BlazeFace anchors', () {
    test('生成正好 896 个 anchor（与模型输出维度严格一致）', () {
      final anchors = blazefaceAnchorsForTest;
      expect(anchors.length, 896,
          reason:
              'anchor 数必须 = 896，否则与模型输出第二维不匹配导致越界静默失败');
    });

    test('所有 anchor 中心坐标在归一化 0~1 区间内', () {
      final anchors = blazefaceAnchorsForTest;
      for (final a in anchors) {
        expect(a.length, 2);
        expect(a[0], inInclusiveRange(0.0, 1.0));
        expect(a[1], inInclusiveRange(0.0, 1.0));
        // 非有限值会破坏后续 clamp（NaN/Infinity）
        expect(a[0].isFinite, isTrue);
        expect(a[1].isFinite, isTrue);
      }
    });

    test('anchor 覆盖 4 个 feature map 层（16/8/8/8 grid）', () {
      // 验证前 512 个 anchor（16×16×2）来自第一层，之后来自 8×8 网格
      final anchors = blazefaceAnchorsForTest;
      // 第一层 stride=8 → feature map 16×16，每 cell 2 anchor = 512
      // 中心应为 (x+0.5)/16
      final firstCx = anchors[0][0];
      final expectedFirstCx = 0.5 / 16;
      expect((firstCx - expectedFirstCx).abs(), lessThan(1e-9));

      // 第 513 个 anchor（8×8 网格起点）中心应为 0.5/8
      final layer2Cx = anchors[512][0];
      final expectedLayer2Cx = 0.5 / 8;
      expect((layer2Cx - expectedLayer2Cx).abs(), lessThan(1e-9));
    });
  });

  group('BlazeFace anchor 解码', () {
    test('零偏移 regressor → bbox 中心 = anchor 中心', () {
      final anchors = blazefaceAnchorsForTest;
      final anchorIdx = 100;
      final anchor = anchors[anchorIdx];
      final face = decodeAnchorForTest(
          anchorIdx, [0.0, 0.0, 0.2, 0.2], 0.9);

      final centerX = (face.left + face.right) / 2;
      final centerY = (face.top + face.bottom) / 2;
      expect((centerX - anchor[0]).abs(), lessThan(1e-9));
      expect((centerY - anchor[1]).abs(), lessThan(1e-9));
    });

    test('解码结果 bbox 在归一化 0~1 内，无 NaN', () {
      final face = decodeAnchorForTest(
          50, [0.1, -0.05, 0.3, 0.4], 0.85);
      expect(face.left, inInclusiveRange(0.0, 1.0));
      expect(face.top, inInclusiveRange(0.0, 1.0));
      expect(face.right, inInclusiveRange(0.0, 1.0));
      expect(face.bottom, inInclusiveRange(0.0, 1.0));
      expect(face.confidence, 0.85);
      expect(face.width, greaterThan(0));
      expect(face.height, greaterThan(0));
      expect(face.area, greaterThan(0));
    });

    test('regressor 正偏移 → bbox 中心相对 anchor 右下移动', () {
      final anchors = blazefaceAnchorsForTest;
      final anchorIdx = 200;
      final anchor = anchors[anchorIdx];
      final face = decodeAnchorForTest(
          anchorIdx, [0.1, 0.1, 0.1, 0.1], 0.9);
      final centerX = (face.left + face.right) / 2;
      final centerY = (face.top + face.bottom) / 2;
      expect(centerX, greaterThan(anchor[0]));
      expect(centerY, greaterThan(anchor[1]));
    });

    test('极端大尺寸 clamp 不越界', () {
      final face = decodeAnchorForTest(
          0, [0.0, 0.0, 10.0, 10.0], 0.9);
      expect(face.right, lessThanOrEqualTo(1.0));
      expect(face.bottom, lessThanOrEqualTo(1.0));
      expect(face.left, greaterThanOrEqualTo(0.0));
      expect(face.top, greaterThanOrEqualTo(0.0));
    });
  });
}
