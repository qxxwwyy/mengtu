# 萌图前端重构计划 v2.0

> **目标**：把萌图从「功能齐全但视觉及格线」提升到「专业摄影工具的视觉语言」。
> 一个以色彩学和美学为核心的应用，前端本身就是品牌宣言。
>
> **v2.0 修订**（基于 reviewer 复核）：
> - 工期从 12-16 天修正为 18-22 天（图表工时被严重低估）
> - Phase 2 聚焦核心三件套（直方图+色卡+色轮），影调/示波器降为可选
> - 删除风格指纹雷达图（v3.5 刚做的系统，延后到未来版本）
> - 砍掉过度设计（自定义图标/纸张质感/浮动动画/手势驱动色轮旋转）
> - 补充测试策略、增量发布、性能基准

---

## 一、现状诊断

### 当前设计系统（app_theme.dart）
| 问题 | 详情 |
|------|------|
| 色彩体系单一 | 只有琥珀色(#E8A838)一个 accent，缺少层次。一个色彩分析工具却只有一种点缀色，讽刺 |
| 缺乏字体层级 | 全靠 `FontWeight.w500/w600` 硬编码，没有 typography scale，数值/标题/正文/标注没有视觉区分 |
| 圆角碎片化 | 8/10/12/16/20px 混用，无设计语义 |
| 间距无规范 | `all(12)` / `symmetric(h:12,v:6)` / `fromLTRB(12,0,12,12)` 散落各处 |
| 动画贫乏 | 只有 `AnimatedSize 220ms` 和 `AnimatedScale 0.96`，全 app 缺乏连贯的动效语言 |
| 图表粗糙 | 直方图/色卡/色轮/影调条都是「功能实现」级别，没有视觉打磨 |

### 图表/可视化问题清单
| 组件 | 当前状态 | 核心问题 |
|------|----------|----------|
| **直方图** (histogram_painter.dart) | RGB 半透明叠加 + 纯色边框 | 线条锯齿、无渐变填充、无网格刻度、ACR风格标注过于简陋 |
| **色卡** (color_card.dart) | 横向色块条 + 点击展开 | 色块无过渡动画、占比数字排版粗糙、无色值复制反馈 |
| **色轮** (color_wheel.dart) | 120段扇形 + 白圆中心 | 分辨率低（120段有明显锯齿）、主色点无动画、无色彩关系连线美化 |
| **影调条** (tone_info_card.dart) | 5个水平占比条 | 纯色块堆砌、无渐变过渡、视觉上像进度条而非影调分布 |
| **肤色示波器** (skin_radar.dart) | 极坐标光点 | 已是项目最好的图表，但网格线太密、光点无脉动动画 |
| **四阶卡片** (grading/stage_card.dart) | 折叠/展开容器 | 边框+背景过于平面，缺少深度层次 |
| **数据仪表盘** (raw_data_dashboard.dart) | 全屏数据页 | 纯文字堆叠，无图表化展示 |

### 页面级问题
| 页面 | 问题 |
|------|------|
| **作品库** (home_page) | 瀑布流卡片千篇一律、空状态简陋、搜索栏无质感 |
| **相册列表** (album_page) | 卡片信息密度高但无视觉层次、标签chips过于朴素 |
| **详情页** (detail_page) | 工具栏按钮排布密集、底部面板与图片过渡生硬 |
| **策划列表** (plan_list_page) | 状态chips + 卡片设计缺乏摄影项目感 |
| **个人页** (profile_page) | 统计数字展示平淡、设置入口列表式 |

---

## 二、设计语言定义

### 2.1 核心美学方向：暗房专业美学（Darkroom Professional）

参考标杆：**Lightroom Classic / DaVinci Resolve / Capture One / Darkroom (iOS)**

关键词：深邃、精确、有呼吸感、工具感不玩具感。

### 2.2 色彩系统重构

```
暗色模式（默认，也是核心场景）
├── 背景层级
│   ├── bg-void      #08080A   ← 最深，照片查看区
│   ├── bg-base      #0F0F12   ← 页面底色（比现在深一点，更有深度）
│   ├── bg-surface   #16161A   ← 卡片底
│   ├── bg-elevated  #1E1E24   ← 浮层/弹窗
│   └── bg-hover     #26262E   ← hover/选中态
│
├── 强调色体系（从单一琥珀色升级为色温光谱）
│   ├── accent-amber   #E8A838  ← 主品牌色（保留，暗房安全灯）
│   ├── accent-cyan    #4ECDC4  ← 数据/图表辅色（冷色系分析）
│   ├── accent-coral   #FF6B6B  ← 警告/溢出（暖色系警告）
│   ├── accent-sage    #95E1A3  ← 成功/确认
│   └── text-glow      #F0E6D2  ← 文字高亮（暖白，比纯白柔和）
│
├── 文字层级
│   ├── text-primary     E8E6E3 (88% alpha)   ← 主文字
│   ├── text-secondary   A0A0A8 (55% alpha)   ← 次要
│   ├── text-muted       6A6A72 (35% alpha)   ← 标注/占位
│   └── text-data        #C8B87A              ← 数据数值（暖金色，区分文字和数据）
│
└── 特殊色
    ├── chart-grid       white 6% alpha       ← 图表网格线
    ├── chart-fill-start ← 渐变填充起始色（按通道动态生成）
    └── overlay-scrim    black 40-60% alpha   ← 蒙层
```

### 2.3 Typography Scale

| Token | Size | Weight | LetterSpacing | 用途 |
|-------|------|--------|---------------|------|
| display | 32 | w700 | -0.5 | 数据仪表盘大数字 |
| headline | 22 | w600 | -0.3 | 页面标题 |
| title | 17 | w600 | -0.2 | 卡片标题、section 标题 |
| body | 15 | w400 | 0 | 正文 |
| label | 13 | w500 | 0.3 | 标签、按钮文字 |
| caption | 11 | w400 | 0.4 | 标注、辅助信息 |
| data-xl | 28 | w300 | 0 | 数值展示（细体大数字，更优雅） |
| data-md | 18 | w400 | 0 | 中等数值 |
| mono | 13 | w400 | 0.5 | 色值/坐标等（等宽字体） |

### 2.4 间距系统（8pt grid）

```dart
class Spacing {
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;
  static const xl  = 24.0;
  static const xxl = 32.0;
}
```

### 2.5 圆角系统

| Token | Value | 语义 |
|-------|-------|------|
| radius-sm | 6 | chip、小按钮 |
| radius-md | 10 | 卡片、列表项 |
| radius-lg | 16 | 大卡片、面板 |
| radius-xl | 24 | 弹窗、BottomSheet |
| radius-pill | 999 | 胶囊按钮、badge |

### 2.6 动效语言

| 场景 | Duration | Curve | 说明 |
|------|----------|-------|------|
| 按压反馈 | 100ms | easeOut | scale 0.97 + 轻微暗化 |
| 卡片展开 | 280ms | easeInOutCubic | 高度+透明度+位移三合一 |
| 页面转场 | 300ms | easeInOut | 共享元素过渡（照片→详情） |
| 图表入场 | 400-600ms | easeOutCubic | 数据从 0 增长到目标值 |
| 图表切换 | 250ms | easeInOut | 模式切换时 morph |
| 空状态出现 | 500ms | easeOutBack | 轻微弹性 |
| 列表项入场 | 200ms staggered | easeOut | 依次淡入+上移 |

**核心原则**：图表必须有入场动画。静止的图表是死的，动画的图表是活的。

---

## 三、图表重构方案（核心）

### 3.1 直方图重构（histogram_painter.dart → histogram_chart.dart）— **最高优先级**

**现状**：RGB 半透明叠加，线条锯齿，纯色填充。

**目标**：参考 Lightroom / ACR 直方图风格

```
改进点：
├── 填充改为渐变（通道色 → 透明），不是纯色块
├── 曲线用 Path + 抗锯齿，连接处用 cubicTo 平滑
├── 底部加细网格线（5档：0/25/50/75/100%）
├── 五段分界线改为虚线 + 顶端标注
├── 溢出区域用红色渐变警示填充
├── 入场动画：从底部生长，400ms easeOutCubic
├── 切换模式时 morph 过渡（RGB→亮度→单通道）
└── 点击显示当前位置的色阶值 tooltip
```

> **技术注意**：通道叠加混色原方案用 Screen blend mode，但 `Paint.blendMode` 在
> CustomPainter 内部叠加效果性能未经验证。先做原型验证，如果掉帧则降级为
> 半透明 alpha 叠加（现有方案）+ 渐变填充补偿视觉效果。**不引入新依赖**。

### 3.2 色卡重构（color_card.dart）— **高优先级**

**现状**：横向色块条 + 点击展开数字。

**目标**：

```
├── 色块入场动画：从中心展开（staggered 50ms 间隔）
├── 点击色块弹出详情卡片（色值 + HSV/HSL + RGB + 占比圆环图）
├── 色块间加 1px 暗色间隙增加层次
├── 底部算法切换器改为 segmented control + 平滑切换
├── 数量调节改为优雅的 slider（不是下拉框）
└── 复制色值时 haptic + toast 反馈
```

> **砍掉**：原方案的「色块可拖拽重排（DragTarget）」过度设计，色卡顺序是按占比
> 自动排列的，拖拽重排没有实际价值。删除。

### 3.3 色轮重构（color_wheel.dart）— **高优先级**

**现状**：120段扇形拼接，锯齿明显。

**目标**：

```
├── 用 SweepGradient + drawCircle 替代扇形拼接（零锯齿）
├── 色轮加径向亮度渐变（外圈饱和→中心灰）
├── 主色点改为发光圆点 + 脉动动画 + 连线
├── 配色关系（互补/三角/类比）用半透明扇形高亮
├── 外圈刻度标注（0/60/120/180/240/300°）
└── 点击左右步进按钮旋转色相参考（90° 步进）
```

> **砍掉**：原方案的「旋转手势：拖拽色轮可旋转查看不同色相关系」。
> 理由：色轮在详情页 GradingPanel 内，与 InteractiveViewer 缩放手势冲突风险高
> （项目已踩过 gotcha #45 蒙层手势冲突坑），改为点击按钮步进旋转，安全且克制。

### 3.4 影调可视化重构（tone_info_card.dart）— **可选**

**现状**：5个水平纯色条。

**目标**：

```
影调光谱条（Tone Spectrum Bar）——唯一方案
├── 一条连续渐变条（纯黑→暗部→中调→高光→纯白）
├── 上方叠加当前照片的像素分布曲线（密度图）
├── 五段分界用细刻度线标注
└── 整体视觉类似 Lightroom 的 tone curve 区域
```

> **砍掉方案B（环形影调图）**：与直方图语义重复，且环形分割不利于精确读取。
> Lightroom 惯例也是用水平条/曲线表示影调分布，保持一致。

### 3.5 肤色示波器优化（skin_radar.dart）— **可选（v6.2 已是最佳）**

**现状**：v6.2 刚重构为达芬奇式示波器，已是项目最好的图表。

**改进**（仅微调，不重写）：

```
├── 光点加呼吸脉动动画（800ms 循环，opacity 0.7→1.0）
├── 网格线减少为 3 圈（25%/50%/75%）+ 6 条角度轴
├── 肤色参考线改为虚线 + 末端标注 "Skin Tone Line"
├── 光点离参考线的距离用弧线 + 数值标注
└── 缺失肤色数据时显示优雅的空状态（虚线圆 + 提示文字）
```

> **不重写**：v6.2 已从 5 维雷达重构为达芬奇式示波器（参考 gotcha #55-57），
> 用户反馈良好。仅做视觉微调（呼吸动画+网格精简），不改核心设计。

### ~~3.6 风格指纹雷达图（新增）~~ — **已删除，延后**

> **延后理由**：风格档案系统 v3.5 刚上线，用户使用习惯尚未形成，立即可视化优先级不高。
> 雷达图维度（影调/对比度/饱和度/暖冷比/信息熵/肤色偏移）与指纹定义（96维直方图+7维标量）
> 不完全对齐，需先澄清业务含义。延后到未来版本。

---

## 四、页面级重构方案

### 4.1 全局导航（main_shell.dart）

```
├── 底部导航栏加 blur 效果（BackdropFilter）
├── 选中态加弹性动画（scale + 颜色过渡）
├── Material Icons 保留（已足够精致，不做自定义图标）
└── Badge：策划 Tab 有未完成项时显示数字 badge
```

> **砍掉**：原方案的「导航图标用自定义线性图标替代 Material Icons」。
> 理由：用户偏好简洁可靠，Material Icons 已足够精致。自定义图标增加维护成本和包体积，
> 属于过度设计。

### 4.2 作品库（home_page.dart）

```
├── 搜索栏改为浮动搜索（blur 背景 + 圆角胶囊）
├── 瀑布流卡片：
│   ├── 圆角加大到 14px
│   ├── 多选蒙层改为 checkmark + accent 色半透明（不是灰色）
│   ├── 长按触发 haptic + 缩放反馈
│   └── 图片加载用 shimmer 占位（不是灰底）
├── 空状态：
│   ├── 简洁线条相机/胶卷微图形
│   ├── 引导文案 + CTA 按钮（带渐变背景）
│   └── 入场动画（easeOutBack 弹性出现，无持续浮动）
└── 多选操作栏：
    ├── 毛玻璃背景
    ├── 操作按钮加 icon + 文字
    └── 取消按钮左侧，主操作右侧（符合拇指热区）
```

> **砍掉**：原方案的空状态「浮动动画（上下飘动 3px）」。
> 理由：持续浮动动画可能让用户觉得多余，入场时一次性弹性动画足够。

### 4.3 相册列表（album_page.dart）

```
├── 相册卡片：
│   ├── 封面图占满卡片上半部（大图模式）
│   ├── 卡片加微妙阴影 + 1px 内边框（双层深度）
│   ├── 标签 chips 用半透明 pill 样式
│   └── 更新时间用 relative time（"3天前"）
├── 顶部标签筛选栏：
│   ├── 横向滚动 chips 加选中态 morph 动画
│   └── 选中时 chip 背景色渐变填充
└── 新建相册入口改为右上角 + 图标
```

### 4.4 详情页（detail_page.dart）— 最核心

```
├── 照片区：
│   ├── 进入时共享元素动画（从瀑布流缩略图放大）
│   ├── 图片背景加微妙的 vignette（径向暗角）
│   └── 双指缩放手势加弹性回弹
├── 顶栏：
│   ├── 半透明 blur 背景
│   ├── 返回按钮 + 文件名（标题栏）
│   └── 更多菜单改为 overflow 弹出列表
├── 底部面板：
│   ├── 拖拽把手（grab handle）替代展开按钮
│   ├── 工具行改为图标 + label（竖排，不是只有图标）
│   ├── 工具按钮选中态：accent 色背景 + 发光
│   └── 面板滑动用自定义 AnimationController（不是 AnimatedSize）
│       ├── 半展开：只露工具行
│       ├── 全展开：工具行 + 四阶卡片
│       └── 拖拽实时跟随手指
├── 四阶卡片：
│   ├── 卡片间距加大，视觉透气
│   ├── 序号圆标改为渐变填充
│   └── 展开时卡片轻微上浮 + 阴影增强
└── 顶部通知（_showTopNotice）：
    └── 保持 v6.1 胶囊通知设计（已避开工具行热区），仅做视觉微调
```

> **不改**：原方案要把顶部通知改为 Material snackbar 风格。
> 理由：v6.1 已专门从底部 SnackBar 改为顶部胶囊通知（gotcha #59），解决了底部工具行遮挡
> 问题。重新改回 snackbar 是走回头路，仅微调胶囊样式即可。

### 4.5 策划列表（plan_list_page.dart）

```
├── 策划卡片视觉升级：
│   ├── 顶部关联相册封面缩略图（如果有）
│   ├── 状态标签改为左侧色条（绿=完成/橙=进行中/灰=未开始）
│   └── shot 完成度用圆环进度条
├── 状态筛选 chips 改为顶部 segmented control
└── 新建策划 FAB 保持右下角（不改为扩展菜单）
```

> **砍掉**：原方案的「拍立得风格」+「微妙的纸张质感（subtle texture）」。
> 理由：纸张质感需要纹理图片，增加包体积和复杂度，与「简洁可靠」冲突。
> 卡片用干净的暗色设计 + 色条状态标识即可传达专业感。
>
> **砍掉**：原方案的「新建策划 FAB 改为右下角扩展菜单（FAB → 策划/相册）」。
> 理由：策划和相册是不同 Tab 下的功能，跨 Tab 扩展菜单增加导航复杂度。保持各自 Tab 的
> 独立 FAB 更直接。

### 4.6 个人页（profile_page.dart）

```
├── 顶部统计区改为数据卡片网格：
│   ├── 4 个统计卡片（照片数/相册数/策划数/标签数）
│   ├── 大数字（data-xl typography）+ 小标签
│   └── 卡片背景微妙渐变
├── 风格档案入口改为横向滚动卡片预览
├── 设置入口加 icon + chevron（列表样式）
└── 版本号 + 关于信息移到底部（footnote 样式）
```

### 4.7 设置页（settings_page.dart）

```
├── 分组列表（iOS Settings 风格）：
│   ├── 每组有 section header
│   ├── 组内项目用 card 包裹
│   └── 项目间用细分割线
├── 主题切换改为三段式预览（亮/暗/跟随系统各一个小预览框）
├── 存储统计改为：
│   ├── 圆环进度图（已用/总量）
│   └── 分类细分（照片/缓存/数据库）
└── 关于区加 app icon + 版本 + 开源信息
```

---

## 五、新增动效系统

### 5.1 需要引入的动画

| 动效 | 位置 | 实现方式 |
|------|------|----------|
| **共享元素转场** | 瀑布流卡片 → 详情页 | Hero widget（照片缩略图） |
| **数字滚动** | 统计数字变化 | TweenAnimationBuilder + 数字插值 |
| **图表入场** | 所有图表首次显示 | TweenAnimationBuilder（progress 0→1） |
| **拖拽面板** | 详情页底部面板 |自定义 DragPanel + AnimationController |
| **弹性空状态** | 空列表页 | TweenAnimationBuilder + easeOutBack |
| **shimmer 加载** | 图片/数据加载中 | 自定义 Shimmer widget |
| **page transition** | 所有页面跳转 | 自定义 PageRouteBuilder（fade + slide） |
| **chip 选中 morph** | 标签/筛选 chips | AnimatedContainer + 颜色过渡 |

### 5.2 Haptic Feedback 策略

```
轻触选择     → HapticFeedback.selectionClick()
长按多选     → HapticFeedback.mediumImpact()
删除/危险操作 → HapticFeedback.heavyImpact()
切换工具     → HapticFeedback.selectionClick()
拖拽排序     → HapticFeedback.mediumImpact()
复制色值     → HapticFeedback.lightImpact()
```

---

## 六、技术实施方案

### 6.1 新增依赖

```yaml
# 无需新增重量级图表库。
# 萌图的所有图表都是高度定制的 CustomPainter，
# 引入 fl_chart 反而丧失控制力。
# 保持纯 CustomPainter 路线，但大幅提升绘制质量。
```

**不引入 fl_chart 的理由**：
- 萌图的图表（直方图/色轮/示波器/影调条）都是专业领域定制图表，fl_chart 的 LineChart/BarChart 模板无法直接满足
- CustomPainter 给予像素级控制力，可以做渐变填充、抗锯齿曲线、自定义网格
- 当前 335 行的 histogram_painter 已经是正确路线，只是视觉打磨不够
- 保持零额外依赖（纯本地应用原则）

### 6.2 文件结构变更

```
lib/
├── theme/
│   ├── app_theme.dart          # 重构（design tokens + theme builder）
│   ├── app_colors.dart         # 新增（色彩系统）
│   ├── app_typography.dart     # 新增（typography scale）
│   ├── app_spacing.dart        # 新增（间距 + 圆角）
│   └── app_animations.dart     # 新增（动效常量 + curves）
├── widgets/
│   ├── charts/                 # 新增目录（统一图表组件）
│   │   ├── histogram_chart.dart     # 重构直方图
│   │   ├── color_palette_bar.dart   # 重构色卡
│   │   ├── color_wheel_v2.dart      # 重构色轮
│   │   ├── tone_spectrum.dart       # 重构影调可视化（可选）
│   │   ├── skin_vectorscope.dart    # 优化肤色示波器（可选）
│   │   └── chart_animations.dart    # 共享动画 mixin/helper
│   ├── common/                 # 新增目录（通用 UI 组件）
│   │   ├── shimmer_placeholder.dart
│   │   ├── drag_bottom_panel.dart
│   │   ├── empty_state.dart
│   │   ├── animated_number.dart
│   │   ├── blur_app_bar.dart
│   │   └── section_header.dart
│   └── ...（原有 widgets 保留，逐步替换）
```

### 6.3 重构顺序（优先级）

#### Phase 1：设计系统地基（2-3天）
1. `app_colors.dart` — 色彩 token 系统
2. `app_typography.dart` — 字体层级
3. `app_spacing.dart` — 间距/圆角常量
4. `app_animations.dart` — 动效常量
5. `app_theme.dart` — 重构 ThemeData builder
6. 全局 grep 替换硬编码颜色/圆角/间距 → token 引用

**验收**：`dart analyze` 零 error；grep 确认零硬编码 `Color(0x` 和 `BorderRadius.circular(` 散落值。

#### Phase 2：图表重构（6-8天，核心价值）— **工时修正**
7. `chart_animations.dart` — 入场动画 helper（1天）
8. `histogram_chart.dart` — 直方图（3天，含原型验证 blend mode）
9. `color_palette_bar.dart` — 色卡（2天）
10. `color_wheel_v2.dart` — 色轮（2天）
11. *（可选）* `tone_spectrum.dart` — 影调可视化
12. *（可选）* `skin_vectorscope.dart` — 肤色示波器优化

> **Phase 2 变更说明**：原 v1.0 计划 3-4 天做完 6 个图表，reviewer 指出严重低估。
> CustomPainter 开发成本高（渐变填充+抗锯齿+网格+动画+性能调优），每个核心图表至少 2-3 天。
> 聚焦三件套（直方图+色卡+色轮），每完成一个立即 Widget 测试 + 真机预览。

#### Phase 3：详情页改造（2-3天）
13. `drag_bottom_panel.dart` — 可拖拽底部面板
14. 详情页工具行重构（图标+label 竖排）
15. 四阶卡片视觉升级
16. 共享元素转场（Hero）

#### Phase 4：全局页面打磨（3-4天）
17. `main_shell.dart` — 导航栏 blur + 动画
18. `home_page.dart` — 搜索栏 + 空状态 + shimmer
19. `album_page.dart` — 相册卡片升级
20. `plan_list_page.dart` — 卡片视觉升级
21. `profile_page.dart` — 数据卡片网格
22. `settings_page.dart` — iOS 风格分组列表

#### Phase 5：动效系统串联（1-2天）
23. 页面转场路由（fade + slide）
24. 数字滚动动画
25. Haptic feedback 全局接入
26. 全局动画一致性 review

**预估总工期：18-22 天**（v1.0 的 12-16 天被 reviewer 判定为严重低估）

### 6.4 增量发布策略

| 里程碑 | 内容 | 发布条件 |
|--------|------|----------|
| **M1** | Phase 1 + Phase 2（直方图+色卡+色轮） | 图表视觉验证通过 |
| **M2** | Phase 3（详情页改造） | 真机交互测试通过 |
| **M3** | Phase 4 + Phase 5（全局打磨+动效） | 全量测试通过 |

> 按 M1→M2→M3 分批交付，每批可独立验证。不一次性 18 天憋大招再发布。

---

## 七、设计参考标杆

| 应用/资源 | 借鉴点 |
|-----------|--------|
| **Adobe Lightroom** | 直方图风格、工具栏布局、暗色专业感 |
| **DaVinci Resolve** | 肤色示波器、色轮、scopes 整体设计语言 |
| **Darkroom (iOS)** | 整体暗色美学、毛玻璃效果、优雅转场 |
| **Capture One** | 色卡展示、影调工具的精确感 |
| **Apple Photos** | 详情页手势、共享元素转场 |
| **Google Photos** | 瀑布流体量感、搜索栏交互 |
| **VSCO** | 极简滤镜界面、胶片美学 |
| **Dribbble: dark mode UI** | 空状态设计、micro-interactions |

---

## 八、验收标准

### 必须达成
- [ ] 全 app 零硬编码颜色值（全部走 token）
- [ ] 全 app 零硬编码圆角/间距（全部走 token）
- [ ] 核心三图表（直方图/色卡/色轮）有入场动画
- [ ] 所有交互有 haptic feedback
- [ ] 暗色/浅色双主题视觉一致
- [ ] 空状态全部美化（不再是空白+文字）
- [ ] 详情页底部面板可拖拽
- [ ] 每个重构图表有 Widget 测试（验证数据正确性 + 边界条件）
- [ ] 低端设备帧率 ≥ 45fps（Android 8.0，1000张照片场景）

### 应该达成
- [ ] 共享元素转场（瀑布流→详情页）
- [ ] shimmer 加载占位
- [ ] 数字滚动动画
- [ ] 图表切换 morph 过渡

### ~~加分项~~ — 已删除
> ~~自定义图标（替代 Material Icons）~~ — 过度设计，已砍
> ~~图表长按 tooltip~~ — 改为点击显示，降复杂度
> ~~手势驱动的色轮旋转~~ — 手势冲突风险，改为步进按钮

---

## 九、测试策略

### 9.1 Widget 测试
每个重构图表必须有测试用例覆盖：
- **直方图**：空数据/全黑图/全白图/正常分布；RGB 叠加不溢出；入场动画 progress 0→1
- **色卡**：3-8 色数量边界；占比归一化（合 = 100%）；点击详情弹窗正确显示 HSV/RGB
- **色轮**：SweepGradient 无锯齿；主色点位置 = 正确角度；空 palette 不崩

### 9.2 性能基准
- `FlutterPerformanceOverlay` 在开发模式下开启
- 低端设备测试：Android 8.0 模拟器，1000 张照片，直方图渲染 + 滚动 → 帧率记录
- `shouldRepaint` 严格验证：不相关数据变化不触发重绘

### 9.3 回归测试
重构图表后，现有 `histogram_service_test` / `tone_service_test` 必须全绿（服务层不变，只改 UI 渲染）。

---

## 十、风险与约束

| 风险 | 缓解措施 |
|------|----------|
| CustomPainter 性能（动画+渐变） | 用 `shouldRepaint` 严格控制重绘范围；static Paint 复用；直方图 blend mode 先做原型验证，掉帧则降级 |
| SCRFD NCNN 插件与新 UI 的兼容 | UI 层与检测层解耦，重构不碰 services/ |
| 1000 张照片的性能 | 瀑布流 shimmer 只对可见区域生效；动画用 `addAutomaticKeepAlives: false` |
| 浅色模式可能变次要 | 暗色模式是核心场景，浅色模式保持功能完整但视觉优先级低 |
| Riverpod 3.x 状态与 UI 动画的协调 | 动画用 Widget 内部 AnimationController，不依赖 Provider 状态变化 |
| CustomPainter 遇技术瓶颈（如 blend mode 性能差） | 每个 chart 先做原型验证，有 fallback 方案（降级为半透明 alpha + 渐变填充） |

---

## 十一、v2.0 修订日志（vs v1.0）

| 修改项 | v1.0 | v2.0 | 原因 |
|--------|------|------|------|
| 工期 | 12-16 天 | 18-22 天 | reviewer 判定严重低估 |
| Phase 2 范围 | 6 个图表 | 3 核心 + 2 可选 | 聚焦三件套，每完成即测试 |
| 风格指纹雷达图 | 新增 | 删除（延后） | v3.5 刚上线，优先级不高 |
| 影调可视化 | 方案A+B | 仅方案A | 方案B 与直方图语义重复 |
| 自定义图标 | 加分项 | 删除 | 过度设计 |
| 纸张质感（策划卡片） | 有 | 删除 | 增加包体积 |
| 浮动动画（空状态） | 持续浮动 | 仅入场弹性 | 用户可能觉得多余 |
| 色轮旋转手势 | 拖拽 | 步进按钮 | 与 InteractiveViewer 手势冲突 |
| 色卡拖拽重排 | 有 | 删除 | 色卡按占比自动排列，拖拽无价值 |
| 顶部通知 | 改 Material snackbar | 保持 v6.1 胶囊 | 不走回头路 |
| FAB 扩展菜单 | 有 | 删除 | 跨 Tab 菜单增加导航复杂度 |
| 增量发布 | 无 | M1/M2/M3 三批 | 降低一次性重构风险 |
| 测试策略 | 无 | 补充 9.1-9.3 | 图表正确性必须验证 |
| 性能基准 | 无 | ≥45fps 低端设备 | 可量化验收 |

---

## 十、重构边界与红线（执行必读）

### 10.1 允许修改的范围

```
lib/
├── theme/              ← 全部重构
├── widgets/            ← 全部可改（含 charts/ 和 common/ 新增）
├── pages/              ← 全部可改（UI 层）
├── utils/              ← 可改（如 color_utils）
└── main.dart           ← 可改（路由/主题初始化）
```

### 10.2 禁止修改的范围（红线）

```
lib/
├── services/           ← 禁止！所有计算服务（tone/histogram/palette/face/fingerprint...）
├── models/             ← 禁止！数据模型（ToneResult/PaletteResult/HistogramData...）
├── algorithms/         ← 禁止！MMCQ/K-Means 算法实现
└── services/database/  ← 禁止！drift 表/DAO/schema
```

> **原则**：本次只改 UI 渲染层（widgets/pages/theme），不碰数据层和计算逻辑。
> 所有图表的数据来源（Provider → Model）保持不变，只改 Widget 如何渲染这些数据。

### 10.3 图表数据流链路（重构时保持不变）

| 图表 | Provider | 数据模型 | 当前 Widget |
|------|----------|----------|-------------|
| 直方图 | `histogramProvider(id)` | `HistogramData`（含 r/g/b/lum/hue 通道） | `HistogramPainter` |
| 色卡 | `paletteProvider(params)` | `PaletteResult`（List<PaletteColor>） | `ColorCard` |
| 色轮 | `analyzeHarmony(palette)` 纯函数 | `HarmonyResult`（hues + type + confidence） | `ColorWheel` |
| 影调 | `toneProvider(id)` | `ToneResult`（5段占比 + entropy + rmsContrast） | `ToneInfoCard` |
| 肤色 | `skinProvider(id)` | `SkinAnalysis`（hueOffset + saturation） | `SkinRadar` |
| 指纹 | `fingerprintProvider(id)` | `PhotoFingerprint`（96维直方图 + 7维标量） | `FingerprintRadar` |

> 重构时新 Widget 接收相同的数据模型类型，不改 Provider 和 Model。

---

## 十一、致命 Gotchas 速查（UI 重构相关）

> 项目 AGENTS.md 有完整 63 条 gotchas，以下是与本次重构直接相关的致命项。

| # | 内容 | 影响 |
|---|------|------|
| #26 | **详情页永远暗色** — 无论全局主题，详情页强制用 `DetailColors` 暗色 token，不随 `themeModeProvider` 切换 | 新 token 系统必须保留 `DetailColors` 独立体系 |
| #45 | **像素蒙层必须挂 InteractiveViewer 内部** — ClippingOverlay/SharpnessOverlay 表达照片像素属性，必须与 Image 共享缩放变换；构图线相反，挂外层 | 详情页 Stack 层级不可乱改 |
| #52 | **蒙层 letterbox 补偿** — `BoxFit.contain` 的图片是 letterboxed，蒙层必须按 imageAspect 计算「图片实际矩形」绘制，否则溢出到黑边 | 所有 overlay 重构时必须保留 letterbox 计算 |
| #56 | **FaceBBoxOverlay 仅在色彩卡片展开时显示** — `colorCardExpandedProvider` 按 photoId 作用域控制 | 详情页重构时必须保留此联动 |
| #58 | **DetailBottomPanel 固定高度** — 用 `AnimatedContainer(height: 368/72)` + `Expanded` 填充，不用 `maxHeight`，否则有黑框 | 拖拽面板重构时必须延续固定高度模式或平滑替代 |
| #59 | **顶部通知替代底部 SnackBar** — 详情页用 `_showTopNotice` 胶囊通知，不用 `ScaffoldMessenger.showSnackBar` | 不改回 SnackBar |
| #61 | **AnimatedOpacity 不能配条件渲染** — `AnimatedOpacity` 首次挂载不动画，必须常驻树用独立 bool 切 opacity | 所有 fade 动画必须遵守此模式 |
| #28 | **PhotoCard 回调直接传入，不外包 GestureDetector** — PhotoCard 内部 recognizer 会吞外部 tap | 瀑布流卡片重构时保留此模式 |
| #37 | **Async 错误兜底要 PlatformDispatcher.onError** — 纯 Dart 异步错误不被 `FlutterError.onError` 捕获 | main.dart 重构时必须保留双兜底 |

### Riverpod 3.x 约束（影响所有页面重构）

- **无 StateProvider / StateNotifierProvider** — 用 `Notifier` + `NotifierProvider`
- **StreamProvider.family 正常可用** — 瀑布流和分析 provider 都用这个
- **代码生成未使用** — 全部手写 provider，不引 `@riverpod` 注解
- **FutureProvider 级联失效** — 必须 `ref.watch(provider.future)` 建依赖，不能 `ref.read(dao)`

---

## 十二、Git 工作流与 CI 约束

### Git
- **新分支开发**：`git checkout -b feature/ui-refactor`，**绝不主动合并 main**
- 大版本编译前必经 reviewer 子代理复核

### CI 约束（Ubuntu 环境）
1. **build_runner 必须在 analyze 前跑** — `dart run build_runner build` → `dart analyze`（否则 .g.dart 缺失报错）
2. **analyze 连 info 也 exit 1** — 必须零 info 级别问题
3. **pubspec.lock 的 url 字段** — 本地用国内镜像会改 `pub.dev`→`pub.flutter-io.cn`，CI 用默认 pub.dev。提交前还原 lock 文件
4. **改序列化/enum 后必须 grep 测试硬编码断言** — 容易漏改

### CI 编译坑
- `tflite_flutter` 相关坑已随 v7.0 SCRFD 迁移下线，但根 `build.gradle.kts` 的 `allprojects { ... }` JVM 统一配置保留不要删
- APK 从 ~150MB 降到 ~30MB 是因为 `--release` 构建，不要改回 `--debug`

---

## 十三、浅色模式说明

暗色模式是核心场景（专业摄影工具惯例），浅色模式保持功能完整但视觉优先级低。
重构时先做暗色，确认暗色完美后再适配浅色。`DetailColors` 始终暗色（详情页场景刚需）。

---

*计划制定：萌萌 | 日期：2026-07-02 | v2.0 修订基于 reviewer 复核*
