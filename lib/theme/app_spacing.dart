// app_spacing.dart — 萌图间距 + 圆角 Token
//
// 8pt grid 间距系统 + 5 档圆角语义。
// 所有 Widget 应引用这些 token，禁止散落 EdgeInsets.all(12) / BorderRadius.circular(8)。
import 'package:flutter/material.dart';

/// 间距常量（8pt grid）
///
/// 用法：
/// - `Spacing.sm` → EdgeInsets.all(Spacing.sm)
/// - `Spacing.hMd(Spacing.lg)` → EdgeInsets.symmetric(horizontal: 16)
/// - `Spacing.vSm` → EdgeInsets.symmetric(vertical: 8)
class Spacing {
  Spacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  // ── 便捷 EdgeInsets 工厂 ──

  /// EdgeInsets.all(value)
  static EdgeInsets all(double value) => EdgeInsets.all(value);

  /// EdgeInsets.symmetric(horizontal: value)
  static EdgeInsets h(double value) =>
      EdgeInsets.symmetric(horizontal: value);

  /// EdgeInsets.symmetric(vertical: value)
  static EdgeInsets v(double value) =>
      EdgeInsets.symmetric(vertical: value);

  /// EdgeInsets.symmetric(horizontal: h, vertical: v)
  static EdgeInsets hv(double h, double v) =>
      EdgeInsets.symmetric(horizontal: h, vertical: v);

  /// EdgeInsets.only(left: value)
  static EdgeInsets left(double value) => EdgeInsets.only(left: value);

  /// EdgeInsets.only(right: value)
  static EdgeInsets right(double value) => EdgeInsets.only(right: value);

  /// EdgeInsets.only(top: value)
  static EdgeInsets top(double value) => EdgeInsets.only(top: value);

  /// EdgeInsets.only(bottom: value)
  static EdgeInsets bottom(double value) => EdgeInsets.only(bottom: value);
}

/// 圆角 Token
///
/// 用法：`Radii.sm` / `Radii.md` / `Radii.lg` 等。
/// 对应 `BorderRadius.circular(Radii.md)` 或直接 `Radii.mdBorder`。
class Radii {
  Radii._();

  // ── 圆角值 ──

  /// chip、小按钮
  static const xs = 4.0;

  /// chip、小按钮
  static const sm = 6.0;

  /// 卡片、列表项
  static const md = 10.0;

  /// 大卡片、面板
  static const lg = 16.0;

  /// 弹窗、BottomSheet
  static const xl = 24.0;

  /// 胶囊按钮、badge
  static const pill = 999.0;

  // ── BorderRadius 工厂 ──

  static const xsBorder = BorderRadius.all(Radius.circular(xs));
  static const smBorder = BorderRadius.all(Radius.circular(sm));
  static const mdBorder = BorderRadius.all(Radius.circular(md));
  static const lgBorder = BorderRadius.all(Radius.circular(lg));
  static const xlBorder = BorderRadius.all(Radius.circular(xl));
  static const pillBorder = BorderRadius.all(Radius.circular(pill));
}
