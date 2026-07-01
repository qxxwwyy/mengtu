// scrfd_api.h — SCRFD 检测器 C ABI（供 Dart FFI 调用）
//
// 纯 C 接口包装 C++ Detector。导出符号用 EXPORT 宏（Android __attribute__((visibility)))).
// 结果数组布局：每张人脸 15 floats：
//   [x, y, w, h, score, kx0, ky0, kx1, ky1, kx2, ky2, kx3, ky3, kx4, ky4]
//   关键点顺序：左眼(0) 右眼(1) 鼻尖(2) 右嘴角(3) 左嘴角(4)
// 坐标均在【输入图原始像素】空间（C++ 已 rescale 回原图，非 640-space）。
#ifndef SCRFD_API_H
#define SCRFD_API_H

#include <stdint.h>

#if defined(_WIN32) || defined(__CYGWIN__)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// 初始化检测器：加载 .param / .bin。返回 0 成功，非 0 失败。
/// 可重复调用（内部先销毁旧实例）。
EXPORT int scrfd_init(const char* param_path, const char* bin_path);

/// 销毁检测器（释放 NCNN 网络内存）。
EXPORT void scrfd_destroy(void);

/// 检测人脸。
/// [rgba_data]  RGBA 像素字节（width*height*4，紧密排列无 padding）
/// [width/height]  输入图像素尺寸
/// [stride]  每行字节数（= width * 4 for 紧密排列）
/// [results]  调用方分配 of float 数组，容量 >= max_results * 15
/// [max_results]  results 最多容纳的人脸数
/// 返回实际检测到的人脸数（<= max_results）。
EXPORT int scrfd_detect(
    const unsigned char* rgba_data,
    int width, int height, int stride,
    float* results, int max_results);

/// 置信度阈值（默认 0.5）。
EXPORT void scrfd_set_score_threshold(float threshold);

/// NMS IoU 阈值（默认 0.45）。
EXPORT void scrfd_set_nms_threshold(float threshold);

/// 输入尺寸（默认 640，正方形）。
EXPORT void scrfd_set_input_size(int size);

/// 推理线程数（默认 4）。
EXPORT void scrfd_set_num_threads(int threads);

/// 版本信息（静态字符串，调用方不应 free）。
EXPORT const char* scrfd_version(void);

#ifdef __cplusplus
}
#endif

#endif // SCRFD_API_H
