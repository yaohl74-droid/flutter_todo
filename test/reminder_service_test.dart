import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo/models/deleted_task.dart';
import 'package:my_todo/models/task.dart';
import 'package:my_todo/models/todo_model.dart';
import 'package:my_todo/services/reminder_service.dart';
import 'package:my_todo/services/task_notification_service.dart';
import 'package:my_todo/services/task_storage.dart';

class _MemoryTaskStorage extends TaskStorage {
  _MemoryTaskStorage(this.initialTasks);

  final List<Task> initialTasks;

  @override
  Future<TaskStorageSnapshot> load({required List<Task> fallbackTasks}) async {
    return TaskStorageSnapshot(
      tasks: initialTasks,
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
  }) async {}
}

class _FakeNotificationScheduler implements TaskNotificationScheduler {
  int reconcileCount = 0;
  Set<String> scheduledTaskIds = <String>{};

  @override
  bool get isAvailable => true;

  @override
  Future<String?> initialize({
    required TaskNotificationTapCallback onTaskSelected,
  }) async => null;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> reconcile(List<Task> tasks) async {
    reconcileCount++;
    scheduledTaskIds = tasks.map((task) => task.id).toSet();
  }

  @override
  Future<bool> requestPermissions() async => true;
}

Future<void> _flushAsyncWork() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('任务删除后对账结果不再包含对应提醒', () async {
    final Task task = Task(
      title: '待删除提醒',
      dueDate: DateTime.now().add(const Duration(hours: 1)),
      reminderEnabled: true,
    );
    final TodoModel model = TodoModel(
      storage: _MemoryTaskStorage(<Task>[task]),
    );
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler();
    final ReminderService service = ReminderService(
      todoModel: model,
      scheduler: scheduler,
    );
    await service.initialize(onTaskSelected: (_) {});
    expect(scheduler.scheduledTaskIds, contains(task.id));

    await model.deleteTask(task);
    await _flushAsyncWork();

    expect(scheduler.scheduledTaskIds, isNot(contains(task.id)));
    service.dispose();
    model.dispose();
  });

  test('taskRevision 未变化时不重复对账', () async {
    final TodoModel model = TodoModel(storage: _MemoryTaskStorage(<Task>[]));
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler();
    final ReminderService service = ReminderService(
      todoModel: model,
      scheduler: scheduler,
    );
    await service.initialize(onTaskSelected: (_) {});
    final int reconcileCount = scheduler.reconcileCount;

    await model.setSortOrder(TaskSortOrder.completion);
    await _flushAsyncWork();

    expect(scheduler.reconcileCount, reconcileCount);
    service.dispose();
    model.dispose();
  });

  test('dispose 后不再响应任务变化', () async {
    final Task task = Task(title: '释放后的任务');
    final TodoModel model = TodoModel(
      storage: _MemoryTaskStorage(<Task>[task]),
    );
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler();
    final ReminderService service = ReminderService(
      todoModel: model,
      scheduler: scheduler,
    );
    await service.initialize(onTaskSelected: (_) {});
    final int reconcileCount = scheduler.reconcileCount;
    service.dispose();

    await model.deleteTask(task);
    await _flushAsyncWork();

    expect(scheduler.reconcileCount, reconcileCount);
    model.dispose();
  });
}
