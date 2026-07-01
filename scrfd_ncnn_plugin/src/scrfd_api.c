// scrfd_api.c — SCRFD 检测器 C ABI 实现（薄包装层）
//
// 仅做 C ↔ C++ 桥接：把 C ABI 函数转发给 scrfd_detector.cpp 的全局 Detector。
// 所有检测逻辑在 scrfd_detector.cpp，本文件不依赖 NCNN 头文件，编译快。
#include "scrfd_api.h"
#include "scrfd_detector.h"

// 版本字符串（静态，scrfd_version 返回其指针）
static const char* kVersion = "scrfd_ncnn 1.0.0 (ncnn + SCRFD 2.5G)";

int scrfd_init(const char* param_path, const char* bin_path) {
    return scrfd_detector_init(param_path, bin_path);
}

void scrfd_destroy(void) {
    scrfd_detector_destroy();
}

int scrfd_detect(
    const unsigned char* rgba_data,
    int width, int height, int stride,
    float* results, int max_results) {
    return scrfd_detector_detect(
        rgba_data, width, height, stride, results, max_results);
}

void scrfd_set_score_threshold(float threshold) {
    scrfd_detector_set_score_threshold(threshold);
}

void scrfd_set_nms_threshold(float threshold) {
    scrfd_detector_set_nms_threshold(threshold);
}

void scrfd_set_input_size(int size) {
    scrfd_detector_set_input_size(size);
}

void scrfd_set_num_threads(int threads) {
    scrfd_detector_set_num_threads(threads);
}

const char* scrfd_version(void) {
    return kVersion;
}
