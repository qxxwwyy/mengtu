#!/bin/bash
set -e

# Change directory to the repository root
cd "$(dirname "$0")/.."

echo "[fetch-native] Creating directories..."
mkdir -p scrfd_ncnn_plugin/android/src/main/jni/ncnn/include
mkdir -p scrfd_ncnn_plugin/android/src/main/jni/ncnn/lib/android/arm64-v8a
mkdir -p scrfd_ncnn_plugin/assets

echo "[fetch-native] Downloading NCNN prebuilt binary..."
curl -L -o ncnn.zip https://github.com/Tencent/ncnn/releases/download/20250428/ncnn-20250428-android-vulkan.zip

echo "[fetch-native] Extracting NCNN headers and library..."
unzip -q ncnn.zip -d ncnn_temp

# NCNN prebuilt structure: ncnn-20250428-android-vulkan/arm64-v8a/
#   include/ncnn/*.h  (net.h, mat.h, ... — no umbrella ncnn.h)
#   include/glslang/*.h
#   lib/libncnn.a
NCNN_ROOT="$(ls -d ncnn_temp/ncnn-*-android-vulkan 2>/dev/null | head -1)"
if [ -z "$NCNN_ROOT" ]; then
    echo "[fetch-native] ERROR: NCNN root directory not found"
    exit 1
fi
echo "[fetch-native] NCNN root: $NCNN_ROOT"

# Copy entire include/ (contains ncnn/ and glslang/ subdirs) and libncnn.a
cp -r "$NCNN_ROOT/arm64-v8a/include/"* scrfd_ncnn_plugin/android/src/main/jni/ncnn/include/
cp "$NCNN_ROOT/arm64-v8a/lib/libncnn.a" scrfd_ncnn_plugin/android/src/main/jni/ncnn/lib/android/arm64-v8a/

echo "[fetch-native] Verifying headers..."
ls scrfd_ncnn_plugin/android/src/main/jni/ncnn/include/ncnn/net.h
ls scrfd_ncnn_plugin/android/src/main/jni/ncnn/lib/android/arm64-v8a/libncnn.a

echo "[fetch-native] Downloading SCRFD models..."
curl -L -o scrfd_ncnn_plugin/assets/scrfd_2.5g_kps-opt2.param \
  https://raw.githubusercontent.com/nihui/ncnn-android-scrfd/master/app/src/main/assets/scrfd_2.5g_kps-opt2.param
curl -L -o scrfd_ncnn_plugin/assets/scrfd_2.5g_kps-opt2.bin \
  https://raw.githubusercontent.com/nihui/ncnn-android-scrfd/master/app/src/main/assets/scrfd_2.5g_kps-opt2.bin

echo "[fetch-native] Cleaning up temp files..."
rm -rf ncnn.zip ncnn_temp

echo "[fetch-native] Done! Native binaries and models successfully set up."
