import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/deleted_task.dart';
import '../models/task.dart';
import '../models/todo_model.dart';
import '../services/quote_service.dart';
import '../services/task_notification_service.dart';
import '../utils/date_format.dart';
import '../widgets/quote_card.dart';
import '../widgets/task_input_bar.dart';
import '../widgets/task_tile.dart';

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

  final TextEditingController _taskController = TextEditingController();
  DateTime? _selectedDueDate;
  bool _selectedReminderEnabled = false;
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
  TodoModel? _todoModel;
  int _lastReminderRevision = 0;
  int _lastPersistenceFailureRevision = 0;
  bool _didInitializeTasksAndReminders = false;
  bool _notificationsInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _quoteService = widget.quoteService ?? QuoteService();
    _notificationScheduler =
        widget.notificationScheduler ?? TaskNotificationService();
    _startQuoteRequest(stage: QuoteLoadStage.loading, notify: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final TodoModel model = context.read<TodoModel>();
    if (!identical(_todoModel, model)) {
      _todoModel?.removeListener(_handleTodoModelChanged);
      _todoModel = model;
      _lastReminderRevision = model.reminderRevision;
      _lastPersistenceFailureRevision = model.persistenceFailure?.revision ?? 0;
      model.addListener(_handleTodoModelChanged);
    }
    if (!_didInitializeTasksAndReminders) {
      _didInitializeTasksAndReminders = true;
      _initializeTasksAndReminders();
    }
  }

  void _handleTodoModelChanged() {
    final TodoModel? model = _todoModel;
    if (model == null) {
      return;
    }

    final TodoPersistenceFailure? failure = model.persistenceFailure;
    if (failure != null &&
        failure.revision != _lastPersistenceFailureRevision) {
      _lastPersistenceFailureRevision = failure.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${failure.action}失败，本次更改可能未写入本地'),
            action: SnackBarAction(
              label: '重试',
              onPressed: model.retryPersistence,
            ),
          ),
        );
      });
    }

    if (model.reminderRevision != _lastReminderRevision) {
      _lastReminderRevision = model.reminderRevision;
    } else {
      return;
    }
    if (_notificationsInitialized) {
      _reconcileReminders();
    }
  }

  Future<void> _initializeTasksAndReminders() async {
    final String? initialTaskId = await _notificationScheduler.initialize(
      onTaskSelected: _selectTaskFromNotification,
    );
    await _todoModel!.load();
    if (!mounted) {
      return;
    }
    _notificationsInitialized = true;
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
      _notificationScheduler.reconcile(List<Task>.of(_todoModel!.tasks));

  void _selectTaskFromNotification(String taskId) {
    if (!mounted) {
      return;
    }
    final TodoModel model = _todoModel!;
    if (!model.tasks.any((task) => task.id == taskId)) {
      // 数据读取前先暂存；读取后仍找不到说明任务已删除，只正常停留首页。
      _pendingTaskSelection = model.isLoaded ? null : taskId;
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
                              : '截止时间：${formatDateTime(editedDueDate!)}',
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
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true && mounted) {
      await context.read<TodoModel>().updateTask(
        task,
        title: editedTitle,
        dueDate: editedDueDate?.toUtc(),
        reminderEnabled: editedReminderEnabled && _canRemindAt(editedDueDate),
      );
    }
  }

  Future<void> _showTrash() async {
    await context.read<TodoModel>().purgeExpiredDeletedTasks();
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return Consumer<TodoModel>(
          builder: (context, todoModel, child) {
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
                      child: todoModel.deletedTasks.isEmpty
                          ? const Center(child: Text('回收站是空的'))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: todoModel.deletedTasks.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(),
                              itemBuilder: (context, index) {
                                final DeletedTask deletedTask =
                                    todoModel.deletedTasks[index];
                                return ListTile(
                                  title: Text(deletedTask.task.title),
                                  trailing: TextButton.icon(
                                    key: ValueKey<String>(
                                      'restore-${deletedTask.task.id}',
                                    ),
                                    onPressed: () => todoModel
                                        .restoreDeletedTask(deletedTask),
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
    _todoModel?.removeListener(_handleTodoModelChanged);
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

  @override
  Widget build(BuildContext context) {
    // watch 订阅 TodoModel；任务或排序变化时页面会自动重建。
    final TodoModel todoModel = context.watch<TodoModel>();
    final List<Task> displayedTasks = todoModel.displayedTasks;

    // Scaffold 是 Material Design 页面结构，提供 AppBar、主体等常用区域。
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '我的待办 (${todoModel.completedCount}/${todoModel.tasks.length})',
        ),
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
                    '排序：${todoModel.sortOrderLabel}'
                    '（${todoModel.sortAscending ? '升序' : '降序'}）',
                    style: const TextStyle(color: Color(0xFF4F6F56)),
                  ),
                ),
                PopupMenuButton<TaskSortOrder>(
                  initialValue: todoModel.sortOrder,
                  tooltip: '选择排序方式',
                  onSelected: context.read<TodoModel>().setSortOrder,
                  itemBuilder: (context) => TaskSortOrder.values
                      .map(
                        (order) => CheckedPopupMenuItem<TaskSortOrder>(
                          value: order,
                          checked: order == todoModel.sortOrder,
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
                  tooltip: todoModel.sortAscending ? '切换为降序' : '切换为升序',
                  onPressed: context.read<TodoModel>().toggleSortDirection,
                  icon: Icon(
                    todoModel.sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                  ),
                ),
              ],
            ),
          ),
          // Expanded 让任务列表占满输入区域之外的剩余空间。
          Expanded(
            child: todoModel.tasks.isEmpty
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
            onTaskAdded: () {
              setState(() {
                // 截止日期和提醒只属于本次新任务，添加后清空草稿。
                _selectedDueDate = null;
                _selectedReminderEnabled = false;
              });
            },
            onPickDueDate: _pickDueDateTime,
            onReminderChanged: _setSelectedReminder,
            onShowTrash: _showTrash,
          ),
        ],
      ),
    );
  }
}
