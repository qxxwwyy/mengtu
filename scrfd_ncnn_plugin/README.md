# scrfd_ncnn — SCRFD 人脸检测 NCNN Flutter 插件

萌图项目专用 FFI 插件。纯 C ABI + NCNN 静态库，CPU 推理，无 Vulkan、无 GMS 依赖。

## 二进制依赖（不入 git，按下方说明下载）

本插件运行需要两类二进制文件，由 `.gitignore` 排除。**克隆后必须手动下载**：

### 1. NCNN 静态库 → `android/src/main/jni/ncnn/`

```bash
# 下载 ncnn-android-vulkan 预编译包（含 libncnn.a + headers）
curl -L -o ncnn.zip \
  https://github.com/Tencent/ncnn/releases/download/20250428/ncnn-20250428-android-vulkan.zip
unzip ncnn.zip

# 仅取 arm64-v8a（与主项目 ABI 一致）
mkdir -p android/src/main/jni/ncnn/include
mkdir -p android/src/main/jni/ncnn/lib/android/arm64-v8a
cp -r ncnn-20250428-android-vulkan/arm64-v8a/include/ncnn \
      android/src/main/jni/ncnn/include/
cp ncnn-20250428-android-vulkan/arm64-v8a/lib/libncnn.a \
   android/src/main/jni/ncnn/lib/android/arm64-v8a/
```

### 2. SCRFD 模型 → `android/src/main/assets/`

```bash
# SCRFD-2.5G（带 5 关键点，opt2 优化版，~1.6MB）
curl -L -o android/src/main/assets/scrfd_2.5g_kps-opt2.param \
  https://raw.githubusercontent.com/nihui/ncnn-android-scrfd/master/app/src/main/assets/scrfd_2.5g_kps-opt2.param
curl -L -o android/src/main/assets/scrfd_2.5g_kps-opt2.bin \
  https://raw.githubusercontent.com/nihui/ncnn-android-scrfd/master/app/src/main/assets/scrfd_2.5g_kps-opt2.bin
```

## 构建要求

- NDK 26.x（`26.1.10909125`）
- CMake 3.22+
- Android ABI：仅 `arm64-v8a`
- `c++_shared` STL

## API

```dart
final scrfd = ScrfdNcnn();
final ret = await scrfd.init(paramPath, binPath); // 0 成功
final faces = scrfd.detect(bgrBytes, width, height); // BGR Uint8List
scrfd.destroy();
```

`detect` 输出坐标在【输入图原始像素】空间（C++ 已 rescale 回原图）。
调用方负责 RGBA→BGR 转换（见 `ScrfdNcnn.rgbaToBgr`）。
