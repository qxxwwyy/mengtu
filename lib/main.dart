// main.dart — 萌图应用入口
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';

void main() {
  // 全局错误兜底：防止 widget build 异常时显示红屏，显示友好错误页
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
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
    );
  };

  // 捕获 Dart 异步错误（避免未处理异常导致崩溃）
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };

  runApp(const ProviderScope(child: MengtuApp()));
}

class MengtuApp extends StatelessWidget {
  const MengtuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '萌图',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark, // 暗色优先（摄影工具气质，不支持浅色）
      home: const HomePage(),
    );
  }
}
