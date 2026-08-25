# 萌图 UI 现状审计（2026-08，feature/ui-refactor 分支 @ 0d42536）

> 本文档是长程体验升级任务的起点输入之一，由 2026-08-25 的全库探索产出。
> 事实基于当次代码勘察，执行时以实际代码为准（可能已变动）。

## 一、全局现状一句话

分支上已有 5-Phase UI 重构（设计系统 token 化 → 三图表暗房美学 → 详情页改造 → 全局打磨 → 动效系统），但火力集中在 detail_page 生态 + profile + main_shell；11 个页面里 8 个几乎未被触碰，页面间存在系统性不一致。

## 二、设计系统（lib/theme/，单一入口 app_theme.dart）

- 颜色 4 套：`AppColors`（全局暗色 5 层背景+琥珀 accent 0xFFE8A838+文字 4 级+浅色 light* 前缀）/ `DetailColors`（详情页独立暗色，不随主题）/ `StatusColors`（语义）/ `ChartColors`（图表通道色/五区色/示波器色）
- `AppTypography`：9 级文字 + dataXl/dataMd/mono 数据字体 —— **页面层几乎零采用**，全是手写 TextStyle
- `Spacing`（8pt：xs4~xxl32 + EdgeInsets 工厂）/ `Radii`（xs4~pill999；`legacy8/12/16` 标注"Phase 4 后清理"仍在 6+ 文件）
- 动效：`Durations`（press100/itemEnter200/expand280/chartSwitch250/pageTransition300/chartEnter500/pulse800）/ `Curves2` / `AppAnimations` 8 场景预设
- 复用组件：`widgets/common/animated_number.dart`（数字滚动）、`widgets/common/page_transitions.dart`（detailPageRoute fade+slide+Hero）、`widgets/common/empty_state.dart`（空状态，**仅 home 在用**）、`widgets/charts/chart_animations.dart`（ChartEnterBuilder/chartEnterScale/pulseOpacity，规范注释"图表必须有入场动画"）

## 三、页面打磨梯度（从粗到细）

| 梯度 | 页面 | 核心问题 |
|---|---|---|
| 最粗糙（重构未触达） | **settings_page** | 唯一零 token 页面（不 import theme）；存储区 FutureBuilder 无 loading 直接显示假数据"0 张/0 B" |
| | **plan_detail_page** | emoji 当图标（📍📅）、10 处硬编码字号、删除按钮无红色、实拍照片九宫格不可点击放大 |
| | **compare_page** | 残留 Colors.white12/24/54、图表零入场动画（违背自家规范）、色卡百分比固定白字浅色块上不可读、ChartColors.channelR/B 被挪用作左右图例色 |
| 粗糙 | tag_manage_page | 空状态一行灰字（全 app 最简陋）；每个 chip 一次 FutureBuilder DB 查询 |
| | plan_edit_page | 无 Form/输入校验；日期范围写死 2020~2030；shot/gear 行与表单区视觉割裂 |
| | album_detail_page | 728 行大杂烩；_showTagPicker ~150 行嵌套 StatefulBuilder；两种网格间距不一致（masonry 6/6+6 vs reorder 4/4+8） |
| 中等 | plan_list_page | 无任何动画/haptic；错误态连 $e 都没有；卡片层级全靠 alpha 0.4/0.5/0.6 微调 |
| | album_page | 空状态手写未用 EmptyState；加载态与 home 不一致；编辑/删除入口只有长按 |
| | home_page | 骨架屏与 masonry 不同构（加载完成跳变）；AppBar 无 blur 与底部导航不一致；SnackBar duration:Duration(days:1) hack；错误态裸文本 |
| 已打磨 | profile_page | Phase 4 数据卡（渐变+AnimatedNumber）；唯一 Spacing/AppTypography 全量使用页 |
| | main_shell | Phase 4 blur 导航栏 + haptic 最好 |
| 精品参照 | detail_page + grading + charts | Phase 2/3/5 火力集中区 |

## 四、详情页生态（核心战场）

- **detail_page.dart（1133 行）God widget**：~18 个状态字段、取色状态机 + 4 个弹窗 + 顶栏 + 黑白滑块混杂；build 内副作用（_prefetchPickerSession）；字体/间距 token 采用率全生态最低；取色放大镜 Positioned 无边界 clamp（图片顶部取色会溢出）
- **skin_radar.dart（661 行）**：单文件塞 widget+painter+legend+computeCloudPoints 纯函数+自写 _hsvToRgb；魔法数密集（127.5/0.75/1.15/135/alpha 0.08~0.85）；Colors.black 硬编码 1 处；`Durations.pulse/pulseOpacity` 呼吸 token 已定义但肤色光点未接入
- **raw_data_dashboard.dart（462 行）**：4 段几乎相同的复制粘贴 GridView.count；错误态三套写法（红字/静默 shrink/原始 $e）；ColorCard/HarmonyCard 各带 SingleChildScrollView 嵌套进外层 ListView
- **color_card.dart / harmony_card.dart**：依赖 `Theme.of(context).colorScheme` —— **浅色主题会泄漏进详情页**（违反 gotcha #26"详情页永远暗色"）；color_card 用 Material Card 与自绘容器混搭、复制成功用 SnackBar（详情页规范是顶部通知）
- **detail_bottom_panel.dart**：高度魔法数 80/368 跨 3 文件注释互相矛盾（368=8+60+300 vs 308−把手 262）；forceCollapsed 时 grab handle 直接消失导致布局跳变
- **grading_panel.dart**：注释宣称"watch advancedMetricsProvider 一次传各卡片"，实际只传了 StageTonalCard，阶②③④各自再 watch（阶④一次 4 个）
- **stage_insight_card.dart**：注释"默认展开"与 `_expanded=false` 直接矛盾；每次 build 实例化 InsightService().generate()
- **reference_histogram.dart**：无入场动画（HistogramPainter 的 progress 能力闲置）；参照色 Color(0x80FFFFFF) 硬编码

## 五、跨页面不一致清单

1. 空状态 4 种做法（EmptyState 组件 vs 手写 icon64+text ×3组不同字号 vs 一行灰字 vs 没有）
2. 加载态 4 种（骨架屏/居中转圈/行内转圈/height:100 转圈；settings 存储区无 loading 显假数据）
3. 错误态 5 种文案（`错误: $e` / `加载失败: $e` / `加载失败` / `$label: 加载失败` / 裸"策划不存在"）
4. AppBar 标题两阵营（home/profile/plan_list 重复手写 w600/20 vs 其余默认）
5. 转场：detailPageRoute 仅 3 处（home/album_detail×2），其余 ~10 处裸 MaterialPageRoute；**相册列表→详情 Hero 链断裂**
6. Radii.legacy8/12/16 未清账（home/album/plan_list/plan_edit/plan_detail/detail_page）
7. 删除确认：home/album/tag_manage 红色 vs plan_detail/plan_edit 无红
8. 按压缩放参数漂移：PhotoCard 0.96/120ms vs _AlbumCard 0.97/120ms vs token pressDuration 100ms
9. 网格间距 4 种（home 6/6+6 / reorder 4/4+8 / 九宫格 4/4+0 / 选择页 4/4+4）
10. haptic 覆盖率极低：仅 main_shell + album_detail 拖拽 + 工具行 + color_card
11. emoji vs Material Icons（plan_detail）
12. 日期格式 3 种无补零无本地化
13. `onSurface.withValues(alpha:0.3~0.6)` 手调透明度链 50+ 处；textSecondary/textMuted token 基本无人用
14. 字体硬编码 fontSize 9~28 遍布全 app；fontFamily:'monospace' 手写 7 处不用 AppTypography.mono
15. letterbox 图片矩形计算函数复制 4 份（clipping/composition/sharpness/face_bbox）+ detail_page 第 5 种

## 六、死代码清单（可安全删除）

- `widgets/sharpness_guide_card.dart` 整文件（被 stage_isolation_card 的 InterpretationRow 替代，_SharpnessRow 与其 90% 重复）
- `widgets/clipping_overlay.dart` 的 ClippingStatusBar 类（无引用）
- `widgets/charts/histogram_chart.dart`（无引用孤儿组件）
- detail_page 的 `onExpandChanged` 死参数

## 七、图表交互现状（用户核心痛点）

- histogram_painter：7 模式静态绘制，progress 入场参数存在但闲置；无任何触摸交互
- skin_radar 示波器：像素云+六色框+肤色线静态显示；_ModeToggle 切换无过渡动画；无缩放/查询交互
- reference_histogram：当前 vs 参照叠放静态
- color_wheel：唯一接了 ChartEnterBuilder 入场的图表
- compare_page 三图表全静态
- 动效规范注释（chart_animations.dart 头部）："图表必须有入场动画" —— 大部分图表未遵守

## 八、数据层速查（UI 消费入口）

- analysis_provider.dart（10 个 provider）：histogram/tone/palette/skin/advancedMetrics/imageScope/detectedFace + colorCardExpandedProvider/manualSkinSelectionProvider/scopeModeProvider
- StreamProvider（drift watch）驱动列表自动刷新；FutureProvider.family 按 photoId 计算含缓存回写
- 详情页交互状态三种机制并存：页面 setState（8 模式开关）/ 全局 Notifier（3 个）/ ValueNotifier（取色高频）
