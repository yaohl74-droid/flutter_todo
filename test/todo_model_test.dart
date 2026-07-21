import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo/models/deleted_task.dart';
import 'package:my_todo/models/task.dart';
import 'package:my_todo/models/todo_model.dart';
import 'package:my_todo/services/task_storage.dart';

class _StubTaskStorage extends TaskStorage {
  _StubTaskStorage({this.snapshot, this.failSave = false});

  final TaskStorageSnapshot? snapshot;
  final bool failSave;

  @override
  Future<TaskStorageSnapshot> load({required List<Task> fallbackTasks}) async {
    return snapshot ??
        TaskStorageSnapshot(
          tasks: fallbackTasks,
          deletedTasks: const <DeletedTask>[],
          sortOrder: TaskSortOrder.dueDate.name,
          sortAscending: true,
        );
  }

  @override
  Future<void> save({
    List<Task>? tasks,
    List<DeletedTask>? deletedTasks,
    String? sortOrder,
    bool? sortAscending,
  }) async {
    if (failSave) {
      throw Exception('disk unavailable');
    }
  }
}

void main() {
  test('保存异常由 TodoModel 捕获并发布可重试的失败事件', () async {
    final TodoModel model = TodoModel(
      storage: _StubTaskStorage(failSave: true),
    );

    final bool added = await model.addTask(title: '不会静默失败');

    expect(added, isTrue);
    expect(model.persistenceFailure, isNotNull);
    expect(model.persistenceFailure!.action, '保存新增任务');
    final int firstFailureRevision = model.persistenceFailure!.revision;

    await model.retryPersistence();

    expect(model.persistenceFailure!.revision, firstFailureRevision + 1);
    expect(model.persistenceFailure!.action, '重新保存任务');
    model.dispose();
  });

  test('清理过期回收站不触发系统提醒重新对账', () async {
    final DeletedTask expiredTask = DeletedTask(
      task: Task(title: '过期回收站任务'),
      deletedAt: DateTime.now().subtract(const Duration(days: 8)),
      originalIndex: 0,
    );
    final TodoModel model = TodoModel(
      storage: _StubTaskStorage(
        snapshot: TaskStorageSnapshot(
          tasks: const <Task>[],
          deletedTasks: <DeletedTask>[expiredTask],
          sortOrder: TaskSortOrder.dueDate.name,
          sortAscending: true,
        ),
      ),
    );
    await model.load();
    final int taskRevision = model.taskRevision;

    await model.purgeExpiredDeletedTasks();

    expect(model.deletedTasks, isEmpty);
    expect(model.taskRevision, taskRevision);
    model.dispose();
  });

  group('完成时间与统计', () {
    TodoModel modelWithTasks(List<Task> tasks) {
      return TodoModel(
        storage: _StubTaskStorage(
          snapshot: TaskStorageSnapshot(
            tasks: tasks,
            deletedTasks: const <DeletedTask>[],
            sortOrder: TaskSortOrder.dueDate.name,
            sortAscending: true,
          ),
        ),
      );
    }

    test('勾选写入 UTC 完成时间，取消勾选清空', () async {
      final TodoModel model = modelWithTasks(<Task>[Task(title: '统计任务')]);
      await model.load();
      final Task task = model.tasks.single;
      expect(task.completedAt, isNull);

      await model.toggleTask(task, true);

      expect(model.tasks.single.completedAt, isNotNull);
      expect(model.tasks.single.completedAt!.isUtc, isTrue);

      await model.toggleTask(task, false);

      expect(model.tasks.single.completedAt, isNull);
      model.dispose();
    });

    test('完成率为已完成占活动任务比例，没有任务时为 0', () async {
      final TodoModel model = modelWithTasks(<Task>[
        Task(title: '完成一', isDone: true),
        Task(title: '完成二', isDone: true),
        Task(title: '未完一'),
        Task(title: '未完二'),
      ]);
      await model.load();

      expect(model.completionRate, 0.5);
      model.dispose();

      final TodoModel emptyModel = modelWithTasks(const <Task>[]);
      await emptyModel.load();

      expect(emptyModel.completionRate, 0.0);
      emptyModel.dispose();
    });

    test('趋势按本地自然日统计最近 7 天，更早和无完成时间的不计入', () async {
      final TodoModel model = modelWithTasks(<Task>[
        Task(
          title: '今天完成',
          isDone: true,
          completedAt: DateTime(2026, 7, 21, 8),
        ),
        Task(
          title: '昨晚完成',
          isDone: true,
          completedAt: DateTime(2026, 7, 20, 23),
        ),
        Task(
          title: '六天前完成之一',
          isDone: true,
          completedAt: DateTime(2026, 7, 15, 9),
        ),
        Task(
          title: '六天前完成之二',
          isDone: true,
          completedAt: DateTime(2026, 7, 15, 21),
        ),
        Task(
          title: '八天前完成',
          isDone: true,
          completedAt: DateTime(2026, 7, 13, 10),
        ),
        Task(title: '未完成'),
      ]);
      await model.load();

      final List<CompletionDay> trend = model.completionTrendAt(
        DateTime(2026, 7, 21, 10, 30),
      );

      expect(trend, hasLength(7));
      expect(trend.first.day, DateTime(2026, 7, 15));
      expect(trend.last.day, DateTime(2026, 7, 21));
      expect(trend.first.count, 2);
      expect(trend[5].count, 1);
      expect(trend.last.count, 1);
      expect(trend.fold<int>(0, (sum, day) => sum + day.count), 4);
      model.dispose();
    });

    test('完成时间正好落在窗口起止分钟时归属正确', () async {
      final TodoModel model = modelWithTasks(<Task>[
        Task(
          title: '窗口首日零点',
          isDone: true,
          completedAt: DateTime(2026, 7, 15, 0, 0),
        ),
        Task(
          title: '窗口前一天最后一分钟',
          isDone: true,
          completedAt: DateTime(2026, 7, 14, 23, 59),
        ),
      ]);
      await model.load();

      final List<CompletionDay> trend = model.completionTrendAt(
        DateTime(2026, 7, 21, 10, 30),
      );

      expect(trend.first.count, 1);
      expect(trend.fold<int>(0, (sum, day) => sum + day.count), 1);
      model.dispose();
    });

    test('UTC 存储的完成时间按设备本地时区归组到自然日', () async {
      // 本用例依赖运行环境为东八区（UTC+8）：本地凌晨 7/21 01:00 对应
      // UTC 7/20 17:00，UTC 日期比本地早一天。若 completionTrendAt 漏掉
      // .toLocal() 直接按 UTC 日期分桶，这条完成会被错归到 7/20（trend[5]），
      // 断言失败；只有转回本地日期才会正确落在 7/21（trend.last）。
      // 注意：在 UTC 或西半球时区下本地凌晨与 UTC 同属一天，本用例会退化
      // 为无效断言，测不出漏掉 toLocal() 的 bug。
      final TodoModel model = modelWithTasks(<Task>[
        Task(
          title: '凌晨完成',
          isDone: true,
          completedAt: DateTime(2026, 7, 21, 1),
        ),
      ]);
      await model.load();
      expect(model.tasks.single.completedAt!.isUtc, isTrue);

      final List<CompletionDay> trend = model.completionTrendAt(
        DateTime(2026, 7, 21, 22),
      );

      expect(trend.last.count, 1);
      expect(trend[5].count, 0);
      expect(trend.fold<int>(0, (sum, day) => sum + day.count), 1);
      model.dispose();
    });

    test('从回收站恢复已完成任务保留原完成时间', () async {
      final DateTime originalCompletedAt = DateTime(2026, 7, 19, 9);
      final TodoModel model = modelWithTasks(<Task>[
        Task(
          title: '完成后又删除',
          isDone: true,
          completedAt: originalCompletedAt,
        ),
      ]);
      await model.load();

      await model.deleteTask(model.tasks.single);
      expect(model.tasks, isEmpty);

      await model.restoreDeletedTask(model.deletedTasks.single);

      final Task restoredTask = model.tasks.single;
      expect(restoredTask.isDone, isTrue);
      expect(restoredTask.completedAt, originalCompletedAt.toUtc());
      model.dispose();
    });
  });
}
