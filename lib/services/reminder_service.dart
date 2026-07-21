import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/task.dart';
import '../models/todo_model.dart';
import 'task_notification_service.dart';

/// 监听任务变化并让系统提醒队列始终与当前任务状态一致。
class ReminderService with WidgetsBindingObserver {
  ReminderService({
    required TodoModel todoModel,
    required this._scheduler,
  })  : _todoModel = todoModel,
        _lastTaskRevision = todoModel.taskRevision {
    _todoModel.addListener(_handleTodoModelChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  final TodoModel _todoModel;
  final TaskNotificationScheduler _scheduler;

  int _lastTaskRevision;
  bool _initialized = false;
  bool _disposed = false;
  bool _reconcileRequested = false;
  Future<void>? _reconcileFuture;
  Future<String?>? _initializeFuture;

  bool get isAvailable => _scheduler.isAvailable;

  Future<String?> initialize({
    required TaskNotificationTapCallback onTaskSelected,
  }) {
    return _initializeFuture ??= _initialize(onTaskSelected);
  }

  Future<String?> _initialize(
    TaskNotificationTapCallback onTaskSelected,
  ) async {
    final String? initialTaskId = await _scheduler.initialize(
      onTaskSelected: onTaskSelected,
    );
    await _todoModel.load();
    if (_disposed) {
      return initialTaskId;
    }
    _initialized = true;
    _lastTaskRevision = _todoModel.taskRevision;
    await _requestReconcile();
    return initialTaskId;
  }

  void _handleTodoModelChanged() {
    final int revision = _todoModel.taskRevision;
    if (revision == _lastTaskRevision) {
      return;
    }
    _lastTaskRevision = revision;
    if (_initialized) {
      _requestReconcile();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _initialized) {
      // 权限、时区或系统队列可能在 App 离开期间变化，恢复前台时强制对账。
      _requestReconcile();
    }
  }

  Future<bool> requestPermissions() => _scheduler.requestPermissions();

  Future<void> openNotificationSettings() =>
      _scheduler.openNotificationSettings();

  /// 串行并合并并发请求，保证最后一次对账使用最新任务状态。
  Future<void> _requestReconcile() {
    if (_disposed) {
      return Future<void>.value();
    }
    _reconcileRequested = true;
    return _reconcileFuture ??= _drainReconcileRequests();
  }

  Future<void> _drainReconcileRequests() async {
    try {
      while (_reconcileRequested && !_disposed) {
        _reconcileRequested = false;
        final List<Task> eligibleTasks = _todoModel.tasks
            .where((task) => task.isEligibleForReminder)
            .toList();
        try {
          await _scheduler.reconcile(List.of(eligibleTasks));
        } on Exception catch (_) {
          // 对账失败不影响后续任务操作，下次恢复前台时会再次对账。
        }
      }
    } finally {
      _reconcileFuture = null;
      // 若请求恰好在循环退出时到达，启动下一轮，避免漏掉最终状态。
      if (_reconcileRequested && !_disposed) {
        unawaited(_requestReconcile());
      }
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _reconcileRequested = false;
    _todoModel.removeListener(_handleTodoModelChanged);
    WidgetsBinding.instance.removeObserver(this);
  }
}
