# 萌图 性能复核报告

> 复核时间：2026-06-18
> 范围：全项目，重点关注应用性能（启动、列表滚动、大图分析、取色、导入、内存）

## 复核结论

项目整体性能工程做得扎实：所有 CPU 密集任务（哈希/缩略图/直方图/色卡/影调/锐度/人脸/取色/EXIF）都在 Isolate 中执行；分析结果有 DB 缓存；瀑布流用 `cacheExtent` + `AutomaticKeepAliveClientMixin` + `cacheWidth` 限制；v3.1 已修复取色卡顿（会话级解码）。下面的问题按"修复收益/风险"分级。

---

## P0 — 高优先级（实测可感知卡顿）

### P0-1 `PhotoCard.build()` 每帧同步 `File.existsSync()` —— 瀑布流滚动卡顿元凶
**位置**：`lib/widgets/photo_card.dart:49`
```dart
final thumbExists = thumbPath.isNotEmpty && File(thumbPath).existsSync();
```
**问题**：`existsSync()` 是阻塞系统调用（Windows 上一次 ~1–5ms，冷盘更慢）。`PhotoCard` 在瀑布流里**每张卡每次 rebuild** 都执行一次。1000 张照片滚动时，每帧可能有数十个 card 同时 build（cacheExtent=500 + 屏外预生成），累计几十~上百 ms 的同步 I/O 抖动，直接表现为滚动掉帧。
**建议**：
- 缩略图存在性是稳定属性，不应每帧查盘。在 `initState` 异步查一次 `exists()`，缓存到 state；或更简单——直接信任 `thumbnailPath` 非空即存在，解码失败由 `Image.file` 的 `errorBuilder` 兜底（已经实现了兜底，`existsSync` 是多余的）。
- 真正的"清缓存后 thumbnailPath='' 已是空串"，`thumbPath.isNotEmpty` 判断已足够；文件意外丢失是极小概率事件，交给 `errorBuilder` 即可。

### P0-2 `watchAlbumsWithTagInfo` 仍有 N+1 查询（聚合宣称消除但实际没消除）
**位置**：`lib/services/database/daos/album_dao.dart:225-241`
```dart
for (final album in albumList) {
  final tags = await _getTagsForAlbumInline(album.id);   // 每相册一次 query
  final photoCount = await getPhotoCount(album.id);       // 每相册一次 query
  ...
}
```
**问题**：注释说"消除相册列表 N+1 查询"，但实现里每个相册仍跑 2 次独立 query（标签 + 计数）。10 个相册 = 20 次串行 await，叠加 broadcast signal 的 tick 重算，相册列表打开有明显延迟。且任一表变化触发**全量重算**（无增量）。
**建议**：用 2 个 `GROUP BY` 聚合 query 一次拉全量：
- `SELECT album_id, COUNT(*) FROM album_photos GROUP BY album_id` → 计数 map
- `SELECT at.album_id, t.* FROM album_tags at JOIN tags t ... ` → 标签 map
然后在内存里 join。从 2N+1 次 query 降到 4 次（albums + 2 聚合 + 变更信号）。

### P0-3 `updatePhotosSortOrder` 拖拽排序逐行 UPDATE
**位置**：`lib/services/database/daos/album_dao.dart:174-186`
```dart
for (int i = 0; i < orderedPhotoIds.length; i++) {
  await (update(albumPhotos)...).write(...);  // 每张照片一次 UPDATE
}
```
**问题**：相册内拖动一次触发 N 次 UPDATE（N=相册照片数，最多 1000）。每次 UPDATE 是独立事务往返，用户拖完有明显"卡一下"。`HapticFeedback.mediumImpact()` 在 await 之前调用还好，但整个事务时间随照片数线性增长。
**建议**：只更新受影响区间（oldIndex 到 newIndex 之间的 sortOrder 批量 ±1），而非全量重写。极端情况下用 `CASE WHEN` 单语句批量更新。1000 张照片拖一格，从 1000 次 UPDATE 降到 ~几十次。

---

## P1 — 中优先级（内存 / 潜在抖动）

### P1-1 `ColorPickerSession` 持有全分辨率 ARGB 像素（大图内存峰值高）
**位置**：`lib/services/pixel_picker_service.dart:157-176`
```dart
final pixels = Uint8List(w * h * 4);  // 4MP 图 ≈ 16MB，12MP ≈ 48MB
```
**问题**：进入取色模式时一次性把全图转成 ARGB `Uint8List` 常驻主线程内存。手机上 12MP 照片 = 48MB 纯像素缓冲 + 已解码的 `img.Image`（在 Isolate 内，GC 后释放，但传输瞬间双倍）。低端机（4GB RAM）叠加系统相册可能 OOM。
**决策：不改**。复核后判断风险/收益不划算：
- `test/unit/pixel_picker_session_test.dart` 强约束 `pick(x,y)` 必须返回与 `img.getPixel(x,y)` 逐像素一致的值。
- `detail_page.dart:127-130` 直接用 `photo.width/height` 作 session 维度，传递全分辨率像素坐标。
- 若降采样需同时改 session API、测试、详情页坐标映射三处，且破坏"取色即真实像素"的语义保证。
- 实际 OOM 风险低：取色是用户主动开启的低频模式，48MB 是峰值而非稳态；现代手机 RAM 充足。
保留原实现，仅在此记录"若未来报告低端机 OOM，优先改这一项"。

### P1-2 ~~`clipping` 复用直方图 bin~~（复核后撤销：需要空间坐标）
原设想：`clippingProvider` 复用直方图 bin 0/255 的计数，省一次解码。
**撤销原因**：`ClippingOverlay` 需要在图上画 **空间坐标点**（`darkPoints`/`brightPoints`
是归一化的 (x,y) 像素位置），直方图 bin 只能给"多少像素溢出"，给不出"在哪里"。
所以 clipping 必须独立解码全图。此项不改。

### P1-3 `face_service._analyzeRoiSkin` 与 `_computeBgStats` 遍历全图两次
**位置**：`lib/services/face_service.dart:184-207`（ROI）和 `259-313`（背景）
**问题**：肤色 ROI 遍历 face bbox 内像素，背景统计**再遍历一次全图**（排除 ROI）。同一张图被扫两遍。`getPixel(x,y)` 在 image 包里是相对慢的调用（每次创建 Pixel 对象）。
**建议**：合并成一次遍历——遍历全图，命中 ROI 累加肤色统计，否则累加背景统计。同时 `getPixel` 换成 `image.getPixel(x, y)` 复用局部变量（face_service 已经在循环里 3 次调用 `getPixel` 取 r/g/b，应一次取出）。

### P1-4 `PhotoCard` 用 `AutomaticKeepAliveClientMixin` 保活所有瀑布流 card
**位置**：`lib/widgets/photo_card.dart:30-35`
**问题**：`wantKeepAlive => true` 让所有 card 永不销毁。1000 张照片全部 keep-alive = 1000 个 Image 缓存在内存（虽然 Flutter ImageCache 有上限 100MB/1000 条，但保活的 widget state 仍占内存）。`cacheExtent=500` 本身已经预渲染屏外内容，再加全量 keepAlive 是双重保活。
**建议**：移除 `AutomaticKeepAliveClientMixin`，依赖 `cacheExtent` 即可。Image 解码缓存由 `ImageCache` 全局管理，card 重建时不会重新解码（命中缓存）。如果担心滚动回来闪烁，`gaplessPlayback: true`（已设置）+ `ImageCache` 已足够。

---

## P2 — 低优先级（代码健康度 / 微优化）

### P2-1 `home_page` 按文件名搜索后内存 `photos.reversed.toList()` 拷贝
**位置**：`lib/pages/home_page.dart:416-418`
```dart
final sorted = sortOrder == SortOrder.oldest ? photos.reversed.toList() : photos;
```
问题很小（1000 个对象引用 ~8KB），但每次 rebuild 都拷贝。可在 DAO 层按 sortOrder 排序，省掉 UI 层拷贝。低优先级。

### P2-2 `_AlbumCard` 在 build() 里 `db.albumDao.getCoverPhoto(...)` 用 FutureBuilder
**位置**：`lib/pages/album_page.dart:484-488`
聚合分支每个卡片仍单独查封面（`getCoverPhoto` 每卡片一次 query）。和 P0-2 同源——聚合查询应把封面 photoId 一起带出来。修了 P0-2 这项自然解决。

### P2-3 `HistogramPainter._drawHueHistogram` 每 bin 创建一个 `Paint`
**位置**：`lib/widgets/histogram_painter.dart:144-145`
```dart
final color = HSLColor.fromAHSL(...).toColor();
canvas.drawRect(..., Paint()..color = color);
```
360 个 bin = 360 个 Paint 对象/frame。CustomPainter 每次 repaint 都创建。改成预生成 360 色的 `static final List<Paint>` 或用 `drawPath` 合并。色相模式不是默认模式，低频，但改起来简单。

### P2-4 详情页 `_buildImageViewer` 每帧 `MediaQuery.of(context).size.width * 3`
**位置**：`lib/pages/detail_page.dart:291-292`
每次 rebuild 算一次 cacheWidth，值不变。可在 initState 算一次缓存。微优化。

---

## 已做得好的（不要动）

1. ✅ 所有 CPU 密集任务在 `compute()` Isolate 中，不阻塞 UI
2. ✅ 直方图/色卡/影调有 DB 缓存，二次打开即时
3. ✅ `toneProvider` 复用直方图亮度数据（不重读图）
4. ✅ `ColorPickerSession` v3.1 会话级解码（取色拖动 <1ms）
5. ✅ `Image.file` 用 `cacheWidth` 限制解码尺寸防 OOM
6. ✅ `searchQueryProvider` 200ms debounce
7. ✅ `_mergeTableSignals` broadcast 流正确管理订阅生命周期
8. ✅ 取色 30fps 节流（`_lastPickAt`）
9. ✅ drift `NativeDatabase.createInBackground`（DB 在独立 Isolate）

---

## 修复计划（按优先级实施）

| 编号 | 修复项 | 风险 | 预期收益 | 状态 |
|------|--------|------|----------|------|
| P0-1 | 移除 PhotoCard.existsSync，依赖 errorBuilder 兜底 | 低 | 滚动掉帧明显改善 | ✅ 已修 |
| P0-2 | album 聚合用 GROUP BY 消除 N+1 | 中（改 SQL） | 相册列表打开加速 | ✅ 已修 |
| P0-3 | 拖拽排序用单条 `customUpdate` + CASE WHEN | 中 | 大相册拖拽不卡 | ✅ 已修 |
| P1-1 | ColorPickerSession 降采样 | — | — | ⏭️ 跳过（破坏像素精度语义+测试，收益/风险不划算） |
| P1-2 | clipping 复用直方图 bin | — | — | ⏭️ 撤销（clipping 需空间坐标点，bin 给不出位置） |
| P1-3 | face_service 合并 ROI+背景遍历 + getPixel 合并 | 低 | 人脸分析提速 ~2x | ✅ 已修 |
| P1-4 | 移除 PhotoCard keepAlive | 低 | 大图库内存降低 | ✅ 已修（随 P0-1） |
| P2-3 | Hue Paint 预生成 | 低 | 色相直方图渲染微提速 | ✅ 已修 |

### 关键技术细节

**P0-3 响应式保留**：拖拽排序的 `customUpdate` 必须传 `updates: {albumPhotos}` + `updateKind: UpdateKind.update`，否则 drift 不会失效 `albumPhotos` 表，`watchPhotosInAlbum` 流不重算，网格不会重排。原误用 `customStatement`（不失效）会引入响应性 bug。

**P0-3 参数上限**：SQLite `SQLITE_MAX_VARIABLE_NUMBER` 默认 999。CASE 的每个 WHEN 用 2 个绑定参数，单语句上限 ~450 项。超过回退逐条事务（保持响应式 + 正确性）。相册照片 ≤1000，极端大相册（>450 张）走回退路径。

**P1-3 语义等价**：合并遍历严格保留原"内缩环（ROI bbox 与内缩 ROI 之间）既不计入肤色也不计入背景"的分类。bbox 外 → 背景；bbox 内但内缩 ROI 外 → 跳过；内缩 ROI 内 → 肤色（带色相/饱和度过滤）。数值输出与原双遍历实现完全一致。

---

## 已跳过项的复核依据

### P1-1 ColorPickerSession（跳过）
`test/unit/pixel_picker_session_test.dart` 断言 `pick(x,y)` 必须返回与 `img.getPixel(x,y)` 逐像素一致的值，且 `detail_page.dart` 用 `photo.width/height` 作 session 维度直接传全分辨率坐标。降采样需同时改三处 + 破坏"取色即真实像素"语义。实际内存峰值 48MB（12MP）是用户主动开启取色时才出现的瞬态值，非稳态，现代手机 RAM 充足。**若未来报告低端机 OOM，优先改这一项。**

### P1-2 clipping 复用直方图（撤销）
复核后发现 `ClippingOverlay` 要在图上画 **空间坐标点**（`darkPoints`/`brightPoints` 是归一化的像素位置），直方图 bin 只能回答"多少像素溢出"，给不出"在哪里溢出"。clipping 必须独立解码全图取坐标。原设想错误。
