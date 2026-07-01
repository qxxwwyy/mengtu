// main.dart — 萌图应用入口
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'pages/main_shell.dart';

import 'providers/database_provider.dart';
import 'providers/theme_provider.dart';
import 'services/builtin_profiles.dart';
import 'services/scrfd_service.dart' show disposeScrfdDetector;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 全局错误兜底：防止 widget build 异常时显示红屏，显示友好错误页。
  // 包一层 Directionality：若错误发生在 MaterialApp 之上，
  // Text 仍能正确渲染（否则会抛 "No Directionality widget found"）。
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.white38),
                const SizedBox(height: 16),
                const Text('应用遇到错误',
                    style: TextStyle(fontSize: 16, color: Colors.white70)),
                const SizedBox(height: 8),
                Text(
                  details.exception.toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  // 捕获 Flutter 框架错误（build/layout/paint）
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };

  // 捕获 Flutter 框架之外的异步错误（Isolate 抛出、未 await 的 Future 等）。
  // FlutterError.onError 只覆盖框架内部，纯 Dart 异步错误会落到这里。
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('未捕获的异步错误: $error\n$stack');
    return true; // true = 已处理，不向上重新抛出
  };

  // v7.0：app 退出时释放 SCRFD (NCNN) 检测器单例（避免 native 内存泄漏）。
  // detached = app 完全退出，此时 destroy NCNN Interpreter。
  final binding = WidgetsBinding.instance;
  binding.addObserver(_AppLifecycleObserver());

  // v3.5 PR5：启动时插入内置理论档案（幂等，已存在不重复插入）
  // 失败不阻塞启动（DB 初始化失败等极端情况降级，档案管理页为空）
  final container = ProviderContainer();
  try {
    final db = container.read(appDatabaseProvider);
    await BuiltinProfiles.ensureSeeded(db);
  } catch (e) {
    debugPrint('内置档案初始化失败（不阻塞启动）: $e');
  }

  runApp(UncontrolledProviderScope(container: container, child: const MengtuApp()));
}

/// v7.0：监听 app 生命周期，detached 时释放 SCRFD 检测器单例
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      disposeScrfdDetector();
    }
  }
}

class MengtuApp extends ConsumerWidget {
  const MengtuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: '萌图',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      home: const MainShell(),
    );
  }
}

