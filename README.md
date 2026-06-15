# 萌图 (Mengtu)

面向摄影爱好者的照片灵感收集与调色参考工具。

## 功能

- 📸 批量导入照片（SHA256 去重）
- 🖼️ 瀑布流浏览
- 📊 RGB / 亮度直方图（Rec.709 标准）
- 🎨 一键黑白（Rec.709 灰度矩阵）
- 🏷️ 标签管理与搜索

## 技术栈

- Flutter 3.x + Riverpod 3.x
- drift (SQLite ORM)
- image (Dart 图像处理)
- material_color_utilities (Google 官方色彩算法)
- wechat_assets_picker (微信风格图片选择)
- flutter_staggered_grid_view (瀑布流)

## 开发

```bash
flutter pub get
dart run build_runner build  # 代码生成（drift/riverpod）
flutter analyze
flutter test
```

> 所有编译打包通过 GitHub Actions 完成，不在本地执行 `flutter build`。
