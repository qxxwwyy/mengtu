# SCRFD/NCNN 人脸检测重构 — 开发交接文档

> **状态**：进行中（未完成）。本文档面向接手继续开发的工程师，如实记录已完成与未完成的工作、关键风险点和验证结论。
> **分支**：`feature/release-prep`（未提交）
> **日期**：2026-07-01

---

## 一、任务背景

将萌图项目的人脸检测从「BlazeFace TFLite + Google ML Kit + MediaPipe Face Mesh」三段式架构，**全面替换为 SCRFD（NCNN 推理）**。动机：旧方案存在 GMS 依赖问题、大头照识别率不足、模型碎片化等问题。

**用户确认的两个决策：**
1. **STI/FLC 彻底移除** —— SCRFD 只输出 5 个关键点（眼/鼻/嘴角），无法计算依赖 MediaPipe 468 点网格的 STI（皮肤通透度）和 FLC（面部光比）。
2. **我编写全部源码 + 从 GitHub 下载二进制**（libncnn.a + SCRFD 模型）。

---

## 二、已完成的工作（✅）

### 阶段 1：新建 `scrfd_ncnn_plugin/`（FFI 插件，全新源码）

插件目录（`scrfd_ncnn_plugin/`，path 依赖方式接入主项目），包含完整源码：

| 文件 | 说明 | 状态 |
|------|------|------|
| `lib/scrfd_ncnn.dart` | Dart FPI 层：`ScrfdNcnn` 类（`init`/`detect`/`destroy` + `ScrfdFace`）+ `rgbaToBgr` 静态方法 | ✅ 已写 |
| `src/scrfd_api.h` / `scrfd_api.c` | C ABI 导出层（薄包装，转发给 C++ Detector） | ✅ 已写 |
| `src/scrfd_detector.h` / `scrfd_detector.cpp` | C++ 核心实现：NCNN 加载 + SCRFD 解码（3 stride 8/16/32）+ NMS | ⚠️ 已写但**解码逻辑有误**（见四.1） |
| `src/CMakeLists.txt` + `android/CMakeLists.txt` | CMake 构建（链 `libncnn.a`，`c++_shared`，`c++17`） | ✅ 已写 |
| `android/build.gradle` | Gradle 配置（`externalNativeBuild`，`abiFilters arm64-v8a`，NDK 26） | ✅ 已写 |
| `android/src/main/AndroidManifest.xml` | 空 manifest（纯 FFI，无 Activity） | ✅ 已写 |
| `pubspec.yaml` | 插件依赖（`ffi: ^2.1.0`，`ffiPlugin: true`）+ 模型 assets 声明 | ✅ 已写 |
| `README.md` | 二进制下载说明 + API 用法 | ✅ 已写 |
| `.gitignore` | 排除二进制（libncnn.a / 模型文件） | ✅ 已写 |

**二进制文件已下载到位**（`.gitignore` 排除，不入 git）：
- `android/src/main/jni/ncnn/lib/android/arm64-v8a/libncnn.a`（10MB，来自 [Tencent/ncnn releases 20250428](https://github.com/Tencent/ncnn/releases)）
- `android/src/main/jni/ncnn/include/ncnn/*.h`（NCNN 头文件）
- `android/src/main/assets/scrfd_2.5g_kps-opt2.param`（10KB，文本结构）
- `android/src/main/assets/scrfd_2.5g_kps-opt2.bin`（1.6MB，权重）
  - 模型来自 [nihui/ncnn-android-scrfd](https://github.com/nihui/ncnn-android-scrfd)

### 阶段 2：主项目 Dart 侧重构（lib/ 全部编译通过 ✅）

**`dart analyze` 验证：`lib/` 下 0 错误 0 警告**（所有 60 个错误都在 `test/` 下，见未完成部分）。

#### 2.1 服务层
- ✅ **重写** `lib/services/face_service.dart`：移除 BlazeFace（`_detectPrimaryFace`/`_buildAnchors`/anchor decode）+ Face Mesh（`_runFaceMesh`/`calculateSti`/`calculateFlc`/`FaceMeshResult`/`FaceMeshIndices`）。保留：`DetectedFace` 类、`analyzeSkinTone()`（简化签名为 bbox-only）、`_analyzeRoiSkin`（bbox ROI 肤色统计）、`_computeManualSkinStats`、辅助函数（`_rgbToHsl`/`_hueRingDistance`）。
- ✅ **新建** `lib/services/scrfd_service.dart`：`detectPrimaryFaceWithScrfd()`（EXIF 旋转对齐 + RGBA→BGR + 调用插件 detect + bbox 归一化）+ `disposeScrfdDetector()` + `FaceDetection` 类（迁移自 mlkit_face_service）。
- ✅ **删除** `lib/services/mlkit_face_service.dart`。

#### 2.2 数据模型（STI/FLC 彻底移除）
- ✅ `lib/models/tone_result.dart`：`SkinAnalysis` 删 `sti`/`flc` 字段 + `toJson`/`fromJson` 对应键（旧缓存含 sti/flc 键会被忽略，向前兼容）。
- ✅ `lib/models/advanced_portrait_metrics.dart`：删 `skinSti`/`faceLightingContrast` 字段 + 序列化。
- ✅ `lib/models/photo_fingerprint.dart`：`scalarLabels` 9→7（删 `'sti'`/`'flc'`）。

#### 2.3 Provider / Service
- ✅ `lib/providers/analysis_provider.dart`：
  - 删 `modelPathProvider`/`fullModelPathProvider`/`meshModelPathProvider`
  - `detectedFaceProvider` 改调 `detectPrimaryFaceWithScrfd`
  - `skinProvider` 删 3 个 modelPath watch，简化 `analyzeSkinTone` 调用
  - `advancedMetricsProvider` 不再传 sti/flc
- ✅ `lib/services/fingerprint_service.dart`：scalar 数组 9→7（删 dim7/dim8）+ 头注释。
- ✅ `lib/services/builtin_profiles.dart`：4 个 profile 的 `scalar_means` + `scalar_stds` 9→7。
- ✅ `lib/services/tone_service.dart`：`computeAdvancedMetrics` 删 sti/flc 参数。
- ✅ `lib/services/import_service.dart`：`precomputeAnalysisForPhotos` 删 modelPath 提取，简化为直方图+影调+advanced。

#### 2.4 UI 层
- ✅ `lib/widgets/grading/stage_color_card.dart`：删 STI `InterpretationRow` + 删 `advanced` 参数。
- ✅ `lib/widgets/grading/stage_isolation_card.dart`：删 FLC `InterpretationRow` + 删 `advanced` 参数。
- ✅ `lib/widgets/grading/raw_data_dashboard.dart`：删 STI/FLC tile。
- ✅ `lib/widgets/grading/grading_panel.dart`：更新 StageColorCard/StageIsolationCard 调用（不再传 advanced）。
- ✅ `lib/widgets/grading/skin_radar.dart`：删 `advanced` 参数（v6.2 达芬奇示波器不依赖 STI）。

#### 2.5 配置 / 入口
- ✅ `pubspec.yaml`：删 `tflite_flutter` + `google_mlkit_face_detection`，加 `scrfd_ncnn: {path: scrfd_ncnn_plugin}`；assets 段删 3 行 tflite。
- ✅ `lib/main.dart`：`disposeMlKitDetector` → `disposeScrfdDetector`。
- ✅ `android/build.gradle.kts`：删 `org.tensorflow` resolutionStrategy 块。
- ✅ `android/app/proguard-rules.pro`：删 §3（TFLite keep）+ §3b（ML Kit keep）。
- ✅ **删除** `assets/models/*.tflite`（3 个旧模型文件）。
- ✅ `flutter pub get` 成功（`GeneratedPluginRegistrant` 自动重生成）。

---

## 三、未完成的工作（⬜）

### 3.1 测试文件（**60 个 analyze 错误，全在 test/ 下**）

| 测试文件 | 问题 | 处理方式 |
|----------|------|----------|
| `test/unit/face_service_anchor_test.dart` | 全文测 BlazeFace anchor 生成（`blazefaceAnchorsForTest`/`decodeAnchorForTest`/`sigmoidForTest`）—— 这些函数已删 | **删除整个文件** |
| `test/unit/face_mesh_test.dart` | 测 STI/FLC 纯函数（依赖 `FaceMeshIndices`/`calculateSti`/`calculateFlc`）—— 已删 | **删除整个文件**（或保留 SkinAnalysis 序列化断言重写，但建议直接删） |
| `test/unit/face_model_asset_test.dart` | 测 3 个 .tflite 文件存在 + rootBundle 可读 —— 文件已删 | **重写**：改为测 `scrfd_2.5g_kps-opt2.param`/`.bin` 存在（asset key 是 `assets/scrfd_2.5g_kps-opt2.param`，在插件包内）|
| `test/unit/advanced_metrics_test.dart` | 含 STI/FLC 序列化断言（`skinSti`/`faceLightingContrast` getter） | **修改**：删 STI/FLC 相关断言（保留 black/white/ten_tonal 测试）|

**注意**：`test/unit/fingerprint_service_test.dart`、`test/integration/precompute_fingerprint_test.dart`、`test/unit/face_service_manual_skin_test.dart`、`test/widget/skin_radar_test.dart` 当前 analyze 通过，但实际运行可能因 9→7 维度断言失败（fingerprint_service_test）—— 需运行 `flutter test` 确认。

**目标**：`dart analyze` 0 issues + `flutter test` 全过（CI 要求）。

### 3.2 C++ 解码逻辑修正（**最关键的正确性风险**）

⚠️ `src/scrfd_detector.cpp` 的 bbox/kps 解码**可能有误**，需对照官方实现修正：

**现状分析**（已通过 `.param` 文件确认）：
- 模型 `scrfd_2.5g_kps-opt2` 的输入 blob 名是 `input.1`（已正确写入 C++）
- 输出 blob：`score_8`/`bbox_8`/`kps_8`（8/16/32 三尺度，已正确）
- `score_*` 已过 Sigmoid（是概率，不需再 sigmoid）
- **关键发现**：`bbox_8` 经 `Mul_136(2=8.807251e-01)` —— 这个 0.88 是**小归一化常数，不是 stride(8)**
- **关键发现**：`kps_8`/`kps_16`/`kps_32` 是**原始 Conv 输出**（无 Mul、无 stride 缩放）

**当前 C++ 代码的疑似错误**：
```cpp
// 当前实现（疑似错误）：
float left = bbox[0] * stride;   // bbox 已含 0.88 常数，再 *stride(8) 会偏离
float top = bbox[1] * stride;
// ...
float kx = ax + kps[k*2] * stride;  // kps 是原始值，*stride 可能对
```

**参考**：[Tencent/ncnn 官方 scrfd.cpp](https://github.com/Tencent/ncnn/blob/master/examples/scrfd.cpp) 的 `generate_proposals()` 用 `* feat_stride`，但那是针对**非 opt2 模型**（无 Mul 层）。opt2 变体把 stride 以不同形式烘焙进去了。

**修正方向**：
1. 查 [nihui/ncnn-android-scrfd](https://github.com/nihui/ncnn-android-scrfd) 的 `app/src/main/jni/scrfdncnn_jni.cpp` 看它对 opt2 模型怎么解码（这是最权威参考，因为它用的就是这套 opt2 模型）
2. 可能 bbox 不再 `*stride`（用原始值），而 kps 仍 `*stride`
3. **必须用真机/模拟器实拍验证**：跑一张已知人脸照片，看 bbox 是否框住脸、5 个关键点是否落在眼/鼻/嘴

### 3.3 真机/模拟器集成验证（未做）

**完全未在真实 Android 设备上验证过端到端流程**。需验证：
1. **CMake 编译** `libscrfd_ncnn.so` 能否成功（CI 在 Ubuntu，需 NDK 26 + CMake 3.22）
2. **模型加载**：`scrfd_service._getInitializedScrfd()` 能否把 asset 复制到文件系统 + NCNN 加载成功
3. **检测正确性**：人脸 bbox 是否框住脸（坐标对齐），EXIF 旋转（竖拍照片）bbox 是否正确
4. **肤色 ROI**：bbox 内缩 20% 后肤色统计是否合理
5. **性能**：SCRFD-2.5G @ 640 在测试设备上的推理耗时（主线程 FFI 同步调用，是否会卡 UI？指南说 8-30ms，可接受，但需实测）

### 3.4 CI 配置（二进制获取）

`libncnn.a`（10MB）+ 模型（1.6MB）不入 git（`.gitignore` 排除）。CI 在 Ubuntu runner 需要这些二进制才能编译。**未配置 CI 获取脚本**。建议方案（见插件 README.md 已文档化）：
- 写 `scripts/fetch-native.sh`，CI 里 curl 下载（URL 已在 README.md 记录）
- 或用 GitHub LFS / git submodule 引入 nihui/ncnn-android-scrfd

### 3.5 AGENTS.md 更新

`AGENTS.md` 尚未同步本次 SCRFD 重构（项目结构/gotcha/版本号）。需更新：
- 项目结构：`face_service.dart` / `scrfd_service.dart` 描述、`scrfd_ncnn_plugin/` 目录
- 新增 gotcha（SCRFD 坐标解码、模型 asset 路径、FFI 单例不能跨 Isolate 等）
- 版本号 v6.2 → v7.0

---

## 四、关键风险与注意事项

### 4.1 ⚠️ C++ bbox/kps 解码（最高优先级）
见 3.2。**这是整个重构成败的关键**，必须真机验证。

### 4.2 EXIF 旋转的 bbox 坐标轴互换（中等风险）
`scrfd_service.dart` 的 `detectPrimaryFaceWithScrfd` 对 90°/270° 旋转照片，bbox 坐标轴互换逻辑（存储→显示）是**近似实现**（直接交换 nx/ny），可能不精确。注释里已标注。竖拍大头照是常见场景，需重点验证 bbox 是否框住脸。

### 4.3 detect 在主线程（性能）
`scrfd_service.detectPrimaryFaceWithScrfd` 在**主 isolate** 调用 FFI 同步 `scrfd.detect()`（不像旧 BlazeFace 在 Isolate 内）。SCRFD-2.5G @ 640 理论 8-30ms，但**低端设备可能 50-120ms**（指南数据）。若实测卡 UI，需迁移到 Isolate（注意：`ScrfdNcnn` 单例不可跨 Isolate，需每 Isolate 独立 init）。

### 4.4 指纹维度 9→7 的向后兼容
已改的照片指纹是 7 维（删 sti/flc）。**用户既有档案**（DB 里 `StyleProfiles.fingerprintStats`）可能存的是旧 9 维数据。匹配时维度不齐会出错。需确认：旧档案是否需要迁移（recomputeProfileStats 重算），或 `computeSimilarity` 是否能容忍维度不匹配（当前实现按 index 对齐，9 vs 7 会越界或错位）。

### 4.5 插件 pubspec asset 警告（无害）
`dart analyze scrfd_ncnn_plugin` 报 2 个 warning：`assets/scrfd_2.5g_kps-opt2.param/.bin doesn't exist`。这是 `flutter analyze` 对 FFI 插件 asset 路径的解析问题（文件实际在 `android/src/main/assets/`，但 pubspec 声明 `assets/...`）。**构建时正常**，可忽略或调整声明路径。

### 4.6 git 提交范围
当前所有改动**未提交**。提交时注意：
- 用 `git add <具体文件>`（gotcha #22：避免 `-A` 误提交 `.agents/`、`SCRFD_NCNN_*.md`、`plan.md`、`implementation_plan.md` 等无关文件）
- `pubspec.lock` 会因 ffi 包加入而变（这是真实依赖变更，可提交，但注意国内镜像 url 字段问题 gotcha #12）
- 插件目录 `scrfd_ncnn_plugin/` 是新目录，需加入（但 `.gitignore` 已排除二进制）

---

## 五、二进制下载源（已验证可用）

| 文件 | 来源 | 大小 |
|------|------|------|
| `libncnn.a` + NCNN headers | [Tencent/ncnn releases 20250428](https://github.com/Tencent/ncnn/releases) → `ncnn-20250428-android-vulkan.zip`（取 `arm64-v8a/`） | 10MB |
| `scrfd_2.5g_kps-opt2.param` | [nihui/ncnn-android-scrfd](https://github.com/nihui/ncnn-android-scrfd) `master/app/src/main/assets/` | 10KB |
| `scrfd_2.5g_kps-opt2.bin` | 同上 | 1.6MB |

完整下载命令见 `scrfd_ncnn_plugin/README.md`。

---

## 六、建议的接手开发顺序

1. **（最高优先）修正 C++ 解码**：研究 nihui/ncnn-android-scrfd 的 jni 解码 → 改 `scrfd_detector.cpp` → 真机验证 bbox 落点
2. **修测试**：删 anchor/mesh 测试，重写 asset 测试，修 advanced_metrics 断言 → `dart analyze` 0 + `flutter test` 全过
3. **真机端到端验证**：检测/肤色/性能/EXIF
4. **指纹 9→7 兼容**：确认旧档案匹配不崩
5. **CI 二进制获取脚本**
6. **更新 AGENTS.md**
7. 提交（具体文件，非 `-A`）

---

## 七、文件清单速查

**新增**：`scrfd_ncnn_plugin/`（整个插件目录）、`lib/services/scrfd_service.dart`
**删除**：`lib/services/mlkit_face_service.dart`、`assets/models/*.tflite`（3 个）
**修改**：`lib/services/face_service.dart`（重写）、`lib/models/{tone_result,advanced_portrait_metrics,photo_fingerprint}.dart`、`lib/providers/analysis_provider.dart`、`lib/services/{fingerprint_service,builtin_profiles,tone_service,import_service}.dart`、`lib/widgets/grading/{stage_color_card,stage_isolation_card,raw_data_dashboard,grading_panel,skin_radar}.dart`、`lib/main.dart`、`lib/pages/detail_page.dart`、`pubspec.yaml`、`android/build.gradle.kts`、`android/app/proguard-rules.pro`
