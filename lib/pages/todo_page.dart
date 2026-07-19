import 'dart:async';

import 'package:flutter/material.dart';

import '../models/deleted_task.dart';
import '../models/task.dart';
import '../services/quote_service.dart';
import '../services/task_notification_service.dart';
import '../services/task_storage.dart';
import '../widgets/quote_card.dart';
import '../widgets/task_input_bar.dart';
import '../widgets/task_tile.dart';

enum TaskSortOrder { added, dueDate, completion }

// 页面中的任务列表会随着用户添加任务而变化，因此要使用 StatefulWidget。
// StatefulWidget 可以把会变化的数据保存在对应的 State 对象中。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key, this.quoteService, this.notificationScheduler});

  final QuoteService? quoteService;
  final TaskNotificationScheduler? notificationScheduler;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> with WidgetsBindingObserver {
  static const int _maxQuoteRetries = 3;
  static const Duration _quoteRetryDelay = Duration(seconds: 60);

  final List<Task> _tasks = [
    Task(title: '买菜'),
    Task(title: '写代码'),
    Task(title: '跑步'),
  ];
  final List<DeletedTask> _deletedTasks = [];
  final TextEditingController _taskController = TextEditingController();
  final TaskStorage _taskStorage = TaskStorage();
  DateTime? _selectedDueDate;
  bool _selectedReminderEnabled = false;
  TaskSortOrder _sortOrder = TaskSortOrder.dueDate;
  bool _sortAscending = true;
  late final QuoteService _quoteService;
  late Future<Quote> _quoteFuture;
  QuoteLoadStage _quoteStage = QuoteLoadStage.idle;
  Timer? _quoteRetryTimer;
  int _quoteRetryCount = 0;
  int _quoteRequestId = 0;
  late final TaskNotificationScheduler _notificationScheduler;
  final Map<String, GlobalKey> _taskKeys = <String, GlobalKey>{};
  Timer? _highlightTimer;
  String? _highlightedTaskId;
  String? _pendingTaskSelection;
  bool _tasksLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _quoteService = widget.quoteService ?? QuoteService();
    _notificationScheduler =
        widget.notificationScheduler ?? TaskNotificationService();
    _startQuoteRequest(stage: QuoteLoadStage.loading, notify: false);
    // initState 是 State 创建后只执行一次的初始化方法，适合在页面启动时读取存档。
    // initState 本身不能标记为 async，所以把异步读取放到单独的方法中调用。
    _initializeTasksAndReminders();
  }

  Future<void> _initializeTasksAndReminders() async {
    final String? initialTaskId = await _notificationScheduler.initialize(
      onTaskSelected: _selectTaskFromNotification,
    );
    await _loadTasks();
    if (!mounted) {
      return;
    }
    await _reconcileReminders();
    final String? taskId = initialTaskId ?? _pendingTaskSelection;
    if (taskId != null) {
      _selectTaskFromNotification(taskId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 权限、时区或系统队列可能在 App 离开期间变化，恢复前台时重新对账。
      _reconcileReminders();
    }
  }

  Future<void> _reconcileReminders() =>
      _notificationScheduler.reconcile(List<Task>.of(_tasks));

  void _selectTaskFromNotification(String taskId) {
    if (!mounted) {
      return;
    }
    if (!_tasks.any((task) => task.id == taskId)) {
      // 数据读取前先暂存；读取后仍找不到说明任务已删除，只正常停留首页。
      _pendingTaskSelection = _tasksLoaded ? null : taskId;
      return;
    }
    _pendingTaskSelection = null;
    _highlightTimer?.cancel();
    setState(() {
      _highlightedTaskId = taskId;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? taskContext = _taskKeys[taskId]?.currentContext;
      if (taskContext != null) {
        Scrollable.ensureVisible(
          taskContext,
          duration: const Duration(milliseconds: 350),
          alignment: 0.4,
        );
      }
    });
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _highlightedTaskId == taskId) {
        setState(() {
          _highlightedTaskId = null;
        });
      }
    });
  }

  Future<void> _loadTasks() async {
    final TaskStorageSnapshot snapshot = await _taskStorage.load(
      fallbackTasks: _tasks,
    );
    final TaskSortOrder restoredSortOrder = TaskSortOrder.values.firstWhere(
      (order) => order.name == snapshot.sortOrder,
      orElse: () => TaskSortOrder.dueDate,
    );

    // 异步读取结束时页面可能已被销毁，mounted 可避免更新已销毁的 State。
    if (!mounted) {
      return;
    }

    setState(() {
      _sortOrder = restoredSortOrder;
      _sortAscending = snapshot.sortAscending;
      if (snapshot.tasks != null) {
        _tasks
          ..clear()
          ..addAll(snapshot.tasks!);
      }
      _deletedTasks
        ..clear()
        ..addAll(snapshot.deletedTasks);
      _tasksLoaded = true;
    });
  }

  Future<void> _setSortOrder(TaskSortOrder order) async {
    setState(() {
      _sortOrder = order;
    });
    await _taskStorage.save(sortOrder: order.name);
  }

  Future<void> _toggleSortDirection() async {
    setState(() {
      _sortAscending = !_sortAscending;
    });
    await _taskStorage.save(sortAscending: _sortAscending);
  }

  Future<void> _addTask() async {
    final String task = _taskController.text.trim();

    // 输入为空或只有空格时，不添加任务。
    if (task.isEmpty) {
      return;
    }

    // setState 告诉 Flutter 状态已经改变，需要重新执行 build 方法，
    // 这样新加入 _tasks 的任务才会显示在界面上。
    final DateTime? dueDate = _selectedDueDate;
    final bool reminderEnabled =
        _selectedReminderEnabled &&
        dueDate != null &&
        dueDate.isAfter(DateTime.now().toUtc());
    setState(() {
      _tasks.add(
        Task(title: task, dueDate: dueDate, reminderEnabled: reminderEnabled),
      );
      // 截止日期只属于本次新任务，添加后清空，避免带到下一条任务。
      _selectedDueDate = null;
      _selectedReminderEnabled = false;
    });
    _taskController.clear();
    await _taskStorage.save(tasks: _tasks);
    await _reconcileReminders();

    if (!mounted) {
      return;
    }

    // 添加成功后给用户一个短暂反馈，不会打断继续输入。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已添加')));
  }

  Future<void> _pickDueDateTime() async {
    final DateTime? picked = await _selectDateTime(
      context,
      _selectedDueDate?.toLocal(),
    );
    if (!mounted || picked == null) {
      return;
    }

    final DateTime dueDateUtc = picked.toUtc();
    final bool canEnable =
        dueDateUtc.isAfter(DateTime.now().toUtc()) &&
        _notificationScheduler.isAvailable;
    setState(() {
      _selectedDueDate = dueDateUtc;
      _selectedReminderEnabled = canEnable;
    });
    if (canEnable && !await _notificationScheduler.requestPermissions()) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedReminderEnabled = false;
      });
      await _showNotificationPermissionDialog();
    }
  }

  Future<DateTime?> _selectDateTime(
    BuildContext pickerContext,
    DateTime? current,
  ) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime firstDate = DateTime(today.year - 100);
    final DateTime lastDate = DateTime(today.year + 100, 12, 31);
    final DateTime selectedDate = current ?? today;
    final DateTime initialDate = selectedDate.isBefore(firstDate)
        ? firstDate
        : selectedDate.isAfter(lastDate)
        ? lastDate
        : selectedDate;

    // showDatePicker 异步等待用户选择或取消，因此用 await 获取最终结果。
    final DateTime? pickedDate = await showDatePicker(
      context: pickerContext,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    // 日期选择器关闭时页面可能已销毁，打开下一个控件前必须检查 mounted。
    if (!pickerContext.mounted || pickedDate == null) {
      return null;
    }

    // Flutter 将日期和时间拆成两个原生控件；第二步选择小时和分钟。
    final TimeOfDay? pickedTime = await showTimePicker(
      context: pickerContext,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );

    if (!pickerContext.mounted || pickedTime == null) {
      return null;
    }
    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  bool _canRemindAt(DateTime? dueDate) =>
      dueDate != null &&
      dueDate.toUtc().isAfter(DateTime.now().toUtc()) &&
      _notificationScheduler.isAvailable;

  Future<void> _setSelectedReminder(bool enabled) async {
    if (!enabled) {
      setState(() {
        _selectedReminderEnabled = false;
      });
      return;
    }
    if (!_canRemindAt(_selectedDueDate)) {
      return;
    }
    final bool granted = await _notificationScheduler.requestPermissions();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedReminderEnabled = granted;
    });
    if (!granted) {
      await _showNotificationPermissionDialog();
    }
  }

  Future<void> _showNotificationPermissionDialog() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('通知权限未开启'),
        content: const Text('任务会正常保存，但无法发送到期提醒。你可以前往系统设置开启通知权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _notificationScheduler.openNotificationSettings();
            },
            child: const Text('前往系统设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditTask(Task task) async {
    String editedTitle = task.title;
    DateTime? editedDueDate = task.dueDate?.toLocal();
    bool editedReminderEnabled = task.reminderEnabled;

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bool canEnableReminder = _canRemindAt(editedDueDate);
          return AlertDialog(
            title: const Text('编辑任务'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    key: const ValueKey<String>('edit-task-title'),
                    initialValue: editedTitle,
                    onChanged: (value) {
                      editedTitle = value;
                    },
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '任务名称'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          editedDueDate == null
                              ? '未设置截止时间'
                              : '截止时间：${_formatDateTime(editedDueDate!)}',
                        ),
                      ),
                      IconButton(
                        key: const ValueKey<String>('edit-due-date-button'),
                        tooltip: '修改截止时间',
                        onPressed: () async {
                          final DateTime? picked = await _selectDateTime(
                            dialogContext,
                            editedDueDate,
                          );
                          if (picked != null && dialogContext.mounted) {
                            setDialogState(() {
                              editedDueDate = picked;
                              if (!_canRemindAt(picked)) {
                                editedReminderEnabled = false;
                              }
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_month),
                      ),
                      if (editedDueDate != null)
                        IconButton(
                          key: const ValueKey<String>('clear-due-date-button'),
                          tooltip: '清除截止时间',
                          onPressed: () {
                            setDialogState(() {
                              editedDueDate = null;
                              editedReminderEnabled = false;
                            });
                          },
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    key: const ValueKey<String>('edit-reminder-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('到期提醒'),
                    subtitle: canEnableReminder
                        ? const Text('到期时发送系统通知和提示音')
                        : Text(
                            editedDueDate == null
                                ? '请先设置截止时间'
                                : '截止时间已过，无法设置提醒',
                          ),
                    value: editedReminderEnabled && canEnableReminder,
                    onChanged: canEnableReminder
                        ? (enabled) async {
                            if (!enabled) {
                              setDialogState(() {
                                editedReminderEnabled = false;
                              });
                              return;
                            }
                            final bool granted = await _notificationScheduler
                                .requestPermissions();
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {
                              editedReminderEnabled = granted;
                            });
                            if (!granted) {
                              await _showNotificationPermissionDialog();
                            }
                          }
                        : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey<String>('save-edited-task'),
                onPressed: () {
                  if (editedTitle.trim().isEmpty) {
                    return;
                  }
                  task
                    ..title = editedTitle.trim()
                    ..dueDate = editedDueDate?.toUtc()
                    ..reminderEnabled =
                        editedReminderEnabled && _canRemindAt(editedDueDate);
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true) {
      setState(() {});
      await _taskStorage.save(tasks: _tasks);
      await _reconcileReminders();
    }
  }

  Future<void> _toggleTask(Task task, bool? isDone) async {
    // 完成状态属于页面数据，必须在 setState 中修改，界面才会重新构建。
    setState(() {
      task.isDone = isDone ?? false;
    });
    await _taskStorage.save(tasks: _tasks);
    await _reconcileReminders();
  }

  Future<void> _deleteTask(Task task) async {
    final int originalIndex = _tasks.indexOf(task);
    if (originalIndex == -1) {
      return;
    }

    final DeletedTask deletedTask = DeletedTask(
      task: task,
      deletedAt: DateTime.now(),
      originalIndex: originalIndex,
    );
    setState(() {
      _tasks.removeAt(originalIndex);
      _deletedTasks.add(deletedTask);
    });

    // 删除后直接进入回收站，不再显示会遮挡底部输入框的撤销 SnackBar。
    await _taskStorage.save(tasks: _tasks, deletedTasks: _deletedTasks);
    await _reconcileReminders();
  }

  Future<void> _restoreDeletedTask(DeletedTask deletedTask) async {
    if (!mounted) {
      return;
    }

    // 若恢复前列表又发生变化，确保插入位置仍在当前列表的有效范围内。
    final int restoredIndex = deletedTask.originalIndex > _tasks.length
        ? _tasks.length
        : deletedTask.originalIndex;

    setState(() {
      _deletedTasks.remove(deletedTask);
      _tasks.insert(restoredIndex, deletedTask.task);
    });
    await _taskStorage.save(tasks: _tasks, deletedTasks: _deletedTasks);
    await _reconcileReminders();
  }

  Future<void> _purgeExpiredDeletedTasks() async {
    final DateTime cutoff = DateTime.now().subtract(TaskStorage.trashRetention);
    final int previousLength = _deletedTasks.length;
    setState(() {
      _deletedTasks.removeWhere((item) => !item.deletedAt.isAfter(cutoff));
    });
    if (_deletedTasks.length != previousLength) {
      await _taskStorage.save(deletedTasks: _deletedTasks);
    }
  }

  Future<void> _showTrash() async {
    await _purgeExpiredDeletedTasks();
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: 360,
                child: Column(
                  children: [
                    const Text(
                      '回收站（保留 7 天）',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _deletedTasks.isEmpty
                          ? const Center(child: Text('回收站是空的'))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: _deletedTasks.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(),
                              itemBuilder: (context, index) {
                                final DeletedTask deletedTask =
                                    _deletedTasks[index];
                                return ListTile(
                                  title: Text(deletedTask.task.title),
                                  trailing: TextButton.icon(
                                    key: ValueKey<String>(
                                      'restore-${deletedTask.task.id}',
                                    ),
                                    onPressed: () async {
                                      await _restoreDeletedTask(deletedTask);
                                      if (sheetContext.mounted) {
                                        setSheetState(() {});
                                      }
                                    },
                                    icon: const Icon(Icons.restore),
                                    label: const Text('恢复'),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _highlightTimer?.cancel();
    // 页面销毁后必须取消等待中的重连，避免 Timer 回调对已销毁页面 setState。
    _quoteRetryTimer?.cancel();
    _quoteService.dispose();
    // 页面销毁时释放输入控制器，避免占用不再需要的资源。
    _taskController.dispose();
    super.dispose();
  }

  void _startQuoteRequest({
    required QuoteLoadStage stage,
    required bool notify,
  }) {
    final int requestId = ++_quoteRequestId;
    final Future<Quote> request = _quoteService.fetchQuote();

    void updateRequest() {
      _quoteStage = stage;
      _quoteFuture = request;
    }

    if (notify) {
      setState(updateRequest);
    } else {
      updateRequest();
    }

    // FutureBuilder 只展示这一次请求；超时后的定时重连由 State 统一调度。
    request.then<void>(
      (_) {
        if (!mounted || requestId != _quoteRequestId) {
          return;
        }
        _quoteRetryTimer?.cancel();
        setState(() {
          _quoteRetryCount = 0;
          _quoteStage = QuoteLoadStage.idle;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || requestId != _quoteRequestId) {
          return;
        }
        // 超时、断网、DNS 和 TLS 等请求失败都统一按 QuoteException 重连。
        if (error is QuoteException && _quoteRetryCount < _maxQuoteRetries) {
          _scheduleQuoteRetry();
          return;
        }
        setState(() {
          _quoteStage = QuoteLoadStage.failed;
        });
      },
    );
  }

  void _scheduleQuoteRetry() {
    _quoteRetryTimer?.cancel();
    setState(() {
      _quoteStage = QuoteLoadStage.retrying;
    });
    _quoteRetryTimer = Timer(_quoteRetryDelay, () {
      if (!mounted) {
        return;
      }
      _quoteRetryCount++;
      _startQuoteRequest(stage: QuoteLoadStage.retrying, notify: true);
    });
  }

  void _refreshQuote() {
    // 手动刷新代表一轮全新尝试：取消旧 Timer，并重置自动重连次数。
    _quoteRetryTimer?.cancel();
    _quoteRetryCount = 0;
    _startQuoteRequest(stage: QuoteLoadStage.loading, notify: true);
  }

  String _formatDateTime(DateTime date) {
    final DateTime localDate = date.toLocal();
    final String month = localDate.month.toString().padLeft(2, '0');
    final String day = localDate.day.toString().padLeft(2, '0');
    final String hour = localDate.hour.toString().padLeft(2, '0');
    final String minute = localDate.minute.toString().padLeft(2, '0');
    return '${localDate.year}-$month-$day $hour:$minute';
  }

  int get _activeDeletedTaskCount {
    final DateTime cutoff = DateTime.now().subtract(TaskStorage.trashRetention);
    return _deletedTasks.where((item) => item.deletedAt.isAfter(cutoff)).length;
  }

  String get _sortOrderLabel {
    return switch (_sortOrder) {
      TaskSortOrder.added => '按添加顺序',
      TaskSortOrder.dueDate => '按截止日期',
      TaskSortOrder.completion => '按完成状态',
    };
  }

  List<Task> get _displayedTasks {
    final List<Task> displayedTasks = List<Task>.of(_tasks);
    final Map<String, int> originalIndexes = {
      for (int index = 0; index < _tasks.length; index++)
        _tasks[index].id: index,
    };

    displayedTasks.sort((first, second) {
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
            // 这里直接返回并跳过下方的升降序翻转，保证无日期任务始终排在最后。
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
    return displayedTasks;
  }

  @override
  Widget build(BuildContext context) {
    // 每次状态变化重新 build 时统计，标题会立即反映最新完成进度。
    final int completedCount = _tasks.where((task) => task.isDone).length;
    final List<Task> displayedTasks = _displayedTasks;

    // Scaffold 是 Material Design 页面结构，提供 AppBar、主体等常用区域。
    return Scaffold(
      appBar: AppBar(
        title: Text('我的待办 ($completedCount/${_tasks.length})'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          QuoteCard(
            quoteFuture: _quoteFuture,
            stage: _quoteStage,
            onRefresh: _refreshQuote,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '排序：$_sortOrderLabel（${_sortAscending ? '升序' : '降序'}）',
                    style: const TextStyle(color: Color(0xFF4F6F56)),
                  ),
                ),
                PopupMenuButton<TaskSortOrder>(
                  initialValue: _sortOrder,
                  tooltip: '选择排序方式',
                  onSelected: _setSortOrder,
                  itemBuilder: (context) => TaskSortOrder.values
                      .map(
                        (order) => CheckedPopupMenuItem<TaskSortOrder>(
                          value: order,
                          checked: order == _sortOrder,
                          child: Text(switch (order) {
                            TaskSortOrder.added => '按添加顺序',
                            TaskSortOrder.dueDate => '按截止日期',
                            TaskSortOrder.completion => '按完成状态',
                          }),
                        ),
                      )
                      .toList(),
                  icon: const Icon(Icons.sort),
                ),
                IconButton(
                  key: const ValueKey<String>('sort-direction-button'),
                  tooltip: _sortAscending ? '切换为降序' : '切换为升序',
                  onPressed: _toggleSortDirection,
                  icon: Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  ),
                ),
              ],
            ),
          ),
          // Expanded 让任务列表占满输入区域之外的剩余空间。
          Expanded(
            child: _tasks.isEmpty
                // 空列表时用图标和提示文字引导用户添加第一条任务。
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.task_alt,
                          size: 88,
                          color: Color(0xFF8AAF91),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '还没有任务,添加一条吧',
                          style: TextStyle(
                            fontSize: 18,
                            color: Color(0xFF66806C),
                          ),
                        ),
                      ],
                    ),
                  )
                // ListView.separated 统一控制卡片之间的留白。
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: displayedTasks.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final Task task = displayedTasks[index];

                      return TaskTile(
                        task: task,
                        contentKey: _taskKeys.putIfAbsent(
                          task.id,
                          GlobalKey.new,
                        ),
                        highlighted: _highlightedTaskId == task.id,
                        onToggle: (isDone) => _toggleTask(task, isDone),
                        onDelete: () => _deleteTask(task),
                        onEdit: () => _showEditTask(task),
                      );
                    },
                  ),
          ),
          TaskInputBar(
            controller: _taskController,
            selectedDueDate: _selectedDueDate,
            reminderEnabled: _selectedReminderEnabled,
            canEnableReminder: _canRemindAt(_selectedDueDate),
            activeDeletedTaskCount: _activeDeletedTaskCount,
            onAdd: _addTask,
            onPickDueDate: _pickDueDateTime,
            onReminderChanged: _setSelectedReminder,
            onShowTrash: _showTrash,
          ),
        ],
      ),
    );
  }
}
