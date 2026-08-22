# 萌图 - AI Agent 开发指引

> 本文件是 AI 编程助手（Hermes/Copilot/Cursor 等）在参与萌图项目开发时必须遵循的规范和上下文。

## 项目概述

萌图是一款面向摄影爱好者的**照片灵感收集与调色参考工具**，核心功能：
1. 批量导入收藏的人像照片，瀑布流浏览
2. 调色分析：RGB/亮度直方图、色卡提取、一键黑白、影调分析
3. 手动标签分类（氛围/场景/情绪/自定义）

**技术栈：** Flutter + Riverpod 3.x + drift (SQLite) + image 包 + material_color_utilities
**目标平台：** Android（优先）→ Windows（二期）
**详细需求：** 参见 [PRD.md](./PRD.md)
**开发计划：** 参见 [DEVPLAN.md](./DEVPLAN.md)

## 当前开发状态（v1.0.0 RC）

### 已完成
- ✅ §1.1 项目初始化（Flutter 3.44 + Riverpod 3.x + drift + CI/CD）
- ✅ §1.2 数据层（drift 3表 + 2 DAO + build_runner）
- ✅ §1.3 照片导入（SHA256 去重 + Isolate 缩略图）
- ✅ §1.4 瀑布流浏览（MasonryGridView + StreamProvider 自动刷新）
- ✅ §1.5 照片详情（InteractiveViewer + 展开/收起式分析面板）
- ✅ §1.6 直方图（RGB三通道叠加 + 亮度 Rec.709 + CustomPainter + 缓存）
- ✅ §1.7 一键黑白（ColorFiltered Rec.709 灰度矩阵）
- ✅ §1.8 标签基础 + 搜索（tag CRUD + 按标签名搜索 + 分组管理）
- ✅ §2.2 色卡提取（QuantizerCelebi + Score + 占比归一化 + 缓存）
- ✅ §3.1 影调分析（三区域占比 + 基调判定 + 统计指标 + 缓存）
- ✅ §3.2 色彩占比（色块宽度按占比动态分配）
- ✅ §3.4 设置页面（存储统计 + 清理缓存 + 关于）
- ✅ §4.1 MMCQ + K-Means 算法（三种算法可切换 + 数量可调节 3-8）
- ✅ §4.2 色相直方图（360 bins HSV + 彩虹色条 + DB schemaVersion v3）

### 待开发
- ⬜ Phase 5 (v1.1.0)：Windows 适配 + 开源发布

## 开发环境

```bash
# Flutter SDK
export PATH="/opt/flutter/bin:$PATH"
flutter --version  # 3.44.2+ / Dart 3.12+

# 代码生成（修改 DAO/表结构后必须执行）
dart run build_runner build

# 分析和测试
dart analyze
flutter test
```

## 关键依赖（pubspec.yaml）

| 依赖 | 版本 | 说明 |
|------|------|------|
| flutter_riverpod | ^3.3.0 | 状态管理（Riverpod 3.x，**不含 StateProvider**） |
| riverpod_annotation | ^4.0.0 | Riverpod 注解 |
| drift | ^2.15.0 | SQLite ORM |
| sqlite3_flutter_libs | ^0.5.0 | drift 原生库 |
| image | ^4.9.1 | 图片解码+像素操作 |
| material_color_utilities | ^0.13.0 | Google 色彩算法（QuantizerCelebi+Score） |
| wechat_assets_picker | ^10.1.2 | 微信风格图片多选 |
| photo_manager | ^3.9.0 | 相册管理 |
| flutter_staggered_grid_view | ^0.7.0 | 瀑布流 |
| uuid | ^4.0.0 | ID 生成 |
| path_provider | ^2.0.0 | 应用目录 |
| path | ^1.8.0 | 路径工具 |

dev_dependencies: drift_dev, riverpod_generator, build_runner, flutter_lints

### Riverpod 3.x 注意事项（重要）

> **Riverpod 3.x 移除了 `StateProvider`、`StateNotifierProvider`、`FamilyNotifierProvider` 等 API。**

- 全局简单状态：用 `Notifier` + `NotifierProvider` 替代 `StateProvider`
- Family 参数化状态：用回调参数传递（Widget state），**不要**试图找 Riverpod 3.x 的 family notifier API
- StreamProvider / FutureProvider / NotifierProvider 正常可用
- `StreamProvider.family` 正常可用
- 代码生成用 `@riverpod` 注解（本项目 MVP 暂未使用 code gen，手写 provider）

### wechat_assets_picker API

```dart
// 正确的调用方式（v10.x）
final List<AssetEntity>? assets = await AssetPicker.pickAssets(
  context,
  pickerConfig: AssetPickerConfig(  // 注意是 AssetPickerConfig 不是 PickerConfig
    maxAssets: 100,
    requestType: RequestType.image,
  ),
);
```

## 项目结构

```
mengtu/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── models/
│   │   └── tone_result.dart         # HistogramData + ToneResult
│   ├── services/
│   │   ├── database/
│   │   │   ├── app_database.dart    # drift 数据库（schemaVersion=3）
│   │   │   ├── app_database.g.dart   # 自动生成（gitignore）
│   │   │   ├── tables.dart          # 表定义（photos, tags, photo_tags）
│   │   │   └── daos/
│   │   │       ├── photo_dao.dart   # 照片CRUD + watch流（自动刷新）
│   │   │       ├── photo_dao.g.dart  # 自动生成
│   │   │       ├── tag_dao.dart     # 标签CRUD + 关联管理
│   │   │       └── tag_dao.g.dart   # 自动生成
│   │   ├── import_service.dart      # 导入去重+缩略图+删除
│   │   └── histogram_service.dart   # 直方图计算（Isolate）
│   ├── pages/
│   │   ├── home_page.dart           # 首页瀑布流+导入+搜索
│   │   ├── detail_page.dart         # 照片详情+黑白+缩放
│   │   └── tag_manage_page.dart     # 标签管理（分组显示）
│   ├── widgets/
│   │   ├── photo_card.dart          # 瀑布流卡片
│   │   ├── histogram_painter.dart   # 直方图 CustomPainter
│   │   └── analysis_panel.dart      # 展开/收起式分析面板
│   ├── providers/
│   │   ├── database_provider.dart   # AppDatabase + ImportService 单例
│   │   ├── photo_provider.dart      # 照片流（StreamProvider 自动刷新）
│   │   ├── tag_provider.dart        # 标签流 + 操作
│   │   └── analysis_provider.dart   # 直方图计算+缓存
│   └── utils/
│       ├── color_utils.dart         # RGB↔HSL, Rec.709 灰度
│       ├── file_hash.dart           # 纯Dart SHA256
│       └── image_utils.dart         # 缩略图生成
├── android/
│   ├── app/
│   │   ├── build.gradle.kts         # namespace=com.mengtu.app, minSdk=26, 固定debug签名
│   │   ├── debug.keystore            # 固定签名（仓库内，保证CI签名一致）
│   │   └── src/main/
│   │       ├── AndroidManifest.xml  # READ_MEDIA_IMAGES 权限
│   │       └── kotlin/com/mengtu/app/MainActivity.kt
│   └── ...
├── test/
│   └── widget_test.dart             # color_utils 单元测试
├── .github/workflows/build.yml      # CI: build_runner → analyze → test → APK
├── AGENTS.md                        # 本文件
├── PRD.md                           # 产品需求文档
├── DEVPLAN.md                       # 开发计划
└── pubspec.yaml
```

## 编码规范

### 通用
- 文件命名 snake_case，类命名 PascalCase，私有成员下划线前缀
- 每个文件顶部添加简要注释说明模块职责
- `dart analyze` 必须 0 issues（包括 info 级别，否则 CI 挂）

### 状态管理（Riverpod 3.x）
- UI 层只通过 `ref.watch()` 消费状态，不直接调用 service
- 列表自动刷新：用 `StreamProvider` + drift `watch()` 而非 `FutureProvider`
- 全局简单状态：用 `Notifier` + `NotifierProvider`（**不是 StateProvider**）
- Family 参数化：避免使用 family notifier API，改用 Widget state + 回调

### 数据库（drift）
- 表定义在 `tables.dart`，DAO 按业务拆分
- 修改表结构/DAO 后必须执行：`dart run build_runner build`
- `*.g.dart` 被 gitignore，CI 里通过 build_runner 生成
- DAO 注解中的 tables 列表必须包含所有 join 涉及的表

### 性能关键路径（必须在 Isolate 中执行）
- 直方图计算：`compute()` 函数
- 图片哈希：`compute()` 函数
- 缩略图生成：`compute()` 函数
- 使用 `image` 包的 `decodeImage()` + `copyResize()`

### 图片处理
- 缩略图长边 360px，JPEG quality 85
- 直方图降采样 step=4
- 一键黑白用 `ColorFiltered` widget，不修改原图
- Rec.709 灰度系数：0.2126R + 0.7152G + 0.0722B

### 分析面板布局
- **不使用 `DraggableScrollableSheet`**（真机上与 InteractiveViewer 手势冲突）
- 改用 `AnimatedContainer` + 展开/收起按钮
- 黑白状态通过 Widget state + 回调传递（不使用 Riverpod family provider）

## Android 配置

- 包名：`com.mengtu.app`
- 最低版本：API 26（Android 8.0）
- **ABI 过滤：仅 `arm64-v8a`**（目标设备均为 ARM64，砍掉 armeabi-v7a/x86_64 约减 80MB）
- 权限：`READ_MEDIA_IMAGES`（API 33+）, `READ_EXTERNAL_STORAGE`（旧版）
- MainActivity 路径必须与 namespace 一致：`kotlin/com/mengtu/app/`
- `requestLegacyExternalStorage="true"` 兼容旧版分区存储
- **固定 debug 签名**：`debug.keystore` 在仓库中，CI 每次构建签名一致可覆盖安装

## CI/CD

**所有编译打包通过 GitHub Actions 完成，不在本地执行 `flutter build`。**

CI 流程（`.github/workflows/build.yml`）：
1. `flutter pub get`
2. `dart run build_runner build`（代码生成）
3. `flutter analyze`（必须 0 issues）
4. `flutter test`
5. `flutter test --coverage`（生成 lcov 覆盖率报告）
6. Upload coverage artifact
7. `flutter build apk --debug`（push 触发）
8. Upload APK artifact

本地只做：代码编辑 + `dart run build_runner build`（代码生成）+ `dart analyze` + `flutter test`

## Git 工作流

- **分支策略：** feature 分支 → PR → main
- **Commit 消息：** 中文描述 + 范围前缀
- **不要直接推 main 分支**（开发阶段暂时直接推，正式版走 PR）

## 已踩过的坑（防再次踩中）

1. **Riverpod 3.x 删了 StateProvider** — 用 Notifier 替代
2. **wechat_assets_picker API** — `AssetPickerConfig` 不是 `PickerConfig`，参数名是 `pickerConfig:`
3. **drift selectOnly 聚合** — 用 `getSingle()` 不是 `get()`，返回的是 `TypedResult`
4. **`*.g.dart` 被 gitignore** — CI 必须跑 `dart run build_runner build`
5. **`flutter analyze` 对 info 级别也返回 exit 1** — CI 里需要修掉所有 info
6. **MainActivity 包路径** — flutter create 默认 `com.xxx.xxx`，改 namespace 后必须同步移动 .kt 文件
7. **DraggableScrollableSheet** — 在 Stack 里与 InteractiveViewer 冲突，改用展开/收起
8. **FutureProvider 不自动刷新** — 列表数据用 StreamProvider + drift watch()

## 测试系统

### 测试结构
```
test/
├── algorithms/
│   ├── mmcq_test.dart             # MMCQ 中位数切分算法
│   ├── kmeans_test.dart           # K-Means++ 聚类算法
│   └── hue_test.dart              # rgbToHue HSV 色相计算
├── unit/
│   ├── color_utils_test.dart      # RGB↔HSL 转换、Rec.709 灰度值、HEX 转换
│   ├── histogram_service_test.dart # 直方图计算、降采样、RGB/亮度通道分离、一致性
│   ├── file_hash_test.dart        # SHA256 文件哈希一致性、空文件、大文件
│   ├── tone_result_test.dart      # HistogramData 序列化（Uint16List）、ToneResult JSON
│   ├── tone_service_test.dart     # 影调分析统计量、基调判定、跨度判定、标签映射
│   └── palette_result_test.dart   # PaletteColor/PaletteResult 序列化往返
├── dao/
│   ├── photo_dao_test.dart        # CRUD、按标签查询、stream 刷新、外键级联、缓存更新、统计
│   └── tag_dao_test.dart          # CRUD、按分组查询、photo_tags 关联、批量打标签、stream
├── integration/
│   ├── import_flow_test.dart      # 导入去重、缩略图生成、失败清理、文件清理
│   └── analysis_flow_test.dart    # 导入→直方图→缓存→二次读取 全链路、影调判定、色卡提取
└── widget/
    ├── photo_card_test.dart       # 卡片渲染（用 IgnorePointer 包裹避免手势）
    ├── histogram_painter_test.dart # RGB 模式渲染验证
    └── analysis_panel_test.dart   # ToneInfoCard 渲染（基调标签/三区域/统计指标/跨度标签）
```

### 测试规范
- drift DAO 测试用内存数据库（`drift/native` + `:memory:`）
- Isolate 测试在 flutter_test 环境自动降级为同步执行
- 每个测试文件独立，不依赖执行顺序
- mock 外部依赖（文件系统路径用临时目录）
- 测试命名：`方法名_场景_预期结果`
- widget 测试用 `ProviderScope` 包裹 + `driftMemoryDb()` 内存数据库 override

### 运行命令
```bash
# 全量测试
flutter test

# 带覆盖率
flutter test --coverage

# 指定目录
flutter test test/unit/
flutter test test/dao/
flutter test test/widget/
flutter test test/integration/
flutter test test/algorithms/
```

### CI 覆盖率
- build.yml 已集成 `flutter test --coverage`
- lcov 报告上传为 artifact
- 核心 service/utils 层覆盖率 ≥ 80%

## 许可证合规

- 算法实现参考 MIT 许可的 color-thief
- 取色卡 Color_Card（GPL-3.0）仅做功能设计参考，不参考其代码
- Rec.709 亮度公式是 ITU 公开标准
- material_color_utilities 是 Apache 2.0

## 注意事项

1. **纯本地应用**，不联网，不收集用户数据
2. **照片数量 ≤ 1000**，性能优化以此为基准
3. **Android 最低 API 26**（Android 8.0）
4. 所有删除操作需二次确认
