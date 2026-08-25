# 夜航计划：萌图体验全面升级（2026-08-25 启动）

> 任务简报见 `docs/night-run-brief.md`。本文件是里程碑与验收对照表，PROGRESS.md 记进度，DECISIONS.md 记决策。
> 恢复会话时读顺序：AGENTS.md → 本文件 → PROGRESS.md → DECISIONS.md → docs/ui-audit-2026-08.md。

## 分支

`feature/experience-overhaul`（从 feature/ui-refactor @ 0d42536 新开）。绝不 push/merge main。

## 里程碑与验收对照

| 里程碑 | 内容 | 对应验收 | 状态 |
|---|---|---|---|
| M0 自举 | night-run 三件套建立；新分支创建；初始 commit | 前置 | 完成 |
| M1 小红书调研 | 批跑 7 个新关键词（日系调色/港风调色/胶片感调色/青橙调色/电影感调色/肤色调整/直方图，每词 ≤20 篇）+ 已有 2 词（调色/达芬奇调色）= 9 词；分析产出 `docs/xhs-research-2026-08.md` | 验收1 | 进行中 |
| M2 图表交互与动效 | 直方图触摸读数（按住显示区间占比/RGB 分量）；示波器模式切换过渡动画 + 长按查询 Cb/Cr；全部核心图表入场动画（直方图/示波器/参照直方图/色轮/对比页） | 验收2 | 未开始 |
| M3 最粗糙三页重做 | settings_page / plan_detail_page / compare_page：全 token 化（零硬编码颜色字号）+ 空态/加载态/错误态齐全 | 验收3 | 未开始 |
| M4 一致性清账 + 死代码 | ui-audit 第五节 15 条跨页不一致清账（保留项写入决策记录）；第六节死代码删除 | 验收4 | 未开始 |
| M5 功能增删 | 依据调研 + 代码分析砍/补功能；`docs/feature-decisions.md` 每项附依据；清理入口/路由/数据路径与对应测试 | 验收5 | 未开始 |
| M6 质量门 + CI | dart analyze 0 issues；flutter test 全绿（新增交互有测试）；push 分支 CI 绿 | 验收6/7 | 未开始 |
| M7 文档同步 | AGENTS.md 同步（已完成清单/gotchas/schemaVersion） | 验收8 | 未开始 |

## 抓取预算（硬约束）

- 已有（验证跑）：39 篇（关键词：调色、达芬奇调色）
- 本轮批跑：7 词 × ≤20 篇 = ≤140 篇
- 总计 ≤179 篇 ≤ 200 上限。CRAWLER_MAX_SLEEP_SEC=2 不动。
- 登录态失效（Login state result: False 两次 120s 超时）→ 停止批跑，WebSearch 兜底并在报告标注降级。

## 里程碑收尾纪律

每个里程碑结束：analyze 通过 + 测试绿 + commit（中文范围前缀）。上下文被压缩后：重读简报验收标准与边界再前进。
