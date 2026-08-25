# 夜航决策记录

> 功能增删、方案取舍、保留不一致的理由都记在这里。每项附依据（调研数据或代码分析）。
> 功能增删详见 `docs/feature-decisions.md`（B/C/R 编号体系），此处记录工程与清账决策。

## D1 分支策略（2026-08-25）

从 `feature/ui-refactor` @ 0d42536 新开 `feature/experience-overhaul`。依据：简报建议 + AGENTS.md 分支纪律（绝不主动 merge main）。

## D2 调研关键词组合（2026-08-25）

已有 2 词（调色、达芬奇调色）+ 新批 7 词（日系调色/港风调色/胶片感调色/青橙调色/电影感调色/肤色调整/直方图）= 9 词 ≥8 验收线。
取舍：不做「Lightroom教程」（与泛「调色」痛点重叠），保留「直方图」（萌图核心可视化，需了解爱好者对直方图的认知语言）。
抓取量：39 + 7×20 = 179 ≤200 上限，留余量防重跑超限。

## D3 histogram_chart.dart 死代码 → InteractiveHistogram（M2）

审计列为死代码孤儿，但它的抽象（ChartEnterBuilder + HistogramPainter 封装）方向正确。决策：不保留文件，将其职责并入新建 `interactive_histogram.dart`（入场动画 + 触摸读数），原文件删除。

## D4 网格间距保留两种（audit 第 9 条）

瀑布流（masonry）6px / 网格（reorder/九宫格/选择页）4px。两种场景视觉密度需求不同（大图浏览 vs 缩略图矩阵），统一反而损害可读性。其余间距随机差异已消除。

## D5 相册封面 Hero 链保留断裂（audit 第 5 条残余）

照片级 Hero 链已通（PhotoCard ↔ DetailPage 双端 `photo_${id}` tag）。相册封面→相册详情无 Hero：详情页没有大封面图位作为 Hero 接收端，强行添加会出现"封面飞进九宫格"的怪异动画。等相册详情有封面头图设计时再补。

## D6 图表 painter 内标注字号保留（audit 第 14 条残余）

histogram_painter 五区标签（8px）/ color_wheel 刻度（8px）等 TextPainter 标注保留裸字号：图表内标注是数据可视化细节（随图表密度调整），不参与全局文字排版层级，AppTypography 已提供 chartAnnotation(9) 供 widget 层使用。

## D7 示波器呼吸动画（Durations.pulse）不接入

audit 提到 pulse token 闲置。决策：不接入 —— 无限循环动画需要常驻 AnimationController 重绘（4096 bins 像素云每帧重画），电量代价大于视觉收益；且与长按查询游标的交互语义冲突（呼吸光点 + 查询十字线并存会混乱）。token 保留供未来非 painter 场景。

## D8 sqlite3 native hook 镜像修复（环境，非代码）

本机无法直连 github.com，sqlite3-3.3.3 build hook 下载 Windows DLL 超时 → flutter test 全挂。修复：pub cache 的 description.dart 下载 URL 临时改走 ghfast.top 镜像（仅本机 pub cache，CI 不受影响）。DLL 落盘后 hooks_runner 缓存生效，后续不再需要网络。若换机/清缓存重现，按同法处理。

## D9 detail_page 深度拆分不做（本轮）

audit 建议"是否拆分 detail_page 等大文件"由我决定。1133 行 God widget 的拆分风险（取色状态机 + GlobalKey 约束 gotcha #29 + 坐标系 gotcha #57）大于收益，本轮已零散 token 化（字号/圆角/颜色），结构性拆分留给后续专门战役。

