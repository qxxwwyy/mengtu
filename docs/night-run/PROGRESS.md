# 夜航进度

## 状态：全部里程碑完成，push 重试中（网络阻塞，见缺口①）

| 里程碑 | 状态 | commit |
|---|---|---|
| M0 自举 | ✅ | 851d384 |
| M1 小红书调研 | ✅ | 193c2c9 |
| M2 图表交互与动效 | ✅ | 5e686f9 |
| M3 三页重做 | ✅ | cbcc27b |
| M4 一致性清账 + 死代码 | ✅ | 9af1c10 + e4b37b5 |
| M5 功能增删 | ✅ | b254250 |
| M6 质量门 | analyze 0 issues ✅ / test 378 全绿 ✅ / push ⏳ | 见下 |
| M7 AGENTS.md 同步 | ✅ | 4b7eeed |

## 验收对照（简报 1-8）

1. **调研报告** ✅ `docs/xhs-research-2026-08.md`：9 关键词（≥8）× 每词 20 篇 = 179 篇全部有产出；痛点 12 条每条 ≥2 证据；风格 8 种（≥5）带参数话术；功能启示→落地对照表 10 条已回填。
2. **图表交互与动效** ✅ 直方图按住读数（亮度/五区/占比/RGB 分量，松手消失）；示波器模式切换 crossfade + 长按查询 Cb/Cr/色相名；全部核心图表有入场动画（直方图生长/示波器从中心生长/参照两段式/色轮已有/对比页三图表 stagger）。
3. **三页重做** ✅ settings/plan_detail/compare 零硬编码颜色字号（token 全覆盖）+ 空态/加载态/错误态齐全（async_views 统一组件）。
4. **一致性清账** ✅ 15 条中 13 条消除，2 条有理由保留（网格间距两种场景 D4、相册封面 Hero 无接收端 D5，见 DECISIONS.md）；死代码 4 项全删。
5. **功能增删** ✅ `docs/feature-decisions.md`：补 5 项（B1 通透度诊断/B2 风格参照库/B3 词典文案/B4 直方图读数/B5 肤色人话）+ 砍改 3 项（C1 置信度伪精确/C2 默认展开/C3 电影感判定），全部附调研/代码依据；被改功能无死链（harmony_card 保留组件只改显示）。
6. **质量门** ✅ `dart analyze` 0 issues；`flutter test` 378 用例全绿（新增交互测试：interactive_histogram widget 4 + histogram_probe unit 6 + vectorscope_probe unit 8 + insight_service unit 14）；无删改既有断言（仅 2 处文案升级同步断言措辞：冷偏移→偏粉气、暖偏移→偏黄气）。
7. **CI** ⏳ push 被网络阻塞（git 代理 127.0.0.1:7897 无进程监听 + 直连被 reset）。后台重试循环已挂（每 5 分钟 × 2 小时）。push 成功后 CI 自动触发。
8. **文档同步** ✅ AGENTS.md v8.1：已完成清单条目 + gotcha #66/#67/#68 + 项目结构树。

## 缺口交接

- **① push/CI（验收 7）**：本机 git 配置代理 127.0.0.1:7897（clash 系），代理软件未运行，直连 github.com 被 reset。全部 8 个 commit 已在本地 feature/experience-overhaul。后台脚本 /tmp/xhs-run/push-retry.sh 每 5 分钟重试（2 小时窗口）。**恢复方式**：启动代理软件后手动 `git push -u origin feature/experience-overhaul`，或等脚本自动成功。本地质量门（analyze/test）已全绿，CI 预期绿（无平台特定改动；sqlite3 hook 的本地镜像 hack 只在本机 pub cache，CI 用原生下载路径）。
- 无其他缺口。

## 环境事件记录（对后续会话有用）

- **sqlite3 native hook**：本机下载 github DLL 超时 → pub cache description.dart 镜像 hack（D8）。DLL 已缓存，后续测试正常。
- **批量正则改 Dart 的坑**：Windows 路径反斜杠让 `'/pages/' in path` 判断失效；const 上下文 copyWith 报错需同步剥 const（gotcha #68 已入库）。
