// scrfd_detector.h — SCRFD NCNN 检测器（C++ 接口，供 scrfd_api.c 调用）
//
// 单例 Detector（全局 g_detector），生命周期由 scrfd_init/destroy 管理。
#ifndef SCRFD_DETECTOR_H
#define SCRFD_DETECTOR_H

#ifdef __cplusplus
extern "C" {
#endif

// 这些函数由 scrfd_detector.cpp 实现，scrfd_api.c 调用。
int scrfd_detector_init(const char* param_path, const char* bin_path);
void scrfd_detector_destroy(void);
int scrfd_detector_detect(
    const unsigned char* bgr_data,
    int width, int height, int stride,
    float* results, int max_results);
void scrfd_detector_set_score_threshold(float threshold);
void scrfd_detector_set_nms_threshold(float threshold);
void scrfd_detector_set_input_size(int size);
void scrfd_detector_set_num_threads(int threads);

#ifdef __cplusplus
}
#endif

#endif // SCRFD_DETECTOR_H
