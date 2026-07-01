# SCRFD + NCNN 人脸检测 — Flutter 应用嵌入指南

> **文档定位**：团队内部知识库，供实习/新入职开发人员独立完成人脸检测功能嵌入  
>
> **技术路线**：Flutter FFI Plugin → NCNN 推理引擎 → SCRFD 检测模型  
>
> **适用场景**：在已有 Flutter Android（及后续多平台）应用中嵌入端侧离线人脸检测能力  
>
> **前置要求**：熟悉 Dart/Flutter 基础开发，了解 C++ 基础语法即可（不需要精通）  
>
> **预计耗时**：3-5 个工作日（按本文档步骤操作）

---

## 目录

1. [你要做什么](#一你要做什么)
2. [需要理解的核心概念（必读）](#二需要理解的核心概念必读)
3. [环境准备](#三环境准备)
4. [获取依赖库和模型文件](#四获取依赖库和模型文件)
5. [创建 FFI Plugin 项目](#五创建-ffi-plugin-项目)
6. [编写 C++ 核心检测代码](#六编写-c-核心检测代码)
7. [编写 C 接口层（FFI 桥接）](#七编写-c-接口层ffi-桥接)
8. [编写 Dart 层代码](#八编写-dart-层代码)
9. [配置 Android 构建](#九配置-android-构建)
10. [将 Plugin 集成到已有应用](#十将-plugin-集成到已有应用)
11. [运行测试与验证](#十一运行测试与验证)
12. [常见问题排查手册](#十二常见问题排查手册)
13. [附录：关键概念速查表](#十三附录关键概念速查表)

---

## 一、你要做什么

### 1.1 任务目标

在你手头的 Flutter 应用中，增加一个**人脸区域识别**功能：

- 用户选择一张照片（或拍照）
- 应用自动找出照片中所有人脸的位置（矩形框）
- 同时标出每张人脸的 5 个关键点（双眼、鼻尖、两嘴角）
- 全部在用户手机上完成，**不需要网络**

### 1.2 技术选型为什么是这套组合

```
你的 Flutter 应用 (Dart 代码)
    ↓ 调用 (dart:ffi，直接函数调用，无中间层)
Native C++ 库 (NCNN 推理引擎)
    ↓ 加载并运行
SCRFD 模型文件 (.param + .bin)
    ↓ 输出
人脸位置列表 → 回传给 Dart → 显示在界面上
```

| 组件 | 是什么 | 为什么用它 |
| --- | --- | --- |
| **SCRFD** | 人脸检测算法模型 | 当前开源领域精度最高的轻量级人脸检测器之一 |
| **NCNN** | 神经网络推理引擎 | 腾讯出品，专为手机优化，CPU 推理速度极快，零第三方依赖 |
| **Flutter FFI** | Dart 调用 C++ 的机制 | 让 Dart 代码直接调用 C++ 函数，跨平台统一 |

### 1.3 你最终要交付的东西

```
一个 Flutter Package（插件包），包含：
├── src/
│   ├── scrfd_detector.h/cpp     # C++ 检测核心逻辑
│   ├── scrfd_api.h/c            # C 导出接口（给 Dart 调用）
│   └── CMakeLists.txt           # C++ 编译配置
├── lib/
│   └── scrfd_ncnn.dart          # Dart API 封装
├── android/build.gradle         # Android 构建配置
├── assets/
│   ├── scrfd-1g.param           # 模型结构文件
│   └── scrfd-1g.bin             # 模型权重文件
└── pubspec.yaml                 # 包描述
```

在你的主应用中引用这个包，调用几行 Dart 代码就能做人脸检测。

---

## 二、需要理解的核心概念（必读）

> **即使你不熟悉 C++，也请花 10 分钟读完本节。** 这些概念会帮助你理解后续的代码。

### 2.1 什么是 FFI？

**FFI = Foreign Function Interface（外部函数接口）**

简单说：让 Dart 代码能够**直接调用 C/C++ 编写的函数**。

```dart
// Dart 侧：像调用普通 Dart 函数一样调用 C 函数
final result = scrfd_detect(imageData, width, height, results, maxFaces);
```

```c
// C 侧：被 Dart 调用的实际执行代码
EXPORT int scrfd_detect(unsigned char* data, int w, int h, float* results, int max) {
    // 这里跑 NCNN 推理...
    return faceCount;
}
```

**你不需要深入理解 FFI 的底层原理**，只需要知道：Dart 通过 `dart:ffi` 库加载编译好的 `.so` 文件（Android）或 `.dylib` 文件（iOS），然后就可以调用里面导出的 C 函数。

### 2.2 什么是 NCNN？

NCNN 是一个**轻量级的神经网络推理框架**。你可以把它理解为：

> "一个能在手机上高效运行 AI 模型的 C++ 库"

它的工作方式：

```cpp
// 1. 加载模型
Net net;
net.load_param("scrfd.param");   // 模型结构：有哪些层、怎么连接
net.load_model("scrfd.bin");     // 模型权重：每层的参数值

// 2. 把图片数据喂进去
Mat input = /* 图片预处理后的数据 */;
Extractor ex = net.create_extractor();
ex.input("input.1", input);

// 3. 取出推理结果
Mat output;
ex.extract("detection_0_score", output);  // 人脸置信度
ex.extract("detection_0_bbox", output);    // 人脸位置
ex.extract("detection_0_kps", output);     // 关键点位置
```

### 2.3 什么是 SCRFD？

SCRFD 是一个**已经训练好的人脸检测模型**。你不需要训练它，只需要下载现成的模型文件（`.param` + `.bin`），放到 NCNN 里运行即可。

它的输入输出：

|  | 说明 |
| --- | --- |
| **输入** | 一张图片（缩放到 640×640 像素，BGR 格式） |
| **输出** | 多组检测结果，每组包含：边界框(x,y,w,h)、置信度(0~1)、5个关键点坐标 |

### 2.4 整体数据流（看一遍就明白）

```
用户选了一张照片 (JPEG/PNG 文件)
        │
        ▼
Flutter: 用 image_picker 获取文件路径
        │
        ▼
Flutter: 读取图片 → 转为 BGR 字节数组 (Uint8List)
        │
        ▼
Dart FFI: 调用 scrfd_detect(bgr_data, width, height, results, max)
        │  (这里跨入 C++ 世界)
        ▼
C++: 将 BGR 数据转为 ncnn::Mat
        │
        ▼
C++: 缩放到 640×640，归一化到 [-1, 1]
        │
        ▼
NCNN: 前向推理（神经网络计算）
        │
        ▼
C++: 解码输出 → NMS 去重 → 得到人脸列表
        │
        ▼
C++: 将结果写入 results 数组
        │  (回到 Dart 世界)
        ▼
Dart: 解析 results 数组 → List<ScrfdFace>
        │
        ▼
Flutter UI: 在图片上绘制矩形框和关键点
```

---

## 三、环境准备

### 3.1 你需要安装的工具

| 工具 | 版本要求 | 安装方式 |
| --- | --- | --- |
| **Android Studio** | 最新稳定版（2024.1+） | https://developer.android.com/studio |
| **Flutter SDK** | ≥ 3.16 | 已有（你在做 Flutter 开发） |
| **Dart SDK** | ≥ 3.2 | 随 Flutter 一起安装 |
| **NDK** | 26.x | Android Studio → SDK Manager → SDK Tools → 勾选 NDK (Side by side) |
| **CMake** | 3.22+ | Android Studio → SDK Manager → SDK Tools → 勾选 CMake |

### 3.2 验证环境是否就绪

打开终端，依次执行以下命令确认：

```bash
# 1. Flutter
flutter doctor -v
# ✅ 确保 Android toolchain 显示 "✓" 或 "✗" 但可修复

# 2. NDK
ls $ANDROID_SDK_ROOT/ndk/
# 应该看到类似 "26.1.10909125" 的目录

# 3. CMake
cmake --version
# 应该显示版本号 ≥ 3.22

# 4. 能否正常创建 Flutter 项目
flutter create test_env_check && cd test_env_check && flutter build apk --debug && cd .. && rm -rf test_env_check
# 应该成功编译
```

如果 `flutter doctor` 报错，先解决环境问题再继续。常见问题：

- **Android license not accepted** → 运行 `flutter doctor --android-licenses`，全部选 y
- **NDK not found** → 在 Android Studio 的 Settings → Appearance → System Settings → Android SDK → SDK Tools 中勾选 NDK 和 CMake

### 3.3 本文档使用的目录约定

```
~/workspace/                          ← 你的工作根目录
├── your_existing_app/                ← 你已有的 Flutter 应用（目标集成对象）
├── scrfd_ncnn_plugin/                ← 你将要创建的 FFI 插件包
└── models/                           ← 存放模型文件的临时目录
```

---

## 四、获取依赖库和模型文件

### 4.1 下载 NCNN Android 预编译库

NCNN 官方提供了编译好的 Android 库，**不需要你自己从源码编译**。

```bash
# 创建工作目录
mkdir -p ~/workspace/models ~/workspace/scrfd_ncnn_plugin

# 下载 NCNN Android 预编译包（含 Vulkan GPU 支持）
cd ~/workspace/models

# 方式一：浏览器下载（推荐）
# 访问 https://github.com/Tencent/ncnn/releases
# 找到最新的 "ncnn-YYYYMMDD-android-vulkan.zip" 下载

# 方式二：命令行下载（如果有 wget/curl）
# 请将下面的 URL 替换为实际的最新 release URL
wget https://github.com/Tencent/ncnn/releases/download/20240410/ncnn-20240410-android-vulkan.zip

# 解压
unzip ncnn-*-android-vulkan.zip
# 解压后得到 ncnn-*/ 目录，里面有:
#   include/   — 头文件
#   lib/android/arm64-v8a/libncnn.a      — 64位 ARM 静态库
#   lib/android/armeabi-v7a/libncnn.a    — 32位 ARM 静态库
```

> **⚠️ 如果 GitHub 下载慢**：可以尝试使用代理，或者从国内镜像站下载。也可以找导师/同事要一份已下载好的副本。

解压后确认文件存在：

```bash
ls ~/workspace/models/ncnn-*/lib/android/arm64-v8a/libncnn.a
# 应该能看到文件（约 3-5MB）
```

### 4.2 下载 SCRFD 模型文件

SCRFD 有多个规格的模型。对于大多数场景，推荐 **SCRFD-1G**（精度和速度的最佳平衡点）。

```bash
cd ~/workspace/models

# 从 InsightFace GitHub Releases 下载
# 访问: https://github.com/deepinsight/insightface/releases
# 找到 model_zoo 中的 SCRFD 相关文件

# 或者从 InsightFace 仓库的 detection/scrfd/ 目录中获取转换脚本后自行导出
git clone --depth 1 https://github.com/deepinsight/insightface.git temp_insightface
cd temp_insightface/detection/scrfd/

# 使用 Python 导出 ONNX 模型（需要安装 insightface Python 包）
pip install insightface onnx onnx-simplifier
python -c "
from insightface.model_zoo import get_model
model = get_model('SCRFD_1G')
print('Model ready')
"
# 导出 ONNX 后，转换为 NCNN 格式（见下节）
```

#### 如果你不想自己转换模型

可以直接使用社区已转换好的 NCNN 格式模型。参考项目 `ncnn-android-scrfd` 的 assets 目录中通常包含可直接使用的 `.param` 和 `.bin` 文件：

```bash
# 从 nihui/ncnn-android-scrfd 仓库获取模型
git clone --depth 1 https://github.com/nihui/ncnn-android-scrfd.git temp_scrfd_demo
cp temp_scrfd_demo/app/src/main/assets/*.param ~/workspace/models/
cp temp_scrfd_demo/app/src/main/assets/*.bin ~/workspace/models/
ls ~/workspace/models/*.param ~/workspace/models/*.bin
# 应该看到 scrfd*.param 和 scrfd*.bin 文件
```

### 4.3 （可选）ONNX → NCNN 模型转换

如果你拿到了 SCRFD 的 ONNX 模型文件（`.onnx`），需要转换为 NCNN 格式：

```bash
# 使用 NCNN 自带的 onnx2ncnn 工具
# 该工具在 NCNN 源码的 tools/onnx/ 目录下，或预编译工具包中

# 转换命令
./onnx2ncnn scrfd_1g.onnx scrfd_1g.param scrfd_1g.bin

# 优化（合并+加速）
./ncnnoptimize scrfd_1g.param scrfd_1g.bin \
    scrfd_1g-opt.param scrfd_1g-opt.bin 65536

# 最终使用 scrfd_1g-opt.param 和 scrfd_1g-opt.bin
```

> 💡 **提示**：如果你对模型转换不熟悉，**直接用 4.2 节的方法获取已转换好的模型文件**。模型转换属于一次性工作，不是每次都需要做的。

### 4.4 确认所有文件就绪

```bash
echo "=== 依赖检查 ==="
echo "NCNN 头文件:"
ls ~/workspace/models/ncnn-*/include/net.h 2>/dev/null && echo "  ✅" || echo "  ❌ 缺失"
echo "NCNN arm64 库:"
ls ~/workspace/models/ncnn-*/lib/android/arm64-v8a/libncnn.a 2>/dev/null && echo "  ✅" || echo "  ❌ 缺失"
echo "SCRFD 模型:"
ls ~/workspace/models/scrfd*.param 2>/dev/null && echo "  ✅ param" || echo "  ❌ param 缺失"
ls ~/workspace/models/scrfd*.bin 2>/dev/null && echo "  ✅ bin" || echo "  ❌ bin 缺失"

# 全部 ✅ 才能继续下一步
```

---

## 五、创建 FFI Plugin 项目

Flutter 提供了专门的 FFI Plugin 模板，可以快速生成项目骨架。

### 5.1 使用模板创建

```bash
cd ~/workspace

# 创建 FFI Plugin 项目
flutter create --template=plugin_ffi \
    --platforms=android \
    --org=com.yourcompany \
    scrfd_ncnn_plugin

cd scrfd_ncnn_plugin
```

创建完成后你会看到如下结构：

```
scrfd_ncnn_plugin/
├── src/                  # ★ C/C++ 源代码放这里
│   └── scrfd_ncnn.h     # 模板生成的示例头文件（后面我们替换掉）
├── lib/
│   └── scrfd_ncnn.dart  # 模板生成的 Dart 文件（后面我们重写）
├── ffigen.yaml           # FFI 绑定生成配置
├── android/
│   ├── CMakeLists.txt    # Android CMake 配置
│   └── build.gradle      # Android Gradle 配置
├── ios/                  # iOS 配置（后续扩展时用到）
├── linux/                # Linux 配置（后续扩展时用到）
├── windows/              # Windows 配置（后续扩展时用到）
├── test/                 # 测试
└── pubspec.yaml          # 包描述
```

### 5.2 清理模板生成的示例代码

模板自带了一些示例代码，我们需要替换成自己的。先看看模板生成了什么：

```bash
# 查看 src/ 目录
ls src/
# 应该看到 scrfd_ncnn.h 和可能的 .c 文件

# 查看 lib/
cat lib/scrfd_ncnn.dart
# 会看到一个 sum() 函数的示例
```

这些示例代码后面会被完全替换，现在**不需要删除**，等我们写好正式代码后覆盖即可。

### 5.3 规划我们要创建的文件

```
scrfd_ncnn_plugin/（最终形态）
├── src/
│   ├── CMakeLists.txt              # C++ 构建配置（★ 需修改）
│   ├── scrfd_detector.h            # ★ 新建：检测器头文件
│   ├── scrfd_detector.cpp          # ★ 新建：检测器实现（核心！）
│   ├── scrfd_api.h                 # ★ 新建：C 导出接口
│   └── scrfd_api.c                 # ★ 新建：C 接口实现
├── lib/
│   └── scrfd_ncnn.dart             # ★ 重写：Dart API 封装
├── android/
│   └── CMakeLists.txt              # ★ 需修改：链接 NCNN 库
├── assets/                         # ★ 新建：存放模型文件
│   ├── scrfd-1g.param
│   └── scrfd-1g.bin
└── pubspec.yaml                    # ★ 需修改：声明 assets
```

---

## 六、编写 C++ 核心检测代码

这是整个功能的核心部分。**请逐行阅读注释**，理解每一段代码的作用。

### 6.1 检测器头文件：`src/scrfd_detector.h`

在 `scrfd_ncnn_plugin/src/` 下创建此文件：

```cpp
#ifndef SCRFD_DETECTOR_H
#define SCRFD_DETECTOR_H

#include <vector>
#include <string>

namespace scrfd {

// ======== 数据结构 ========

/// 单张人脸的检测结果
struct FaceResult {
    float x, y, w, h;           // 边界框：左上角 x,y 和宽高 w,h
    float score;                 // 置信度：0.0 ~ 1.0，越大越可能是人脸
    float landmarks[10];         // 5 个关键点的 (x,y) 坐标，共 10 个浮点数
                                // 顺序：左眼(0,1) 右眼(2,3) 鼻尖(4,5) 右嘴角(6,7) 左嘴角(8,9)
};

// ======== 检测器类 ========

class Detector {
public:
    Detector();
    ~Detector();

    /// 加载模型文件
    /// @param param_path  .param 文件的完整路径（模型结构）
    /// @param bin_path    .bin 文件的完整路径（模型权重）
    /// @return 0 表示成功，非 0 表示失败
    int load(const std::string& param_path, const std::string& bin_path);

    /// 从原始像素数据检测人脸
    /// @param bgr_data  BGR 格式的像素数据（排列方式：BGRBGRBGR...）
    /// @param width      图像宽度（像素）
    /// @param height     图像高度（像素）
    /// @param stride     每一行字节数（通常 = width * 3，但可能有对齐填充）
    /// @param faces      输出参数：检测到的人脸列表
    /// @return 检测到的人脸数量
    int detect_from_bytes(
        const unsigned char* bgr_data,
        int width, int height, int stride,
        std::vector<FaceResult>& faces
    );

    // ===== 参数调整方法 =====
    void set_input_size(int size);       // 模型输入尺寸，默认 640
    void set_score_threshold(float t);   // 置信度阈值，默认 0.5（低于此值的结果丢弃）
    void set_nms_threshold(float t);     // NMS 阈值，默认 0.45（重叠超过此值的框合并）
    void set_num_threads(int n);         // CPU 线程数，默认 4

private:
    // 内部实现（Pimpl 模式：隐藏 NCNN 依赖细节）
    void* net_impl_;

    // 参数
    int input_size_;
    float score_thresh_;
    float nms_thresh_;
    int num_threads_;

    // 内部方法
    void generate_proposals(
        const struct ncnn::Mat& score_blob,
        const struct ncnn::Mat& bbox_blob,
        const struct ncnn::Mat& kps_blob,
        int stride,
        float prob_threshold,
        std::vector<FaceResult>& face_objects
    );

    static float iou(const FaceResult& a, const FaceResult& b);
    static void nms(std::vector<FaceResult>& faces, float threshold);
};

} // namespace scrfd

#endif
```

### 6.2 检测器实现：`src/scrfd_detector.cpp`

这是**最关键的文件**——包含了完整的 SCRFD 推理流程：图像预处理 → NCNN 前向推理 → 结果解码 → NMS 去重。

```cpp
#include "scrfd_detector.h"
#include "net.h"               // NCNN 头文件
#include <algorithm>
#include <cmath>
#include <android/log.h>

// 日志宏（方便在 Android Logcat 中查看调试信息）
#define LOG_TAG "SCRFD"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace scrfd {

// ==================== 内部实现类 ====================

// 使用 Pimpl（Pointer to Implementation）模式将 NCNN 依赖隐藏在 .cpp 中
// 这样修改头文件时不会暴露 NCNN 的类型定义
class NetImpl {
public:
    ncnn::Net net;            // NCNN 网络实例
};

// ==================== 构造 / 析构 ====================

Detector::Detector()
    : net_impl_(new NetImpl())
    , input_size_(640)
    , score_thresh_(0.5f)
    , nms_thresh_(0.45f)
    , num_threads_(4)
{
}

Detector::~Detector() {
    if (net_impl_) {
        delete static_cast<NetImpl*>(net_impl_);
        net_impl_ = nullptr;
    }
}

// ==================== 模型加载 ====================

int Detector::load(const std::string& param_path, const std::string& bin_path) {
    auto* impl = static_cast<NetImpl*>(net_impl_);

    // 配置 NCNN 推理选项
    impl->net.opt.use_vulkan_compute = false;   // 使用 CPU 推理
                                               // （小模型上 CPU 通常比 GPU 更快更稳定）
    impl->net.opt.num_threads = num_threads_;    // 使用多线程加速
    impl->net.opt.use_bf16_storage = true;       // BF16 存储（ARMv8.2+ 硬件加速）

    // 加载模型结构和权重
    int ret_param = impl->net.load_param(param_path.c_str());
    int ret_model = impl->net.load_model(bin_path.c_str());

    if (ret_param != 0 || ret_model != 0) {
        LOGE("模型加载失败! param=%d model=%d", ret_param, ret_model);
        return -1;
    }

    LOGI("SCRFD 模型加载成功 (input_size=%d)", input_size_);
    return 0;
}

// ==================== 核心检测流程 ====================

int Detector::detect_from_bytes(
    const unsigned char* bgr_data,
    int width, int height, int stride,
    std::vector<FaceResult>& faces
) {
    auto* impl = static_cast<NetImpl*>(net_impl_);
    faces.clear();

    // ---- 第 1 步：图像预处理 ----
    //
    // SCRFD 要求的预处理：
    //   1. 将图片等比缩放到 input_size_ × input_size_
    //   2. 像素值归一化：pixel = (pixel - 127.5) / 128
    //      即把 [0, 255] 映射到 [-1, 1]
    //   3. 颜色顺序：BGR（不是 RGB！）

    ncnn::Mat in = ncnn::Mat::from_pixels_resize(
        bgr_data,
        ncnn::MAT_BGR,          // ⚠️ 必须是 BGR 格式
        width, height, stride,
        input_size_, input_size_   // 缩放到正方形
    );

    // 归一化（SCRFD 特定参数，不要改！）
    const float mean_vals[3] = {127.5f, 127.5f, 127.5f};
    const float norm_vals[3]  = {1.0f/128.0f, 1.0f/128.0f, 1.0f/128.0f};
    in.substract_mean_normalize(mean_vals, norm_vals);

    // ---- 第 2 步：NCNN 前向推理 ----
    //
    // 创建 Extractor（推理执行器）
    ncnn::Extractor ex = impl->net.create_extractor();
    ex.set_light_mode(true);           // 轻量模式（减少内存占用）
    ex.set_num_threads(num_threads_);

    // 输入预处理后的图像
    // "input.1" 是 SCRFD 模型的输入节点名（固定不变）
    ex.input("input.1", in);

    // SCRFD 有 3 个尺度的特征图（stride 8, 16, 32）
    // 每个尺度产生 3 组输出：score（置信度）、bbox（边界框）、kps（关键点）
    static const int feature_strides[3] = {8, 16, 32};
    std::vector<FaceResult> proposals;  // 所有候选框（NMS 前）

    for (int i = 0; i < 3; i++) {
        ncnn::Mat score_blob, bbox_blob, kps_blob;

        // 尝试提取第 i 个尺度的输出
        // 注意：节点名取决于模型导出时的设置，以下是两种常见的命名风格
        char score_name[64], bbox_name[64], kps_name[64];

        // 风格 1: detection_0_score, detection_0_bbox, detection_0_kps
        sprintf(score_name, "detection_%d_score", i);
        sprintf(bbox_name,  "detection_%d_bbox",  i);
        sprintf(kps_name,   "detection_%d_kps",   i);

        int ret = 0;
        ret |= ex.extract(score_name, score_blob);
        ret |= ex.extract(bbox_name,  bbox_blob);
        ret |= ex.extract(kps_name,   kps_blob);

        if (ret != 0) {
            // 风格 2: score_80, bbox_80, kps_80 (数字 = input_size / stride)
            int grid_size = input_size_ / feature_strides[i];
            sprintf(score_name, "score_%d", grid_size);
            sprintf(bbox_name,  "bbox_%d",  grid_size);
            sprintf(kps_name,   "kps_%d",   grid_size);

            // 需要重新创建 extractor（因为之前的 extract 已经消耗了状态）
            ex = impl->net.create_extractor();
            ex.set_light_mode(true);
            ex.set_num_threads(num_threads_);
            ex.input("input.1", in);

            // 先提取前 i 个尺度的输出（消耗掉才能取到后面的）
            for (int j = 0; j < i; j++) {
                ncnn::Mat dummy;
                char dn[64];
                sprintf(dn, "detection_%d_score", j); ex.extract(dn, dummy);
                sprintf(dn, "detection_%d_bbox",  j); ex.extract(dn, dummy);
                sprintf(dn, "detection_%d_kps",   j); ex.extract(dn, dummy);
            }
            // 再提取当前尺度
            ex.extract(score_name, score_blob);
            ex.extract(bbox_name,  bbox_blob);
            ex.extract(kps_name,   kps_blob);
        }

        // 解码当前尺度的候选框
        generate_proposals(score_blob, bbox_blob, kps_blob,
                            feature_strides[i], score_thresh_, proposals);
    }

    // ---- 第 3 步：NMS（非极大值抑制）----
    //
    // 同一张人脸可能在不同尺度都被检测到
    // NMS 的作用：去掉重复的框，只保留最好的那个
    nms(proposals, nms_thresh_);

    faces = std::move(proposals);
    return static_cast<int>(faces.size());
}

// ==================== 后处理：解码候选框 ====================

void Detector::generate_proposals(
    const ncnn::Mat& score_blob,
    const ncnn::Mat& bbox_blob,
    const ncnn::Mat& kps_blob,
    int stride,
    float prob_threshold,
    std::vector<FaceResult>& face_objects
) {
    // score_blob 的形状取决于具体模型
    // 通常: h = anchor 数量, w = 类别数（人脸检测通常只有 1 类）
    const int num_anchors = score_blob.h;

    for (int q = 0; q < num_anchors; q++) {
        // 获取当前 anchor 的置信度
        const float* scores = score_blob.row(q);
        float max_score = scores[0];

        // 如果置信度低于阈值，直接跳过（加速）
        if (max_score < prob_threshold) continue;

        // 获取边界框回归量和关键点回归量
        const float* bbox_delta = bbox_blob.row(q);
        const float* kps_delta  = kps_blob.row(q);

        // 计算网格中心坐标
        // SCRFD 是 anchor-free 设计：每个网格点直接预测其周围的人脸
        int grid_w = score_blob.w > 1 ? score_blob.w : (int)std::sqrt((float)num_anchors);
        int grid_h = num_anchors / grid_w;
        int gy = q / grid_w;
        int gx = q % grid_w;

        float cx = gx * stride;
        float cy = gy * stride;

        // 解码边界框
        // SCRFD 使用 distance-based prediction：
        //   左边距 = cx - delta_left * stride
        //   上边距 = cy - delta_top  * stride
        //   右边距 = cx + delta_right * stride
        //   下边距 = cy + delta_bottom * stride
        FaceResult face;
        face.x = cx - bbox_delta[0] * stride;
        face.y = cy - bbox_delta[1] * stride;
        face.w = (cx + bbox_delta[2] * stride) - face.x;
        face.h = (cy + bbox_delta[3] * stride) - face.y;
        face.score = max_score;

        // 解码 5 个关键点（同理，基于中心点的偏移量）
        for (int k = 0; k < 5; k++) {
            face.landmarks[k * 2]     = cx + kps_delta[k * 2]     * stride;
            face.landmarks[k * 2 + 1] = cy + kps_delta[k * 2 + 1] * stride;
        }

        face_objects.push_back(face);
    }
}

// ==================== IoU 计算 ====================

float Detector::iou(const FaceResult& a, const FaceResult& b) {
    float inter_left   = std::max(a.x, b.x);
    float inter_top    = std::max(a.y, b.y);
    float inter_right  = std::min(a.x + a.w, b.x + b.w);
    float inter_bottom = std::min(a.y + a.h, b.y + b.h);

    if (inter_right <= inter_left || inter_bottom <= inter_top) {
        return 0.0f;  // 不相交
    }

    float inter_area = (inter_right - inter_left) * (inter_bottom - inter_top);
    float union_area = a.w * a.h + b.w * b.h - inter_area;

    return inter_area / union_area;
}

// ==================== NMS ====================

void Detector::nms(std::vector<FaceResult>& faces, float threshold) {
    // 1. 按置信度降序排序（最自信的排前面）
    std::sort(faces.begin(), faces.end(),
        [](const FaceResult& a, const FaceResult& b) {
            return a.score > b.score;
        });

    std::vector<int> picked;  // 保留的索引

    for (size_t i = 0; i < faces.size(); i++) {
        bool keep = true;

        // 与所有已保留的框比较
        for (size_t j = 0; j < picked.size(); j++) {
            if (iou(faces[i], faces[picked[j]]) >= threshold) {
                keep = false;  // 重叠度过高，丢弃
                break;
            }
        }

        if (keep) {
            picked.push_back(i);
        }
    }

    // 只保留 picked 中的结果
    std::vector<FaceResult> result;
    for (int idx : picked) {
        result.push_back(faces[idx]);
    }
    faces = std::move(result);
}

// ==================== Setter 方法 ====================

void Detector::set_input_size(int size)       { input_size_ = size; }
void Detector::set_score_threshold(float t)   { score_thresh_ = t; }
void Detector::set_nms_threshold(float t)     { nms_thresh_ = t; }
void Detector::set_num_threads(int n)         { num_threads_ = n; }

} // namespace scrfd
```

### 6.3 关于这段代码你需要知道的

| 部分 | 作用 | 你可能需要修改的地方 |
| --- | --- | --- |
| `load()` | 加载模型文件 | 一般不需要改 |
| `detect_from_bytes()` | 主入口：接收图片→返回人脸列表 | 一般不需要改 |
| 图像预处理（mean_vals / norm_vals） | 将像素值归一化 | **绝对不要改**，这是 SCRFD 的标准参数 |
| `generate_proposals()` | 解码网络输出为人脸框 | 只有换模型时才需改 |
| `iou()` / `nms()` | 去重 | 一般不需要改 |
| `input_size_` 默认值 640 | 模型输入分辨率 | 可改为 480/320（更快）或保持 640（更准） |
| `score_thresh_` 默认 0.5 | 置信度阈值 | 可调低到 0.3（检测更多弱人脸）或调高（减少误检） |
| `num_threads_` 默认 4 | CPU 线程数 | 根据手机 CPU 核心数调整（4-8 均可） |

---

## 七、编写 C 接口层（FFI 桥接）

这一层的作用：把 C++ 的 `Detector` 类包装成 **纯 C 函数**，因为 Dart FFI 只能调用 C 函数，不能直接调用 C++ 类的方法。

### 7.1 C 接口头文件：`src/scrfd_api.h`

```c
#ifndef SCRFDAPI_H
#define SCRFDAPI_H

#ifdef __cplusplus
extern "C" {  // 告诉 C++ 编译器：这些函数用 C 语言的命名规则
#endif

// 导出宏：让这些函数在编译后的 .so 库中可见
#ifdef _WIN32
#  define EXPORT __declspec(dllexport)
#else
#  define EXPORT __attribute__((visibility("default")))
#endif

// ===== 初始化与销毁 =====

/// 初始化检测器并加载模型
/// @param param_path  .param 文件路径
/// @param bin_path    .bin 文件路径
/// @return 0=成功, 非0=失败
EXPORT int scrfd_init(const char* param_path, const char* bin_path);

/// 销毁检测器，释放内存
EXPORT void scrfd_destroy(void);

// ===== 检测 =====

/// 检测人脸
/// @param bgr_data    BGR 格式的像素数据
/// @param width       图像宽度
/// @param height      图像高度
/// @param stride       每行字节数（通常 = width * 3）
/// @param results     [输出] 结果数组，由调用者分配内存
/// @param max_results results 数组的最大容量（最多存几张人脸）
/// @return 实际检测到的人脸数量（<= max_results）
///
/// results 数组的布局（每张人脸占 15 个 float）：
///   [x, y, w, h, score, kx0, ky0, kx1, ky1, kx2, ky2, kx3, ky3, kx4, ky4]
EXPORT int scrfd_detect(
    const unsigned char* bgr_data,
    int width, int height, int stride,
    float* results,
    int max_results
);

// ===== 参数设置（可选，可在 init 之后、detect 之前调用）=====

/// 设置置信度阈值（默认 0.5）
EXPORT void scrfd_set_score_threshold(float threshold);

/// 设置 NMS 阈值（默认 0.45）
EXPORT void scrfd_set_nms_threshold(float threshold);

/// 设置模型输入尺寸（默认 640）
EXPORT void scrfd_set_input_size(int size);

/// 设置 CPU 线程数（默认 4）
EXPORT void scrfd_set_num_threads(int threads);

// ===== 信息查询 =====

/// 获取版本字符串
EXPORT const char* scrfd_version(void);

#ifdef __cplusplus
}
#endif

#endif // SCRFDAPI_H
```

### 7.2 C 接口实现：`src/scrfd_api.c`

```c
#include "scrfd_api.h"
#include "scrfd_detector.h"
#include <stdlib.h>
#include <string.h>

// ===== 全局状态 =====

static scrfd::Detector* g_detector = NULL;

// ===== 实现 =====

EXPORT int scrfd_init(const char* param_path, const char* bin_path) {
    // 如果之前已经初始化过，先销毁旧的
    if (g_detector) {
        delete g_detector;
        g_detector = NULL;
    }

    // 创建新的检测器
    g_detector = new scrfd::Detector();
    if (!g_detector) return -1;

    // 加载模型
    return g_detector->load(param_path, bin_path);
}

EXPORT void scrfd_destroy(void) {
    if (g_detector) {
        delete g_detector;
        g_detector = NULL;
    }
}

EXPORT int scrfd_detect(
    const unsigned char* bgr_data,
    int width, int height, int stride,
    float* results,
    int max_results
) {
    // 参数校验
    if (!g_detector || !bgr_data || !results || max_results <= 0) {
        return -1;
    }

    // 调用 C++ 检测器
    std::vector<scrfd::FaceResult> faces;
    g_detector->detect_from_bytes(bgr_data, width, height, stride, faces);

    // 将 C++ 的结果复制到 C 数组中（给 Dart 用）
    int count = (int)faces.size();
    if (count > max_results) count = max_results;

    for (int i = 0; i < count; i++) {
        const scrfd::FaceResult& f = faces[i];
        int base = i * 15;  // 每张人脸 15 个 float

        results[base + 0] = f.x;
        results[base + 1] = f.y;
        results[base + 2] = f.w;
        results[base + 3] = f.h;
        results[base + 4] = f.score;

        // 5 个关键点 × 2 个坐标 = 10 个 float
        for (int k = 0; k < 10; k++) {
            results[base + 5 + k] = f.landmarks[k];
        }
    }

    return count;
}

// ===== 参数设置的简单转发 =====

EXPORT void scrfd_set_score_threshold(float t) {
    if (g_detector) g_detector->set_score_threshold(t);
}

EXPORT void scrfd_set_nms_threshold(float t) {
    if (g_detector) g_detector->set_nms_threshold(t);
}

EXPORT void scrfd_set_input_size(int s) {
    if (g_detector) g_detector->set_input_size(s);
}

EXPORT void scrfd_set_num_threads(int n) {
    if (g_detector) g_detector->set_num_threads(n);
}

EXPORT const char* scrfd_version(void) {
    return "SCRFD-1G via NCNN (Flutter FFI)";
}
```

### 7.3 这一层的作用总结

```
Dart 世界                     C 世界                      C++ 世界
───────                       ────                       ──────
scrfd_detect()  ─────────►  scrfd_api.c  ──────────►  scrfd_detector.cpp
(Dart FFI 调用)             (纯 C 函数包装)              (实际的检测逻辑)

为什么要中间这层？
→ Dart FFI 只能调用 C 风格的函数（不能直接调用 C++ 类的方法）
→ scrfd_api.c 就是这个"翻译官"
→ 你以后如果要换模型（比如换成 YOLOv8-Face），只需改 scrfd_detector.cpp，
   scrfd_api.c 和 Dart 层都不用动
```

---

## 八、编写 Dart 层代码

### 8.1 重写 `lib/scrfd_ncnn.dart`

将模板生成的 `lib/scrfd_ncnn.dart` 替换为以下内容：

```dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ============================================================
// SCRFD NCNN — Dart FFI 绑定
//
// 使用方式：
//   final scrfd = ScrfdNcnn();
//   await scrfd.init(modelParamPath, modelBinPath);
//   final faces = scrfd.detect(bgrBytes, width, height);
//   scrfd.destroy();
// ============================================================

/// 单张人脸检测结果
class ScrfdFace {
  final double x;
  final double y;
  final double w;
  final double h;
  final double score;
  /// 5 个关键点：(左眼), (右眼), (鼻尖), (右嘴角), (左嘴角)
  final List<(double x, double y)> landmarks;

  ScrfdFace({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.score,
    required this.landmarks,
  });

  @override
  String toString() =>
      'Face(${x.toStringAsFixed(0)},${y.toStringAsFixed(0)} '
      '${w.toStringAsFixed(0)}×${h.toStringAsFixed(0)} '
      'score=${score.toStringAsFixed(3)})';
}

/// SCRFD NCNN 检测器的 Dart 封装
class ScrfdNcnn {
  late final DynamicLibrary _lib;

  // ===== 函数指针（通过 FFI 绑定的 C 函数）=====
  late final _InitFn _init;
  late final _DestroyFn _destroy;
  late final _DetectFn _detect;
  late final _SetFloatFn _setScoreThresh;
  late final _SetFloatFn _setNmsThresh;
  late final _SetIntFn _setInputSize;
  late final _SetIntFn _setNumThreads;
  late final _VersionFn _version;

  bool _initialized = false;

  /// 构造函数：绑定所有 C 函数
  ScrfdNcnn() {
    // DynamicLibrary.process() 加载当前进程中的 native 库
    // 在 Android 上就是 libscrfd_ncnn.so
    _lib = DynamicLibrary.process();

    // 绑定每个 C 函数
    _init = _lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)>('scrfd_init');

    _destroy = _lookupFunction<Void Function(), void Function>('scrfd_destroy');

    _detect = _lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, Int32, Int32, Pointer<Float>, Int32),
        int Function(Pointer<Utf8>, int, int, int, Pointer<Float>, int)>('scrfd_detect');

    _setScoreThresh = _lookupVoidFloat('scrfd_set_score_threshold');
    _setNmsThresh = _lookupVoidFloat('scrfd_set_nms_threshold');
    _setInputSize = _lookupVoidInt('scrfd_set_input_size');
    _setNumThreads = _lookupVoidInt('scrfd_set_num_threads');

    _version = _lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()>('scrfd_version');
  }

  // ===== FFI 绑定辅助方法 =====

  /// 通用的函数查找+类型转换
  T _lookupFunction<NativeType, DartType>(String name) {
    return _lib
        .lookup<NativeFunction<NativeType>>(name)
        .asFunction<DartType>();
  }

  void Function(double) _lookupVoidFloat(String name) {
    return _lib
        .lookup<NativeFunction<Void Function(Float)>>(name)
        .asFunction<void Function(double)>();
  }

  void Function(int) _lookupVoidInt(String name) {
    return _lib
        .lookup<NativeFunction<Void Function(Int32)>>(name)
        .asFunction<void Function(int)>();
  }

  // ===== 公开 API =====

  /// 是否已完成初始化
  bool get isInitialized => _initialized;

  /// 初始化模型（必须在 detect 之前调用一次）
  ///
  /// [paramPath] .param 模型结构文件的绝对路径
  /// [binPath]   .bin 模型权重文件的绝对路径
  Future<int> init(String paramPath, String binPath) async {
    // 使用 compute 在 isolate 中执行，避免阻塞 UI 线程
    // （模型加载通常需要几十到几百毫秒）
    return await _runInIsolate(() {
      final pPtr = paramPath.toNativeUtf8();
      final bPtr = binPath.toNativeUtf8();
      try {
        final ret = _init(pPtr, bPtr);
        _initialized = (ret == 0);
        return ret;
      } finally {
        calloc.free(pPtr);
        calloc.free(bPtr);
      }
    });
  }

  /// 检测人脸
  ///
  /// [bgrData] BGR 格式的图像像素数据（Uint8List）
  /// [width]   图像宽度
  /// [height]  图像高度
  /// 返回检测到的所有人脸列表
  List<ScrfdFace> detect(Uint8List bgrData, int width, int height) {
    if (!_initialized) {
      throw StateError('SCRFD 未初始化！请先调用 init()');
    }

    const int maxFaces = 100;  // 最多检测 100 张人脸（足够了）
    const int floatsPerFace = 15;  // 每张人脸 15 个 float

    // 分配 C 可写的内存
    final results = calloc<Float>(maxFaces * floatsPerFace);

    try {
      // 将 Dart 的 Uint8List 转为 C 的指针
      final dataPtr = bgrData.cast<Utf8>();

      // 调用 C 函数
      final count = _detect(
        dataPtr.value,
        width,
        height,
        width * 3,  // stride = width * 3 (BGR)
        results,
        maxFaces,
      );

      // 将 C 数组结果转回 Dart 对象
      final faces = <ScrfdFace>[];
      for (var i = 0; i < count; i++) {
        final base = i * floatsPerFace;
        faces.add(ScrfdFace(
          x: results[base + 0],
          y: results[base + 1],
          w: results[base + 2],
          h: results[base + 3],
          score: results[base + 4],
          landmarks: List.generate(5, (k) => (
            results[base + 5 + k * 2],
            results[base + 5 + k * 2 + 1],
          )),
        ));
      }

      return faces;
    } finally {
      calloc.free(results);  // 释放 C 内存
    }
  }

  /// 销毁检测器，释放资源（在不再使用时调用）
  void destroy() {
    _destroy();
    _initialized = false;
  }

  /// 获取版本信息
  String get version {
    final ptr = _version();
    return ptr.toDartString();
  }

  // ===== Isolate 辅助 =====

  /// 在 Isolate 中执行耗时操作
  Future<T> _runInIsolate<T>(T Function() operation) async {
    // 对于简单的初始化操作，也可以同步执行
    // 这里为了安全起见使用同步调用
    return operation();
  }
}
```

### 8.2 Dart 层代码说明

| 部分 | 作用 | 注意事项 |
| --- | --- | --- |
| `DynamicLibrary.process()` | 加载 native 库 | 在 Android 上自动找到 `libscrfd_ncnn.so` |
| `_lookupFunction<>()` | 将 C 函数指针转为可调用的 Dart 函数 | 函数签名必须和 C 头文件严格一致 |
| `calloc<Float>()` | 分配 C 可读写内存 | **必须**用 `calloc.free()` 释放，否则内存泄漏 |
| `toNativeUtf8()` | 将 Dart String 转为 C 字符串 | 用完必须 free |
| `cast<Utf8>()` | 将 Uint8List 转为 C 指针 | 用于传递图像数据 |

---

## 九、配置 Android 构建

### 9.1 修改插件级 `src/CMakeLists.txt`

将模板生成的 `src/CMakeLists.txt` 替换为：

```cmake
cmake_minimum_required(VERSION 3.22)
project(scrfd_ncnn LANGUAGES CXX C)

# ===== NCNN 库路径 =====
# 注意：这里的路径指向你放置 NCNN 预编译库的位置
# 后面我们会通过变量传入，这里先用占位符
set(NCNN_DIR "" CACHE PATH "Path to NCNN library")

if(NCNN_DIR STREQUAL "")
    message(FATAL_ERROR "Please set -DNCNN_DIR=/path/to/ncnn")
endif()

include_directories(${NCNN_DIR}/include)

# ===== 编译源文件 =====
add_library(scrfd_ncnn SHARED
    scrfd_api.c
    scrfd_detector.cpp
)

# ===== 链接库 =====
target_link_libraries(scrfd_ncnn
    ${NCNN_DIR}/lib/android/${ANDROID_ABI}/libncnn.a
    log             # Android 日志
    z               # 压缩库
    m               # 数学库
    android         # Android Native API
)

# 设置 C++ 标准
target_compile_features(scrfd_ncnn PUBLIC cxx_std_17)
```

### 9.2 修改 `android/CMakeLists.txt`

这个文件负责告诉 Android 构建系统如何编译 C++ 代码以及去哪里找 NCNN 库：

```cmake
# android/CMakeLists.txt
cmake_minimum_required(VERSION 3.22)

# 定义 NCNN 库的位置
# 这里的路径相对于插件的 android/ 目录
# 你需要根据实际情况调整这个路径
set(NCNN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../src/main/jni/ncnn")

# 引入 src/ 目录下的 CMakeLists.txt（上面那个）
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../src 
                 ${CMAKE_BINARY_DIR}/scrfd_native)
```

> ⚠️ **重要**：上面的 `NCNN_DIR` 路径假设你把 NCNN 库放在了 `android/src/main/jni/ncnn/` 目录下。你也可以选择其他位置，只要确保路径正确即可。下一节会详细说明文件应该放在哪里。

### 9.3 修改 `android/build.gradle`

```groovy
// android/build.gradle
// （这是插件级别的 build.gradle，不是 app 级别的）

group 'com.yourcompany.scrfd_ncnn'
version '1.0'

android {
    compileSdk 35
    ndkVersion "26.1.10909125"

    defaultConfig {
        minSdk 24
        externalNativeBuild {
            cmake {
                arguments "-DANDROID_STL=c++_shared"
                cppFlags "-std=c++17 -frtti -fexceptions"
                abiFilters 'arm64-v8a', 'armeabi-v7a'
            }
        }
    }

    buildTypes {
        release {
            minifyEnabled false
        }
    }

    // 关联 CMake 构建
    externalNativeBuild {
        cmake {
            path "CMakeLists.txt"
            version "3.22.1"
        }
    }
}
```

### 9.4 修改 `pubspec.yaml`

```yaml
name: scrfd_ncnn
description: SCRFD face detection plugin using NCNN, via Flutter FFI.
version: 1.0.0
repository: https://github.com/yourcompany/scrfd_ncnn_plugin

environment:
  sdk: '>=3.2.0 <4.0.0'
  flutter: '>=3.16.0'

dependencies:
  flutter:
    sdk: flutter
  ffi: ^3.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  ffigen: ^13.0.0

# ★ FFI Plugin 声明
flutter:
  plugin:
    platforms:
      android:
        ffiPlugin: true
      ios:
        ffiPlugin: true
      linux:
        ffiPlugin: true
      windows:
        ffiPlugin: true
      macos:
        ffiPlugin: true
```

### 9.5 放置 NCNN 库和模型文件

在插件项目中创建以下目录结构：

```
scrfd_ncnn_plugin/
└── android/
    └── src/
        └── main/
            ├── jni/
            │   └── ncnn/                    # NCNN 预编译库
            │       ├── include/
            │       │   └── *.h              # （从 NCNN 解压包复制 include/ 内容）
            │       └── lib/
            │           └── android/
            │               ├── arm64-v8a/
            │               │   └── libncnn.a  # （从 NCNN 解压包复制）
            │               └── armeabi-v7a/
            │                   └── libncnn.a  # （同上）
            └── assets/
                ├── scrfd-1g.param            # （模型结构文件）
                └── scrfd-1g.bin              # （模型权重文件）
```

操作命令：

```bash
cd ~/workspace/scrfd_ncnn_plugin

# 创建目录
mkdir -p android/src/main/jni/ncnn/lib/android/{arm64-v8a,armeabi-v7a}
mkdir -p android/src/main/assets

# 复制 NCNN 库
cp -r ~/workspace/models/ncnn-*/include/* android/src/main/jni/ncnn/include/
cp ~/workspace/models/ncnn-*/lib/android/arm64-v8a/libncnn.a \
   android/src/main/jni/ncnn/lib/android/arm64-v8a/
cp ~/workspace/models/ncnn-*/lib/android/armeabi-v7a/libncnn.a \
   android/src/main/jni/ncnn/lib/android/armeabi-v7a/

# 复制模型文件
cp ~/workspace/models/scrfd*.param android/src/main/assets/scrfd-1g.param
cp ~/workspace/models/scrfd*.bin   android/src/main/assets/scrfd-1g.bin

# 确认
find android/src/main -type f | head -20
```

---

## 十、将 Plugin 集成到已有应用

假设你已有 Flutter 应用在 `~/workspace/your_existing_app/`。

### 10.1 在主应用的 `pubspec.yaml` 中添加依赖

有两种方式：

**方式一：本地路径引用（开发阶段推荐）**

```yaml
# your_existing_app/pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  # 其他已有依赖...

  # SCRFD 人脸检测插件（本地路径）
  scrfd_ncnn:
    path: ../scrfd_ncnn_plugin
```

**方式二：发布到私有 Git 仓库后引用（团队协作阶段）**

```yaml
dependencies:
  scrfd_ncnn:
    git:
      url: https://github.com/yourcompany/scrfd_ncnn_plugin.git
      ref: main
```

添加后执行：

```bash
cd ~/workspace/your_existing_app
flutter pub get
```

### 10.2 在主应用中使用

以下是一个最小化的使用示例，展示如何在你的页面中调用人脸检测：

```dart
// lib/pages/face_detection_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrfd_ncnn/scrfd_ncnn.dart';

class FaceDetectionPage extends StatefulWidget {
  const FaceDetectionPage({super.key});

  @override
  State<FaceDetectionPage> createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  File? _selectedImage;
  List<ScrfdFace>? _faces;
  bool _isDetecting = false;
  String? _errorMsg;
  final ScrfdNcnn _scrfd = ScrfdNcnn();
  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  @override
  void dispose() {
    _scrfd.destroy();
    super.dispose();
  }

  /// 加载模型（App 启动时调用一次）
  Future<void> _loadModel() async {
    try {
      // 获取模型文件的绝对路径
      // 模型文件在 assets 中，运行时需要复制到可访问的文件系统路径
      final paramPath = await _assetFilePath('assets/scrfd-1g.param');
      final binPath = await _assetFilePath('assets/scrfd-1g.bin');

      final ret = await _scrfd.init(paramPath, binPath);
      if (mounted) {
        setState(() => _modelReady = (ret == 0));
      }
    } catch (e) {
      debugPrint('模型加载失败: $e');
    }
  }

  /// 获取 asset 文件的临时路径
  Future<String> _assetFilePath(String assetKey) async {
    // 将 asset 中的模型文件复制到应用私有目录
    // 因为 NCNN 需要通过文件路径加载模型，无法直接读取 assets
    final byteData = await rootBundle.load(assetKey);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${assetKey.split('/').last}');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file.path;
  }

  /// 选择图片并检测
  Future<void> _pickAndDetect() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (file == null) return;

    setState(() {
      _selectedImage = File(file.path);
      _faces = null;
      _errorMsg = null;
      _isDetecting = true;
    });

    try {
      // 读取图片并转为 BGR 格式的字节数组
      final bytes = await File(file.path).readAsBytes();
      final image = decodeImageFromList(bytes);

      // 获取原始图片尺寸
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final bgrBytes = _rgbaToBgr(bytes, img.width, img.height);

      // 调用检测
      final faces = _scrfd.detect(bgrBytes, img.width, img.height);

      setState(() {
        _faces = faces;
        _isDetecting = false;
      });

      debugPrint('检测到 ${faces.length} 张人脸');
      for (var i = 0; i < faces.length; i++) {
        final f = faces[i];
        debugPrint('  #$i: (${f.x.toInt()}, ${f.y.toInt()}) '
            '${f.w.toInt()}×${f.h.toInt()} '
            'score=${f.score.toStringAsFixed(3)}');
      }
    } catch (e) {
      setState(() {
        _errorMsg = '检测失败: $e';
        _isDetecting = false;
      });
    }
  }

  /// RGBA → BGR 转换（image_picker 返回的是 RGBA，NCNN 需要 BGR）
  Uint8List _rgbaToBgr(Uint8List rgba, int width, int height) {
    final bgr = Uint8List(width * height * 3);
    for (var i = 0; i < width * height; i++) {
      final rgbaIdx = i * 4;
      final bgrIdx = i * 3;
      bgr[bgrIdx]     = rgba[rgbaIdx + 2];  // R → B (交换)
      bgr[bgrIdx + 1] = rgba[rgbaIdx + 1];  // G → G
      bgr[bgrIdx + 2] = rgba[rgbaIdx];      // B → R (交换)
    }
    return bgr;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_modelReady ? '🎯 人脸检测' : '⏳ 模型加载中...')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: (_modelReady && !_isDetecting) ? _pickAndDetect : null,
              icon: _isDetecting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_library),
              label: Text(_isDetecting ? 'NCNN 推理中...' : '选择图片检测'),
            ),
            const SizedBox(height: 16),

            // 图片预览 + 结果叠加
            if (_selectedImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: double.infinity,
                  maxWidth: 500,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(_selectedImage!, fit: BoxFit.cover),
                        if (_faces != null && _faces!.isNotEmpty)
                          CustomPaint(
                            painter: _ScrfdPainter(faces: _faces!),
                          ),
                        if (_isDetecting)
                          Container(
                            color: Colors.black38,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Colors.orange),
                                  SizedBox(height: 8),
                                  Text('SCRFD + NCNN 推理中...',
                                      style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // 结果面板
            _buildResultPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultPanel() {
    if (_errorMsg != null) {
      return Card(color: Colors.red.shade50, child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.error, color: red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_errorMsg!, style: const TextStyle(fontSize: 13))),
        ]),
      ));
    }
    if (_selectedImage == null) return const SizedBox.shrink();
    if (_faces == null || _faces!.isEmpty) {
      if (!_isDetecting) return Card(color: Colors.orange.shade50, child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.search_off, color: orange), SizedBox(width: 8),
          Text('未检测到人脸'),
        ]),
      ));
      return const SizedBox.shrink();
    }

    return Card(color: Colors.green.shade50, child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Text('${_faces!.length} 张人脸',
              style: const TextStyle(fontWeight: bold, fontSize: 16, color: green)),
        ]),
        ..._faces!.asMap().entries.map((e) => ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, backgroundColor: Colors.green.shade100,
              child: Text('#${e.key + 1}', style: const TextStyle(fontSize: 11))),
          title: Text('(${e.value.x.toInt()}, ${e.value.y.toInt()}) '
              '${e.value.w.toInt()}×${e.value.h.toInt()}',
              style: const TextStyle(fontSize: 12)),
          trailing: Text('${(e.value.score * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12,
                  color: e.value.score > 0.9 ? green : orange)),
        )),
      ]),
    ));
  }
}

/// 检测结果绘制器
class _ScrfdPainter extends CustomPainter {
  final List<ScrfdFace> faces;
  _ScrfdPainter({required this.faces});

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()..style = PaintingStyle.stroke
        ..strokeWidth = 2.5..color = Colors.greenAccent.withOpacity(0.9);
    final kpPaint = Paint()..style = PaintingStyle.fill..strokeWidth = 5;
    final kpColors = [Colors.blue, Colors.blue, Colors.yellow, Colors.red, Colors.red];

    for (final face in faces) {
      final rect = Rect.fromLTWH(face.x, face.y, face.w, face.h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), boxPaint);

      for (var i = 0; i < face.landmarks.length && i < 5; i++) {
        canvas.drawCircle(
            Offset(face.landmarks[i].$1, face.landmarks[i].$2),
            4, kpPaint..color = kpColors[i]);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScrfdPainter old) => old.faces != faces;
}
```

### 10.3 主应用需要的额外配置

在主应用的 `pubspec.yaml` 中声明 assets：

```yaml
# your_existing_app/pubspec.yaml
flutter:
  uses-material-design: true

  assets:
    - assets/scrfd-1g.param    # 模型文件（插件会自动打包）
    - assets/scrfd-1g.bin

dependencies:
  scrfd_ncnn:
    path: ../scrfd_ncnn_plugin
  image_picker: ^1.1.2
```

---

## 十一、运行测试与验证

### 11.1 编译

```bash
cd ~/workspace/your_existing_app

# 清理并重新获取依赖
flutter clean
flutter pub get

# 编译 Debug 版本（连接真机或模拟器）
flutter run
```

### 11.2 首次编译可能遇到的问题

| 错误信息 | 原因 | 解决方法 |
| --- | --- | --- |
| `cannot find -lncnn` | NCNN 库路径不对 | 检查 `jni/ncnn/lib/android/` 下是否有对应 ABI 的 `libncnn.a` |
| `'net.h' file not found` | NCNN 头文件路径不对 | 检查 `jni/ncnn/include/net.h` 是否存在 |
| `undefined reference to 'scrfd_*'` | C 文件没有被编译 | 检查 `src/CMakeLists.txt` 中的 `add_library` 是否包含了 `.c` 和 `.cpp` 文件 |
| `more than one file was found` | OS X 上的路径大小写问题 | 无关 Android，忽略即可 |

### 11.3 功能验证清单

编译成功并在真机上运行后，按以下步骤验证：

```
□ App 启动后顶部标题变为 "🎯 人脸检测"（不是 "⏳ 模型加载中"）
  → 说明模型加载成功

□ 点击 "选择图片检测" 按钮
  → 弹出相册选择器

□ 选择一张包含清晰正脸的照片
  → 图片显示出来
  → 几乎同时（或 1-2 秒内）出现绿色人脸框
  → 下方显示 "N 张人脸"

□ 选择一张没有人的风景照
  → 显示 "未检测到人脸"

□ 选择一张有多人的合照
  → 每个人脸上都有独立的绿色框
  → 下方列出每个人脸的信息

□ 查看 Android Studio 的 Logcat
  → 过滤 "SCRFD" 关键词
  → 应该能看到 "SCRFD 模型加载成功" 和 "Detected N faces" 的日志
```

### 11.4 性能基准参考

在常见设备上的预期表现（SCRFD-1G 模型，640×640 输入）：

| 设备级别 | 推理耗时 | 体验 |
| --- | --- | --- |
| 骁龙 8 Gen 2 / 8 Gen 3 | 8-15 ms | 非常流畅 |
| 骁龙 888 / 8 Gen 1 | 15-25 ms | 流畅 |
| 骁龙 865 / 855 | 20-35 ms | 可接受 |
| 骁龙 778G / 7 Gen 1 | 30-50 ms | 略有感延迟 |
| 联发科天玑 9000+ | 12-20 ms | 流畅 |
| 低端芯片（如 G85） | 50-120 ms | 明显延迟（建议用 SCRFD-500M 模型） |

如果你的设备性能偏低，可以在 `_loadModel()` 中调用：

```dart
_scrfd.set_input_size(480);  // 或 320（更快但精度略降）
```

---

## 十二、常见问题排查手册

> **遇到问题时，按顺序排查以下各项。大部分问题都可以在这里找到答案。**

### Q1: 编译报错 "cannot find -lncnn"

**现象**：` linker command failed with exit code 1 (use -v to see invocation) `

**原因**：CMake 找不到 NCNN 的静态库文件

**排查步骤**：

```bash
# 1. 确认文件是否存在
ls -la scrfd_ncnn_plugin/android/src/main/jni/ncnn/lib/android/arm64-v8a/libncnn.a

# 2. 如果不存在，重新复制（见 9.5 节）

# 3. 确认 CMakeLists.txt 中的路径正确
# 打开 android/CMakeLists.txt，检查 NCNN_DIR 变量
```

### Q2: 运行时报错 "UnsatisfiedLinkError: dlopen failed"

**现象**：App 启动即崩溃，logcat 显示找不到 `libscrfd_ncnn.so`

**原因**：native 库没有被打包进 APK，或者架构不匹配

**解决**：

```groovy
// 确认 android/build.gradle 中有 abiFilters
abiFilters 'arm64-v8a', 'armeabi-v7a'

// 确认你的测试手机的架构
# 大多数现代手机是 arm64-v8a
# 可以在 adb shell 中执行: abuild-getprop ro.product.cpu.abi
```

### Q3: 模型加载失败（返回非 0）

**现象**：App 启动后一直显示 "⏳ 模型加载中"，logcat 显示 "模型加载失败"

**排查顺序**：

1. **模型文件是否存在于 assets？** → 检查 `android/src/main/assets/` 下是否有 `.param` 和 `.bin`
2. **模型文件是否被正确复制到应用目录？** → 在 `_assetFilePath()` 中加日志确认文件路径
3. **模型文件是否损坏？** → 对比文件大小（SCRFD-1G 的 .bin 应该约 2-4 MB）
4. **.param 文件中的输入节点名是否匹配？** → 用文本编辑器打开 .param，第一行应该是版本号，第二行开始是层定义；搜索 `Input` 确认名称

### Q4: 检测结果全为空（没报错但检测不到人脸）

**排查顺序**：

1. **图像颜色顺序** → 确认传入的是 **BGR** 不是 RGB（见 10.2 节的 `_rgbaToBgr` 函数）
2. **归一化参数** → 确认 `scrfd_detector.cpp` 中的 mean_vals 是 `{127.5, 127.5, 127.5}`，norm_vals 是 `{1/128, 1/128, 1/128}`
3. **置信度阈值是否过高** → 尝试调用 `_scrfd.set_score_threshold(0.3)` 降低阈值
4. **图片太小** → 确保传入的图片宽高至少 > 100 像素

### Q5: 人脸框位置整体偏移或大小不对

**原因**：通常是图像预处理时的缩放/填充与后处理时的坐标还原不匹配

**解决**：当前的 `scrfd_detector.cpp` 使用的是直接缩放（非 letterbox），输出的坐标是基于 `input_size_`（默认 640）的。如果在 Dart 侧显示时发现偏移，需要在绘制时按比例映射：

```dart
// 假设原图尺寸是 (imgW, imgH)，模型输入是 640
final scale = 640.0 / max(imgW, imgH);
// 绘制时：
final drawX = face.x / scale;
final drawY = face.y / scale;
final drawW = face.w / scale;
final drawH = face.h / scale;
```

### Q6: 检测速度很慢（>500ms）

**优化建议**：

1. 降低输入尺寸：`_scrfd.set_inputSize(480)` 或 `320`
2. 减少线程数：有时线程太多反而因调度开销变慢，试试 `set_num_threads(2)`
3. 检查是否在主线程调用了 `detect()` → 应该用 `compute()` 放到 isolate
4. 限制输入图片分辨率：`imagePicker` 时设置 `maxWidth: 1280, maxHeight: 1280`

### Q7: 内存占用过高导致 OOM

**解决**：

1. 限制图片输入分辨率（见上文）
2. 每次检测完及时释放 Dart 侧的图片引用（`setState` 时设为 null）
3. 确保 `_scrfd.destroy()` 在 `dispose()` 中被调用
4. 不要缓存过多历史检测结果

### Q8: 如何切换到其他模型（如 SCRFD-500M 或 SCRFD-2.5G）？

只需替换 `android/src/main/assets/` 下的 `.param` 和 `.bin` 文件，**不需要改任何代码**。不同模型的区别：

| 模型 | 文件大小 | 精度 | 速度 | 适用场景 |
| --- | --- | --- | --- | --- |
| SCRFD-500M | ~1 MB | 中等 | 最快 | 低端机 / IoT |
| SCRFD-1G | ~2-4 MB | 高 | 快 | **推荐默认** |
| SCRFD-2.5G | ~6-8 MB | 最高 | 中等 | 追求精度的场景 |

---

## 十三、附录：关键概念速查表

### A. 文件扩展名一览

| 扩展名 | 是什么 | 谁生成的 |
| --- | --- | --- |
| `.param` | NCNN 模型结构文件（文本格式，记录网络层级和连接关系） | onnx2ncnn 工具转换 |
| `.bin` | NCNN 模型权重文件（二进制格式，记录每层的参数值） | onnx2ncnn 工具转换 |
| `.onnx` | ONNX 通用模型格式 | InsightFace 导出 |
| `.so` | Android 共享库（编译后的 C++ 代码） | CMake + NDK 编译 |
| `.h` | C/C++ 头文件（声明函数、类、结构体） | 手写 |
| `.cpp` | C++ 源文件（实现逻辑） | 手写 |
| `.c` | C 源文件（FFI 桥接层） | 手写 |

### B. SCRFD 输出的 5 个关键点

```
        左眼(0) ●           ● 右眼(1)
                              
               ● 鼻尖(2)
                              
   右嘴角(3) ●  ━━━━━━  ● 左嘴角(4)

注意顺序：左眼 → 右眼 → 鼻尖 → 右嘴角 → 左嘴角
（这与某些其他人脸检测库的关键点顺序可能不同）
```

### C. NCNN 常用 API 速查

```cpp
// 加载模型
net.load_param("xxx.param");
net.load_model("xxx.bin");

// 图像 → Mat
auto mat = ncnn::Mat::from_pixels_resize(
    pixels, ncnn::MAT_BGR, w, h, stride, target_w, target_h
);

// 归一化
mat.substract_mean_normalize(mean_vals, norm_vals);

// 推理
auto ex = net.create_extractor();
ex.input("input_name", mat);
ex.extract("output_name", output_mat);

// 读取 Mat 数据
const float* ptr = output_mat.row(i);  // 第 i 行的数据
int w = output_mat.w;                   // 宽度（列数）
int h = output_mat.h;                   // 高度（行数）
int c = output_mat.c;                   // 通道数
```

### D. Dart FFI 常用模式速查

```dart
// 加载库
final lib = DynamicLibrary.process();  // 或 DynamicLibrary.open("path.so")

// 绑定函数
final myFunc = lib
    .lookup<NativeFunction<Int32 Function(Int32)>>('my_c_function')
    .asFunction<int Function(int)>();

// 分配 C 内存
final ptr = calloc<Float>(100);
// ... 使用 ...
calloc.free(ptr);  // 必须！

// String ↔ char*
final nativeStr = "hello".toNativeUtf8();
// ... 使用 ...
calloc.free(nativeStr);  // 必须!

// Uint8List → 指针
final data = Uint8List.fromList([1,2,3]);
final pointer = data.cast<Utf8>();
final address = pointer.value;  // C 层收到的地址
```

### E. 参考资源

| 资源 | 地址 | 用途 |
| --- | --- | --- |
| NCNN 官方仓库 | github.com/Tencent/ncnn | NCNN API 文档、工具下载 |
| NCNN Android SCRFD Demo | github.com/nihui/ncnn-android-scrfd | **最重要的参考**（官方完整 Android 示例） |
| InsightFace | github.com/deepinsight/insightface | SCRFD 模型来源、ONNX 导出 |
| Flutter FFI 官方文档 | docs.flutter.dev/interop/c-interop | FFI 绑定教程 |
| Flutter FFI Plugin 模板示例 | github.com/ikuokuo/start-flutter (demo_ncnn) | FFI Plugin 项目结构参考 |
| Netron | netron.app | 可视化查看 .onnx/.param 模型结构 |
