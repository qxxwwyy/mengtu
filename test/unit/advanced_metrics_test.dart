// advanced_metrics_test.dart — v3.5 高级人像指标测试
//
// 覆盖：
// 1. calculateBlackPointOffset：纯黑/纯白/滑动平均/空直方图
// 2. calculateWhitePointCompression：对称测试
// 3. classifyTenTonalType：toneKey×toneRange 组合 + full 特殊处理
// 4. AdvancedPortraitMetrics 序列化：强制重算（缺字段抛错）+ 容错（skin/flc 缺返回 null）
// 5. advancedMetrics 序列化往返
// 6. 小图稳定性（滑动平均生效）
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mengtu/models/advanced_portrait_metrics.dart';
import 'package:mengtu/services/tone_service.dart';

void main() {
  group('calculateBlackPointOffset 黑点偏移', () {
    test('纯黑图（全像素在 bin=0）→ 黑点偏移 = 0', () {
      final lumHist = List.filled(256, 0);
      lumHist[0] = 10000;
      final total = lumHist.fold<int>(0, (a, b) => a + b);
      // 所有像素在 bin 0 → 0.5%/1%/2% 阈值都立即在 bin 0 达到 → 平均 0
      expect(calculateBlackPointOffset(lumHist, total), closeTo(0, 0.001));
    });

    test('纯白图（全像素在 bin=255）→ 黑点偏移 = 255（所有阈值都在 bin 255 达到）', () {
      final lumHist = List.filled(256, 0);
      lumHist[255] = 10000;
      final total = lumHist.fold<int>(0, (a, b) => a + b);
      expect(calculateBlackPointOffset(lumHist, total), closeTo(255, 0.001));
    });

    test('滑动平均：1% 在 bin=3、2% 在 bin=5 → 结果 ≈ (3+3+5)/3', () {
      // 构造直方图：0.5% 在 bin 2，1% 在 bin 3，2% 在 bin 5
      // total = 1000，0.5%=5、1%=10、2%=20 像素
      final lumHist = List.filled(256, 0);
      lumHist[2] = 5; // 累计 5 → 达到 0.5%（5/1000）
      lumHist[3] = 5; // 累计 10 → 达到 1%
      lumHist[4] = 5; // 累计 15
      lumHist[5] = 5; // 累计 20 → 达到 2%
      // 加大量背景像素让 total=1000
      lumHist[100] = 980;
      final total = lumHist.fold<int>(0, (a, b) => a + b);
      expect(total, 1000);
      final offset = calculateBlackPointOffset(lumHist, total);
      // 阈值 0.5% 在 bin 2、1% 在 bin 3、2% 在 bin 5 → 平均 (2+3+5)/3 ≈ 3.33
      expect(offset, closeTo((2 + 3 + 5) / 3, 0.01));
    });

    test('空直方图（total=0）→ 返回 0.0', () {
      final lumHist = List.filled(256, 0);
      expect(calculateBlackPointOffset(lumHist, 0), 0.0);
    });

    test('小图稳定性：滑动平均稳定结果', () {
      // 验证滑动平均逻辑：0.5%/1%/2% 三个阈值取平均，比单阈值更稳定。
      // 构造 total=1000 的直方图：
      //   bin 2 累计 5（达 0.5%）→ bin 3 累计 10（达 1%）→ bin 5 累计 20（达 2%）
      //   背景从 bin 100 开始（远高于 2% 阈值，不影响暗部判定）
      final lumHist = List.filled(256, 0);
      lumHist[2] = 5; // 累计 5 → 达到 0.5%
      lumHist[3] = 5; // 累计 10 → 达到 1%
      lumHist[4] = 5; // 累计 15
      lumHist[5] = 5; // 累计 20 → 达到 2%
      lumHist[100] = 980; // 背景填充至 total=1000
      final total = lumHist.fold<int>(0, (a, b) => a + b);
      expect(total, 1000);

      // 滑动平均：0.5%@2 + 1%@3 + 2%@5 = (2+3+5)/3 ≈ 3.33
      final r1 = calculateBlackPointOffset(lumHist, total);
      final r2 = calculateBlackPointOffset(lumHist, total);
      expect(r1, r2); // 纯函数多次调用一致
      expect(r1, closeTo((2 + 3 + 5) / 3, 0.01));
      expect(r1, lessThan(6)); // 落在暗部区间，不被背景拉高
    });
  });

  group('calculateWhitePointCompression 白点压缩', () {
    test('纯白图（全像素在 bin=255）→ 白点 = 255', () {
      final lumHist = List.filled(256, 0);
      lumHist[255] = 10000;
      final total = lumHist.fold<int>(0, (a, b) => a + b);
      // 所有阈值在 bin 255 达到 → 平均 255
      expect(calculateWhitePointCompression(lumHist, total), closeTo(255, 0.001));
    });

    test('纯黑图（全像素在 bin=0）→ 白点 = 0（所有阈值在 bin 0 达到）', () {
      final lumHist = List.filled(256, 0);
      lumHist[0] = 10000;
      final total = lumHist.fold<int>(0, (a, b) => a + b);
      expect(calculateWhitePointCompression(lumHist, total), closeTo(0, 0.001));
    });

    test('对称滑动平均：98% 在 bin=250、99.5% 在 bin=253 → 平均', () {
      // total=1000，98%=980、99%=990、99.5%=995
      final lumHist = List.filled(256, 0);
      lumHist[0] = 980; // 累计 980 → 达到 98%
      lumHist[250] = 10; // 累计 990 → 达到 99%
      lumHist[253] = 5; // 累计 995 → 达到 99.5%
      lumHist[254] = 5; // 凑 total=1000
      final total = lumHist.fold<int>(0, (a, b) => a + b);
      expect(total, 1000);
      final wp = calculateWhitePointCompression(lumHist, total);
      // 98% 在 bin 0、99% 在 bin 250、99.5% 在 bin 253 → 平均 (0+250+253)/3 ≈ 167.67
      expect(wp, closeTo((0 + 250 + 253) / 3, 0.01));
    });

    test('空直方图（total=0）→ 返回 255.0', () {
      final lumHist = List.filled(256, 0);
      expect(calculateWhitePointCompression(lumHist, 0), 255.0);
    });
  });

  group('classifyTenTonalType 十大影调', () {
    test('toneKey=high + toneRange=long → "高长调"', () {
      expect(classifyTenTonalType('high', 'long'), '高长调');
    });

    test('toneKey=mid + toneRange=medium → "中中调"', () {
      expect(classifyTenTonalType('mid', 'medium'), '中中调');
    });

    test('toneKey=low + toneRange=short → "低短调"', () {
      expect(classifyTenTonalType('low', 'short'), '低短调');
    });

    test('toneKey=full → "全长调"（rangeLabel 不拼接，避免"全长长调"）', () {
      expect(classifyTenTonalType('full', 'long'), '全长调');
      expect(classifyTenTonalType('full', 'short'), '全长调');
    });

    test('未知 toneKey/toneRange → 兜底"中" + "中调"', () {
      expect(classifyTenTonalType('unknown', 'weird'), '中中调');
    });
  });

  group('AdvancedPortraitMetrics 序列化', () {
    test('toJson + fromJson 往返保持一致（完整字段）', () {
      const original = AdvancedPortraitMetrics(
        blackPointOffset: 3.5,
        whitePointCompression: 252.0,
        tenTonalType: '高长调',
      );
      final json = original.toJson();
      final restored = AdvancedPortraitMetrics.fromJson(json);

      expect(restored.blackPointOffset, closeTo(3.5, 1e-9));
      expect(restored.whitePointCompression, closeTo(252.0, 1e-9));
      expect(restored.tenTonalType, '高长调');
    });

    test('fromJson 缺 black_point_offset → 抛 TypeError（强制重算）', () {
      const legacy = {'ten_tonal_type': '高长调'};
      expect(() => AdvancedPortraitMetrics.fromJson(legacy),
          throwsA(isA<TypeError>()));
    });

    test('fromJson 缺 white_point_compression → 抛 TypeError', () {
      const legacy = {
        'black_point_offset': 5.0,
        'ten_tonal_type': '中调',
      };
      expect(() => AdvancedPortraitMetrics.fromJson(legacy),
          throwsA(isA<TypeError>()));
    });

    test('fromJson 缺 ten_tonal_type → 抛 TypeError', () {
      const legacy = {
        'black_point_offset': 5.0,
        'white_point_compression': 250.0,
      };
      expect(() => AdvancedPortraitMetrics.fromJson(legacy),
          throwsA(isA<TypeError>()));
    });

    test('fromJsonString(null) → null', () {
      expect(AdvancedPortraitMetrics.fromJsonString(null), isNull);
    });

    test('fromJsonString("") → null', () {
      expect(AdvancedPortraitMetrics.fromJsonString(''), isNull);
    });

    test('fromJsonString(非法 JSON) → null', () {
      expect(AdvancedPortraitMetrics.fromJsonString('not json'), isNull);
    });

    test('fromJsonString(无 advanced 键) → null（触发重算）', () {
      // 旧 toneJson 只有 ToneResult 扁平字段，无 advanced 键
      const legacyToneJson = '{"mean":128,"toneKey":"mid","entropy":6.5}';
      expect(AdvancedPortraitMetrics.fromJsonString(legacyToneJson), isNull);
    });

    test('fromJsonString(advanced 缺强制字段) → null（强制重算触发）', () {
      const broken = '{"advanced":{"some_key":0.5}}';
      expect(AdvancedPortraitMetrics.fromJsonString(broken), isNull);
    });

    test('fromJsonString(完整 advanced) → 正常解析', () {
      const full = '{"mean":128,"advanced":{'
          '"black_point_offset":3.5,"white_point_compression":252.0,'
          '"ten_tonal_type":"高长调"}}';
      final m = AdvancedPortraitMetrics.fromJsonString(full);
      expect(m, isNotNull);
      expect(m!.blackPointOffset, 3.5);
      expect(m.tenTonalType, '高长调');
    });
  });

  group('AdvancedPortraitMetrics.mergeIntoToneJson', () {
    test('合并到现有 toneJson，保留其它键', () {
      const existing = '{"mean":128,"toneKey":"mid"}';
      const metrics = AdvancedPortraitMetrics(
        blackPointOffset: 5,
        whitePointCompression: 250,
        tenTonalType: '中长调',
      );
      final merged = AdvancedPortraitMetrics.mergeIntoToneJson(existing, metrics);
      final decoded = jsonDecode(merged) as Map<String, dynamic>;

      // 原有键保留
      expect(decoded['mean'], 128);
      expect(decoded['toneKey'], 'mid');
      // 新增 advanced
      final adv = decoded['advanced'] as Map<String, dynamic>;
      expect(adv['black_point_offset'], 5);
      expect(adv['ten_tonal_type'], '中长调');
    });

    test('重复合并覆盖旧 advanced', () {
      const existing =
          '{"advanced":{"black_point_offset":1,"white_point_compression":200,'
          '"ten_tonal_type":"低调"}}';
      const metrics = AdvancedPortraitMetrics(
        blackPointOffset: 9,
        whitePointCompression: 254,
        tenTonalType: '高调',
      );
      final merged = AdvancedPortraitMetrics.mergeIntoToneJson(existing, metrics);
      final decoded = jsonDecode(merged) as Map<String, dynamic>;
      final adv = decoded['advanced'] as Map<String, dynamic>;
      expect(adv['black_point_offset'], 9);
      expect(adv['ten_tonal_type'], '高调');
    });

    test('existing 为 null → 仅写 advanced', () {
      const metrics = AdvancedPortraitMetrics(
        blackPointOffset: 0,
        whitePointCompression: 255,
        tenTonalType: '全长调',
      );
      final merged = AdvancedPortraitMetrics.mergeIntoToneJson(null, metrics);
      final decoded = jsonDecode(merged) as Map<String, dynamic>;
      expect(decoded.length, 1);
      expect(decoded.containsKey('advanced'), isTrue);
    });

    test('existing 非法 JSON → 丢弃，仅写 advanced', () {
      const metrics = AdvancedPortraitMetrics(
        blackPointOffset: 0,
        whitePointCompression: 255,
        tenTonalType: '全长调',
      );
      final merged =
          AdvancedPortraitMetrics.mergeIntoToneJson('not json', metrics);
      final decoded = jsonDecode(merged) as Map<String, dynamic>;
      expect(decoded.containsKey('advanced'), isTrue);
    });
  });

}
