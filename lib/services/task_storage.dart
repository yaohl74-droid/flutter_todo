import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/deleted_task.dart';
import '../models/task.dart';

class TaskStorageSnapshot {
  const TaskStorageSnapshot({
    required this.tasks,
    required this.deletedTasks,
    required this.sortOrder,
    required this.sortAscending,
  });

  // null 表示存档缺失或损坏，页面继续保留内存中的示例任务。
  final List<Task>? tasks;
  final List<DeletedTask> deletedTasks;
  final String? sortOrder;
  final bool sortAscending;
}

class TaskStorage {
  static const String _tasksStorageKey = 'tasks';
  static const String _sortOrderStorageKey = 'task_sort_order';
  static const String _sortAscendingStorageKey = 'task_sort_ascending';
  static const String _deletedTasksStorageKey = 'deleted_tasks';
  static const Duration trashRetention = Duration(days: 7);

  Future<TaskStorageSnapshot> load({required List<Task> fallbackTasks}) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? sortOrder = preferences.getString(_sortOrderStorageKey);
    final bool sortAscending =
        preferences.getBool(_sortAscendingStorageKey) ?? true;
    final String? tasksJson = preferences.getString(_tasksStorageKey);
    final List<DeletedTask> deletedTasks = await _loadDeletedTasks(preferences);

    // 没有存档说明是首次启动：保留示例任务，并立刻保存到用户设备。
    if (tasksJson == null) {
      await _saveTasks(preferences, fallbackTasks);
      return TaskStorageSnapshot(
        tasks: null,
        deletedTasks: deletedTasks,
        sortOrder: sortOrder,
        sortAscending: sortAscending,
      );
    }

    // 旧版本可能保存的是字符串数组；无效 JSON 则让页面保留示例任务。
    final dynamic decodedJson;
    try {
      decodedJson = jsonDecode(tasksJson);
    } on FormatException {
      return TaskStorageSnapshot(
        tasks: null,
        deletedTasks: deletedTasks,
        sortOrder: sortOrder,
        sortAscending: sortAscending,
      );
    }

    if (decodedJson is! List) {
      return TaskStorageSnapshot(
        tasks: null,
        deletedTasks: deletedTasks,
        sortOrder: sortOrder,
        sortAscending: sortAscending,
      );
    }

    final List<Task> savedTasks = [];
    final Set<String> usedIds = {};
    bool needsMigration = false;

    for (final dynamic item in decodedJson) {
      Task? task;

      if (item is String) {
        // 兼容最早版本直接保存 List<String> 的格式。
        task = Task(title: item);
        needsMigration = true;
      } else if (item is Map) {
        final Map<String, dynamic> taskJson = Map<String, dynamic>.from(item);
        task = Task.fromJson(taskJson);
        if (taskJson['id'] == null ||
            taskJson['id'].toString().isEmpty ||
            taskJson.containsKey('dueDate') ||
            !taskJson.containsKey('dueDateUtc') ||
            !taskJson.containsKey('reminderEnabled')) {
          needsMigration = true;
        }
      } else {
        needsMigration = true;
      }

      // 缺少标题的损坏记录没有展示价值，安全跳过。
      if (task == null || task.title.trim().isEmpty) {
        needsMigration = true;
        continue;
      }

      // 若旧数据中意外存在重复 ID，重新创建任务以获得新的唯一 ID。
      if (!usedIds.add(task.id)) {
        task = Task(
          title: task.title,
          isDone: task.isDone,
          dueDate: task.dueDate,
          reminderEnabled: task.reminderEnabled,
        );
        usedIds.add(task.id);
        needsMigration = true;
      }

      savedTasks.add(task);
    }

    // 读取旧格式后立即写回新结构，下次启动即可直接使用当前 JSON。
    if (needsMigration) {
      await _saveTasks(preferences, savedTasks);
    }

    return TaskStorageSnapshot(
      tasks: savedTasks,
      deletedTasks: deletedTasks,
      sortOrder: sortOrder,
      sortAscending: sortAscending,
    );
  }

  Future<void> save({
    List<Task>? tasks,
    List<DeletedTask>? deletedTasks,
    String? sortOrder,
    bool? sortAscending,
  }) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    if (tasks != null) {
      await _saveTasks(preferences, tasks);
    }
    if (deletedTasks != null) {
      await _saveDeletedTasks(preferences, deletedTasks);
    }
    if (sortOrder != null) {
      await preferences.setString(_sortOrderStorageKey, sortOrder);
    }
    if (sortAscending != null) {
      await preferences.setBool(_sortAscendingStorageKey, sortAscending);
    }
  }

  Future<void> _saveTasks(
    SharedPreferences preferences,
    List<Task> tasks,
  ) async {
    final String tasksJson = jsonEncode(
      tasks.map((task) => task.toJson()).toList(),
    );
    await preferences.setString(_tasksStorageKey, tasksJson);
  }

  Future<List<DeletedTask>> _loadDeletedTasks(
    SharedPreferences preferences,
  ) async {
    final String? deletedTasksJson = preferences.getString(
      _deletedTasksStorageKey,
    );
    if (deletedTasksJson == null) {
      return [];
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(deletedTasksJson);
    } on FormatException {
      await _saveDeletedTasks(preferences, []);
      return [];
    }
    if (decoded is! List) {
      await _saveDeletedTasks(preferences, []);
      return [];
    }

    final DateTime cutoff = DateTime.now().subtract(trashRetention);
    final List<DeletedTask> retainedTasks = [];
    bool needsCleanup = false;
    for (final dynamic item in decoded) {
      if (item is! Map) {
        needsCleanup = true;
        continue;
      }
      final dynamic rawTask = item['task'];
      if (rawTask is Map &&
          (rawTask.containsKey('dueDate') ||
              !rawTask.containsKey('dueDateUtc') ||
              !rawTask.containsKey('reminderEnabled'))) {
        needsCleanup = true;
      }
      final DeletedTask? deletedTask = DeletedTask.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (deletedTask == null || !deletedTask.deletedAt.isAfter(cutoff)) {
        needsCleanup = true;
        continue;
      }
      retainedTasks.add(deletedTask);
    }

    if (needsCleanup) {
      await _saveDeletedTasks(preferences, retainedTasks);
    }
    return retainedTasks;
  }

  Future<void> _saveDeletedTasks(
    SharedPreferences preferences,
    List<DeletedTask> deletedTasks,
  ) async {
    final String deletedTasksJson = jsonEncode(
      deletedTasks.map((item) => item.toJson()).toList(),
    );
    await preferences.setString(_deletedTasksStorageKey, deletedTasksJson);
  }
}
