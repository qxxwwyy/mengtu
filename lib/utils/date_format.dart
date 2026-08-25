// date_format.dart — 日期时间统一格式化（跨页一致，补零）
//
// 消除审计清单第五节「日期格式 3 种无补零」问题。
// 全 app 日期显示统一走这里，禁止页面内手写 '${dt.year}/${dt.month}/...'。
/// 日期：2026-08-25
String fmtDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
}

/// 日期时间：2026-08-25 14:30
String fmtDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${fmtDate(dt)} ${two(dt.hour)}:${two(dt.minute)}';
}

/// 相对时间：刚刚 / 5 分钟前 / 3 小时前 / 2 天前 / 更早退回 fmtDate
String fmtRelative(DateTime dt, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return fmtDate(dt);
}

/// 月日短格式：8月25日（列表卡片用）
String fmtMonthDay(DateTime dt) => '${dt.month}月${dt.day}日';
