// page_transitions.dart — 自定义页面转场路由
//
// fade + slide 过渡（300ms easeInOut），配合 Hero 共享元素动画。
import 'package:flutter/material.dart';
import '../../theme/app_animations.dart';

/// 详情页转场路由（fade + slide + Hero）
///
/// 用法：
/// ```dart
/// Navigator.push(context, detailPageRoute(DetailPage(photoId: id)));
/// ```
Route<T> detailPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: AppAnimations.pageTransitionCurve,
          )),
          child: child,
        ),
      );
    },
    transitionDuration: AppAnimations.pageTransitionDuration,
    reverseTransitionDuration: AppAnimations.pageTransitionDuration,
  );
}
