import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo/models/task.dart';
import 'package:my_todo/services/task_notification_service.dart';

void main() {
  group('TaskNotificationService.eligibleTasks', () {
    final DateTime now = DateTime.utc(2026, 7, 19, 4);

    test('只保留未来、未完成且已开启提醒的任务', () {
      final List<Task> result = TaskNotificationService.eligibleTasks([
        Task(
          title: '有效提醒',
          dueDate: now.add(const Duration(hours: 2)),
          reminderEnabled: true,
        ),
        Task(title: '未开启提醒', dueDate: now.add(const Duration(hours: 1))),
        Task(
          title: '已经完成',
          dueDate: now.add(const Duration(hours: 1)),
          reminderEnabled: true,
          isDone: true,
        ),
        Task(
          title: '已经过期',
          dueDate: now.subtract(const Duration(minutes: 1)),
          reminderEnabled: true,
        ),
        Task(title: '没有日期', reminderEnabled: true),
      ], now: now);

      expect(result.map((task) => task.title), ['有效提醒']);
    });

    test('按到期时间选择最近 64 条', () {
      final List<Task> tasks = List<Task>.generate(
        70,
        (index) => Task(
          title: '任务 $index',
          dueDate: now.add(Duration(minutes: 70 - index)),
          reminderEnabled: true,
        ),
      );

      final List<Task> result = TaskNotificationService.eligibleTasks(
        tasks,
        now: now,
        limit: TaskNotificationService.applePendingLimit,
      );

      expect(result, hasLength(64));
      expect(result.first.title, '任务 69');
      expect(result.last.title, '任务 6');
    });
  });
}
