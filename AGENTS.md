# 萌图 - AI Agent 开发指引

> 本文件是 AI 编程助手（Hermes/Copilot/Cursor 等）在参与萌图项目开发时必须遵循的规范和上下文。

## 项目概述

萌图是一款面向摄影爱好者的**照片灵感收集与调色参考工具**，核心功能：
1. 批量导入收藏的人像照片，瀑布流浏览
2. 调色分析：RGB/亮度直方图、色卡提取、一键黑白、影调分析
3. 手动标签分类（氛围/场景/情绪/自定义）

**技术栈：** Flutter + Riverpod 3.x + drift (SQLite) + image 包 + material_color_utilities
**目标平台：** Android（优先）→ Windows（二期）
**详细需求：** 以本文档"已完成"清单 + [README.md](./README.md) 功能列表为准（PRD.md/DEVPLAN.md 未入库）

## 当前开发状态（v1.2.0）

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
- ✅ §3.1 影调分析（**五区域占比**（黑/阴/中/高/白，分界 51/102/153/204）+ 基调判定 + 统计指标 + 缓存）
- ✅ §3.2 色彩占比（色块宽度按占比动态分配）
- ✅ §3.4 设置页面（存储统计 + 清理缓存 + 关于）
- ✅ §4.1 MMCQ + K-Means 算法（三种算法可切换 + 数量可调节 3-8）
- ✅ §4.2 色相直方图（360 bins HSV + 彩虹色条 + DB schemaVersion v3→v5）
- ✅ §5.x CI 体积优化（`--debug` → `--release`，APK 从 ~150MB 降到 ~30MB）

### 待开发
- ⬜ Phase 5 (v1.1.0)：Windows 适配 + 开源发布

## 开发环境

当前开发机为 Windows。Flutter SDK 采用**便携式隔离安装**（不污染系统 PATH，卸载删文件夹即可）。

```bash
# Flutter SDK 激活（每次开新 cmd 窗口执行，临时加入 PATH + 国内镜像）
C:\Users\10492\flutter-sdk-activate.bat
flutter --version  # 3.44.2 / Dart 3.12+

# 卸载 Flutter：删 C:\Users\10492\flutter-sdk 文件夹 + flutter-sdk-activate.bat

# 代码生成（修改 DAO/表结构后必须执行）
dart run build_runner build

# 分析和测试
dart analyze
flutter test
```

激活脚本（`flutter-sdk-activate.bat`）内已配置国内镜像：
- `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- `PUB_HOSTED_URL=https://pub.flutter-io.cn`

> 注：CI 跑在 Ubuntu，用默认 pub.dev，**不要把本地镜像产生的 `pubspec.lock` 变更提交**（只有 url 字段改 pub.dev→pub.flutter-io.cn，是环境噪音）。

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
│   │   │   ├── app_database.dart    # drift 数据库（schemaVersion=5）
│   │   │   ├── app_database.g.dart   # 自动生成（gitignore）
│   │   │   ├── tables.dart          # 表定义（photos, tags, photo_tags, colorPins, albums, albumPhotos）
│   │   │   └── daos/
│   │   │       ├── photo_dao.dart   # 照片CRUD + watch流（自动刷新）
│   │   │       ├── photo_dao.g.dart  # 自动生成
│   │   │       ├── tag_dao.dart     # 标签CRUD + 关联管理
│   │   │       ├── album_dao.dart   # 相册CRUD
│   │   │       ├── color_pin_dao.dart # 取色点CRUD
│   │   │       └── *.g.dart        # 自动生成
│   │   ├── import_service.dart      # 导入去重+缩略图+删除
│   │   ├── histogram_service.dart   # 直方图计算（Isolate）
│   │   ├── tone_service.dart        # 影调分析（5区域占比）
│   │   ├── palette_service.dart     # 色卡提取
│   │   ├── clipping_service.dart    # 高光/阴影溢出警告
│   │   ├── harmony_service.dart     # 配色和谐度
│   │   └── pixel_picker_service.dart # 取色器像素拾取
│   ├── pages/
│   │   ├── home_page.dart           # 首页瀑布流+导入+搜索
│   │   ├── detail_page.dart         # 照片详情+黑白+缩放
│   │   ├── compare_page.dart        # 多图对比
│   │   ├── album_page.dart          # 相册列表
│   │   ├── album_detail_page.dart   # 相册详情
│   │   ├── settings_page.dart       # 设置（存储统计+清理缓存）
│   │   └── tag_manage_page.dart     # 标签管理（分组显示）
│   ├── widgets/
│   │   ├── photo_card.dart          # 瀑布流卡片
│   │   ├── histogram_painter.dart   # 直方图 CustomPainter（5段标注）
│   │   ├── analysis_panel.dart      # 展开/收起式分析面板（高度 340）
│   │   ├── tone_info_card.dart      # 影调 5 区域占比条
│   │   ├── color_card.dart          # 色卡展示
│   │   ├── harmony_card.dart        # 配色和谐度
│   │   ├── color_wheel.dart         # 色轮
│   │   ├── color_picker_loupe.dart  # 取色放大镜
│   │   ├── clipping_overlay.dart    # 溢出警告蒙层
│   │   ├── composition_overlay.dart # 构图辅助线
│   │   └── tone_info_card.dart      # 统计指标网格
│   ├── providers/
│   │   ├── database_provider.dart   # AppDatabase + ImportService 单例
│   │   ├── photo_provider.dart      # 照片流（StreamProvider 自动刷新）
│   │   ├── tag_provider.dart        # 标签流 + 操作
│   │   ├── analysis_provider.dart   # 直方图/影调/色卡计算+缓存
│   │   └── clipping_provider.dart   # 溢出状态
│   └── utils/
│       ├── color_utils.dart         # RGB↔HSL, Rec.709 灰度
│       ├── file_hash.dart           # 纯Dart SHA256
│       └── image_utils.dart         # 缩略图生成
├── algorithms/                      # 取色算法（独立模块）
│   ├── mmcq.dart                    # MMCQ 改进中位切分
│   └── kmeans.dart                  # K-Means++
├── android/
│   ├── app/
│   │   ├── build.gradle.kts         # namespace=com.mengtu.app, minSdk=26, abiFilters=arm64-v8a
│   │   │                             # 签名：CI 环境变量注入（KEYSTORE_*），本地 fallback debug 默认
│   │   └── src/main/
│   │       ├── AndroidManifest.xml  # READ_MEDIA_IMAGES 权限
│   │       └── kotlin/com/mengtu/app/MainActivity.kt
│   └── .gitignore                   # 含 **/*.keystore（keystore 不入库，走 CI secret）
├── test/                            # 测试（17 个文件，分 4 层）
│   ├── algorithms/                  # hue/kmeans/mmcq 算法测试
│   ├── dao/                         # photo_dao/tag_dao 数据层测试
│   ├── integration/                 # analysis_flow/import_flow 全链路测试
│   ├── unit/                        # color_utils/file_hash/histogram/tone 等单元测试
│   ├── widget/                      # analysis_panel/histogram_painter/photo_card Widget 测试
│   └── helpers/test_helpers.dart    # 测试工具（图片生成、DB 创建）
├── .github/workflows/build.yml      # CI: build_runner → analyze → test → release APK
├── AGENTS.md                        # 本文件
├── REVIEW.md                        # 代码审查报告（gitignore，不入库）
├── README.md                        # 项目说明（功能列表 + 技术栈）
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

### 影调分析（5 段划分）
- **分界点**：51 / 102 / 153 / 204（均分 0-255，与直方图视觉分界线对齐）
- **5 段命名**：黑色(blacks 0-51) / 阴影(shadows 52-102) / 中间调(midtones 103-153) / 高光(highlights 154-204) / 白色(whites 205-255)
- **基调判定**：`dark = blacks + shadows`、`light = highlights + whites`，两端占比都 >15% 即全长调（合并段判定，单看 shadows/highlights 会漏判高对比图）
- **缓存兼容**：旧 3 段 JSON 缺 blacks/whites 键 → `fromJson` 强转抛 TypeError → `fromJsonString` 的 try/catch 兜底返回 null → provider 自动重算，**无需数据库迁移**

### 分析面板布局
- **不使用 `DraggableScrollableSheet`**（真机上与 InteractiveViewer 手势冲突）
- 改用 `AnimatedContainer` + 展开/收起按钮
- 黑白状态通过 Widget state + 回调传递（不使用 Riverpod family provider）
- 展开高度 `340px`（maxHeight `380px`），容纳 5 段影调占比条 + 统计指标网格（曾用 268px 装 5 段会溢出需滚动）

## Android 配置

- 包名：`com.mengtu.app`
- 最低版本：API 26（Android 8.0）
- **ABI 过滤：仅 `arm64-v8a`**（目标设备均为 ARM64，砍掉 armeabi-v7a/x86_64 约减 80MB）
- 权限：`READ_MEDIA_IMAGES`（API 33+）, `READ_EXTERNAL_STORAGE`（旧版）
- MainActivity 路径必须与 namespace 一致：`kotlin/com/mengtu/app/`
- `requestLegacyExternalStorage="true"` 兼容旧版分区存储
- **签名配置（重要，曾踩坑）**：
  - `debug.keystore` **不在仓库**（`android/.gitignore` 的 `**/*.keystore` 规则忽略）
  - CI 通过 4 个 Actions secret 注入：`KEYSTORE_BASE64`（keystore 文件 base64）、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`
  - `build.gradle.kts` 的 `signingConfigs.release` 优先读环境变量（CI），本地开发 fallback 到固定 debug 默认（`android/android`）
  - **坑**：release 构建会触发 `validateSigningRelease` 严格校验（debug 构建有 Android 默认 keystore 兜底），所以 release 必须能找到 keystore 文件

## CI/CD

**所有编译打包通过 GitHub Actions 完成，不在本地执行 `flutter build`。**

CI 流程（`.github/workflows/build.yml`）：
1. `flutter pub get`
2. `dart run build_runner build`（代码生成）
3. `flutter analyze`（必须 0 issues）
4. `flutter test`
5. `flutter test --coverage`（生成 lcov 覆盖率报告）
6. Upload coverage artifact
7. **Decode keystore**：base64 解码 `KEYSTORE_BASE64` secret 到 `android/app/release.keystore`，通过 `GITHUB_ENV` 注入 `KEYSTORE_PATH`
8. `flutter build apk --release`（push 触发，**不再用 --debug**；env 注入其余 3 个签名 secret）
9. Upload APK artifact（`mengtu-apk`，产物 `app-release.apk`）

**APK 体积**：release + abiFilters=arm64-v8a 约 **30MB**（曾用 --debug 约 150MB）

**签名 secret（Actions secrets）**：
- `KEYSTORE_BASE64`：keystore 文件 base64 编码
- `KEYSTORE_PASSWORD`：keystore 密码
- `KEY_ALIAS`：密钥别名
- `KEY_PASSWORD`：密钥密码

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
9. **`--split-per-abi` 与 `ndk.abiFilters` 互斥** — Gradle 报 "Conflicting configuration"。`abiFilters=arm64-v8a` 已限制单 ABI，`--split-per-abi` 多余且会冲突，去掉即可
10. **release 构建严格校验签名** — `validateSigningRelease` 找不到 keystore 直接挂（debug 构建有 Android 默认 keystore 兜底）。keystore 走 CI secret，不在仓库
11. **Kotlin 变量遮蔽（shadowing）** — `signingConfigs` 配置块里，外层 `val keyAlias` 与 `this.keyAlias` 同名会被当成"重赋值 val"报错。局部变量加前缀（如 `ciKeyAlias`）规避
12. **`pubspec.lock` 的 url 字段** — 本地用国内镜像会改 `pub.dev`→`pub.flutter-io.cn`，提交会让 CI 产生无关 diff，还原即可
13. **影调分段升级的基调判定** — 3 段→5 段后，`_classifyToneKey` 的全长调判定要改用合并段（dark=blacks+shadows / light=highlights+whites），否则高对比图会漏判

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
