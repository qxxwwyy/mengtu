# 萌图 - AI Agent 开发指引

> 本文件是 AI 编程助手（Hermes/Copilot/Cursor 等）在参与萌图项目开发时必须遵循的规范和上下文。

## 项目概述

萌图是一款面向摄影爱好者的**摄影师全流程工作台**，核心场景：
1. **前期策划**：拍摄策划（主题/风格/器材/shot list/参考图），可复用模板
2. **照片管理**：批量导入、相册管理（封面/描述/批量操作）、瀑布流浏览、标签分类
3. **调色参考**：RGB/亮度直方图、色卡提取、一键黑白、影调分析、取色器、对比

**技术栈：** Flutter 3.44 + Riverpod 3.x + drift (SQLite) + image 包 + material_color_utilities
**目标平台：** Android（优先）→ Windows（二期）
**详细需求：** 以本文档"已完成"清单 + [README.md](./README.md) 功能列表为准（PRD.md/DEVPLAN.md 未入库）

## 当前开发状态（v3.5）

### 已完成
- ✅ §1.1 项目初始化（Flutter 3.44 + Riverpod 3.x + drift + CI/CD）
- ✅ §1.2 数据层（drift 11 表 + 6 DAO + build_runner）
- ✅ §1.3 照片导入（SHA256 去重 + fileHash 唯一约束 + Isolate 缩略图 + 解码失败保护）
- ✅ §1.4 瀑布流浏览（MasonryGridView + StreamProvider + 长按多选 + 批量操作）
- ✅ §1.5 照片详情（InteractiveViewer + 渐进式披露分层工具栏）
- ✅ §1.6 直方图（RGB三通道叠加 + 亮度 Rec.709 + CustomPainter + 缓存 + Uint16 clamp）
- ✅ §1.7 一键黑白（ColorFiltered Rec.709 灰度矩阵 + 对比度/曝光）
- ✅ §1.8 标签基础 + 搜索（tag CRUD + 按标签名搜索 + 分组管理 + 标签 chips 筛选）
- ✅ §2.2 色卡提取（QuantizerCelebi + Score + 占比归一化 + 缓存）
- ✅ §3.1 影调分析（**五区域占比**（黑/阴/中/高/白，分界 51/102/153/204）+ 合并段基调判定 + 统计指标 + 缓存）
- ✅ §3.2 色彩占比（色块宽度按占比动态分配）
- ✅ §3.4 设置页面（存储统计 + 清理缓存 + 关于）
- ✅ §4.1 MMCQ + K-Means 算法（三种算法可切换 + 数量可调节 3-8）
- ✅ §4.2 色相直方图（360 bins HSV + 彩虹色条 + DB schemaVersion v3→v7）<br>（当前 schemaVersion 已演进至 v11，见下"数据库表"小节）
- ✅ §5.x CI 体积优化（`--debug` → `--release`，APK 从 ~150MB 降到 ~30MB）
- ✅ v2.0 底部导航 4 Tab（作品库/相册/策划/我的）
- ✅ v2.0 详情页渐进式披露（常驻4按钮 + 激活工具栏 + 更多BottomSheet）
- ✅ v2.0 快速标签（卡片右下角图标 + 瀑布流长按多选批量操作）
- ✅ v2.0 相册系统（封面卡片 + 设封面 + 编辑描述 + 详情页/瀑布流加入相册）
- ✅ v2.0 拍摄策划（shooting_plans 三表 + 列表/创建/详情 + 内置模板 + shot list）
- ✅ v2.0 标签筛选 chips（作品库顶部横向标签快速筛选）
- ✅ v2.0 UI/UX 审查修复（光标漂移修复/批量删除/Quick Dock 悬浮工具栏）
- ✅ v2.0 静默导入（非阻断式导入 + SnackBar 延后分类加入相册）
- ✅ v2.0 自适应主题（暗色/浅色/跟随系统，SharedPreferences 持久化）
- ✅ v2.0 相册拖拽排序（ReorderableGridView + HapticFeedback）
- ✅ v2.0 策划编辑器吸底保存（拇指热区 Easy 区 + 子组件状态隔离）
- ✅ v2.0 EXIF 拍摄参数（exif 包 + Isolate 解析 JPEG + schemaVersion v7→v8 + 历史照片补全）
- ✅ v2.0 详情页统一底部面板重构（融合 Quick Dock + AnalysisPanel 为单一组件 + 黑白入口去重 + 顶栏更多菜单归位低频功能 + 信息 Tab）
- ✅ v2.0 开源前最终复核（17 项修复：相册点击/取色报错/FK级联崩溃/批量计数清零/分析刷新链/色相标记联动/Tab索引保留/统计刷新/版本号统一/LIKE escape/版本号单一数据源 app_info.dart）
- ✅ v2.1 相册系统重构 + 标签迁移到相册（PhotoTags→AlbumTags，schemaVersion v8→v9 + 尽力迁移 photo_tags→album_tags + 相册列表顶栏标签chips筛选 + 富信息卡片聚合查询消除N+1 + 相册详情顶部标签编辑面板 + 作品库去标签化改为按文件名搜索 + 详情页信息Tab「所属相册」+ album_provider.dart 集中相册provider修跨页耦合）
- ✅ v3.0 数理审美调色指引（ToneResult 新增 entropy/rmsContrast + SkinAnalysis 4 维度 + tone_service 信息熵/RMS/冷暖比/P3补偿公式 + ToneGuideCard 纯文字指引卡片嵌入直方图/影调 Tab）
- ✅ v3.0 策划关联样片相册（ShootingPlans.associatedAlbumId，schemaVersion v9→v10 + FK setNull + deleteAlbum 事务内显式清关联 + PlanEditPage 下拉选择器 + PlanDetailPage 跳转卡片）
- ✅ v3.0 BlazeFace 离线人脸 ROI（tflite_flutter 0.11 + face_detection_short_range.tflite 229KB + face_service Isolate 推理 + NMS + 主脸面积最大 + ROI 内缩 20% + SLS/SCS 隔离度 + 手动覆盖通路）
- ✅ v3.0 峰值对焦蒙层（sharpness_service 拉普拉斯边缘响应 240×160 降采样 + Variance of Laplacian 全局锐度评分 + SharpnessOverlay CustomPainter + BlendMode.screen 发光叠加 + 详情页「对焦」工具按钮）
- ✅ v3.5 PR1 数据地基（AdvancedPortraitMetrics[STI/FLC 可空 + black_point/white_point/ten_tonal 强制重算] + PhotoFingerprint[96维直方图+9维标量] + StyleProfiles/StyleProfilePhotos 两表 + schemaVersion v10→v11 + tone_service 黑点/白点/十大影调纯直方图函数 + deletePhoto 钩子清档案关联）
- ✅ v3.5 PR2 三段式 Face Mesh + STI/FLC（BlazeFace short→full→face_mesh.tflite[468 landmarks] 三段式 + STI 高斯接近度公式 + FLC 带可见性判定[侧脸降级 null] + SkinAnalysis 扩展 sti/flc + advancedMetricsProvider 聚合 + mesh 失败降级 bbox ROI）
- ✅ v3.5 PR3 解构卡片重构（DetailBottomPanel 6 Tab → 四阶卡片[影调/色彩/主体/档案] + 参照直方图叠放[教学核心] + 数据仪表盘全屏页[4 section] + stage_card 通用折叠容器 + interpretation_row 解读式措辞）
- ✅ v3.5 PR4+PR5 风格档案 + 标准化欧氏匹配 + 复刻参数 + 内置理论档案（FingerprintService 卡方60%+标准化欧氏40% 融合 + precomputeAnalysisForPhotos 批量预计算 + StyleProfileMatch 分层置信度 + 风格档案列表/创建/详情 + 阶④接入真实匹配 + ReplicationHintsService 解读式复刻参数 + BuiltinProfiles 日系/港风[做精]/青橙/中式[待校准] + ensureSeeded 幂等启动插入）
- ✅ v3.5 复核修复（BLOCKER: 内置档案 scalar_means 改 RAW 单位 + 补 hist_means；MAJOR: advancedMetricsProvider cache-hit 提前 return 跳过 ref.watch[gotcha #33] + ReplicationHintsService 魔数文档化；MINOR: PhotoFingerprint 标量单位标注与实现一致）
- ✅ v3.5 二轮复核修复（P1: precomputeAnalysisForPhotos 补 advanced 含 Face Mesh，让 STI/FLC 进入档案匹配 + tone_service 提取 computeAdvancedMetrics 纯函数共享；P3: computeSimilarity exp 衰减 2.0→4.0 宽容理论档案 + 内置档案相似度补 confidenceHint 文案；P4: _SimilarityTile 颜色跟随 similarityText 分层[isBuiltin/<5/≥5]；P5: AGENTS.md 同步 schemaVersion/版本/gotcha #46-50/项目结构）
- ✅ v6.0 八大问题修复（①BlazeFace 解码三大 bug[sigmoid+inputSize 归一化]让人脸检测真正生效；②取色后台预解码[maxDim 1200]零等待；③构图线 letterbox 补偿基于图片不溢出；④取色 Pin 弹菜单+设为肤色基准[manualSkinSelectionProvider 接 UI]；⑤放大镜 130px+中心格高亮+HSV 标签；⑥锐度蒙层恢复[SharpnessOverlay BlendMode 发光+数据卡]；⑦GradingPanel 顶部黑框消除+FingerprintRadar AspectRatio 居中+补全 polygon；⑧SkinRadar 肤色合理性雷达[5 维/中心=理想肤色]嵌入阶②色彩卡片）
- ✅ v6.1 二轮手动测试修复（①BlazeFace→ML Kit 人脸检测迁移[google_mlkit_face_detection bundled/minFaceSize 0.15 抓大头照]+FaceBBoxOverlay 检测框可视化[建立用户信任]+Face Mesh 保留算 STI/FLC；②顶部通知替代底部 SnackBar[避开工具行操作热区]；③取色坐标系统一 Stack-local[放大镜/像素/pin 三者对齐]+InteractiveViewer 取色锁定 scale=1；④DetailBottomPanel 固定高度 368/72+Expanded 填充消除黑框；⑤作品库多选栏重构[隐藏 FAB+Material 底栏+取消 IconButton 醒目]）

### 待开发
- ⬜ 空状态美化（发光线条微图形 + CTA 引导按钮）
- ⬜ Windows 适配 + 开源发布

## 开发环境

当前开发机为 Windows。Flutter SDK 采用**便携式隔离安装**（不污染系统 PATH，卸载删文件夹即可）。

```bash
# Flutter SDK 激活（每次开新 cmd 窗口执行，临时加入 PATH + 国内镜像）
C:\Users\10492\flutter-sdk-activate.bat
flutter --version  # 3.44.2 / Dart 3.12+

# 卸载 Flutter：删 C:\Users\10492\flutter-sdk 文件夹 + flutter-sdk-activate.bat

# 代码生成（修改 DAO/表结构后必须执行）
dart run build_runner build

# 分析和测试
dart analyze
flutter test
```

激活脚本（`flutter-sdk-activate.bat`）内已配置国内镜像：
- `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- `PUB_HOSTED_URL=https://pub.flutter-io.cn`

> 注：CI 跑在 Ubuntu，用默认 pub.dev，**不要把本地镜像产生的 `pubspec.lock` 变更提交**（只有 url 字段改 pub.dev→pub.flutter-io.cn，是环境噪音）。

## 关键依赖（pubspec.yaml）

| 依赖 | 版本 | 说明 |
|------|------|------|
| flutter_riverpod | ^3.3.0 | 状态管理（Riverpod 3.x，**不含 StateProvider**） |
| riverpod_annotation | ^4.0.0 | Riverpod 注解 |
| drift | ^2.15.0 | SQLite ORM |
| sqlite3_flutter_libs | ^0.5.0 | drift 原生库 |
| image | ^4.9.1 | 图片解码+像素操作 |
| material_color_utilities | ^0.13.0 | Google 色彩算法（QuantizerCelebi+Score） |
| exif | ^3.3.0 | EXIF 拍摄参数解析（纯 Dart，Isolate 内读取 JPEG 字节） |
| wechat_assets_picker | ^10.1.2 | 微信风格图片多选 |
| photo_manager | ^3.9.0 | 相册管理 |
| flutter_staggered_grid_view | ^0.7.0 | 瀑布流 |
| uuid | ^4.0.0 | ID 生成 |
| path_provider | ^2.0.0 | 应用目录 |
| path | ^1.8.0 | 路径工具 |
| crypto | ^3.0.7 | SHA256 哈希 |
| reorderable_grid_view | ^2.2.8 | 相册照片拖拽排序 |
| shared_preferences | ^2.5.5 | 主题模式持久化 |
| tflite_flutter | ^0.11.0 | v3.0 离线人脸检测（BlazeFace TFLite 推理，FFI 插件；v6.1 起降级为 ML Kit 不可用时的回退）|
| google_mlkit_face_detection | ^0.13.1 | v6.1 人脸检测主链（Google ML Kit bundled，minFaceSize 0.15 抓大头照，不依赖 GMS）|

dev_dependencies: drift_dev, riverpod_generator, build_runner, flutter_lints

### Riverpod 3.x 注意事项（重要）

> **Riverpod 3.x 移除了 `StateProvider`、`StateNotifierProvider`、`FamilyNotifierProvider` 等 API。**

- 全局简单状态：用 `Notifier` + `NotifierProvider` 替代 `StateProvider`
- Family 参数化状态：用回调参数传递（Widget state），**不要**试图找 Riverpod 3.x 的 family notifier API
- StreamProvider / FutureProvider / NotifierProvider 正常可用
- `StreamProvider.family` 正常可用
- 代码生成用 `@riverpod` 注解（本项目 MVP 暂未使用 code gen，手写 provider）

### wechat_assets_picker API

```dart
// 正确的调用方式（v10.x）
final List<AssetEntity>? assets = await AssetPicker.pickAssets(
  context,
  pickerConfig: AssetPickerConfig(  // 注意是 AssetPickerConfig 不是 PickerConfig
    maxAssets: 100,
    requestType: RequestType.image,
  ),
);
```

## 项目结构

```
mengtu/
├── lib/
│   ├── main.dart                    # 应用入口（ErrorWidget 兜底 + MainShell）
│   ├── models/
│   │   ├── tone_result.dart         # HistogramData + ToneResult（5段）+ SkinAnalysis（v3.5 扩展 sti/flc）
│   │   ├── palette_result.dart      # PaletteColor + PaletteResult
│   │   ├── exif_info.dart           # ExifInfo 强类型 + JSON 序列化 + 格式化（f/2.8、1/250s）
│   │   ├── advanced_portrait_metrics.dart # v3.5 高级人像指标（STI/FLC 可空 + black/white/ten_tonal 强制重算 + mergeIntoToneJson）
│   │   ├── photo_fingerprint.dart   # v3.5 照片指纹（96维直方图 + 9维标量[RAW 单位]）
│   │   └── style_profile_match.dart # v3.5 档案匹配结果（分层置信度 similarityText/confidenceHint）
│   ├── theme/
│   │   └── app_theme.dart           # 设计系统（暗房美学：AppColors + 详情页 DetailColors 暗色专用 token）
│   ├── services/
│   │   ├── database/
│   │   │   ├── app_database.dart    # drift 数据库（schemaVersion=11）
│   │   │   ├── tables.dart          # 表定义（11张表，见下）
│   │   │   └── daos/
│   │   │       ├── photo_dao.dart   # 照片CRUD + watch流 + watchPhotosByName(按文件名搜索) + 缓存更新 + 清缩略图 + updateExifCache
│   │   │       ├── tag_dao.dart     # 标签CRUD + 相册-标签关联（v2.1 标签迁移到相册）
│   │   │       ├── album_dao.dart   # 相册CRUD + 关联 + getCoverPhoto + watchAlbumsByTag/getAlbumsWithTagInfo/watchAlbumsForPhoto（v2.1）+ AlbumWithTags 聚合类
│   │   │       ├── color_pin_dao.dart # 取色点CRUD
│   │   │       ├── plan_dao.dart    # 拍摄策划CRUD + shot list/gear序列化 + 模板
│   │   │       ├── style_profile_dao.dart # v3.5 风格档案CRUD + 关联 + removePhotoFromAllProfiles(删照片钩子) + getProfilePhotoCount
│   │   │       └── *.g.dart        # 自动生成（gitignore）
│   │   ├── import_service.dart      # 导入去重+缩略图+EXIF解析+删除+regenerateThumbnail+readExifForExistingPhoto+precomputeAnalysisForPhotos(v3.5 批量预计算含advanced)
│   │   ├── exif_service.dart        # EXIF 解析纯函数（extractExifJson，Isolate 内调用）
│   │   ├── histogram_service.dart   # 直方图计算（Isolate）
│   │   ├── tone_service.dart        # 影调分析（5区域 + 合并段基调 + 信息熵 + RMS对比度 + 冷暖比 + P3补偿 + v3.5 黑点/白点/十大影调/computeAdvancedMetrics 纯函数）
│   │   ├── palette_service.dart     # 色卡提取
│   │   ├── clipping_service.dart    # 高光/阴影溢出警告（动态step）
│   │   ├── harmony_service.dart     # 配色和谐度（6种HarmonyType）
│   │   ├── pixel_picker_service.dart # 取色器像素拾取
│   │   ├── face_service.dart        # v3.0 BlazeFace 人脸 ROI + 肤色 HSL + v3.5 三段式 Face Mesh + STI/FLC（Isolate 推理）
│   │   ├── sharpness_service.dart   # v3.0 拉普拉斯边缘响应（峰值对焦蒙层数据源）
│   │   ├── fingerprint_service.dart # v3.5 照片指纹（96维直方图+9维标量 Isolate）+ 档案统计 + 标准化欧氏+卡方融合匹配
│   │   ├── builtin_profiles.dart    # v3.5 内置理论档案（日系/港风[做精]/青橙/中式[待校准]）+ ensureSeeded 幂等
│   │   └── replication_hints_service.dart # v3.5 复刻参数生成（解读式「样片手法」语境，非诊断）
│   ├── pages/
│   │   ├── main_shell.dart          # 底部导航 4 Tab（作品库/相册/策划/我的）
│   │   ├── home_page.dart           # 作品库（瀑布流+按文件名搜索+长按多选[加入相册/删除]+静默导入）v2.1去标签化
│   │   ├── detail_page.dart         # 照片详情（顶栏更多菜单 + 统一底部面板 + 永远暗色）
│   │   ├── compare_page.dart        # 多图对比
│   │   ├── album_page.dart          # 相册列表（v2.1 顶栏标签chips筛选 + 富信息卡片[封面/数量/标签chips/更新时间]）
│   │   ├── album_detail_page.dart   # 相册详情（v2.1 顶部标签编辑面板 + 3列网格/瀑布流 + 设封面 + 拖拽排序 + reactive AppBar）
│   │   ├── plan_list_page.dart      # 策划列表（状态筛选chips+卡片）
│   │   ├── plan_edit_page.dart      # 策划创建/编辑（EditableShotRow子组件隔离+吸底保存）
│   │   ├── plan_detail_page.dart    # 策划详情（shot完成度+实拍照片）
│   │   ├── profile_page.dart        # 我的（统计+标签管理[全局相册标签]+设置入口+v3.5 风格档案入口）
│   │   ├── settings_page.dart       # 设置（存储+缓存+主题切换+版本）
│   │   ├── tag_manage_page.dart     # 标签管理（分组显示 + 每标签相册使用计数）
│   │   ├── style_profile_page.dart  # v3.5 风格档案列表/创建（选样片→预计算→关联→recomputeProfileStats）
│   │   └── style_profile_detail_page.dart # v3.5 风格档案详情（照片列表+移除+重算指纹）
│   ├── widgets/
│   │   ├── photo_card.dart          # 瀑布流卡片（+多选蒙层；v2.1移除快速标签按钮）
│   │   ├── detail_bottom_panel.dart # 详情页统一底部面板（高频工具行[黑白/溢出/构图/锐度/取色/数据] + 展开 GradingPanel 四阶解构卡片[v3.5 重构]）
│   │   ├── histogram_painter.dart   # 直方图 CustomPainter（5段标注）
│   │   ├── tone_info_card.dart      # 影调 5 区域占比条
│   │   ├── tone_guide_card.dart     # v3.0 数理审美调色指引（信息熵/RMS/肤色4维度纯文字卡片）
│   │   ├── color_card.dart          # 色卡展示
│   │   ├── harmony_card.dart        # 配色和谐度
│   │   ├── color_wheel.dart         # 色轮
│   │   ├── color_picker_loupe.dart  # 取色放大镜 + ColorPinMarker（v6.0：Pin 弹菜单设肤色基准 + 选中高亮）
│   │   ├── clipping_overlay.dart    # 溢出警告蒙层
│   │   ├── sharpness_overlay.dart   # v6.0 恢复峰值对焦蒙层（拉普拉斯响应 CustomPainter，按强度暖橙→青绿，letterbox 补偿）
│   │   ├── composition_overlay.dart # 构图辅助线（v6.0：letterbox 补偿，基于图片实际矩形不溢出）
│   │   └── grading/                 # v3.5 四阶解构卡片（替代原 6 Tab）
│   │       ├── grading_panel.dart   # 四阶卡片 ListView 容器（watch advancedMetricsProvider 一次；v6.0 去顶部 padding 消黑框）
│   │       ├── stage_card.dart      # 通用阶卡片（序号+标题+摘要+折叠/展开）
│   │       ├── stage_tonal_card.dart # 阶①影调手法（黑点/白点/RMS/十大影调 + 参照直方图）
│   │       ├── stage_color_card.dart # 阶②色彩手法（v6.0：顶部嵌 SkinRadar + STI/ΔH/饱和解读）
│   │       ├── stage_isolation_card.dart # 阶③主体手法（SLS/SCS/FLC/锐度解读）
│   │       ├── stage_archive_match_card.dart # 阶④档案比对（相似度列表+雷达图+复刻参数；颜色跟随 similarityText 分层）
│   │       ├── reference_histogram.dart # 参照直方图叠放（教学核心，当前 vs 典型影调高斯/U型）
│   │       ├── fingerprint_radar.dart # 指纹雷达图 9 维（current vs archive；v6.0：AspectRatio 居中+补全 polygon）
│   │       ├── skin_radar.dart      # v6.0 肤色合理性雷达图 5 维（中心=理想肤色，嵌入阶②色彩卡片）
│   │       ├── interpretation_row.dart # 解读行（共享）+ InterpretationStatus 状态色
│   │       ├── replication_hints_card.dart # 复刻参数附录（解读式「样片手法」）
│   │       └── raw_data_dashboard.dart # 数据仪表盘全屏页（4 section：影调/色彩/隔离/EXIF）
│   ├── providers/
│   │   ├── database_provider.dart   # AppDatabase + ImportService 单例
│   │   ├── photo_provider.dart      # 照片流 + 搜索debounce + 排序 + photosByNameSearchProvider
│   │   ├── tag_provider.dart        # 标签流 + TagActions（v2.1 相册作用域：addTagToAlbum/removeTagFromAlbum）
│   │   ├── album_provider.dart      # 相册流（v2.1 集中：albumsProvider/albumsWithTagsProvider/albumPhotosProvider/albumTagsProvider/albumsByTagProvider/photoAlbumsProvider + albumTagFilterProvider）
│   │   ├── analysis_provider.dart   # 直方图/影调/色卡计算+缓存 + v3.0 skinProvider（BlazeFace 肤色 ROI）+ modelPathProvider + v3.5 meshModelPathProvider/advancedMetricsProvider（聚合 advanced 含 STI/FLC）
│   │   ├── exif_provider.dart       # EXIF Provider + colorPinsProvider（取色点流）
│   │   ├── clipping_provider.dart   # 溢出状态
│   │   ├── sharpness_provider.dart  # v3.0 拉普拉斯边缘响应（峰值对焦蒙层数据源，按需计算不缓存）
│   │   ├── plan_provider.dart       # 策划流 + 模板 + 状态筛选
│   │   ├── style_profile_provider.dart # v3.5 风格档案流 + fingerprintServiceProvider + photoFingerprintProvider + styleProfileMatchProvider
│   │   └── theme_provider.dart      # 主题模式（暗色/浅色/跟随系统 + SharedPreferences）
│   └── utils/
│       ├── app_info.dart           # 应用版本常量（单一数据源，与 pubspec version 对齐）
│       ├── color_utils.dart         # RGB↔HSL, Rec.709 灰度
│       └── file_hash.dart           # 纯Dart SHA256
├── algorithms/                      # 取色算法（独立模块）
│   ├── mmcq.dart                    # MMCQ 改进中位切分
│   └── kmeans.dart                  # K-Means++
├── android/
│   ├── app/
│   │   ├── build.gradle.kts         # namespace=com.mengtu.app, minSdk=26, abiFilters=arm64-v8a
│   │   │                             # 签名：CI 环境变量注入（KEYSTORE_*），本地 fallback debug
│   │   └── src/main/
│   │       ├── AndroidManifest.xml  # READ_MEDIA_IMAGES 权限
│   │       └── kotlin/com/mengtu/app/MainActivity.kt
│   └── .gitignore                   # 含 **/*.keystore
├── test/                            # 测试（21 个文件，230+ 用例）
│   ├── algorithms/                  # hue/kmeans/mmcq 算法测试
│   ├── dao/                         # photo_dao/tag_dao/album_dao/color_pin_dao/plan_dao
│   ├── integration/                 # analysis_flow/import_flow 全链路测试
│   ├── unit/                        # color_utils/file_hash/histogram/tone/harmony/clipping/migration
│   ├── widget/                      # tone_info_card/histogram_painter/photo_card Widget 测试
│   └── helpers/test_helpers.dart    # 测试工具（图片生成、内存DB、ProviderContainer、fixture builder）
├── .github/workflows/build.yml      # CI: build_runner → analyze → test → release APK
├── AGENTS.md                        # 本文件
├── LICENSE                          # MIT + 第三方依赖致谢
├── README.md                        # 项目说明
└── pubspec.yaml                     # version: 1.3.0+1
```

**数据库表（11 张，schemaVersion=11）：**
- `Photos` — 照片 + 分析缓存（直方图/色卡/影调）+ EXIF 拍摄参数（exifJson，v8）+ fileHash 唯一索引。v3.5：toneJson 内嵌 `advanced` 键（black_point/white_point/ten_tonal/skin_sti/face_lighting_contrast），不改表结构
- `Tags` — 标签（name + group: 氛围/场景/情绪/自定义）。v2.1 起标签是相册的子系统，全局定义、可复用
- `AlbumTags` — 相册-标签多对多（v2.1 替代原 PhotoTags，标签从照片迁移到相册）
- `ColorPins` — 取色点（v4）
- `Albums` — 相册（name + description + coverPhotoId）
- `AlbumPhotos` — 相册-照片多对多（含 sortOrder）
- `ShootingPlans` — 拍摄策划（v7，标题/风格/器材/shot list/状态 + v10 associatedAlbumId 关联样片相册，FK setNull）
- `PlanPhotos` — 策划-照片关联（区分 reference/result 角色）
- `PlanTemplates` — 策划模板（内置 3 个：人像外拍/街拍/静物）
- `StyleProfiles` — v3.5 风格档案（id/name/description/fingerprintStats[JSON{mean,std}]/isBuiltin/builtinKey）
- `StyleProfilePhotos` — v3.5 档案-照片多对多（profileId FK cascade / photoId FK setNull，测试库不生效由 DAO 显式清理，gotcha #40）

## 编码规范

### 通用
- 文件命名 snake_case，类命名 PascalCase，私有成员下划线前缀
- 每个文件顶部添加简要注释说明模块职责
- `dart analyze` 必须 0 issues（包括 info 级别，否则 CI 挂）

### 状态管理（Riverpod 3.x）
- UI 层只通过 `ref.watch()` 消费状态，不直接调用 service
- 列表自动刷新：用 `StreamProvider` + drift `watch()` 而非 `FutureProvider`
- 全局简单状态：用 `Notifier` + `NotifierProvider`（**不是 StateProvider**）
- Family 参数化：避免使用 family notifier API，改用 Widget state + 回调

### 数据库（drift）
- 表定义在 `tables.dart`，DAO 按业务拆分
- 修改表结构/DAO 后必须执行：`dart run build_runner build`
- `*.g.dart` 被 gitignore，CI 里通过 build_runner 生成
- DAO 注解中的 tables 列表必须包含所有 join 涉及的表

### 性能关键路径（必须在 Isolate 中执行）
- 直方图计算：`compute()` 函数
- 图片哈希：`compute()` 函数
- 缩略图生成：`compute()` 函数
- EXIF 拍摄参数解析：`compute()` 函数（`readExifFromBytes` 返回 Future，Isolate 内 await）
- 使用 `image` 包的 `decodeImage()` + `copyResize()`

### 图片处理
- 缩略图长边 360px，JPEG quality 85
- 直方图降采样 step=4
- 一键黑白用 `ColorFiltered` widget，不修改原图
- Rec.709 灰度系数：0.2126R + 0.7152G + 0.0722B

### 影调分析（5 段划分）
- **分界点**：51 / 102 / 153 / 204（均分 0-255，与直方图视觉分界线对齐）
- **5 段命名**：黑色(blacks 0-51) / 阴影(shadows 52-102) / 中间调(midtones 103-153) / 高光(highlights 154-204) / 白色(whites 205-255)
- **基调判定**：`dark = blacks + shadows`、`light = highlights + whites`，两端占比都 >15% 即全长调（合并段判定，单看 shadows/highlights 会漏判高对比图）
- **缓存兼容**：旧 3 段 JSON 缺 blacks/whites 键 → `fromJson` 强转抛 TypeError → `fromJsonString` 的 try/catch 兜底返回 null → provider 自动重算，**无需数据库迁移**

### 详情页底部面板布局（v2.0 重构后）
- **统一组件 `DetailBottomPanel`**：融合原 QuickToolsDock + AnalysisPanel 为单一组件，消除两套割裂的工具系统
- **常驻工具行**（始终可见）：高频调色工具（黑白/溢出/构图/取色）+ 展开/收起把手
- **展开内容**：TabBarView（信息/直方图/色卡/影调/和谐/取色），`AnimatedSize` 切换（220ms，收起 72 / 展开 380）
- **取色模式特殊处理**：`forceCollapsed=true` 时只保留工具行可见（可点"取色"退出），收起 TabBarView 避免与取色放大镜争夺空间；把手显示"长按图片取色点"提示
- **不使用 `DraggableScrollableSheet`**（真机上与 InteractiveViewer 手势冲突）
- 黑白控制**统一为工具行 1 处入口**（删除原顶栏快捷栏 + AnalysisPanel Switch 的重复）
- 黑白状态通过 Widget state + 回调传递（不使用 Riverpod family provider）
- **永远暗色**：详情页 `DetailColors` token（不随全局主题切换），让照片色彩最准确

### UI/UX 设计原则（v2.0 审查后确立）
- **拇指热区**：高频操作（底部面板工具行/导入 FAB/多选操作栏/保存按钮）放在屏幕底部 Easy 区；低频操作（返回/删除/更多菜单/对比/加入相册）放顶部
- **渐进式披露**：详情页工具分层（常驻顶栏 → 底部面板常驻工具行 → 展开 TabBarView 信息/分析）
- **工具入口去重**：同一功能（如黑白）只保留一个入口，避免 Dock toggle + Switch 多处重复造成困惑
- **子组件状态隔离**：表单编辑（shot list/gear list）用独立 StatefulWidget 管理 controller，避免光标漂移
- **静默导入**：选图后不弹分类弹窗，直接导入 + SnackBar 延后分类

### 信息架构（v2.1 底部导航 4 Tab）
- **作品库 Tab**：瀑布流（全部照片）+ 按文件名搜索 + 长按多选（加入相册/删除）+ FAB 静默导入。**v2.1 去标签化**（照片不再有标签）
- **相册 Tab**：相册列表（顶栏标签 chips 筛选相册 + 富信息卡片：封面/名称/数量/标签chips/更新时间）→ 相册详情（**顶部标签编辑面板** + 3 列网格/瀑布流 + 拖拽排序 + 设封面 + 导入/添加/移除）
- **策划 Tab**：策划列表 → 创建/编辑（EditableShotRow 子组件 + 吸底保存）→ 详情（shot list + 实拍照片）
- **我的 Tab**：统计 + 标签管理（全局标签 CRUD，服务于相册）+ 设置（含主题切换）
- **详情页**：常驻顶栏（返回+文件名+删除+⋮更多菜单[加入相册/照片对比]）→ 统一底部面板 DetailBottomPanel（常驻工具行：黑白/溢出/构图/取色 + 展开 TabBarView：信息[EXIF/文件/**所属相册**]/直方图/色卡/影调/和谐/取色）。永远暗色背景
- **标签体系（v2.1）**：标签是相册的子系统，全局定义、多对多关联到相册（AlbumTags）。照片不再有标签。相册列表顶栏 chips 按标签筛选相册；相册详情顶部编辑标签；我的 Tab 统一管理全局标签
- **主题**：暗色（默认）/浅色/跟随系统，`theme_provider.dart` + SharedPreferences 持久化
- **导入**：静默导入（选图后直接导入，SnackBar 带延后"加入相册"action，不弹分类弹窗）

## Android 配置

- 包名：`com.mengtu.app`
- 最低版本：API 26（Android 8.0）
- **ABI 过滤：仅 `arm64-v8a`**（目标设备均为 ARM64，砍掉 armeabi-v7a/x86_64 约减 80MB）
- 权限：`READ_MEDIA_IMAGES`（API 33+）, `READ_EXTERNAL_STORAGE`（旧版）
- MainActivity 路径必须与 namespace 一致：`kotlin/com/mengtu/app/`
- `requestLegacyExternalStorage="true"` 兼容旧版分区存储
- **签名配置（重要，曾踩坑）**：
  - `debug.keystore` **不在仓库**（`android/.gitignore` 的 `**/*.keystore` 规则忽略）
  - CI 通过 4 个 Actions secret 注入：`KEYSTORE_BASE64`（keystore 文件 base64）、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`
  - `build.gradle.kts` 的 `signingConfigs.release` 优先读环境变量（CI），本地开发 fallback 到固定 debug 默认（`android/android`）
  - **坑**：release 构建会触发 `validateSigningRelease` 严格校验（debug 构建有 Android 默认 keystore 兜底），所以 release 必须能找到 keystore 文件

## CI/CD

**所有编译打包通过 GitHub Actions 完成，不在本地执行 `flutter build`。**

CI 流程（`.github/workflows/build.yml`）：
1. `flutter pub get`
2. `dart run build_runner build`（代码生成）
3. `flutter analyze`（必须 0 issues）
4. `flutter test`
5. `flutter test --coverage`（生成 lcov 覆盖率报告）
6. Upload coverage artifact
7. **Decode keystore**：base64 解码 `KEYSTORE_BASE64` secret 到 `android/app/release.keystore`，通过 `GITHUB_ENV` 注入 `KEYSTORE_PATH`
8. `flutter build apk --release`（push 触发，**不再用 --debug**；env 注入其余 3 个签名 secret）
9. Upload APK artifact（`mengtu-apk`，产物 `app-release.apk`）

**APK 体积**：release + abiFilters=arm64-v8a 约 **30MB**（曾用 --debug 约 150MB）

**签名 secret（Actions secrets）**：
- `KEYSTORE_BASE64`：keystore 文件 base64 编码
- `KEYSTORE_PASSWORD`：keystore 密码
- `KEY_ALIAS`：密钥别名
- `KEY_PASSWORD`：密钥密码

本地只做：代码编辑 + `dart run build_runner build`（代码生成）+ `dart analyze` + `flutter test`

## Git 工作流

- **分支策略：** 所有开发在 `feature/release-prep` 分支进行，**除非用户明确要求，绝不主动合并到 main**
- **Commit 消息：** 中文描述 + 范围前缀（feat/fix/refactor/test/docs/build）
- **CI 验证：** 每次推送到 feature 分支自动触发 CI，跑通后再继续开发
- **pubspec.lock**：本地用国内镜像会改 url 字段，提交前必须 `git checkout -- pubspec.lock` 还原

## 已踩过的坑（防再次踩中）

1. **Riverpod 3.x 删了 StateProvider** — 用 Notifier 替代
2. **wechat_assets_picker API** — `AssetPickerConfig` 不是 `PickerConfig`，参数名是 `pickerConfig:`
3. **drift selectOnly 聚合** — 用 `getSingle()` 不是 `get()`，返回的是 `TypedResult`
4. **`*.g.dart` 被 gitignore** — CI 必须跑 `dart run build_runner build`
5. **`flutter analyze` 对 info 级别也返回 exit 1** — CI 里需要修掉所有 info
6. **MainActivity 包路径** — flutter create 默认 `com.xxx.xxx`，改 namespace 后必须同步移动 .kt 文件
7. **DraggableScrollableSheet** — 在 Stack 里与 InteractiveViewer 冲突，改用展开/收起
8. **FutureProvider 不自动刷新** — 列表数据用 StreamProvider + drift watch()
9. **`--split-per-abi` 与 `ndk.abiFilters` 互斥** — Gradle 报 "Conflicting configuration"。`abiFilters=arm64-v8a` 已限制单 ABI，`--split-per-abi` 多余且会冲突，去掉即可
10. **release 构建严格校验签名** — `validateSigningRelease` 找不到 keystore 直接挂（debug 构建有 Android 默认 keystore 兜底）。keystore 走 CI secret，不在仓库
11. **Kotlin 变量遮蔽（shadowing）** — `signingConfigs` 配置块里，外层 `val keyAlias` 与 `this.keyAlias` 同名会被当成"重赋值 val"报错。局部变量加前缀（如 `ciKeyAlias`）规避
12. **`pubspec.lock` 的 url 字段** — 本地用国内镜像会改 `pub.dev`→`pub.flutter-io.cn`，提交会让 CI 产生无关 diff，还原即可
13. **影调分段升级的基调判定** — 3 段→5 段后，`_classifyToneKey` 的全长调判定要改用合并段（dark=blacks+shadows / light=highlights+whites），否则高对比图会漏判
14. **onCreate 不创建索引** — drift 的 `MigrationStrategy.onCreate` 只跑 `createAll()`，migration 的 `customStatement`（如唯一索引）只在 `onUpgrade` 跑。全新安装的用户不会执行 onUpgrade，导致索引缺失。必须在 onCreate 里也手动创建索引
15. **drift `.like()` 的 escape 参数** — **（已过时更新）** drift 2.34+ 的 `Expression.like(pattern, {String? escapeChar})` **已支持** escape 命名参数。早期文档记的"不支持 escape、只能 customStatement"是旧版本的限制。现用法：`.like('%$escaped%', escapeChar: r'\')` + 手动转义 `\`/`%`/`_`。否则 SQLite 默认 LIKE 无转义符，`\%` 仍按反斜杠+通配符处理，含 `_` 的标签名会误匹配（如 `a_b` 命中 `axb`）
16. **Riverpod 3.x Notifier 无 dispose** — `Notifier` 子类没有 `dispose()` 方法可 override，用 `ref.onDispose(() => ...)` 注册清理（如 Timer.cancel）
17. **相册入口断链** — 从 ⋮ 菜单移除功能后，必须在底部 Tab 或其他入口补上，否则页面成死代码。v2.0 改造时漏补相册入口导致 album_page 不可达
18. **Uint16List 溢出** — 直方图 bin 计数超过 65535 时序列化截断，纯色大图（如 75 万像素集中在一个 bin）会丢失数据。`toBytes` 前必须 clamp 到 65535
19. **Kotlin 变量遮蔽** — `signingConfigs` 块内局部变量不能与 SigningConfig 同名属性重名（如 `val keyAlias` vs `this.keyAlias`），加前缀规避（`ciKeyAlias`）
20. **TextField 光标漂移** — 在 `build()` 中创建 `TextEditingController(text: value)` 会在每次 setState 时重建 controller，导致光标跳到末尾。必须用独立 StatefulWidget 子组件管理 controller 生命周期，失焦时才回传数据
21. **StateNotifierProvider 已移除** — Riverpod 3.x 没有 StateNotifierProvider。主题持久化用 `NotifierProvider` + `SharedPreferences`，不用 StateNotifier
22. **`git add -A` 误提交无关文件** — `.gemini/`、`.agents/` 等技能/配置目录会被 `-A` 一并加入。提交前用 `git add <具体文件>` 或在 `.gitignore` 排除这些目录
23. **取色模式隐藏面板导致死锁** — 用 `if(!_colorPickMode)` 整块隐藏 DetailBottomPanel 会让"取色"按钮一起消失，用户无法退出取色模式。正确做法是面板始终保留、用 `forceCollapsed` 只收起 TabBarView（工具行可见可退出）
24. **FutureProvider 依赖缓存不刷新** — FutureProvider A 内部 `watch(FutureProvider B.future)` 时，invalidate A 不会让 B 重算（B 缓存了旧结果）。更新 DB 后需同时 invalidate A 和 B。详见 exifInfoProvider + photoByIdProvider 的刷新链
25. **exif 包 ISO printable 格式** — `EXIF ISOSpeedRatings` 是 SHORT/LONG 数组，`.printable` 可能输出 `"[200]"` 形式，`int.tryParse` 直接失败。需 `replaceAll(RegExp(r'[\[\]]'))` 剥离方括号
26. **详情页永远暗色** — 作为图片查看/调色场景，详情页无论全局主题都用暗色（`DetailColors` token），不随 `themeModeProvider` 切换，避免浅色下调色分析的色彩偏差
27. **`PermissionState.isAuth` 漏判 limited** — photo_manager 3.9.0 的 `isAuth` 仅匹配 `PermissionState.authorized`，不含 `limited`。用户选了 Android 14+ / iOS「仅允许访问选中的照片」（`limited`）时，应用其实已授权，但 `!permission.isAuth` 判为未授权，导致每次点导入都误弹"需要相册权限"。改用 `permission.hasAccess`（含 `authorized` + `limited`）
28. **内部带 recognizer 的 widget 外层包 GestureDetector 会吞事件** — `PhotoCard` 内部 `GestureDetector` 注册了 `onTapDown/onTapUp/onTapCancel`（按压动画），若外部再包一层 `GestureDetector(onTap)` 且 PhotoCard 的 onTap 为 null，内部 recognizer 赢得手势竞技场并吞掉 tap，外层永远收不到。**回调应直接传给 PhotoCard**（home_page/album_detail_page 统一模式：onTap/onLongPress 传 PhotoCard，不外包 GestureDetector）
29. **GlobalKey 不应挂在会随条件分支迁移的 widget 上** — 详情页 `_imageKey` 曾同时挂在两条代码路径的 Image 上（非取色分支 vs 取色模式 `_buildImageWithOverlays`），切换取色模式时 widget 树结构变化，同一帧可能让两个 Image 同时引用同一 GlobalKey → "Multiple widgets used the same GlobalKey" 断言。**GlobalKey 只挂在一处**，且条件分支复用同一个已构建的 widget 子树（取色模式复用 `viewer` 而非重建第二个 Image）
30. **清空集合前先取 length** — `_selectedIds.clear()` 后再读 `_selectedIds.length` 永远是 0。批量操作的 SnackBar 计数必须 `final count = list.length` 在 clear 之前存住
31. **drift FK 无 cascade 时 delete 父表必须事务内先清子表** — `PRAGMA foreign_keys=ON` 已开启，但关联表 FK 默认 `NO ACTION`（未配 `onDelete: KeyAction.cascade()`）。直接删带子引用的父行（如删带照片的 plan、删被相册/策划引用的 photo）会抛 `FOREIGN KEY constraint failed`。`deleteAlbum` 必须事务内先删 albumPhotos**和 albumTags**（v2.1 相册也有关联标签）；`deletePlan` 必须先删 planPhotos；`deletePhoto` 必须先清 colorPins/albumPhotos/planPhotos（v2.1 起照片不再有标签，无需清 photoTags）。零迁移方案（不升 schemaVersion）
32. **build() 期间不可用 `AsyncValue.whenData` 改局部变量** — `ref.read(provider).whenData((data)=>photo=data)` 是反模式：FutureProvider 处于 loading 时闭包不执行，`photo` 留 null 且无报错。应 `await ref.read(...future)`（在事件回调里）或直接用 `build()` 顶部已 watch 的 data 分支值传入子方法
33. **FutureProvider 要级联失效必须 watch 而非 read DAO** — 分析 provider（histogram/palette/tone/clipping）曾直连 `db.photoDao.getPhotoById`，导致 invalidate `photoByIdProvider` 时分析数据不刷新（gotcha #24 的另一半）。必须 `ref.watch(photoByIdProvider(id).future)` 建立依赖，invalidate 才能级联
34. **IndexedStack 常驻页面的本地状态不刷新** — `ProfilePage` 在 IndexedStack 中常驻，initState 里一次性 `_loadStats` 后永不刷新（增删照片后统计数字不变）。常驻页面要用 reactive（watch StreamProvider）而非一次性 Future
35. **动态列表 row 的 ValueKey 必须用稳定 id 而非 index** — `EditableShotRow`/`EditableGearRow` 曾用 `ValueKey('shot_$i')`（index），删中间项后下方行 index 变化，Flutter 按 index 复用导致 `TextEditingController` 文本错位（与光标漂移 gotcha #20 同源）。`ShotItem`/`GearItem` 加稳定 `id` 字段，ValueKey 用 `item.id`
36. **版本号单一数据源** — profile 曾写 `v2.0.0`、settings 写 `v1.2.0`、pubspec 是 `1.2.0+1`，三处不一致。统一引用 `lib/utils/app_info.dart`（`appVersion`/`appVersionLabel`），改版本时只改 app_info.dart + pubspec.yaml 两处
37. **Async 错误兜底要 PlatformDispatcher.onError** — `FlutterError.onError` 只覆盖框架错误（build/layout/paint），纯 Dart 异步错误（Isolate 抛出、未 await 的 Future）不被捕获。需额外设 `PlatformDispatcher.instance.onError`（返回 true 表示已处理）。ErrorWidget 兜底页要包 `Directionality`，否则 MaterialApp 之上报错时 Text 渲染失败
38. **标签体系从照片迁移到相册的尽力迁移（v2.1）** — 标签改为相册的子系统后，旧 `photo_tags` 数据需在 v9 migration 内尽力迁移：`INSERT INTO album_tags SELECT DISTINCT ap.album_id, pt.tag_id FROM photo_tags JOIN album_photos ON photo_id`，再 `deleteTable('photo_tags')`。**注意**：不属于任何相册的照片标签会被丢弃（照片已无标签归属）；`searchQueryProvider` 原同时驱动「搜索框」和「作品库标签chips筛选」，标签下线后 chips 删除，搜索框改喂 `watchPhotosByName`（按文件名）。`albumsWithTagsProvider` 聚合查询消除原 `_AlbumCard` 每张卡 2 个 FutureBuilder 的 N+1 问题
39. **ToneResult v3.0 字段强制重算策略** — 新增 `entropy`/`rmsContrast`/`skin` 后，`ToneResult.fromJson` 对 entropy/rmsContrast 用 `(j[key] as num).toDouble()` 强转（**不加默认值**）。旧 toneJson 缺这些键 → 抛 TypeError → 被 `fromJsonString` 的 try/catch 捕获返回 null → `toneProvider` 自动重算并回写。**唯独 `skin` 用 `SkinAnalysis.fromJson(j['skin'] as Map?)` 容错**：因为肤色数据依赖 BlazeFace 人脸检测（非全量预计算），旧缓存只缺 skin 不应触发重算（会陷入"无脸→空 skin→重算→还是空"死循环）。skin 由 `skinProvider` 独立异步补算
40. **drift FK setNull 在测试内存库不生效** — drift 的 `references(..., onDelete: KeyAction.setNull)` 依赖 `PRAGMA foreign_keys=ON`，但 `createTestDatabase()` 用的 `NativeDatabase.memory()` 未启用该 pragma（生产 `_open()` 才开）。因此 v10 的 `ShootingPlans.associatedAlbumId` FK setNull **在测试中不会自动触发**。遵循现有 v2.1 模式：`deleteAlbum` 事务内显式 `update(shootingPlans)..where(associatedAlbumId.equals(albumId)).write(Value(null))`，DAO 自管级联不依赖 pragma。同时 `AlbumDao` 注解的 tables 列表必须包含 `ShootingPlans`，否则 `shootingPlans` 标识符在 DAO 内不可见
41. **TFLite 模型在 Isolate 内只能从文件加载** — `tflite_flutter` 的 `Interpreter.fromAsset` 内部用 `rootBundle`，但 `rootBundle` 是 platform channel，**在 Isolate 内不可用**。正确流程：主线程 `ensureModelExtracted()` 把 asset 拷贝到 `getTemporaryDirectory()/tflite_models/`，把**文件路径**传给 Isolate，Isolate 内 `Interpreter.fromFile()`。`face_service.dart` 的 `_FaceAnalysisArgs.modelPath` 因此是文件路径而非 asset key
42. **冷暖色相区间的 bin 计数不对称** — `calculateWarmToColdRatio` 暖色区 `h<=60 || h>=300`（121 bins），冷色区 `150<=h<=250`（101 bins）。即使每 bin 计数相同，比率也是 121/101 ≈ 1.2 而非 1.0。测试断言要用 `closeTo(121/101, 0.01)` 而非 `closeTo(1.0, ...)`
43. **ToneInfoCard 不自带滚动容器** — v3.0 重构后 `ToneInfoCard` 去掉了内部 `SingleChildScrollView`（避免与 `_buildToneTab` 外层 `SingleChildScrollView` 嵌套产生 ScrollController 异常）。Widget 测试需手动包 `SingleChildScrollView` 模拟真实使用场景，否则内容溢出 576px 测试视口
44. **tflite_flutter 触发两个 Android 构建坑** — 引入 `tflite_flutter: ^0.11.0` 后 CI 连续三次构建失败，根因和修复：(a) 插件 Java(1.8) 与主项目 Kotlin(17) JVM 目标不一致 → 根 `build.gradle.kts` 加 `subprojects { afterEvaluate { ...统一 JVM 17 } }`，**必须**在 `evaluationDependsOn(":app")` 之前注册；(b) 插件间接依赖 `org.tensorflow:tensorflow-lite{,-gpu,-api}:2.11.0` 共用 namespace `org.tensorflow.lite` 触发 AGP 9.x 的 `uniqueManifestNamespace` 校验。**关键**：`android.uniqueManifestNamespaceRequired=false` 降级 flag 在 AGP 9.x **已被忽略**，不能靠 gradle.properties 关闭。正确修复：根 `build.gradle.kts` 的 `allprojects { configurations.configureEach { resolutionStrategy.eachDependency { ... } } }` 强制 `org.tensorflow:*` 升级到 2.16.1（已正确声明独立 namespace），**必须放在 allprojects 内**让 `:tflite_flutter` 插件模块的依赖解析也生效
45. **像素物理属性蒙层必须挂在 InteractiveViewer 内部** — `ClippingOverlay` / `SharpnessOverlay` 表达的是照片像素属性（合焦/溢出），必须与 Image 共享 InteractiveViewer 的缩放/平移变换。若挂外层 Stack（如取色放大镜那种屏幕坐标组件），放大检查时斑点会错位、对焦/溢出功能彻底失效。构图参考线 `CompositionOverlay` 相反，是屏幕坐标三分线，应挂外层不随缩放
46. **STI 接近度公式弃用乘积** — `plan.md` 原 STI = Y×(1−S)×(1−Texture) 乘积公式在低饱和/低纹理场景反直觉（塑料脸误判为高通透）。改为高斯接近度 `⅓·gaussian(Y,0.65,0.15) + ⅓·gaussian(S,0.25,0.1) + ⅓·(1−|ΔH|/30)`，理想肤色点 Y=0.65/S=0.25/H=17°（达芬奇肤色线）。Texture 独立为粗糙度维度，不参与通透度。**已知限制（待修）**：STI 理想肤色测试阈值 `>0.85` 可收紧到 `>0.95`（高斯理想点理论值=1.0，采样扰动下 0.85 偏松，属测试精度优化）
47. **标准化欧氏距离替代马氏距离** — 用户档案匹配用各维度 {mean, std} 的标准化欧氏距离，**不用**多维高斯马氏距离（N=3 协方差矩阵奇异，数学硬伤）。融合：直方图卡方 60% + 标量标准化欧氏 40%，相似度 `exp(-D²/4.0)`（衰减系数 v3.5 二轮复核从 2.0 放宽到 4.0，因为内置理论档案 hist_means 是高斯生成、与真实照片多峰分布天然偏离，2.0 系数会让相似度系统性偏低）。缺失维度（STI/FLC = -1）跳过，不影响其他维度
48. **Face Mesh 需可见性判定** — FLC 切左右脸时，`visibility < 0.5` 的 landmark 跳过，左右脸区域平均 visibility < 0.5 时 FLC 返回 null（侧脸降级）。旧格式 `face_mesh.tflite` 无原生 visibility，用 z 深度归一化近似。**已知限制（待修）**：(a) 当前左右脸划分用固定 landmark 索引集（leftFaceRegion/rightFaceRegion）而非动态中轴线（鼻尖 1 + 双眼 33/133），轻微偏头场景数值偏小，待对称 landmark 对方案；(b) z 归一化对侧脸检测语义偏弱
49. **导入不预计算，档案需批量钩子** — 现有架构是懒计算（详情页打开才算），档案系统需全量数据，必须在创建档案时主动调用 `precomputeAnalysisForPhotos`。**v3.5 二轮复核修复**：`precomputeAnalysisForPhotos` 现在也计算 advanced（含 Face Mesh 的 STI/FLC），让档案样片即使未打开详情页，STI/FLC 也能进入指纹匹配（之前预计算只写 toneJson 不写 advanced 键，导致用户档案的 STI/FLC 维度恒为 -1 被跳过）。核心计算逻辑提取为 `tone_service.computeAdvancedMetrics` 纯函数，`advancedMetricsProvider` 和 `precomputeAnalysisForPhotos` 共用
50. **ten_tonal_type 复用 toneKey×toneRange** — 不引入 `plan.md` 的 `classifyTenTonalities(mean/stdDev 阈值)` 分类（与现有基于像素分布的 `_classifyToneKey`[峰值+合并段占比] 和 `_classifyToneRange`[最值分布范围] 双逻辑冲突）。直接组合 `toneKey×toneRange`，`toneKey='full'` 时特判为「全长调」（不再拼接 rangeLabel，避免「全长长调」）。**v3.5 二轮复核修复**：`builtin_profiles.dart` 的 `scalar_means` 必须用 RAW 单位（与 `_computeFingerprintIsolate` 一致）—— 原 RMS=0.15~0.35 差 2 个数量级（应为 0~128 区间），导致内置档案匹配功能失效，已修正为日系 RMS≈25/港风≈45/青橙≈60/中式≈22，并补全 hist_means（原缺失导致卡方融合退化为 0/40）
51. **BlazeFace 解码三大致命 bug（v6.0 根因修复）** — `_detectPrimaryFace` 与 MediaPipe 官方解码不符（参考 [patlevin/face-detection-tflite](https://github.com/patlevin/face-detection-tflite/blob/main/fdlite/face_detection.py)），导致「永远检测不到脸」：(a) classifier 输出是 **logit**，原代码当概率用 → 阈值 0.5 永远过不了 → 必须套 `sigmoid`；(b) box 回归值是 **INPUT_SIZE 像素空间**的偏移，原 `cx = anchor[0] + r[0]` 直接加到 [0,1] 归一化 anchor 上 → 中心偏离几百倍 → 必须 `/ inputSize` 归一化；(c) short(128)/full(192) inputSize 不同，必须传对应 inputSize 给解码。anchor 数 short&full 都是 896（feature map [16,8,8,8]×2 与 inputSize 解耦）。回归测试在 `face_service_anchor_test.dart` v6.0 组
52. **构图/锐度蒙层的 letterbox 补偿** — `Image(fit: BoxFit.contain)` 在容器内是 letterboxed（上下/左右留黑），蒙层（CompositionOverlay/SharpnessOverlay/ClippingOverlay）若直接用整个 Stack 尺寸画线/斑点会溢出图片到黑边区域。**必须按 imageAspect 计算「图片实际矩形」**（offsetX/offsetY + drawWidth/drawHeight），只在图片矩形内绘制。CompositionOverlay 现用 `canvas.clipRect(rect)` + translate 裁剪到图片区域；蒙层（clipping/sharpness/构图）必须挂 InteractiveViewer **内部**共享变换（gotcha #45），但 letterbox 补偿是独立的坐标问题，两者都要做
53. **取色 session 后台预解码** — 进入详情页时 fire-and-forget 预解码 `ColorPickerSession.begin(maxDim:1200)`，用户点「取色」时命中缓存零等待（v3.1 的同步 `setState(loading=true)` 阻塞 UI 几秒）。用 `_photoFilePath` guard 幂等（同一张照片只触发一次）。预解码失败静默兜底，按下取色按钮再走正常 `_enterColorPickMode`。maxDim 1600→1200 降 30% 内存（取色精度 1200 长边仍足够单像素）
54. **取色 Pin 弹菜单 + 设为肤色基准** — `ColorPinMarker` 的 `onTap` 接到 `_showPinMenu`：色值预览/「设为肤色基准」(`manualSkinSelectionProvider.select`)/删除。当前选中的 pin 用 accent 描边 + face 图标高亮（与 manualSkinSelectionProvider 联动，RGB 三通道匹配）。删的若是当前基准必须清 manualSkinSelection 避免悬空引用。手动校准优先于 BlazeFace（skinProvider 已支持，见 gotcha #39 skin 容错策略）
55. **肤色雷达图（5 维合理性可视化）** — `SkinRadar` 把肤色 5 维（ΔH/饱和/明度/STI/SLS）归一化到 [0,1] 画雷达多边形，中心=理想肤色（达芬奇线 H=17/S=25/Y=65），越饱满越健康。区别于「指纹雷达」FingerprintRadar（9 维物理量，档案匹配用）。归一化阈值与 ToneGuideCard/stage_color_card 解读阈值对齐（ΔH ±30°、饱和 40±30、明度 65±25、STI 0.85、SLS 20）。嵌入阶②色彩卡片顶部，无肤色时显示空雷达占位 + 手动校准引导
56. **ML Kit 替代 BlazeFace 作主检测链（v6.1）** — BlazeFace short_range（128 输入）对大头照/小脸召回不足（用户反馈「明显大头照检不出，露出一点皮肤反而检出」）。改用 `google_mlkit_face_detection`（bundled 不依赖 GMS）作主链：`FaceDetectorMode.accurate` + `minFaceSize:0.15` 稳定抓大头照。**关键**：(a) ML Kit 走 platform channel，**不能在 Isolate 内用**，在主线程跑返回 bbox；(b) `InputImage.fromFilePath` 的 `metadata` **恒为 null**（google_mlkit_commons 0.11.1 源码确认，只存文件路径），不能拿旋转后尺寸；(c) ML Kit 原生侧**应用 EXIF 旋转**，bbox 在【旋转后图像像素】空间，但 image 包 `decodeImage` 给【存储尺寸未旋转】——**必须读 EXIF Orientation，对 90°/270° 旋转的照片宽高互换后再归一化**（否则竖拍照片 bbox 整体扭曲）；(d) `detectedFaceProvider` 返回 `FaceDetection`（bbox + displayWidth/Height），overlay 必须用显示尺寸算 letterbox，**不能用 `photo.width/height`（存储尺寸）**；(e) `FaceDetectorMode` 不是 `PerformanceMode`（指南写错）；(f) 必须 `close()` 释放（单例 `_singletonDetector`，main.dart `_AppLifecycleObserver` detached 时 `disposeMlKitDetector`）。ML Kit 失败/不可用 → `skinProvider` 回退 BlazeFace Isolate
57. **取色坐标系统一为 Stack-local（v6.1 问题3）** — 原放大镜用 `localPosition`、像素查找用 `globalPosition`、pin 用 `_imageKey` box 局部坐标，三者参考系不一致 → 取色位置/放大镜中心/pin 落点错位。修复：全部统一为【取色 Stack 的 local 坐标系】——(a) 取色模式 `InteractiveViewer` 锁定 scale=1 + 禁用 pan/scale（坐标固定不漂移）；(b) 像素查找 `_pickColorAtSync(localPos)` 用 `_calculateImageRectInStack()`（图片 global 坐标→Stack local via `globalToLocal`）；(c) pin 渲染用同一 `_calculateImageRectInStack` 映射。放大镜 position=localPos → 中心对准手指；像素=手指下像素；pin=取色时的放大镜中心，三者必然对齐
58. **DetailBottomPanel 固定高度而非 maxHeight（v6.1 问题4）** — 原用 `maxHeight:380` + `Column(mainAxisSize.min)`，当内容（工具行+GradingPanel）高度 < 380 时，Column 居中导致上下留暗色空隙，展开后顶部出现「大黑框」。改为 `AnimatedContainer(height: 368/72)`（精确高度 = 工具行 60 + GradingPanel 308）+ `Column` 内 `Expanded(GradingPanel)` 紧贴工具行填满剩余空间 + `clipBehavior: hardEdge` 裁剪溢出。消除所有暗色空隙
59. **顶部通知替代底部 SnackBar（v6.1 问题2）** — 详情页底部 SnackBar 正好挡住工具行操作按钮（黑白/构图/取色等）。改用 `_showTopNotice` 在顶栏下方浮出胶囊通知（accent 色 + check 图标），3 秒自动消失，避开操作热区。详情页所有 `ScaffoldMessenger.showSnackBar` 统一替换为 `_showTopNotice`
60. **作品库多选模式重构（v6.1 问题5）** — 原操作栏 `Row(spaceAround)` 的「取消」按钮被导入 FAB 遮挡。修复：(a) 多选模式隐藏 FAB（`floatingActionButton: _selectMode ? null : FAB`）；(b) 操作栏改 Material elevation 底栏，左侧「取消」IconButton 醒目（绝不被遮挡）+ 已选数量 chip + 右侧「加入相册/删除」主操作按钮
61. **AnimatedOpacity 不能配条件渲染（v6.1 review 修复）** — `AnimatedOpacity` 是 `ImplicitlyAnimatedWidget`，opacity **值变化**才触发动画，且 widget **首次挂载时不动画**（直接以当前 opacity 渲染）。反模式：`if (visible) AnimatedOpacity(opacity: visible?1:0)` —— widget 存在时 visible 必为 true（opacity 恒 1），移除时直接消失来不及播淡出，**淡入淡出都不触发（死代码）**。正确做法：widget **常驻树**，用独立的 `_visible` bool 切 opacity（先挂载 opacity:0，再 setState opacity:1 触发淡入；onTimeout 先 setState opacity:0 播淡出，动画结束再清内容）。`_buildTopNotice` 已按此重构

## v3.5 已知限制（非阻塞，待后续优化）

- **P6**：`style_profile_page._PhotoSelectDialog` 当前用文字列表 + checkbox 选样片，无缩略图预览（与 v2.0 瀑布流多选体验割裂）。MVP 可接受，待补缩略图瀑布流多选
- **P7**：STI 理想肤色测试阈值 >0.85 可收紧到 >0.95（见 gotcha #46）
- **P2**：FLC 左右脸划分用固定 landmark 集而非动态中轴线（见 gotcha #48）

## 许可证合规

- 算法实现参考 MIT 许可的 color-thief
- 取色卡 Color_Card（GPL-3.0）仅做功能设计参考，不参考其代码
- Rec.709 亮度公式是 ITU 公开标准
- material_color_utilities 是 Apache 2.0

## 注意事项

1. **纯本地应用**，不联网，不收集用户数据（无 INTERNET 权限）
2. **照片数量 ≤ 1000**，性能优化以此为基准
3. **Android 最低 API 26**（Android 8.0）
4. 所有删除操作需二次确认
5. **绝不主动合并 main**，所有开发在 feature 分支，除非用户明确要求
6. **导入权限预检**：`PhotoManager.requestPermissionExtend()` 在 `AssetPicker.pickAssets` 之前调用，拒绝时引导设置。**判定授权用 `permission.hasAccess`（含 `limited` 部分授权），不要用 `permission.isAuth`（仅 `authorized` 完全授权）**，否则 Android 14+ / iOS「仅允许访问选中照片」的已授权用户每次导入都会误弹权限提示
7. **清缓存后缩略图按需重生成**：photo_card 检测 thumbnailPath 空时用原图兜底（cacheWidth:360 防 OOM）
