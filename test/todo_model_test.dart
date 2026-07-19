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
    final int reminderRevision = model.reminderRevision;

    await model.purgeExpiredDeletedTasks();

    expect(model.deletedTasks, isEmpty);
    expect(model.reminderRevision, reminderRevision);
    model.dispose();
  });
}
