import 'package:flutter/foundation.dart';

import '../services/task_storage.dart';
import 'deleted_task.dart';
import 'task.dart';

enum TaskSortOrder { added, dueDate, completion }

class TodoPersistenceFailure {
  const TodoPersistenceFailure({required this.revision, required this.action});

  final int revision;
  final String action;
}

/// 最近 7 天趋势中某一天的完成数量。
class CompletionDay {
  const CompletionDay({required this.day, required this.count});

  /// 本地时区的当天零点，仅作分桶键和展示用。
  final DateTime day;
  final int count;
}

/// 待办任务的业务状态：统一管理任务、回收站、排序和本地持久化。
class TodoModel extends ChangeNotifier {
  TodoModel({TaskStorage? storage}) : _storage = storage ?? TaskStorage();

  final TaskStorage _storage;
  final List<Task> _tasks = <Task>[
    Task(title: '买菜'),
    Task(title: '写代码'),
    Task(title: '跑步'),
  ];
  final List<DeletedTask> _deletedTasks = <DeletedTask>[];

  TaskSortOrder _sortOrder = TaskSortOrder.dueDate;
  bool _sortAscending = true;
  bool _isLoaded = false;
  bool _isDisposed = false;
  // 提醒对账版本号：仅活动任务集合或内容变化（加载/增/删/改/恢复）时递增；
  // 回收站清理只改变已删除列表，不影响提醒对账，因此不递增。
  int _taskRevision = 0;
  int _persistenceFailureRevision = 0;
  TodoPersistenceFailure? _persistenceFailure;
  Future<void>? _loadFuture;

  List<Task> get tasks => List<Task>.unmodifiable(_tasks);
  List<DeletedTask> get deletedTasks =>
      List<DeletedTask>.unmodifiable(_deletedTasks);
  TaskSortOrder get sortOrder => _sortOrder;
  bool get sortAscending => _sortAscending;
  bool get isLoaded => _isLoaded;

  /// 只有活动任务发生变化时才递增，供提醒服务判断是否需要重新对账。
  int get taskRevision => _taskRevision;
  TodoPersistenceFailure? get persistenceFailure => _persistenceFailure;

  int get completedCount => _tasks.where((task) => task.isDone).length;

  /// 活动任务的完成率；没有任务时为 0，避免除零。
  double get completionRate =>
      _tasks.isEmpty ? 0.0 : completedCount / _tasks.length;

  int get activeDeletedTaskCount {
    final DateTime cutoff = DateTime.now().subtract(TaskStorage.trashRetention);
    return _deletedTasks.where((item) => item.deletedAt.isAfter(cutoff)).length;
  }

  String get sortOrderLabel => switch (_sortOrder) {
    TaskSortOrder.added => '按添加顺序',
    TaskSortOrder.dueDate => '按截止日期',
    TaskSortOrder.completion => '按完成状态',
  };

  List<Task> get displayedTasks {
    final List<Task> result = List<Task>.of(_tasks);
    final Map<String, int> originalIndexes = <String, int>{
      for (int index = 0; index < _tasks.length; index++)
        _tasks[index].id: index,
    };

    result.sort((first, second) {
      int comparison;
      switch (_sortOrder) {
        case TaskSortOrder.added:
          comparison = originalIndexes[first.id]!.compareTo(
            originalIndexes[second.id]!,
          );
          break;
        case TaskSortOrder.dueDate:
          if (first.dueDate == null && second.dueDate == null) {
            comparison = 0;
          } else if (first.dueDate == null) {
            // 这两个 return 跳过下方的升降序翻转，让无日期任务始终排最后。
            return 1;
          } else if (second.dueDate == null) {
            return -1;
          } else {
            comparison = first.dueDate!.compareTo(second.dueDate!);
          }
          break;
        case TaskSortOrder.completion:
          comparison = (first.isDone ? 1 : 0).compareTo(second.isDone ? 1 : 0);
          break;
      }

      if (comparison != 0) {
        return _sortAscending ? comparison : -comparison;
      }
      return originalIndexes[first.id]!.compareTo(originalIndexes[second.id]!);
    });
    return result;
  }

  /// 最近 7 天（含今天）每天的完成数，供统计页展示；测试用 completionTrendAt。
  List<CompletionDay> get completionTrend =>
      completionTrendAt(DateTime.now());

  /// 以 now 所在的本地日为终点向前数 7 天，按本地自然日统计每天完成的任务数。
  /// completedAt 以 UTC 存储，归组时转回设备本地时区；没有完成时间的任务
  /// （未勾选或统计功能上线前已完成）不计入任何一天。
  List<CompletionDay> completionTrendAt(DateTime now) {
    final DateTime localNow = now.toLocal();
    final DateTime today = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
    );

    // 先按本地零点分桶，再取出最近 7 天；同一天多次完成分别计数。
    final Map<DateTime, int> countByDay = <DateTime, int>{};
    for (final Task task in _tasks) {
      final DateTime? completedAt = task.completedAt;
      if (completedAt == null) {
        continue;
      }
      final DateTime localCompleted = completedAt.toLocal();
      final DateTime dayKey = DateTime(
        localCompleted.year,
        localCompleted.month,
        localCompleted.day,
      );
      countByDay[dayKey] = (countByDay[dayKey] ?? 0) + 1;
    }

    final List<CompletionDay> result = <CompletionDay>[];
    // DateTime 构造函数会把溢出的日期规范化成上个月，跨月跨年都安全。
    for (int offset = 6; offset >= 0; offset--) {
      final DateTime day = DateTime(today.year, today.month, today.day - offset);
      result.add(CompletionDay(day: day, count: countByDay[day] ?? 0));
    }
    return result;
  }

  Future<void> load() => _loadFuture ??= _performLoad();

  Future<void> _performLoad() async {
    final TaskStorageSnapshot snapshot = await _storage.load(
      fallbackTasks: _tasks,
    );
    if (_isDisposed) {
      return;
    }

    _sortOrder = TaskSortOrder.values.firstWhere(
      (order) => order.name == snapshot.sortOrder,
      orElse: () => TaskSortOrder.dueDate,
    );
    _sortAscending = snapshot.sortAscending;
    if (snapshot.tasks != null) {
      _tasks
        ..clear()
        ..addAll(snapshot.tasks!);
    }
    _deletedTasks
      ..clear()
      ..addAll(snapshot.deletedTasks);
    _isLoaded = true;
    _taskRevision++;
    notifyListeners();
  }

  Future<bool> addTask({
    required String title,
    DateTime? dueDate,
    bool reminderEnabled = false,
  }) async {
    final String trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      return false;
    }
    final Task task = Task(
      title: trimmedTitle,
      dueDate: dueDate,
      reminderEnabled: reminderEnabled,
    );
    // 新增任务必然未完成，资格规则在此等价于“开启提醒且截止时间未过期”。
    task.reminderEnabled = task.isEligibleForReminder;
    _tasks.add(task);
    _taskRevision++;
    notifyListeners();
    await _persist('保存新增任务', () => _storage.save(tasks: _tasks));
    return true;
  }

  Future<void> toggleTask(Task task, bool? isDone) async {
    if (!_tasks.contains(task)) {
      return;
    }
    final bool nowDone = isDone ?? false;
    // 完成时间只记录“最后一次勾选完成”的时刻；取消完成时清空，不再计入趋势。
    // 状态没有真正翻转时不改动 completedAt，重复置为同一状态不会刷新完成时间。
    if (task.isDone != nowDone) {
      task.isDone = nowDone;
      task.completedAt = nowDone ? DateTime.now().toUtc() : null;
    }
    _taskRevision++;
    notifyListeners();
    await _persist('保存任务状态', () => _storage.save(tasks: _tasks));
  }

  Future<void> updateTask(
    Task task, {
    required String title,
    required DateTime? dueDate,
    required bool reminderEnabled,
  }) async {
    if (!_tasks.contains(task) || title.trim().isEmpty) {
      return;
    }
    task
      ..title = title.trim()
      ..dueDate = dueDate
      ..reminderEnabled = reminderEnabled;
    task.reminderEnabled = task.isEligibleForReminder;   // 用户编辑一个任务,把截止时间改成昨天,同时保持"开启提醒"——reminderEnabled 就会是 true 但已过期
    _taskRevision++;
    notifyListeners();
    await _persist('保存任务修改', () => _storage.save(tasks: _tasks));
  }

  Future<void> deleteTask(Task task) async {
    final int originalIndex = _tasks.indexOf(task);
    if (originalIndex == -1) {
      return;
    }
    _tasks.removeAt(originalIndex);
    _deletedTasks.add(
      DeletedTask(
        task: task,
        deletedAt: DateTime.now(),
        originalIndex: originalIndex,
      ),
    );
    _taskRevision++;
    notifyListeners();
    await _persist(
      '保存删除操作',
      () => _storage.save(tasks: _tasks, deletedTasks: _deletedTasks),
    );
  }

  Future<void> restoreDeletedTask(DeletedTask deletedTask) async {
    if (!_deletedTasks.remove(deletedTask)) {
      return;
    }
    final int restoredIndex = deletedTask.originalIndex > _tasks.length
        ? _tasks.length
        : deletedTask.originalIndex;
    _tasks.insert(restoredIndex, deletedTask.task);
    _taskRevision++;
    notifyListeners();
    await _persist(
      '保存恢复操作',
      () => _storage.save(tasks: _tasks, deletedTasks: _deletedTasks),
    );
  }

  Future<void> purgeExpiredDeletedTasks() async {
    final DateTime cutoff = DateTime.now().subtract(TaskStorage.trashRetention);
    final int previousLength = _deletedTasks.length;
    _deletedTasks.removeWhere((item) => !item.deletedAt.isAfter(cutoff));
    if (_deletedTasks.length == previousLength) {
      return;
    }
    // 这里只改变回收站，不影响活动任务和系统提醒，因此不递增 taskRevision。
    notifyListeners();
    await _persist('清理回收站', () => _storage.save(deletedTasks: _deletedTasks));
  }

  Future<void> setSortOrder(TaskSortOrder order) async {
    _sortOrder = order;
    notifyListeners();
    await _persist('保存排序方式', () => _storage.save(sortOrder: order.name));
  }

  Future<void> toggleSortDirection() async {
    _sortAscending = !_sortAscending;
    notifyListeners();
    await _persist(
      '保存排序方向',
      () => _storage.save(sortAscending: _sortAscending),
    );
  }

  /// 用户可从错误提示中重试，把当前完整状态重新写入本地存储。
  Future<void> retryPersistence() => _persist(
    '重新保存任务',
    () => _storage.save(
      tasks: _tasks,
      deletedTasks: _deletedTasks,
      sortOrder: _sortOrder.name,
      sortAscending: _sortAscending,
    ),
  );

  Future<void> _persist(String action, Future<void> Function() save) async {
    try {
      await save();
    } on Exception {
      // UI 回调通常不会 await Future，因此在模型内部统一截获并发布可展示的错误。
      _persistenceFailure = TodoPersistenceFailure(
        revision: ++_persistenceFailureRevision,
        action: action,
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
