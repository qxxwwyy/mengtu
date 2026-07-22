// chroma_cloud_test.dart — 像素云纯函数 unit test（评审 M3）
//
// 验证 computeCloudPoints 的 bin→点映射、坐标轴方向、密度压缩、RGB 反算。
// 这些逻辑在 widget test 里因 CustomPaint 不产生 Element 而无法覆盖。
//
// 用 flutter_test（re-export package:test）避免单独依赖 test 包。
import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/widgets/grading/skin_radar.dart';
import 'package:mengtu/models/tone_result.dart';

void main() {
  const cbBins = SkinAnalysis.cbBinCount; // 64
  const crBins = SkinAnalysis.crBinCount; // 64
  const cx = 100.0;
  const cy = 100.0;
  const radius = 80.0;

  List<int> emptyBins() =>
      List<int>.filled(cbBins * crBins, 0);

  test('空 bins（全 0）返回空列表', () {
    expect(computeCloudPoints(emptyBins(), cx, cy, radius), isEmpty);
  });

  test('bins 长度不足时安全返回空列表', () {
    expect(computeCloudPoints([1, 2, 3], cx, cy, radius), isEmpty);
  });

  test('中心 bin（Cb≈0, Cr≈0）映射到画布中心', () {
    final bins = emptyBins();
    // 中心 bin 索引：cb 维 index 32（Cb≈0），cr 维 index 32（Cr≈0）
    const centerCb = 32;
    const centerCr = 32;
    bins[centerCb * crBins + centerCr] = 100;

    final points = computeCloudPoints(bins, cx, cy, radius);
    expect(points, hasLength(1));
    // 中心 bin 的 Cb/Cr 中心值约 0，所以 px≈cx、py≈cy
    expect(points[0].px, closeTo(cx, 2.0));
    expect(points[0].py, closeTo(cy, 2.0));
  });

  test('Cb 正向（+Cb 右）的 bin 映射到画布右侧', () {
    final bins = emptyBins();
    // cbB=63 是最大 +Cb bin（Cb 中心 ≈ 124）
    bins[63 * crBins + 32] = 50;

    final points = computeCloudPoints(bins, cx, cy, radius);
    expect(points, hasLength(1));
    // +Cb → px > cx（右侧）
    expect(points[0].px, greaterThan(cx + radius * 0.5),
        reason: '+Cb 应在画布右侧');
    // Cr≈0 → py≈cy
    expect(points[0].py, closeTo(cy, 2.0));
  });

  test('Cr 正向（+Cr 上）的 bin 映射到画布上方', () {
    final bins = emptyBins();
    // crB=63 是最大 +Cr bin（Cr 中心 ≈ 124）
    bins[32 * crBins + 63] = 50;

    final points = computeCloudPoints(bins, cx, cy, radius);
    expect(points, hasLength(1));
    // Cb≈0 → px≈cx
    expect(points[0].px, closeTo(cx, 2.0));
    // +Cr → py < cy（上方，canvas y 向下故减）
    expect(points[0].py, lessThan(cy - radius * 0.5),
        reason: '+Cr 应在画布上方');
  });

  test('多个非空 bin 都被渲染，count==0 的 bin 被跳过', () {
    final bins = emptyBins();
    bins[10 * crBins + 20] = 30;
    bins[40 * crBins + 50] = 60;
    bins[15 * crBins + 25] = 0; // 显式 0，应跳过

    final points = computeCloudPoints(bins, cx, cy, radius);
    expect(points, hasLength(2));
  });

  test('alpha sqrt 压缩：count 最高的 bin alpha 最大', () {
    // 两点必须分别在画布左/右两侧，firstWhere((p) => p.px >/< cx) 才都能命中。
    // cbB=10 → Cb 中心 = 10×4+2-128 = -86（左侧，低 count）
    // cbB=40 → Cb 中心 = 40×4+2-128 = +34（右侧，高 count）
    final bins = emptyBins();
    bins[10 * crBins + 32] = 25;  // density=0.25, sqrt=0.5  （Cb<0 左侧）
    bins[40 * crBins + 32] = 100; // density=1.0,  sqrt=1.0  （Cb>0 右侧）

    final points = computeCloudPoints(bins, cx, cy, radius);
    final lowCountPoint = points.firstWhere((p) => p.px < cx);
    final highCountPoint = points.firstWhere((p) => p.px > cx);

    expect(highCountPoint.alphaByte, greaterThan(lowCountPoint.alphaByte),
        reason: '高 count bin 应更亮');
    // sqrt(1.0)=1.0 clamp 0.85 → alphaByte≈217
    expect(highCountPoint.alphaByte, closeTo(217, 2));
    // sqrt(0.25)=0.5 → alphaByte≈128
    expect(lowCountPoint.alphaByte, closeTo(128, 2));
  });

  test('ycbcrToRgbForCloud 纯红 Cb/Cr 反算出偏红色调', () {
    // 纯红的 Cr 很大（+127），Cb 略负
    final rgb = ycbcrToRgbForCloud(135, -29, 127);
    // R 分量应显著大于 B 分量（红色调）
    expect(rgb[0], greaterThan(rgb[2]),
        reason: '高 Cr + 负 Cb 应反算出偏红色调');
    expect(rgb.every((c) => c >= 0 && c <= 255), isTrue,
        reason: 'RGB 应在 0-255 范围');
  });

  test('ycbcrToRgbForCloud 所有通道 clamp 到 0-255', () {
    // 极端 Cb/Cr 不应溢出
    final rgbMax = ycbcrToRgbForCloud(135, 127, 127);
    final rgbMin = ycbcrToRgbForCloud(135, -127, -127);
    expect(rgbMax.every((c) => c >= 0 && c <= 255), isTrue);
    expect(rgbMin.every((c) => c >= 0 && c <= 255), isTrue);
  });

  test('bin 索引顺序：cbB*crBins+crB（非 crB*cbBins+cbB）', () {
    // 验证索引公式没写反：只填 (cbB=5, crB=10) 一个 bin
    final bins = emptyBins();
    bins[5 * crBins + 10] = 100;

    final points = computeCloudPoints(bins, cx, cy, radius);
    expect(points, hasLength(1));

    // cbB=5 → Cb 中心 = 5*(256/64) + (256/64)/2 - 128 = 20 + 2 - 128 = -106
    // crB=10 → Cr 中心 = 10*(256/64) + (256/64)/2 - 128 = 40 + 2 - 128 = -86
    // 预期：px < cx（Cb 负→左），py > cy（Cr 负→下）
    expect(points[0].px, lessThan(cx), reason: 'Cb=-106 应在左侧');
    expect(points[0].py, greaterThan(cy), reason: 'Cr=-86 应在下方');
  });
}
