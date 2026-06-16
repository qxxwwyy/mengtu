// app_info.dart — 应用版本等常量（单一数据源）
//
// 版本号必须与 pubspec.yaml 的 version 字段保持一致。
// 当前 1.2.0+1（versionName=1.2.0，buildNumber=1）。
// 各页面（设置/我的/关于）统一引用此处，避免硬编码版本号不一致。

/// 应用版本显示标签（与 pubspec.yaml version 对齐）
const String appVersionLabel = '萌图 Mengtu v1.2.0';

/// 纯版本号（用于 PackageInfo 比对等场景）
const String appVersion = '1.2.0';
