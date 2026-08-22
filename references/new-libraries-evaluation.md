# 新发现可参考项目/库评估

> 萌图项目补充调研，2026-06-11

---

## 🔴 高价值

### 1. material_color_utilities（Google 官方）⭐⭐⭐⭐⭐

- **pub.dev**: https://pub.dev/packages/material_color_utilities (v0.13.0, 278 likes, **559万周下载**)
- **GitHub**: https://github.com/material-foundation/material-color-utilities (**2.2K stars**)
- **许可证**: **Apache 2.0** ✅
- **发布者**: Google Material 官方 (material.io)
- **维护状态**: 活跃（2个月前更新）

**核心 API 已确认存在：**
- `QuantizerCelebi.quantize(Iterable<int> pixels, int maxColors)` — 两步量化（Wu量化 + WSmeans聚类）
- `Score.score()` — 基于 HCT 色彩空间的主色评分筛选
- `HCT` 色彩空间（Hue-Chroma-Tone，比 HSL 更符合人眼感知）
- `contrast` 对比度检查
- `palettes` 调色板生成
- `temperature` 色温
- `dislike` 不喜欢色检测

**对萌图的价值：**
- **替代 colorgram 作为色卡提取核心算法**（Google 维护、Apache 2.0、更科学的算法）
- HCT 色彩空间可用于色卡展示和色温分析
- 559万周下载量说明生产级可靠性

**使用方式：**
```dart
import 'package:material_color_utilities/material_color_utilities.dart';

// 提取主色
final result = await QuantizerCelebi().quantize(pixels, 5);
final scored = Score.score(result.colorToCount);
```

### 2. Immich Mobile（Flutter 大型照片管理项目）⭐⭐⭐⭐

- **GitHub**: https://github.com/immich-app/immich (**86,400+ stars**)
- **技术栈确认**: Flutter + **hooks_riverpod ^2.6.1** + **drift ^2.32.1**
- **许可证**: **AGPL-3.0**（不能复制代码，架构设计可参考）

**参考价值：**
- drift 数据库表结构和 DAO 组织方式
- Riverpod Provider 组织方式（不过 Immich 用的是 hooks_riverpod 2.x，不是 3.x）
- Isolate 处理媒体任务
- 分层架构设计

**局限：**
- Immich 是服务端同步架构，大量代码是网络/API相关，萌图是纯本地应用
- AGPL-3.0 限制，只能参考架构思路

### 3. extended_image（Flutter 图片扩展库）⭐⭐⭐⭐

- **pub.dev**: https://pub.dev/packages/extended_image
- **GitHub**: https://github.com/fluttercandies/extended_image
- **核心能力**: 手势缩放/平移、图片编辑、缓存管理、ExtendedImageGallery 左右滑动切换
- **对萌图的价值**: 详情页"双指缩放 + 左右滑动切换"可直接用，省去自己实现手势
- **注意**: 会增加依赖，MVP 阶段可先用 InteractiveViewer + PageView（Flutter 内置），后期如果体验不够好再切换

---

## 🟡 中等价值

### 4. fl_chart（图表库）
- 源码可参考坐标轴绘制、数据归一化、触摸交互，但 PRD 要求 CustomPainter 自绘
- **建议**: 不引入依赖，但开发直方图时可以看看它的源码思路

### 5. color_extractor（C FFI 色彩提取）
- 3 stars，风险太大
- material_color_utilities 已经是更好的选择

### 6. photo_manager
- wechat_assets_picker 底层已依赖，无需单独引入
- 如果需要 EXIF 信息或按文件夹导入，可以直接用 photo_manager API

---

## 📋 技术选型变更建议

| 原方案 | 新建议 | 理由 |
|--------|--------|------|
| `colorgram` ^2.0.0 (9 stars) | `material_color_utilities` ^0.13.0 (2.2K stars, Google) | Google 官方、Apache 2.0、科学算法、559万周下载、HCT 色彩空间 |
