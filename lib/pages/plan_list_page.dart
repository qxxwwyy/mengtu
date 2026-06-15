// plan_list_page.dart — 策划列表页（Phase 1 占位，Phase 2 实现完整策划功能）
import 'package:flutter/material.dart';

class PlanListPage extends StatelessWidget {
  const PlanListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('策划',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: theme.colorScheme.primary)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_outlined,
                  size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text('拍摄策划功能即将上线',
                  style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 8),
              Text(
                '提前规划主题、风格、器材清单、shot list\n让每次拍摄都有备而来',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
