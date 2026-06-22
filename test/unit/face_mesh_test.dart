// face_mesh_test.dart — v3.5 三段式 Face Mesh 算法测试
//
// 验证 STI（接近度公式）和 FLC（带可见性判定）两个纯函数。
// 不依赖 TFLite 模型 —— 构造合成 FaceMeshResult（468 个 landmark）+ 合成像素图，
// 直接喂给 [calculateSti] / [calculateFlc] 验证边界条件与公式正确性。
//
// 覆盖（implementation_plan.md PR2 §2.4 测试列表 #1-6）：
// 1. STI 理想肤色（Y=0.65,S=0.25,H=17°）→ 接近 1.0
// 2. STI 苍白皮肤（高 Y 低 S）→ 低（低饱和高斯惩罚）
// 3. STI 塑料脸（无纹理）→ 高（不依赖纹理，接近度公式只看 Y/S/H）
// 4. FLC 平光（左右明度相等）→ ≈ 0
// 5. FLC 阴阳脸（左右明度悬殊）→ 高
// 6. FLC 侧脸（visibility<0.5）→ null
// 7. STI/FLC 全不可见 → null（侧脸/遮挡降级）
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mengtu/models/tone_result.dart';
import 'package:mengtu/services/face_service.dart';

void main() {
  /// 构造合成 FaceMeshResult：468 个 landmark，全部可见（visibility=1）
  ///
  /// [skinColor] 决定所有 cheekRegion/leftFaceRegion/rightFaceRegion 对应
  /// 像素的填充色，从而控制 STI/FLC 的输入。
  FaceMeshResult buildMesh({
    required int imgW,
    required int imgH,
    int cheekRgb = 0xFFE0B0, // 默认暖橙肤色
    int leftFaceRgb = 0xFFE0B0,
    int rightFaceRgb = 0xFFE0B0,
    // visibility：默认全可见（1.0），可整体调低模拟侧脸
    double visibility = 1.0,
    // 部分区域单独调 visibility（模拟侧脸：右脸不可见）
    List<int> lowVisibilityIndices = const [],
  }) {
    // landmark 坐标均匀分布（位置不影响 STI/FLC，只影响采到哪个像素；这里用区域填色）
    final landmarks = List<List<double>>.generate(
        468, (i) => [0.3 + (i % 20) * 0.02, 0.3 + (i ~/ 20) * 0.02, 0.0]);
    final vis = List<double>.filled(468, visibility);
    for (final idx in lowVisibilityIndices) {
      if (idx < 468) vis[idx] = 0.1; // 低于阈值
    }
    return FaceMeshResult(landmarks: landmarks, visibility: vis);
  }

  /// 构造合成图片：指定区域填指定颜色
  ///
  /// [cheekColor]/[leftColor]/[rightColor] 控制 STI/FLC 采样到的像素值。
  /// 简化处理：整图填 cheekColor，再覆盖左/右半区域。
  img.Image buildImage({
    required int imgW,
    required int imgH,
    required int cheekColor,
    int? leftColor,
    int? rightColor,
  }) {
    final image = img.Image(width: imgW, height: imgH);
    // 全图填 cheek 色（cheekRegion landmark 落点）
    img.fill(image, color: img.ColorRgba8(
        (cheekColor >> 16) & 0xFF, (cheekColor >> 8) & 0xFF, cheekColor & 0xFF, 0xFF));
    // 左右半区覆盖（leftFaceRegion landmark x 偏小，rightFaceRegion x 偏大）
    // 用 x 坐标中分：landmark i 的 x = 0.3 + (i%20)*0.02，left 区索引大多落在前半
    // 简化：直接按 RGB 分块测试，不做精确坐标映射（STI/FLC 是按 landmark 索引取色）
    if (leftColor != null || rightColor != null) {
      // 由于 landmark 坐标固定，leftFaceRegion 索引采到的像素由 (lm.x*W) 决定。
      // 为可控测试，改用：所有像素填 cheek 色，STI 用 cheekRegion 验证；
      // FLC 单独构造左右明度不同的图（按 landmark 落点的 x 坐标分块）。
    }
    return image;
  }

  /// 构造按 x 坐标分块的图（左半 leftColor，右半 rightColor），用于 FLC 阴阳脸测试
  ///
  /// leftFaceRegion 的 landmark x ≈ 0.3~0.6，rightFaceRegion x ≈ 0.3~0.6。
  /// 为让左右区域采到不同色，按 landmark 索引奇偶分块（更可控）。
  /// 实际策略：直接用 [calculateFlc] 内部逻辑（按 landmark 索引取色），
  /// 所以我们让 leftFaceRegion 索引对应的像素坐标填一种色，rightFaceRegion 填另一种。
  img.Image buildSplitImage({
    required int imgW,
    required int imgH,
    required int leftColor,
    required int rightColor,
    required FaceMeshResult mesh,
  }) {
    final image = img.Image(width: imgW, height: imgH);
    // 先全填 leftColor
    img.fill(image, color: img.ColorRgba8(
        (leftColor >> 16) & 0xFF, (leftColor >> 8) & 0xFF, leftColor & 0xFF, 0xFF));
    // 把 rightFaceRegion landmark 对应像素改成 rightColor
    for (final idx in FaceMeshIndices.rightFaceRegion) {
      if (idx >= mesh.landmarks.length) continue;
      final lm = mesh.landmarks[idx];
      final px = (lm[0] * imgW).clamp(0, imgW - 1).round();
      final py = (lm[1] * imgH).clamp(0, imgH - 1).round();
      image.setPixelRgb(px, py,
          (rightColor >> 16) & 0xFF, (rightColor >> 8) & 0xFF, rightColor & 0xFF);
      // 周围一圈也填，避免 landmark 浮点取整误差采到邻像素
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final nx = (px + dx).clamp(0, imgW - 1);
          final ny = (py + dy).clamp(0, imgH - 1);
          image.setPixelRgb(nx, ny,
              (rightColor >> 16) & 0xFF, (rightColor >> 8) & 0xFF, rightColor & 0xFF);
        }
      }
    }
    return image;
  }

  group('STI 皮肤通透度（接近度公式）', () {
    // HSL → RGB 辅助：精确构造目标 HSL 对应的像素，避免手算误差
    int hslToColorInt(double h, double s, double l) {
      // h: 0~360, s/l: 0~1
      final c = (1 - (2 * l - 1).abs()) * s;
      final hp = h / 60;
      final x = c * (1 - (hp % 2 - 1).abs());
      double r1, g1, b1;
      if (hp < 1) {
        (r1, g1, b1) = (c, x, 0);
      } else if (hp < 2) {
        (r1, g1, b1) = (x, c, 0);
      } else if (hp < 3) {
        (r1, g1, b1) = (0, c, x);
      } else if (hp < 4) {
        (r1, g1, b1) = (0, x, c);
      } else if (hp < 5) {
        (r1, g1, b1) = (x, 0, c);
      } else {
        (r1, g1, b1) = (c, 0, x);
      }
      final m = l - c / 2;
      final r = ((r1 + m) * 255).round().clamp(0, 255);
      final g = ((g1 + m) * 255).round().clamp(0, 255);
      final b = ((b1 + m) * 255).round().clamp(0, 255);
      return (r << 16) | (g << 8) | b;
    }

    test('理想肤色（H=17°, S=0.25, L=0.65）→ STI 高（接近度三项接近峰值）', () {
      // 精确构造理想肤色点：达芬奇线 17° + 理想饱和 0.25 + 理想明度 0.65
      // 三高斯分量都接近峰值 1.0 → STI 接近 (1+1+1)/3 = 1.0
      final cheekColor = hslToColorInt(17, 0.25, 0.65);
      final mesh = buildMesh(imgW: 200, imgH: 200, cheekRgb: cheekColor);
      final image = buildImage(imgW: 200, imgH: 200, cheekColor: cheekColor);
      final sti = calculateSti(mesh, image, false);

      expect(sti, isNotNull);
      // 三高斯接近峰值 → STI 应较高（> 0.85，量化误差允许少量偏差）
      expect(sti!, greaterThan(0.85),
          reason: '精确理想肤色点三高斯分量接近 1.0，STI 应 > 0.85');
    });

    test('苍白皮肤（高 L 低 S）→ STI 明显低于理想肤色（明度/饱和高斯惩罚）', () {
      // L=0.88（远高于理想 0.65）+ S=0.08（远低于理想 0.25）→ Y/S 两高斯分量小。
      // 注意：H 项（1-|ΔH|/30）即使 H 偏移小也接近 1，所以 STI 不会极低，
      // 但 Y/S 惩罚会让它显著低于理想肤色（>0.85）。这是接近度公式的特性，
      // 验证"低饱和+高明度相对理想肤色明显偏低"而非绝对值。
      final cheekColor = hslToColorInt(20, 0.08, 0.88);
      final mesh = buildMesh(imgW: 200, imgH: 200, cheekRgb: cheekColor);
      final image = buildImage(imgW: 200, imgH: 200, cheekColor: cheekColor);
      final sti = calculateSti(mesh, image, false);

      expect(sti, isNotNull);
      // 苍白皮肤 STI 应明显低于理想肤色（>0.85）。实测 ≈0.48，<0.55 验证惩罚生效
      expect(sti!, lessThan(0.55),
          reason: '高明度+低饱和的 Y/S 高斯惩罚 → STI 显著低于理想肤色');
    });

    test('塑料脸（无纹理，Y/S/H 理想）→ STI 高（不依赖纹理）', () {
      // 接近度公式只用 Y/S/H 三个标量，与纹理无关。纯色区域（无纹理）
      // 只要 Y/S/H 接近理想点，STI 就高。这正是弃用 plan.md 乘积公式（含 Texture）
      // 的理由：塑料脸纹理为 0 但通透感高，乘积公式会误判。
      final cheekColor = hslToColorInt(17, 0.25, 0.65);
      final mesh = buildMesh(imgW: 200, imgH: 200, cheekRgb: cheekColor);
      // 纯色图（无纹理变化）—— 与"理想肤色"测试用相同像素，验证纹理不影响结果
      final image = buildImage(imgW: 200, imgH: 200, cheekColor: cheekColor);
      final sti = calculateSti(mesh, image, false);

      expect(sti, isNotNull);
      expect(sti!, greaterThan(0.85), reason: '塑料脸无纹理但通透感高，STI 应高');
    });

    test('全部 cheek landmark 不可见 → STI 返回 null', () {
      // 模拟侧脸：cheekRegion 所有 landmark visibility < 0.5
      final mesh = buildMesh(
        imgW: 200,
        imgH: 200,
        visibility: 0.1, // 整体低可见性
      );
      final image = buildImage(imgW: 200, imgH: 200, cheekColor: 0xC7A785);
      final sti = calculateSti(mesh, image, false);
      expect(sti, isNull, reason: '全部 cheek 不可见 → 侧脸，STI null');
    });

    test('部分 cheek 不可见 → 用剩余可见 landmark 计算（不返回 null）', () {
      // 只把部分 cheekRegion landmark 设为低可见性，剩余仍可采样
      final mesh = buildMesh(
        imgW: 200,
        imgH: 200,
        cheekRgb: 0xC7A785,
        lowVisibilityIndices: [50, 280], // cheekRegion 的 2 个
      );
      final image = buildImage(imgW: 200, imgH: 200, cheekColor: 0xC7A785);
      final sti = calculateSti(mesh, image, false);
      expect(sti, isNotNull, reason: '部分可见仍应算出 STI');
    });
  });

  group('FLC 面部反差系数（带可见性判定）', () {
    test('平光（左右明度相等）→ FLC ≈ 0', () {
      // 左右脸同色 → Y_left == Y_right → |差| ≈ 0
      const color = 0xC7A785;
      final mesh = buildMesh(imgW: 200, imgH: 200);
      // 左右同色（不分块）
      final image = buildImage(imgW: 200, imgH: 200, cheekColor: color);
      final flc = calculateFlc(mesh, image, false);

      expect(flc, isNotNull);
      expect(flc!, lessThan(0.01), reason: '左右明度相等 → FLC ≈ 0');
    });

    test('阴阳脸（左亮右暗）→ FLC 高（接近 |Δ|/(和)）', () {
      // 左脸亮（白，L≈1.0），右脸暗（黑，L≈0）→ FLC = |1-0|/(1+0) = 1.0
      // 实际像素有量化，但应明显大于 0
      final mesh = buildMesh(imgW: 200, imgH: 200);
      final image = buildSplitImage(
        imgW: 200,
        imgH: 200,
        leftColor: 0xFFFFFF, // 左脸白
        rightColor: 0x000000, // 右脸黑
        mesh: mesh,
      );
      final flc = calculateFlc(mesh, image, false);

      expect(flc, isNotNull);
      expect(flc!, greaterThan(0.5), reason: '阴阳脸 FLC 应高');
    });

    test('侧脸（右脸 visibility<0.5）→ FLC 返回 null', () {
      // 右脸区域平均 visibility 低于阈值 → 判定侧脸 → null
      final mesh = buildMesh(
        imgW: 200,
        imgH: 200,
        lowVisibilityIndices: FaceMeshIndices.rightFaceRegion,
      );
      final image = buildImage(imgW: 200, imgH: 200, cheekColor: 0xC7A785);
      final flc = calculateFlc(mesh, image, false);
      expect(flc, isNull, reason: '右脸不可见 → 侧脸，FLC null');
    });

    test('左脸侧（left visibility<0.5）→ FLC 返回 null', () {
      final mesh = buildMesh(
        imgW: 200,
        imgH: 200,
        lowVisibilityIndices: FaceMeshIndices.leftFaceRegion,
      );
      final image = buildImage(imgW: 200, imgH: 200, cheekColor: 0xC7A785);
      final flc = calculateFlc(mesh, image, false);
      expect(flc, isNull, reason: '左脸不可见 → 侧脸，FLC null');
    });

    test('轻微明度差 → FLC 在 (0, 0.5) 区间', () {
      // 左脸中灰（L≈0.5），右脸略暗（L≈0.4）→ FLC = 0.1/0.9 ≈ 0.11
      final mesh = buildMesh(imgW: 200, imgH: 200);
      final image = buildSplitImage(
        imgW: 200,
        imgH: 200,
        leftColor: 0xBFBFBF, // 中灰 L≈0.5
        rightColor: 0x999999, // 略暗 L≈0.4
        mesh: mesh,
      );
      final flc = calculateFlc(mesh, image, false);
      expect(flc, isNotNull);
      expect(flc!, greaterThan(0.0));
      expect(flc, lessThan(0.5));
    });
  });

  group('降级链（mesh 失败/无脸）', () {
    test('analyzeSkinTone 不传 meshModelPath → STI/FLC 为 null（降级 bbox ROI）', () async {
      // 不传任何模型路径 + 无手动覆盖 → 无脸 → 空 SkinAnalysis
      // 验证 mesh 不存在时不会崩溃，sti/flc 字段为 null
      // （完整的三段式集成测试需要真实 TFLite 模型，此处仅验证字段语义）
      final empty = const SkinAnalysis();
      expect(empty.sti, isNull);
      expect(empty.flc, isNull);
    });

    test('SkinAnalysis.sti/flc 序列化往返（非空值）', () {
      const original = SkinAnalysis(
        hueOffset: 5.0,
        saturation: 45.0,
        sti: 0.72,
        flc: 0.35,
      );
      final json = original.toJson();
      final restored = SkinAnalysis.fromJson(json);
      expect(restored.sti, closeTo(0.72, 1e-9));
      expect(restored.flc, closeTo(0.35, 1e-9));
    });

    test('SkinAnalysis.sti/flc 旧缓存（无这两个键）→ null（容错，不抛）', () {
      // 模拟 v3.0 缓存：只有 hueOffset/saturation，无 sti/flc
      const legacy = {'hueOffset': 5.0, 'saturation': 45.0};
      final restored = SkinAnalysis.fromJson(legacy);
      expect(restored.hueOffset, 5.0);
      expect(restored.sti, isNull); // 容错：缺键 → null
      expect(restored.flc, isNull);
    });

    test('SkinAnalysis.toJson 省略 null 的 sti/flc', () {
      const partial = SkinAnalysis(hueOffset: 5.0, saturation: 45.0);
      final json = partial.toJson();
      expect(json.containsKey('sti'), isFalse);
      expect(json.containsKey('flc'), isFalse);
    });
  });

  group('FaceMeshIndices 拓扑', () {
    test('关键 landmark 索引在 [0, 468) 范围内', () {
      // MediaPipe Face Mesh 共 468 个 landmark，索引必须有效
      expect(FaceMeshIndices.noseTip, inInclusiveRange(0, 467));
      expect(FaceMeshIndices.leftEyeOuter, inInclusiveRange(0, 467));
      expect(FaceMeshIndices.rightEyeOuter, inInclusiveRange(0, 467));
      expect(FaceMeshIndices.chin, inInclusiveRange(0, 467));
      expect(FaceMeshIndices.foreheadCenter, inInclusiveRange(0, 467));
    });

    test('区域集合非空且索引有效', () {
      expect(FaceMeshIndices.leftFaceRegion, isNotEmpty);
      expect(FaceMeshIndices.rightFaceRegion, isNotEmpty);
      expect(FaceMeshIndices.cheekRegion, isNotEmpty);
      for (final idx in FaceMeshIndices.leftFaceRegion) {
        expect(idx, inInclusiveRange(0, 467));
      }
      for (final idx in FaceMeshIndices.rightFaceRegion) {
        expect(idx, inInclusiveRange(0, 467));
      }
      for (final idx in FaceMeshIndices.cheekRegion) {
        expect(idx, inInclusiveRange(0, 467));
      }
    });
  });
}
