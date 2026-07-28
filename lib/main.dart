import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/todo_model.dart';
import 'pages/todo_page.dart';
import 'services/cloud_settings.dart';
import 'services/reminder_service.dart';
import 'services/task_notification_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.notificationScheduler,
    this.todoModel,
    this.cloudSettingsStore,
    this.cloudTaskResolver,
  });

  final TaskNotificationScheduler? notificationScheduler;
  final TodoModel? todoModel;
  final CloudSettingsStore? cloudSettingsStore;
  final CloudTaskResolver? cloudTaskResolver;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoModel>(
          create: (_) => (todoModel ?? TodoModel())..load(),
        ),
        Provider<ReminderService>(
          create: (context) => ReminderService(
            todoModel: context.read<TodoModel>(),
            scheduler: notificationScheduler ?? TaskNotificationService(),
          ),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp(
        title: '我的待办',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          // 用低饱和度绿色作为种子色，生成统一、柔和的 Material 配色。
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6F9D7A)),
          // 统一使用打包的思源黑体 CN 子集字体：Flutter Web 默认字体中文字形
          // 不全，“趋”“佚”这类字会显示成豆腐块；其余平台同样走该字体，
          // 保证各端渲染一致。
          fontFamily: 'SourceHanSansCN',
          scaffoldBackgroundColor: const Color(0xFFF4F8F4),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFE5F1E7),
            foregroundColor: Color(0xFF294E32),
            elevation: 0,
          ),
        ),
        home: TodoPage(
          cloudSettingsStore: cloudSettingsStore,
          cloudTaskResolver: cloudTaskResolver,
        ),
      ),
    );
  }
}
