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

  // v6.0 回归测试：BlazeFace 解码三大致命 bug 修复
  group('BlazeFace v6.0 解码修复', () {
    test('sigmoid：classifier logit → 概率（防"未 sigmoid 导致阈值过不了"）', () {
      // logit=0 → sigmoid=0.5（决策边界）
      expect(sigmoidForTest(0), closeTo(0.5, 1e-9));
      // 大正 logit → 接近 1
      expect(sigmoidForTest(5), greaterThan(0.99));
      // 大负 logit → 接近 0
      expect(sigmoidForTest(-5), lessThan(0.01));
      // 原 bug：classifier 输出 logit 被当概率用，负 logit 永远 < 0.5 阈值
    });

    test('box 回归值按 inputSize 归一化（防"中心点偏离几百倍"）', () {
      // anchor 中心 + regressor 偏移必须 / inputSize 才回到 [0,1] 归一化空间
      // 原 bug：cx = anchor[0] + r[0]，r[0] 是 128 像素空间的值（如 20），
      // 直接加到 [0,1] 的 anchor 上 → cx=20.5，clamp 后全跑到边缘，bbox 全画面外
      final anchors = blazefaceAnchorsForTest;
      final anchorIdx = 0;
      final anchor = anchors[anchorIdx];
      // regressor[0]=20（像素空间，对应 20/128≈0.156 归一化）
      final face = decodeAnchorForTest(
          anchorIdx, [20.0, 0.0, 30.0, 30.0], 0.9);
      final centerX = (face.left + face.right) / 2;
      // 归一化后中心 = anchor + 20/128，而非 anchor + 20
      final expectedCx = anchor[0] + 20.0 / 128;
      expect((centerX - expectedCx).abs(), lessThan(1e-9),
          reason: 'box 偏移必须 / inputSize 归一化，否则中心偏离几百倍');
      expect(centerX, inInclusiveRange(0.0, 1.0));
    });

    test('full_range (inputSize=192) 与 short_range (128) 解码独立正确', () {
      // full_range 用 192 输入，box 偏移除以 192；short 除以 128。
      // 同样的 regressor 值在两模型下应产生不同归一化偏移。
      final face128 = decodeAnchorForTest(
          0, [40.0, 0.0, 40.0, 40.0], 0.9,
          inputSize: 128);
      final face192 = decodeAnchorForTest(
          0, [40.0, 0.0, 40.0, 40.0], 0.9,
          inputSize: 192);
      final cx128 = (face128.left + face128.right) / 2;
      final cx192 = (face192.left + face192.right) / 2;
      // 40/128 ≈ 0.3125 vs 40/192 ≈ 0.208 → 不同
      expect(cx128, greaterThan(cx192),
          reason: '相同像素偏移下，短距模型归一化偏移更大（除以更小的 inputSize）');
    });

    test('short & full 都生成 896 anchor（防锚点结构不匹配）', () {
      // 两个模型的 anchor 数都必须 = 896（feature map [16,8,8,8]×2）
      expect(blazefaceAnchorsForTest.length, 896);
      // full 的 anchor 通过 inputSize=192 路径也能取到（结构与 short 同）
      final fullFace = decodeAnchorForTest(
          895, [0.0, 0.0, 0.5, 0.5], 0.8,
          inputSize: 192);
      expect(fullFace.area, greaterThan(0),
          reason: 'full_range 最后一个 anchor（index 895）必须可解码');
    });
  });
}
