import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo/models/task.dart';
import 'package:my_todo/utils/date_format.dart';

void main() {
  group('Task 过期判定', () {
    final DateTime dueDate = DateTime(2026, 7, 19, 14, 30);

    test('当前截止分钟不算过期，进入下一分钟后才算过期', () {
      final Task task = Task(title: '分钟规则', dueDate: dueDate);

      expect(task.isOverdueAt(DateTime(2026, 7, 19, 14, 30, 59)), isFalse);
      expect(task.isOverdueAt(DateTime(2026, 7, 19, 14, 31)), isTrue);
    });

    test('未到期、已完成或无截止时间的任务不算过期', () {
      final DateTime beforeDueDate = DateTime(2026, 7, 19, 14, 29);

      expect(
        Task(title: '未到期', dueDate: dueDate).isOverdueAt(beforeDueDate),
        isFalse,
      );
      expect(
        Task(
          title: '已完成',
          dueDate: dueDate,
          isDone: true,
        ).isOverdueAt(DateTime(2026, 7, 19, 14, 31)),
        isFalse,
      );
      expect(
        Task(title: '无日期').isOverdueAt(DateTime(2026, 7, 19, 14, 31)),
        isFalse,
      );
    });
  });

  group('Task 完成时间', () {
    test('completedAt 以 UTC ISO8601 序列化并能还原', () {
      final DateTime completedAt = DateTime(2026, 7, 20, 22, 15);
      final Task task = Task(
        title: '已完成',
        isDone: true,
        completedAt: completedAt,
      );

      final Map<String, dynamic> json = task.toJson();
      final Task restoredTask = Task.fromJson(json);

      expect(json['completedAtUtc'], completedAt.toUtc().toIso8601String());
      expect(restoredTask.completedAt, completedAt.toUtc());
      expect(restoredTask.completedAt!.isUtc, isTrue);
    });

    test('旧 JSON 没有 completedAtUtc 键时还原为 null', () {
      final Task legacyTask = Task.fromJson({
        'title': '旧任务',
        'isDone': true,
      });

      expect(legacyTask.completedAt, isNull);
    });

    test('未完成的任务即使带脏的完成时间也不采信', () {
      final Task dirtyTask = Task.fromJson({
        'title': '脏数据',
        'isDone': false,
        'completedAtUtc': '2026-07-20T14:00:00.000Z',
      });

      expect(dirtyTask.completedAt, isNull);
    });
  });

  test('日期格式统一显示到分钟', () {
    expect(formatDateTime(DateTime(2026, 7, 9, 4, 5)), '2026-07-09 04:05');
  });
}
