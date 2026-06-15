// main.dart — 萌图应用入口
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';

void main() {
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
