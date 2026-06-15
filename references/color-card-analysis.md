# 取色卡 Color_Card 核心源码分析报告

> 基于取色卡 v1.11.0 源码分析，供萌图 Dart 移植参考。
> **⚠️ GPL-3.0 合规决策（2026-06-11）：取色卡仅作为功能设计和影调分类规则的参考，不参考其算法实现代码。MMCQ/K-Means 算法移植优先参考 MIT 许可的 color-thief。本报告中的算法分析仅供理解设计思路，不可作为实现参考。**

---

## 一、项目整体架构

```
UI层
 ├── ColorService (color_service.py) ──→ DominantColorExtractor线程
 │       └── color.extract_dominant_colors() ──→ MMCQ / K-Means
 │       └── color.find_dominant_color_positions()
 ├── HistogramService (histogram_service.py) ──→ HistogramCalculator线程
 │       └── color.calculate_histogram()
 │       └── color.calculate_rgb_histogram()
 │       └── color.calculate_hue_histogram()
 ├── ImageService (image_service.py) ──→ ProgressiveImageLoader线程
 │       └── ColorSpaceDetector.detect()
 │       └── _convert_to_srgb() (ICC转换)
 │       └── ImageMemoryManager (LRU图片缓存)
 └── ToneAnalysisService (tone_analysis.py)
         └── color.calculate_luminance_from_array()
         └── ToneAnalysisCache (LRU)
```

---

## 二、core/color.py — 核心色彩算法模块（~600行）

### 2.1 色彩空间转换

**关键数据结构：`_COLORSPACE_MATRICES`**
- 支持 5 种色彩空间：sRGB、Adobe RGB、ProPhoto RGB、DCI-P3、Display P3
- 每种包含：`rgb_to_xyz`（3×3矩阵）、`xyz_to_rgb`（3×3矩阵）、`white_point`（D65/D50）、`gamma`值、`use_srgb_curve`标志

**核心函数签名：**

| 函数 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `rgb_to_hsb(r, g, b)` | int×3 | (H:0-360, S:0-100, B:0-100) | RGB→HSB |
| `rgb_to_lab(r, g, b, colorspace='sRGB')` | int×3, str | (L:0-100, A:-128~127, B:-128~127) | RGB→CIELAB |
| `rgb_to_hex(r, g, b)` | int×3 | "#RRGGBB" | |
| `hex_to_rgb(hex_value)` | str | (R, G, B) | |
| `rgb_to_hsl(r, g, b)` | int×3 | (H, S, L) | 0-360/0-100/0-100 |
| `rgb_to_cmyk(r, g, b)` | int×3 | (C, M, Y, K) | 0-100 |
| `lab_to_rgb(L, A, B, colorspace)` | float×3, str | (R, G, B) | LAB→RGB逆转换 |
| `convert_rgb_colorspace(r,g,b,src,tgt)` | int×3, str×2 | (R, G, B) | 色彩空间间转换（以LAB为中介） |

**RGB→LAB 转换步骤：**
1. RGB归一化到 [0, 1]
2. Gamma校正：若 `use_srgb_curve=True`，使用 sRGB 分段函数（阈值0.04045）；否则用 `c^gamma`
3. 矩阵乘法 RGB→XYZ
4. 除以白点坐标归一化
5. 应用 LAB f 函数（阈值0.008856，分段线性/立方根）
6. 计算 L、A、B 值

### 2.2 MMCQ 主色调提取算法

**`_ColorCube` 类（核心数据结构）：**
- 存储：像素数组 (N×3)
- 缓存属性：`_cache_volume`、`_cache_avg_color`、`_cache_ranges`（惰性计算+缓存）

**关键方法：**
- `get_volume()` → 三通道范围乘积
- `get_longest_axis()` → 'r'/'g'/'b'
- `split()` → 沿最长轴中位数切分，返回两个新 Cube

**MMCQ 量化算法步骤：**
1. 初始化：所有像素放入一个 Cube
2. 循环直到 Cube 数量达到目标 count：
   a. 找到体积最大的 Cube（且像素数 > 1）
   b. 移除该 Cube，沿最长轴的中位数切分为两个子 Cube
   c. 添加两个子 Cube
3. 返回 Cube 列表

**切分策略：** 按最长轴排序，在中位数位置切分（非均匀，自动平衡像素数）

### 2.3 K-Means 聚类算法

**算法步骤：**
1. 采样：`sample_step` 步长采样 + 合并边缘像素
2. K-Means++ 初始化：
   - 随机选第一个中心
   - 后续中心以距离平方为概率选择（距离越远越可能被选中）
   - 增量更新最小距离（不重算全部）
3. 迭代（最多 `max_iterations=10`）：
   - **距离计算优化**：展开式 `||p-c||² = ||p||² - 2*p·c + ||c||²`
   - 分配标签：`argmin(distances)`
   - 更新中心：聚类内均值，空聚类保留原中心
   - 收敛检查：`allclose(centroids, new_centroids)`
4. 按聚类大小降序排列

**关键限制：** 颜色数量 3-8

### 2.4 统一入口

**`extract_dominant_colors(image, count, sample_step, original_pixels, algorithm)`**
- `algorithm='mmcq'` 或 `'kmeans'`
- `original_pixels` 优先于 `image`（支持原始色彩空间数据）
- 采样策略：等间隔采样 + 保留边缘像素（right_edge + bottom_edge）

### 2.5 主色调位置查找

**`find_dominant_color_positions(image, dominant_colors, sample_step, original_pixels)`**
- 计算所有采样像素到各主色调的欧氏距离
- 每个聚类内取平均坐标，归一化为相对坐标 `(rel_x, rel_y)`

### 2.6 Zone 系统

- 255 平分 9 区，每区宽 28.333
- `get_zone(luminance)` → "0-1" ~ "8-9"

---

## 三、core/histogram_service.py — 直方图服务（~450行）

### 3.1 HistogramCalculator

```
class HistogramCalculator(QThread):
    finished = Signal(object)
    error = Signal(str)
    
    __init__(image: QImage, calc_type: str, sample_step: int, gamma: float)
    cancel() -> None  # 设标志位，不阻塞
    run() -> None     # 子线程执行
```

- 构造时 `image.copy()` 避免线程安全问题
- `calc_type` 支持 "luminance"、"rgb"、"hue"

### 3.2 HistogramService

**关键特性：**
- **延迟计算**：`QTimer.singleShot(delay_ms)` 延迟启动，避免频繁触发
- **缓存复用**：先查 HistogramCache，命中直接返回
- **自适应采样步长**：
  - fine 模式：step=1（全像素）
  - fast 模式：根据像素数自适应
    - >2000万 → step=6
    - >800万 → step=5
    - >400万 → step=4
    - >100万 → step=3
    - ≤100万 → step=2
- **取消机制**：设标志位 + 定时清理已结束线程

**统计信息计算：**
- 加权均值、加权标准差（直接从直方图计算）
- 中位数：`searchsorted(cumsum, total/2)`
- min/max：`nonzero(counts)` 首尾

---

## 四、core/tone_analysis.py — 影调分析（~400行）

### 4.1 数据结构

```python
class ToneKey(str, Enum):     # HIGH / MID / LOW / FULL
class ToneRange(str, Enum):   # LONG / MEDIUM / SHORT

@dataclass
class ToneAnalysisResult:
    mean, median, std: float
    min_val, max_val: int
    shadows, midtones, highlights: float  # 各区域占比(%)
    tone_key: ToneKey
    tone_range: ToneRange
    histogram: np.ndarray
    peak_position: float
    tone_key_confidence: float
    tone_range_confidence: float
```

### 4.2 核心分析流程

1. 采样
2. RGB→灰度（Rec. 709 + sRGB Gamma 校正）
3. 计算统计值：mean, median, std, min, max
4. 三区域占比：shadows(≤85) / midtones(86-170) / highlights(≥171)
5. 直方图 + 波峰位置
6. 影调分类

### 4.3 影调分类算法

**全长调判断：**
- 条件：暗部>15% 且 亮部>15% 且 min<30 且 max>225
- U型分布验证：中间调均值 < 边缘均值 × 0.7
- 置信度 = 0.5 + 0.5 × (边缘占比因子×0.4 + U型因子×0.4 + 范围因子×0.2)

**基调判断：**
- 波峰 ≥ 171 → HIGH
- 波峰 ≤ 85 → LOW
- 否则 → MID
- 置信度 = 位置置信度 × 尖锐度因子

**跨度判断：**
- 统计有明显分布的区域数（阈值 0.5%）
- 3个→LONG, 2个→MEDIUM, 1个→SHORT

---

## 五、core/image_service.py — 图片服务（~500行）

### 5.1 色彩空间检测

**检测流程：**
1. 优先从 ICC 配置文件检测（字节匹配已知配置文件名）
2. 其次从 EXIF 信息检测
3. 默认 sRGB

**已知 Gamma 值：** sRGB:2.2, Adobe RGB:2.2, ProPhoto RGB:1.8, DCI-P3:2.6, Display P3:2.2

### 5.2 分阶段加载

**两阶段加载：**
1. 快速显示：打开→色彩空间检测→转sRGB→超1920px缩放→导出BMP
2. 完整数据：全尺寸sRGB BMP

**关键设计：显示与取色分离**
- 显示用 sRGB（已做色域映射）
- 取色用 original_pixels（保留原始色彩空间数值）

### 5.3 内存管理

- `ImageMemoryManager`（LRU缓存图片数据）
- 取消机制：设标志位
- 缩略图生成：QImage.scaled + QPixmap.fromImage

---

## 六、core/color_service.py — 颜色服务（~150行）

```
ColorService.extract_dominant_colors(image, count, original_pixels, algorithm)
  └── DominantColorExtractor.run()
        ├── extract_dominant_colors() → dominant_colors: list[(R,G,B)]
        └── find_dominant_color_positions() → positions: list[(rel_x, rel_y)]
        └── emit extraction_finished(dominant_colors, positions)
```

---

## 七、Dart 移植关键参考

### 7.1 数据结构映射（Python→Dart）

| Python | Dart 建议 |
|--------|-----------|
| `np.ndarray` (H,W,3) | `Uint8List` + 手动索引，或 `image` 包的 Image 对象 |
| `np.ndarray` (N,3) | `List<List<int>>` 或自定义 PixelBuffer |
| `_ColorCube` | 自定义类，缓存范围/体积/均值 |
| `OrderedDict` (LRU) | `LinkedHashMap` + 手动 LRU |
| `@dataclass` | Dart class 或 freezed |
| `Enum(str, Enum)` | Dart enum |

### 7.2 性能关键优化点

1. **采样策略**：默认 sample_step=4，自适应步长按像素数调整（2-6）
2. **边缘像素保留**：采样时额外加入右边缘和底边缘，避免颜色丢失
3. **K-Means 距离优化**：展开式 + 预计算范数
4. **缓存机制**：LRU，直方图/影调分析均缓存
5. **异步计算**：Dart 用 Isolate/`compute()` 替代 QThread
6. **无 NumPy**：需手写矩阵运算或用 scidart/ml_linalg

### 7.3 萌图 MVP 可简化项

- 色彩空间检测 → v1.x 再做，MVP 假设 sRGB
- ICC 转换 → MVP 跳过
- 配色方案生成 → v1.x
- Zone 系统 → v1.x（影调分析用三区域即可）
- 分阶段加载 → MVP 用 image 包一次性解码
- 自适应采样步长 → MVP 固定 step=4

### 7.4 GPL-3.0 注意事项

- 不能直接复制代码，只参考算法思路
- MMCQ、K-Means、Rec. 709 等算法是公开标准，不受许可证限制
- 数据结构设计可借鉴但需重写
