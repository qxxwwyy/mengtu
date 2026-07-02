// scrfd_detector.cpp — SCRFD 人脸检测 NCNN 实现
//
// 参考 Tencent/ncnn 官方 examples/scrfd.cpp + nihui/ncnn-android-scrfd。
// SCRFD 是 anchor-free 多尺度人脸检测器，输出 bbox + 5 关键点。
//
// 输入：BGR 像素 → resize 到 input_size_×input_size_（默认 640，直接 resize 非 letterbox）
//       归一化 mean={127.5} norm={1/128}（映射到 [-1,1]）
// 输出：3 个尺度（stride 8/16/32）的 score + bbox + kps，经 NMS 后输出
//
// 配置：CPU only（use_vulkan=false）+ BF16 存储（ARMv8.2+ 加速）+ light_mode。
// 性能：SCRFD-2.5G @ 640 在骁龙 8 系约 8-30ms（参考指南 §11.4）。
#include "scrfd_detector.h"

#include <android/log.h>
#include <ncnn/net.h>
#include <ncnn/mat.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

#define TAG "scrfd_ncnn"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

namespace {

struct FaceResult {
    float x, y, w, h;
    float score;
    float landmarks[10]; // 5 × (x, y)
};

// NMS 辅助
float iou(const FaceResult& a, const FaceResult& b) {
    float ax1 = a.x, ay1 = a.y, ax2 = a.x + a.w, ay2 = a.y + a.h;
    float bx1 = b.x, by1 = b.y, bx2 = b.x + b.w, by2 = b.y + b.h;
    float ix1 = std::max(ax1, bx1), iy1 = std::max(ay1, by1);
    float ix2 = std::min(ax2, bx2), iy2 = std::min(ay2, by2);
    float iw = std::max(0.f, ix2 - ix1);
    float ih = std::max(0.f, iy2 - iy1);
    float inter = iw * ih;
    float ua = a.w * a.h + b.w * b.h - inter;
    return ua > 0 ? inter / ua : 0.f;
}

static void generate_proposals(const ncnn::Mat& score_blob,
                               const ncnn::Mat& bbox_blob,
                               const ncnn::Mat& kps_blob,
                               int stride, float threshold,
                               std::vector<FaceResult>& faces) {
    if (score_blob.empty() || bbox_blob.empty() || score_blob.c * 4 > bbox_blob.c) return;
    if (!kps_blob.empty() && score_blob.c * 10 > kps_blob.c) return;
    if (bbox_blob.w != score_blob.w || bbox_blob.h != score_blob.h) return;

    const int feat_h = score_blob.h;
    const int feat_w = score_blob.w;

    for (int q = 0; q < score_blob.c; q++) {
        const float* scores = score_blob.channel(q);

        for (int y = 0; y < feat_h; y++) {
            for (int x = 0; x < feat_w; x++) {
                int idx = y * feat_w + x;
                float prob = scores[idx];
                if (prob < threshold) continue;

                // Anchor centre
                float ax = (x + 0.5f) * stride;
                float ay = (y + 0.5f) * stride;

                // BBox: channel-based access — model outputs in stride-space,
                // must multiply by stride to get pixel-space distances
                float dx = bbox_blob.channel(0 + q * 4)[idx] * stride;
                float dy = bbox_blob.channel(1 + q * 4)[idx] * stride;
                float dw = bbox_blob.channel(2 + q * 4)[idx] * stride;
                float dh = bbox_blob.channel(3 + q * 4)[idx] * stride;

                FaceResult fr;
                fr.x = ax - dx;
                fr.y = ay - dy;
                fr.w = dx + dw;
                fr.h = dy + dh;
                fr.score = prob;
                std::memset(fr.landmarks, 0, sizeof(fr.landmarks));

                // Key-points: channel-based access, NO stride multiplication
                if (!kps_blob.empty()) {
                    for (int k = 0; k < 5; k++) {
                        fr.landmarks[k * 2]     = ax + kps_blob.channel(k * 2 + q * 10)[idx];
                        fr.landmarks[k * 2 + 1] = ay + kps_blob.channel(k * 2 + 1 + q * 10)[idx];
                    }
                }

                faces.push_back(fr);
            }
        }
    }
}

// 单例检测器
struct Detector {
    ncnn::Net net;
    bool loaded = false;
    float score_threshold = 0.5f;
    float nms_threshold = 0.45f;
    int input_size = 640;
    int num_threads = 4;

    int load(const char* param_path, const char* bin_path) {
        if (loaded) {
            return 0; // Idempotent load, avoid clearing if already loaded
        }
        net.opt.use_vulkan_compute = false; // CPU 推理（小模型更快更稳）
        net.opt.num_threads = num_threads;
        net.opt.use_bf16_storage = true;    // ARMv8.2+ 加速

        int rp = net.load_param(param_path);
        int rm = net.load_model(bin_path);
        if (rp != 0 || rm != 0) {
            LOGE("模型加载失败 param=%d model=%d (param=%s bin=%s)",
                 rp, rm, param_path, bin_path);
            return -1;
        }
        loaded = true;
        LOGI("SCRFD 模型加载成功 (input_size=%d threads=%d)",
             input_size, num_threads);
        return 0;
    }

    std::vector<FaceResult> detect(
        const unsigned char* rgba_data, int width, int height, int stride) {
        std::vector<FaceResult> faces;
        if (!loaded) return faces;

        // 预处理：RGBA → BGR + resize 到 input_size×input_size（直接 resize，非 letterbox）
        ncnn::Mat in = ncnn::Mat::from_pixels_resize(
            rgba_data, ncnn::Mat::PIXEL_RGBA2BGR, width, height, stride,
            input_size, input_size);
        const float mean_vals[3] = {127.5f, 127.5f, 127.5f};
        const float norm_vals[3] = {1.0f / 128.0f, 1.0f / 128.0f, 1.0f / 128.0f};
        in.substract_mean_normalize(mean_vals, norm_vals);

        ncnn::Extractor ex = net.create_extractor();
        ex.set_light_mode(true);
        ex.set_num_threads(num_threads);
        // 输入 blob 名「input.1」（scrfd_2.5g_kps-opt2.param 的 Input 层定义）
        ex.input("input.1", in);

        // 3 个 stride（8/16/32）输出。SCRFD 节点命名：score_N / bbox_N / kps_N。
        static const char* kScoreNames[3] = {"score_8", "score_16", "score_32"};
        static const char* kBboxNames[3] = {"bbox_8", "bbox_16", "bbox_32"};
        static const char* kKpsNames[3] = {"kps_8", "kps_16", "kps_32"};
        static const int kStrides[3] = {8, 16, 32};

        // 缩放因子：640-space → 原图像素
        const float x_scale = (float)width / input_size;
        const float y_scale = (float)height / input_size;

        for (int s = 0; s < 3; s++) {
            ncnn::Mat score_mat, bbox_mat, kps_mat;
            if (ex.extract(kScoreNames[s], score_mat) != 0) continue;
            if (ex.extract(kBboxNames[s], bbox_mat) != 0) continue;
            if (ex.extract(kKpsNames[s], kps_mat) != 0) continue;

            const int stride = kStrides[s];
            const int feat_size = input_size / stride; // 正方形特征图
            const int num_anchors = 2; // SCRFD 每位置 2 anchor

            const float* score_ptr = (const float*)score_mat.data;
            const float* bbox_ptr = (const float*)bbox_mat.data;
            const float* kps_ptr = (const float*)kps_mat.data;
            std::vector<FaceResult> local_faces;
            generate_proposals(score_mat, bbox_mat, kps_mat, kStrides[s], score_threshold, local_faces);

            for (auto& fr : local_faces) {
                fr.x *= x_scale;
                fr.y *= y_scale;
                fr.w *= x_scale;
                fr.h *= y_scale;
                for (int k = 0; k < 5; k++) {
                    fr.landmarks[k * 2] *= x_scale;
                    fr.landmarks[k * 2 + 1] *= y_scale;
                }
                faces.push_back(fr);
            }
        }

        // 跨尺度 NMS
        std::sort(faces.begin(), faces.end(),
                  [](const FaceResult& a, const FaceResult& b) {
                      return a.score > b.score;
                  });
        std::vector<FaceResult> picked;
        std::vector<char> suppressed(faces.size(), 0);
        for (size_t i = 0; i < faces.size(); i++) {
            if (suppressed[i]) continue;
            picked.push_back(faces[i]);
            for (size_t j = i + 1; j < faces.size(); j++) {
                if (suppressed[j]) continue;
                if (iou(faces[i], faces[j]) > nms_threshold) {
                    suppressed[j] = 1;
                }
            }
        }
        return picked;
    }
};

// 全局单例与互斥锁
Detector* g_detector = nullptr;
std::mutex g_detector_mutex;

} // namespace

// ===== extern "C" 接口（scrfd_api.c 调用）=====
extern "C" {

int scrfd_detector_init(const char* param_path, const char* bin_path) {
    std::lock_guard<std::mutex> lock(g_detector_mutex);
    if (!g_detector) g_detector = new Detector();
    return g_detector->load(param_path, bin_path);
}

void scrfd_detector_destroy(void) {
    std::lock_guard<std::mutex> lock(g_detector_mutex);
    if (g_detector) {
        delete g_detector;
        g_detector = nullptr;
    }
}

int scrfd_detector_detect(
    const unsigned char* rgba_data, int width, int height, int stride,
    float* results, int max_results) {
    if (!g_detector || !g_detector->loaded) return 0;
    std::vector<FaceResult> faces =
        g_detector->detect(rgba_data, width, height, stride);

    int n = (int)faces.size();
    if (n > max_results) n = max_results;
    for (int i = 0; i < n; i++) {
        const FaceResult& f = faces[i];
        float* out = results + i * 15;
        out[0] = f.x;
        out[1] = f.y;
        out[2] = f.w;
        out[3] = f.h;
        out[4] = f.score;
        memcpy(out + 5, f.landmarks, 10 * sizeof(float));
    }
    return n;
}

void scrfd_detector_set_score_threshold(float threshold) {
    if (g_detector) g_detector->score_threshold = threshold;
}

void scrfd_detector_set_nms_threshold(float threshold) {
    if (g_detector) g_detector->nms_threshold = threshold;
}

void scrfd_detector_set_input_size(int size) {
    if (g_detector) g_detector->input_size = size;
}

void scrfd_detector_set_num_threads(int threads) {
    if (g_detector && threads > 0) g_detector->num_threads = threads;
}

} // extern "C"
