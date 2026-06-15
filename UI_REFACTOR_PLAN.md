# UI 重构计划 — v1.0.0 Polish

> 设计方向：暗房美学（Darkroom Aesthetic）
> 配色：深炭灰 + 琥珀点缀 + 柔光表面
> 参考：Lightroom Mobile、VSCO、Apple Photos 的暗色模式

## 设计 Token 系统

### 配色（暗色优先）
| Token | 值 | 用途 |
|---|---|---|
| bgBase | `#0F0F0F` | 最底层背景 |
| bgSurface | `#1A1A1A` | 卡片/面板表面 |
| bgElevated | `#242424` | 提升层（Dialog/Sheet） |
| accent | `#E8A838` | 琥珀色主点缀（暗房安全灯） |
| accentDim | `#8C6818` | 琥珀色弱化（边框/底色） |
| textPrimary | `#E8E8E8` | 主文字 |
| textSecondary | `#9A9A9A` | 次文字 |
| textMuted | `#6A6A6A` | 弱化文字 |

### 浅色模式
| Token | 值 |
|---|---|
| bgBase | `#FAFAFA` |
| bgSurface | `#FFFFFF` |
| bgElevated | `#F5F5F5` |
| accent | `#C8881C` |
| textPrimary | `#1A1A1A` |
| textSecondary | `#666666` |

## 改动清单

### 1. 主题系统 `lib/theme/app_theme.dart`（新建）
- 定义 `AppColors` 静态类（暗/亮两套配色）
- `buildDarkTheme()` / `buildLightTheme()` 工厂函数
- 自定义 AppBar、Card、Chip 的默认样式
- 配色基于琥珀 accent 而非 M3 紫

### 2. `main.dart`
- 替换紫色 seed → 自定义 Theme
- 默认 `darkMode`（摄影 App 暗色优先）

### 3. `photo_card.dart` 瀑布流卡片
- 添加 Shimmer 骨架屏加载占位（Image 加载期间）
- 点击缩放动画（`AnimatedScale` + tap down/up）
- 阴影 + 更大圆角(12px)

### 4. `home_page.dart` 首页
- 半透明 AppBar（`flexibleSpace` 渐变）
- 空状态：大号琥珀色图标 + 引导文案 + 暗示性 CTA
- 导入进度：线性 `LinearProgressIndicator` + 百分比文字
- FAB 用琥珀色

### 5. `detail_page.dart` 详情页
- `Hero` 动画连接瀑布流→详情页
- 顶部工具栏毛玻璃效果（`BackdropFilter`）
- 标签 Chip 更精致（半透明 + 细边框）

### 6. `analysis_panel.dart` 分析面板
- 面板顶栏更精致（拖拽提示条 + 暗色表面）
- Tab 指示器用琥珀色

### 7. `color_card.dart` 色卡
- 算法 ChoiceChip 和 Slider 用琥珀色选中态

### 8. `tone_info_card.dart` 影调卡
- 统计格子改用暗色 surface，数值用琥珀色高亮

### 9. `settings_page.dart` 设置页
- 版本号用琥珀色
- 清理缓存按钮加确认 loading 态

### 10. `tone_info_card.dart` / `photo_card.dart` 统一
- 去掉所有 `Colors.grey.shadeXXX` 硬编码 → 用 `AppColors.textSecondary` 等

## 不改动的部分
- 数据层（DAO/database/provider 逻辑）
- 算法（MMCQ/K-Means/histogram）
- 业务流程（导入/搜索/删除逻辑）
- CI/CD 配置

## 验收标准
- `dart analyze` 0 issues
- `flutter test` 全绿
- 深色模式为默认，浅色模式可用
- 无 `Colors.grey.shadeXXX` 硬编码（统一走 AppColors）
- CI 构建通过
