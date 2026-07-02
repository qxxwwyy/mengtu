// app_animations.dart — 萌图动效 Token
//
// 统一的动效语言：duration + curve + 8 种场景预设。
// 核心原则：图表必须有入场动画。静止的图表是死的，动画的图表是活的。
import 'package:flutter/animation.dart';

/// 动效 Duration Token
class Durations {
  Durations._();

  /// 按压反馈
  static const press = Duration(milliseconds: 100);

  /// 列表项入场
  static const itemEnter = Duration(milliseconds: 200);

  /// 卡片展开
  static const expand = Duration(milliseconds: 280);

  /// 图表切换 morph
  static const chartSwitch = Duration(milliseconds: 250);

  /// 页面转场
  static const pageTransition = Duration(milliseconds: 300);

  /// 图表入场
  static const chartEnter = Duration(milliseconds: 500);

  /// 弹性空状态
  static const bounceEnter = Duration(milliseconds: 500);

  /// 肤色光点呼吸脉动
  static const pulse = Duration(milliseconds: 800);
}

/// 动效 Curve Token
class Curves2 {
  Curves2._();

  /// 按压反馈（快速减速）
  static const press = Curves.easeOut;

  /// 卡片展开（进出都平滑）
  static const expand = Curves.easeInOutCubic;

  /// 图表入场（从 0 增长到目标值）
  static const chartEnter = Curves.easeOutCubic;

  /// 弹性出现（空状态）
  static const bounce = Curves.easeOutBack;

  /// 页面转场
  static const pageTransition = Curves.easeInOut;
}

/// 动效场景预设（duration + curve 打包）
class AppAnimations {
  AppAnimations._();

  /// 按压反馈：scale 0.97 + 轻微暗化
  static const pressDuration = Durations.press;
  static const pressCurve = Curves2.press;

  /// 卡片展开：高度+透明度+位移三合一
  static const expandDuration = Durations.expand;
  static const expandCurve = Curves2.expand;

  /// 页面转场：共享元素过渡（照片→详情）
  static const pageTransitionDuration = Durations.pageTransition;
  static const pageTransitionCurve = Curves2.pageTransition;

  /// 图表入场：数据从 0 增长到目标值
  static const chartEnterDuration = Durations.chartEnter;
  static const chartEnterCurve = Curves2.chartEnter;

  /// 图表切换：模式切换时 morph
  static const chartSwitchDuration = Durations.chartSwitch;
  static const chartSwitchCurve = Curves.easeInOut;

  /// 空状态出现：轻微弹性
  static const bounceEnterDuration = Durations.bounceEnter;
  static const bounceEnterCurve = Curves2.bounce;

  /// 列表项入场：依次淡入+上移
  static const itemEnterDuration = Durations.itemEnter;
  static const itemEnterCurve = Curves2.press;

  /// 肤色光点呼吸脉动（opacity 0.7→1.0 循环）
  static const pulseDuration = Durations.pulse;
}
