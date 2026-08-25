# 夜航进度

## 状态：M3 进行中（三页重做）；M1 数据已齐待写报告；M2 已完成 commit 5e686f9

## 里程碑记录

### M0 自举（2026-08-25）✅
- night-run 三件套 + 分支 feature/experience-overhaul + 初始 commit 851d384

### M1 小红书调研
- [x] 批跑 7 关键词完成：日系/港风/胶片感/青橙/电影感/肤色调整/直方图，每词 20 篇 + 评论
- [x] 数据总量：9 关键词 179 篇笔记 + ~1500 条评论（≤200 上限内）
- [ ] 分析 jsonl → 痛点清单（每条 ≥2 证据）+ 流行风格 ≥5 种
- [ ] 写 docs/xhs-research-2026-08.md（含「功能启示 → 萌图落地情况」对照表）

### M2 图表交互与动效 ✅（commit 5e686f9）
- [x] InteractiveHistogram 触摸读数（亮度/五区/占比/RGB 分量，Listener raw pointer）
- [x] 示波器模式切换 crossfade + 长按查询 Cb/Cr/色相名 + 入场生长动画
- [x] 参照直方图两段式入场 + token 化；色轮已有入场
- [x] 数据仪表盘接入；全量 364 测试绿 + analyze 0 issues
- 注：compare_page 三图表入场动画并入 M3 重做（一页一趟改完）

### M3 三页重做（进行中）
- [ ] settings_page：token 化 + 存储 FutureBuilder 加 loading 态（消除假数据 0张/0B）
- [ ] plan_detail_page：Material Icons 替代 emoji、字号 token、删除红色、实拍照片可点击放大
- [ ] compare_page：token 化（Colors.white12/24/54 清除）+ 三图表入场动画 + 色卡可读性

## 发现与关键事实

- **本地 sqlite3 native hook 修复**（环境问题，非代码问题）：本机无法直连 github.com，sqlite3-3.3.3 的 build hook 下载 sqlite3.x64.windows.dll 超时导致 flutter test 全挂。修复：pub cache 的 description.dart 下载 URL 临时改走 ghfast.top 镜像（本地 hack，CI 不受影响），成功一次后 hooks_runner 缓存生效。若以后缓存失效重现此问题，重跑一次即可重新缓存。
- jsonl 记录含 `source_keyword` 字段，关键词归因精确。
- 已有高赞内容如「为什么你调色越来越脏？」(8.7万赞)。
- ui-audit 确认的死代码：sharpness_guide_card 整文件 / ClippingStatusBar / ~~histogram_chart.dart（已被 InteractiveHistogram 承接并删除）~~ / onExpandChanged 死参数。

## 缺口交接（部分完成时填）

- 无（进行中）。
