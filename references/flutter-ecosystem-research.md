# Flutter/Dart 生态代码调研报告

> 萌图项目筹备阶段调研，2026-06-11

---

## 一、关键发现

### ⚠️ palette_generator 已废弃
- Flutter 官方的 `palette_generator` 包状态已变为 **DISCONTINUED（已废弃）**
- 原PRD和DEVPLAN中MVP阶段依赖此包，必须更换方案
### ⚠️ colorgram 包（已被 material_color_utilities 替代）

> **更新（2026-06-11）：** colorgram 已被 `material_color_utilities` 替代。Google 官方库（2.2K stars，559万周下载，Apache 2.0）提供了更科学的 `QuantizerCelebi` 量化算法 + HCT 色彩空间。以下 colorgram 信息仅作历史记录。

- pub.dev: https://pub.dev/packages/colorgram (v2.0.0)
- GitHub: https://github.com/fisherman-23/colorgram-dart (9 stars)
- 基于 colorgram.js 的 Dart 移植，使用相对亮度+HSL聚类
- 返回 CgColor(r, g, b, percentage)，含占比
- 性能：512x512 JPEG ~30ms, 5120x1440 ~200ms
- API：`extractColor(ImageProvider, count)` 一行调用

### ✅ wechat_assets_picker（推荐替代 image_picker）
- pub.dev: https://pub.dev/packages/wechat_assets_picker (v10.1.2, 866 likes)
- GitHub: https://github.com/fluttercandies/flutter_wechat_assets_picker (1.6K stars)
- 许可证: Apache-2.0
- 微信风格多选、预览、原图选择
- 底层 photo_manager 提供相册管理API
- 活跃维护，替代 image_picker 的最佳方案

### ✅ flutter_staggered_grid_view
- v0.7.0, 4.7K likes, 3.2K stars, MIT
- 2年未更新，需测试兼容性
- MasonryGridView.count 用于瀑布流

### ℹ️ 直方图无现成包
- 需基于 image 包自行实现
- image 包提供像素遍历 API 和 Command API (支持 executeThread 在 Isolate 中执行)

---

## 二、推荐的依赖变更

| 原方案 | 问题 | 推荐替代 |
|--------|------|----------|
| `palette_generator` | 已废弃(DISCONTINUED) | `colorgram` v2.0.0 |
| `image_picker` | 功能简陋，不支持批量选择 | `wechat_assets_picker` v10.1.2 |

推荐 pubspec.yaml:
```yaml
dependencies:
  flutter: sdk: flutter
  flutter_riverpod: ^3.3         # Riverpod 3.x（替代旧版 riverpod: ^2.5）
  drift: ^2.15
  image: ^4.9.1
  material_color_utilities: ^0.13.0  # 替代 colorgram（Google 官方，Apache 2.0）
  wechat_assets_picker: ^10.1.2  # 替代 image_picker
  photo_manager: ^3.9.0          # wechat_assets_picker 依赖
  flutter_staggered_grid_view: ^0.7.0
  uuid: ^4.0
  path_provider: ^2.0
  path: ^1.8
```

---

## 三、各方案详情

### colorgram 核心用法
```dart
import 'package:colorgram/colorgram.dart';

// 缩小图片提升性能
ImageProvider provider = FileImage(File('photo.jpg'));
List<CgColor> colors = await extractColor(
  ResizeImage(provider, height: 200, width: 200),
  5,  // 提取5个主色
);
// CgColor.r, .g, .b, .percentage
```

### wechat_assets_picker 核心用法
```dart
final List<AssetEntity>? assets = await AssetPicker.pickAssets(
  context,
  pickerConfig: AssetPickerConfig(
    maxAssets: 50,
    requestType: RequestType.image,
  ),
);
```

### 直方图实现参考
```dart
import 'package:image/image.dart' as img;

Map<String, List<int>> computeHistogram(img.Image image) {
  final rHist = List<int>.filled(256, 0);
  final gHist = List<int>.filled(256, 0);
  final bHist = List<int>.filled(256, 0);
  for (var pixel in image) {
    rHist[pixel.r.toInt()]++;
    gHist[pixel.g.toInt()]++;
    bHist[pixel.b.toInt()]++;
  }
  return {'r': rHist, 'g': gHist, 'b': bHist};
}
```
