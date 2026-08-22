# 萌图 (Mengtu) - 摄影师全流程工作台

[![Flutter CI](https://github.com/qxxwwyy/mengtu/actions/workflows/build.yml/badge.svg)](https://github.com/qxxwwyy/mengtu/actions)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows-green.svg)](#)

萌图（Mengtu）是一款专为摄影爱好者与专业摄影师设计的**全流程灵感收集与影像分析工作台**。从前期的拍摄策划，到中期的照片批量导入与相册归纳，再到后期的 RGB/HSV 直方图分析、五段式影调占比、色卡提取与色彩和谐度判定，萌图提供了单手可达的流畅体验，是您灵感收集与后期调色的得力助手。

---

## ✨ 核心功能特性

### 1. 📸 智能非阻塞导入与去重 (Smart Import)

- **微信风格选择器**：集成 `wechat_assets_picker` 提供优雅的多图选择体验。
- **SHA256 去重**：纯 Dart 实现 SHA256 哈希计算，入库前自动对照片文件去重。
- **非阻塞后台静默导入**：导入时不锁死屏幕，通过底部 SnackBar 提示进度，导入完成后支持一键“加入相册”或“新建相册”进行延迟归档。
- **异步防 OOM 缩略图**：通过 Flutter Isolate 在后台线程解码大图并进行长边 360px 降采样，生成轻量 JPEG 缩略图，保证界面流畅不卡顿。

### 2. 🖼️ 相册系统与多维排版 (Album & Reordering)

- **双布局无缝切换**：在相册详情页中，支持一键在 **3 列紧凑网格 (Grid)** 与 **2 列美观瀑布流 (Waterfall)** 布局之间无缝切换。
- **物理手势拖拽重排**：在网格视图下，长按图片会触发**触觉振动反馈 (Haptic Feedback)** 并开启物理拖拽，图片排列顺序自动实时持久化在 SQLite 中。
- **封面与描述管理**：支持一键设置相册封面，自定义相册名称与备注描述。

### 3. 🏷️ 瀑布流管理与多选批量操作 (Batch Operations)

- **横向标签筛选栏**：主页顶部配有可横向滚动的标签 chips，点击即刻对瀑布流进行过滤。
- **长按多选模式**：主页瀑布流长按进入多选状态，支持批量加入相册、批量添加标签以及批量从库中移除照片。
- **详情页极速加标签**：在照片详情页中，标签展示 Wrap 区域尾部集成 `+` 样式的交互式 `InputChip`，一键弹出输入框，交互更加贴合浏览上下文。

### 4. 📊 深度图像学分析面板 (Image Analysis)

- **RGB / 亮度直方图**：支持 RGB 三通道叠加直方图、Rec.709 亮度直方图展示，基于 CustomPainter 精准绘制。
- **五段式影调占比**：基于分界点（51/102/153/204）将像素亮度划分为黑色、阴影、中间调、高光、白色 5 段占比统计，智能判定照片基调（如低调、高对比全长调等），兼容旧版 3 段缓存自动平滑重算。
- **色彩占比与色卡提取**：集成 MMCQ (改进中位切分) 与 K-Means++ 算法（支持提取数量 3-8 个自由调节），色块显示宽度根据占比比例动态分配。
- **色相直方图**：360 bins HSV 环状彩虹色条直方图，展示照片的色彩冷暖倾向。

### 5. 🎨 调色辅助工具 Dock (Assistance Tools)

- **悬浮毛玻璃 Dock**：详情页底栏常驻的 6 项毛玻璃悬浮 QuickToolsDock（黑白/溢出/构图/取色/相册/对比），完美贴合手持设备大拇指热区，方便单手操作。
- **一键黑白预览**：基于 Rec.709 灰度矩阵（0.2126R + 0.7152G + 0.0722B）提供纯前端灰度滤镜，支持实时对比度与曝光微调，不破坏原始文件。
- **高光/阴影溢出警告**：红蓝双色交替闪烁，直观展示过曝与死黑区域（支持动态步长调节）。
- **色彩和谐度与色轮**：根据 6 种 HarmonyType（互补、邻近、分裂互补等）计算画面配色和谐度，并在 HSV 色轮上可视化取色点。

### 6. ⚙️ 日光自适应设计系统 (Theme & Settings)

- **自适应外观**：支持跟随系统、浅色模式和深色模式的外观切换，完美兼容明暗双主题。
- **高对比度浅色风格**：在浅色模式下对文字、卡片阴影与边框颜色进行了精心调优，符合 WCAG AA 级对比度标准，保证日光下清晰易读。
- **应用管理**：关于信息展示，支持查看应用存储占用情况并提供一键清理缩略图缓存的功能。

---

## 🛠️ 技术栈

- **核心框架**：Flutter 3.44.2 (Dart 3.12+)
- **状态管理**：Riverpod 3.x (无 `StateProvider` / `StateNotifier`，使用 `Notifier` 与 `StreamProvider.family` 异步流组合)
- **本地数据库**：drift 2.15.0 (SQLite ORM) & sqlite3_flutter_libs
- **核心依赖库**：
  - `image` (纯 Dart 解码与图像采样)
  - `material_color_utilities` (Google 色彩提取算法)
  - `reorderable_grid_view` (拖拽手势重排组件)
  - `wechat_assets_picker` & `photo_manager` (相册选择与管理)
  - `flutter_staggered_grid_view` (瀑布流网格)
  - `shared_preferences` (设置项持久化)

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。

部分算法实现参考了 [color-thief](https://github.com/lokesh/color-thief) (MIT License)。

直方图等亮度亮度判定符合 ITU-R BT.709 公开标准。
