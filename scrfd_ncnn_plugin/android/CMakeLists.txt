# android/CMakeLists.txt — Android NDK 构建入口
#
# 由 android/build.gradle 的 externalNativeBuild 调用。
# 指向 src/ 的 CMake（编译 .so），NCNN_DIR 指 jni/ncnn。
cmake_minimum_required(VERSION 3.22)

set(NCNN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/main/jni/ncnn")
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../src
                 ${CMAKE_BINARY_DIR}/scrfd_native)
