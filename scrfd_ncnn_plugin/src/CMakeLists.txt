# src/CMakeLists.txt — 编译 scrfd_ncnn.so（链 NCNN 静态库）
#
# 被 android/CMakeLists.txt add_subdirectory。
# NCNN_DIR 由上层（android/CMakeLists.txt）指向 jni/ncnn。
cmake_minimum_required(VERSION 3.22)
project(scrfd_ncnn LANGUAGES CXX C)

# NCNN 头文件 + 静态库
if(NOT DEFINED NCNN_DIR)
    set(NCNN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/jni/ncnn")
endif()
message(STATUS "NCNN_DIR = ${NCNN_DIR}")

include_directories(${NCNN_DIR}/include)

add_library(scrfd_ncnn SHARED
    scrfd_api.c
    scrfd_detector.cpp
)

find_package(OpenMP)
if(OpenMP_CXX_FOUND)
    target_link_libraries(scrfd_ncnn OpenMP::OpenMP_CXX)
else()
    # Fallback: NDK libomp (always available in NDK 21+)
    target_link_libraries(scrfd_ncnn omp)
endif()

# 链接 NCNN 静态库（Android ABI 自动选 arm64-v8a 等）
target_link_libraries(scrfd_ncnn
    ${NCNN_DIR}/lib/android/${ANDROID_ABI}/libncnn.a
    log    # android logging
    z
    m
)

# C++17 + 异常/RTTI（NCNN 需要）
target_compile_features(scrfd_ncnn PUBLIC cxx_std_17)
