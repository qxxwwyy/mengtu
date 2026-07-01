// photo_fingerprint.dart — 照片可量化指纹（v3.5 用户档案匹配用）
//
// 设计原则：只匹配可量化的物理量，不判主观风格（"这是日系"不可靠且无意义）。
// 分两层特征：
//   1. histogramFeatures：直方图降维分布（用于卡方距离匹配）
//   2. scalarFeatures：标量特征向量（用于标准化欧氏距离匹配，不用多维高斯马氏距离
//      —— N=3 时协方差矩阵奇异，是数学硬伤，见 plan.md 差异总结表）
//
// 序列化约定：本类不直接写 DB，由 FingerprintService 在内存中聚合后，
// 把各维度 {mean, std} 统计写入 StyleProfiles.fingerprintStats（JSON）。
// 单张照片的指纹是派生数据，按需重算（不持久化），缓存到会话即可。

/// 照片可量化指纹
///
/// 顺序固定：[scalarFeatures] 与 [scalarLabels] 一一对应，
/// 与档案的统计均值/标准差按相同维度做标准化欧氏距离匹配。
class PhotoFingerprint {
  /// 降维后的直方图分布（每通道 32 bins，共 96 个值，归一化到 [0, 1]）
  ///
  /// 由 256 bins 的 RGB 直方图按每 8 bin 求和 + 归一化得到（R 32 + G 32 + B 32）。
  /// 用于卡方距离匹配（用户档案）。
  final List<double> histogramFeatures;

  /// 标量特征向量（顺序固定，与 [scalarLabels] 一一对应）
  ///
  /// 单位为 RAW 值（未归一化，与 FingerprintService._computeFingerprintIsolate 一致）：
  /// `[RMS对比度(0~128), 冷暖比(0.5~2), 黑点偏移(0~255), 白点压缩(0~255),
  ///   信息熵(0~8), SCS(0~180), SLS(-100~100)]`
  ///
  /// v7.0：原 9 维（含 STI/FLC）缩减为 7 维（移除依赖 Face Mesh 的 STI/FLC，
  /// SCRFD 只给 5 点无法计算）。缺失维度（如无脸照片的 SCS/SLS）用 `-1` 占位，
  /// 匹配时跳过该维度。
  final List<double> scalarFeatures;

  /// 标量特征标签（用于调试与 UI 展示，顺序与 [scalarFeatures] 一致）
  static const scalarLabels = [
    'rms_contrast',
    'warm_cold_ratio',
    'black_point',
    'white_point',
    'entropy',
    'scs',
    'sls',
  ];

  /// 缺失维度的占位值（匹配时跳过）
  static const double missing = -1.0;

  const PhotoFingerprint({
    required this.histogramFeatures,
    required this.scalarFeatures,
  });

  Map<String, dynamic> toJson() => {
        'hist': histogramFeatures,
        'scalar': scalarFeatures,
        'v': 1, // schema 版本，便于未来升级
      };

  factory PhotoFingerprint.fromJson(Map<String, dynamic> j) => PhotoFingerprint(
        histogramFeatures: (j['hist'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
        scalarFeatures: (j['scalar'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}
