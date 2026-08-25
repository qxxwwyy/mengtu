# 萌图体验全面升级（夜航）：小红书调研驱动的前端重做 + 功能增删

对萌图（Flutter 摄影师工作台，`feature/ui-refactor` 分支）做一轮全程自主的体验升级：先用已装好的 MediaCrawler 调研小红书后期调色的真实痛点与流行风格 → 以调研结论为输入重做前端（视觉 / 交互 / 动效 / 页面衔接，重点是示波器、直方图等专业图表的可视化与交互）→ 自主判断砍改鸡肋功能、补齐缺失功能。
完成标志速览：调研报告落地 `docs/`；最粗糙页面重做且全 app 空态/加载态/错误态/转场统一；核心图表可交互、有入场动效；功能增删附决策记录；`dart analyze` 0 issues、`flutter test` 全绿、push 后 CI 绿。

## 为什么做这件事

- 萌图是作者的练手项目，功能骨架完整（v8.0），但作者自评：**作为影像 app，示波器、直方图这类专业可视化"显示糟糕且缺乏交互"，整体缺乏动画、动效和页面衔接**；功能上既有鸡肋项也有缺口。
- 产品定位（v8.0 已确立，写在 AGENTS.md）：不做伪精确的相似度匹配，做**"样片解读"**——帮摄影爱好者看懂自己照片的影调/色彩/手法。所有产出向这个定位收敛：解读要跟用户的语言同频，而不是堆数值。
- 目标用户：摄影爱好者（非专业调色师），他们平时在小红书上看调色教程、追流行色调。调研他们的真实痛点和审美话术，让萌图的解读语言与他们同频。
- 成功之后的样子：打开萌图像走进一间专业暗房——图表既好看又可读可玩，每个功能都有存在的理由，页面之间衔接顺滑。

## 范围

交付物：

1. **调研报告** `docs/xhs-research-2026-08.md`：后期调色痛点清单（带笔记/评论证据）+ 流行风格趋势 + 对萌图的功能启示
2. **前端全面升级**（代码）：页面统一到设计系统；图表交互化与动效；空态/加载态/错误态/转场统一；token 清账（legacy 圆角、手调 alpha 链、手写 fontSize）
3. **功能增删**（代码 + `docs/feature-decisions.md` 决策记录）：砍什么、补什么由你全权判断，依据调研数据与代码分析
4. **测试与文档**：为新增交互补测试；AGENTS.md 同步本轮变更

留给后续（本轮不做）：Windows 适配、超 1000 张照片的性能压测、iOS——因为它们是独立战役，混进来会稀释本轮的体验主线。

## 资源与已核实事实

- **仓库**：`C:\Users\10492\Desktop\VibeCoding\mengtu`，分支 `feature/ui-refactor`（HEAD 0d42536 = origin，工作区干净）。**必读 `AGENTS.md`**——项目宪法：Riverpod 3.x 陷阱、65 条已踩坑记录（gotchas）、CI 规则、编码规范、数据库迁移规则。
- **`docs/ui-audit-2026-08.md`**（已核实，2026-08-25 全库勘察产出）：页面打磨梯度（settings/plan_detail/compare 最粗糙）、详情页生态问题清单、15 条跨页不一致、死代码清单、图表交互现状。升级工作的靶子，先读它。
- **设计系统**：`lib/theme/app_theme.dart` 单一入口（AppColors/DetailColors/StatusColors/ChartColors + AppTypography + Spacing/Radii + Durations/Curves2）。token 齐备但页面层消化不足——本轮的核心工作之一就是清账。复用组件已存在：`widgets/common/empty_state.dart`、`animated_number.dart`、`page_transitions.dart`、`widgets/charts/chart_animations.dart`（ChartEnterBuilder，头部注释"图表必须有入场动画"是本项目图表动效规范）。
- **图表数据源**：`lib/providers/analysis_provider.dart`（histogram/tone/palette/skin/advancedMetrics/imageScope/detectedFace 等 10 个 provider）。
- **小红书调研工具（已装好、已登录、已验证可抓取，2026-08-25）**：
  - 位置 `C:\Users\10492\Desktop\VibeCoding\xhs-tools\MediaCrawler`（独立 venv；它在 mengtu 仓库之外，不是本项目代码）
  - 换关键词：编辑 `config/base_config.py` 的 `KEYWORDS = "关键词1,关键词2"`（英文逗号分隔）
  - 运行：`.venv/Scripts/python.exe main.py --platform xhs --lt qrcode --type search`（工作目录必须在 MediaCrawler 根目录）
  - 登录态已持久化于 `browser_data/cdp_xhs_user_data_dir/`，正常复跑**不会**再弹二维码（用系统 Edge CDP 模式启动，会弹浏览器窗口，属正常）
  - 输出：`data/xhs/jsonl/search_contents_*.jsonl`（笔记：标题/描述/点赞/收藏/评论数）+ `search_comments_*.jsonl`（评论），按日期命名追加写
  - 规模约束：`CRAWLER_MAX_NOTES_COUNT` 默认 15（最多调到 20），`CRAWLER_MAX_SLEEP_SEC` 保持 ≥2，整个任务总抓取 ≤200 篇（该工具为非商业学习许可 + 平台风控考虑）
  - 若登录态失效（日志出现 `Login state result: False` 且两次 120 秒二维码超时）：无人值守无法扫码，改用 WebSearch 检索小红书/摄影社区公开内容兜底，并在调研报告显著标注数据源降级
- **环境事实**：Flutter SDK 在 `C:\Users\10492\flutter-sdk`，用 `C:\Users\10492\flutter-sdk\bin\dart.bat analyze` 与 `flutter.bat test`；本地**绝不** `flutter build`（打包由 CI 负责）；本地 pub 镜像会污染 `pubspec.lock` 的 url 字段，每次提交前 `git checkout -- pubspec.lock` 还原。

## 验收标准（完成即停）

1. **调研报告真实落地**：`docs/xhs-research-2026-08.md` 存在；覆盖 ≥8 个关键词且每个关键词在 `data/xhs/jsonl/` 有对应产出；痛点清单每条附 ≥2 条笔记/评论证据；流行风格 ≥5 种且描述具体到可指导实现（色调倾向/影调特征/常见参数话术）；结尾有「功能启示 → 萌图落地情况」对照表。
2. **图表交互与动效**（行为级）：
   - 直方图：手指按在直方图上时能读到所指亮度区间的信息（如该区间占比/RGB 分量），松手消失；
   - 示波器（skin_radar）：模式切换有过渡动画；支持至少一种主动交互（如长按查询点位 Cb/Cr 值，或缩放平移像素云）；
   - 对比页三图表有入场动画；
   - 全部核心图表（直方图/示波器/参照直方图/色轮/对比页图表）有入场动画，无静态突现。
3. **最粗糙三页重做**：`docs/ui-audit-2026-08.md` 第三节"最粗糙"梯队的 settings_page / plan_detail_page / compare_page 重做后零硬编码颜色与字号（全部 token 化）、空态/加载态/错误态齐全。
4. **一致性清账**：审计文档第五节 15 条跨页不一致中，除在决策记录里写明理由保留的以外全部消除；第六节死代码全部删除。
5. **功能增删**：`docs/feature-decisions.md` 存在，每项砍/补附依据（调研数据或代码分析）；被砍功能的入口/路由/数据路径清理干净无死链；其对应测试同步移除并在决策记录中列明。
6. **质量门**：`dart.bat analyze` 0 issues；`flutter.bat test` 全绿（新增交互有对应测试；既有测试除随功能砍除外不得删改断言）。
7. **CI**：全部工作 push 到 feature 分支（建议从 `feature/ui-refactor` 新开，如 `feature/experience-overhaul`），GitHub Actions 全绿。
8. **文档同步**：AGENTS.md 反映本轮变更（已完成清单、新 gotchas、schemaVersion 若有变化）。

- 部分完成的交接标准：做不到的验收项在 `docs/night-run/PROGRESS.md` 逐条标注缺口与原因，以最高完成度状态交付，不因个别项卡住整体。
- 对捷径的要求：验收以真实功能为准，不得通过删改既有测试断言、硬编码预期输出、把未做的事写成已完成等方式通过。

## 边界与升级

- **禁区**（有理由，仅这几条）：
  - 绝不 push 或 merge `main`（作者的 CI 与发布纪律，AGENTS.md 明令）；
  - 绝不删除/重置 `browser_data/`（小红书登录态，无人值守下无法重建）;
  - 绝不给 app 引入联网能力或依赖（纯本地是产品底线：无 INTERNET 权限）；
  - 用户数据（Photos/Albums 等表）不做破坏性变更，schema 演进走 drift 正规 migration + schemaVersion 递增；
  - MediaCrawler 控制在小规模（总量 ≤200 篇、间隔 ≥2s、每关键词 ≤20 篇）。
- **你可以自行决定**：技术选型（纯本地约束内）、文件组织、实现顺序、UI 设计细节、砍什么补什么（全权，附决策记录即可）、feature 分支命名、是否拆分 detail_page 等大文件。
- **记录并降级继续**（过夜无人可问，原则：不停下来等，记录后降级）：小红书登录态失效 → WebSearch 兜底；CI 连续 3 次同一原因红 → 记录并绕开；网络/磁盘异常 → 重试超 30 分钟无改善则收尾交接；AGENTS.md 与代码大面积矛盾 → 以代码为准并写入交接报告。
- **唯一硬停条件**：任务前提被证伪（如仓库被锁无法提交）——写完交接报告再停。

## 自举记忆（先建后干）

开工第一件事建立 `docs/night-run/`：`PLAN.md`（你自拟的里程碑与验收对照表）、`PROGRESS.md`（进度与发现，每个里程碑更新）、`DECISIONS.md`（功能增删等关键决策及依据）。达到"任何时刻中断，新会话凭这三个文件 + AGENTS.md 即可无损恢复"的标准。每完成一个里程碑、以及上下文被压缩后：重读本简报的验收标准与边界，对照自查再前进。每个里程碑收尾时仓库处于可交接状态（analyze 通过、测试绿、有 commit）。

## 收尾复述

一句话：以小红书调研为输入，把萌图前端（视觉/交互/动效/图表/页面衔接）升级到专业暗房水准，全权砍改鸡肋功能、补齐缺口，过夜自主执行、里程碑 commit+push 由 CI 验证。完成即停：验收 1-8 全过（做不到的按部分交接标准标注缺口）。禁区：不碰 main、不删 browser_data、不加联网、用户数据无破坏性迁移、爬取 ≤200 篇。执行顺序与实现方式由你决定。
