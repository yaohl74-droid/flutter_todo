import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/quote_model.dart';
import 'models/todo_model.dart';
import 'pages/todo_page.dart';
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
  });

  final TaskNotificationScheduler? notificationScheduler;
  final TodoModel? todoModel;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoModel>(
          create: (_) => (todoModel ?? TodoModel())..load(),
        ),
        ChangeNotifierProvider<QuoteModel>(
          create: (_) => QuoteModel()..refresh(),
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
          scaffoldBackgroundColor: const Color(0xFFF4F8F4),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFE5F1E7),
            foregroundColor: Color(0xFF294E32),
            elevation: 0,
          ),
        ),
        home: const TodoPage(),
      ),
    );
  }
}
