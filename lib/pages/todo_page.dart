import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/quote_service.dart';
import '../services/task_storage.dart';

enum TaskSortOrder { added, dueDate, completion }

enum QuoteLoadStage { idle, loading, retrying, failed }

// 页面中的任务列表会随着用户添加任务而变化，因此要使用 StatefulWidget。
// StatefulWidget 可以把会变化的数据保存在对应的 State 对象中。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key, this.quoteService});

  final QuoteService? quoteService;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  static const int _maxQuoteRetries = 3;
  static const Duration _quoteRetryDelay = Duration(seconds: 60);

  final List<Task> _tasks = [
    Task(title: '买菜'),
    Task(title: '写代码'),
    Task(title: '跑步'),
  ];
  final TextEditingController _taskController = TextEditingController();
  final TaskStorage _taskStorage = TaskStorage();
  DateTime? _selectedDueDate;
  TaskSortOrder _sortOrder = TaskSortOrder.dueDate;
  bool _sortAscending = true;
  late final QuoteService _quoteService;
  late Future<Quote> _quoteFuture;
  QuoteLoadStage _quoteStage = QuoteLoadStage.idle;
  Timer? _quoteRetryTimer;
  int _quoteRetryCount = 0;
  int _quoteRequestId = 0;

  @override
  void initState() {
    super.initState();
    _quoteService = widget.quoteService ?? QuoteService();
    _startQuoteRequest(stage: QuoteLoadStage.loading, notify: false);
    // initState 是 State 创建后只执行一次的初始化方法，适合在页面启动时读取存档。
    // initState 本身不能标记为 async，所以把异步读取放到单独的方法中调用。
    _loadTasks();
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
    setState(() {
      _tasks.add(Task(title: task, dueDate: _selectedDueDate));
      // 截止日期只属于本次新任务，添加后清空，避免带到下一条任务。
      _selectedDueDate = null;
    });
    _taskController.clear();
    await _taskStorage.save(tasks: _tasks);

    if (!mounted) {
      return;
    }

    // 添加成功后给用户一个短暂反馈，不会打断继续输入。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已添加')));
  }

  Future<void> _pickDueDateTime() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime firstDate = DateTime(today.year - 100);
    final DateTime lastDate = DateTime(today.year + 100, 12, 31);
    final DateTime selectedDate = _selectedDueDate ?? today;
    final DateTime initialDate = selectedDate.isBefore(firstDate)
        ? firstDate
        : selectedDate.isAfter(lastDate)
        ? lastDate
        : selectedDate;

    // showDatePicker 异步等待用户选择或取消，因此用 await 获取最终结果。
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    // 日期选择器关闭时页面可能已销毁，打开下一个控件前必须检查 mounted。
    if (!mounted || pickedDate == null) {
      return;
    }

    // Flutter 将日期和时间拆成两个原生控件；第二步选择小时和分钟。
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDueDate ?? now),
    );

    if (!mounted || pickedTime == null) {
      return;
    }

    setState(() {
      _selectedDueDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _toggleTask(Task task, bool? isDone) async {
    // 完成状态属于页面数据，必须在 setState 中修改，界面才会重新构建。
    setState(() {
      task.isDone = isDone ?? false;
    });
    await _taskStorage.save(tasks: _tasks);
  }

  Future<void> _deleteTask(Task task) async {
    final int originalIndex = _tasks.indexOf(task);
    if (originalIndex == -1) {
      return;
    }

    setState(() {
      _tasks.removeAt(originalIndex);
    });

    // 保存可以异步进行，但删除反馈应立即出现，不必等磁盘写入结束。
    final Future<void> saveOperation = _taskStorage.save(tasks: _tasks);

    if (!mounted) {
      await saveOperation;
      return;
    }

    // 左滑和删除按钮共用提示；SnackBarAction 提供一次撤销机会。
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已删除 ${task.title}'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => _restoreTask(task, originalIndex),
          ),
        ),
      );

    await saveOperation;
  }

  Future<void> _restoreTask(Task task, int originalIndex) async {
    // SnackBar 的回调触发时页面可能已经销毁，必须先检查 mounted，
    // 避免对已销毁的 State 调用 setState。
    if (!mounted) {
      return;
    }

    // 若撤销前列表又发生变化，确保插入位置仍在当前列表的有效范围内。
    final int restoredIndex = originalIndex > _tasks.length
        ? _tasks.length
        : originalIndex;

    setState(() {
      _tasks.insert(restoredIndex, task);
    });
    await _taskStorage.save(tasks: _tasks);
  }

  @override
  void dispose() {
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

  Widget _buildQuoteCard() {
    return Card(
      key: const ValueKey<String>('daily-quote-card'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: FutureBuilder<Quote>(
                future: _quoteFuture,
                builder: (context, snapshot) {
                  if (_quoteStage == QuoteLoadStage.retrying) {
                    return const Text('正在联网获取名言,请稍等');
                  }

                  // FutureBuilder 的三种状态：waiting 表示加载中；hasError
                  // 表示本次请求失败；hasData 表示请求成功并可安全展示名言。
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError ||
                      _quoteStage == QuoteLoadStage.failed) {
                    final String message = _quoteStage == QuoteLoadStage.failed
                        ? '无法连接,无法显示名言'
                        : '获取名言失败';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message),
                        TextButton(
                          onPressed: _refreshQuote,
                          child: const Text('重试'),
                        ),
                      ],
                    );
                  }
                  if (snapshot.hasData) {
                    final Quote quote = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('“${quote.content}”'),
                        const SizedBox(height: 6),
                        Text(
                          '—— ${quote.author}',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    );
                  }

                  return const Text('暂无名言');
                },
              ),
            ),
            IconButton(
              key: const ValueKey<String>('refresh-quote-button'),
              tooltip: '刷新名言',
              onPressed: _refreshQuote,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    final DateTime localDate = date.toLocal();
    final String month = localDate.month.toString().padLeft(2, '0');
    final String day = localDate.day.toString().padLeft(2, '0');
    final String hour = localDate.hour.toString().padLeft(2, '0');
    final String minute = localDate.minute.toString().padLeft(2, '0');
    return '${localDate.year}-$month-$day $hour:$minute';
  }

  bool _isOverdue(Task task) {
    if (task.isDone || task.dueDate == null) {
      return false;
    }

    final DateTime localDueDate = task.dueDate!.toLocal();
    final DateTime dueMinute = DateTime(
      localDueDate.year,
      localDueDate.month,
      localDueDate.day,
      localDueDate.hour,
      localDueDate.minute,
    );
    final DateTime now = DateTime.now();
    final DateTime currentMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );

    // 精确到分钟比较；当前分钟内不算过期，进入下一分钟后才标红。
    return dueMinute.isBefore(currentMinute);
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
          _buildQuoteCard(),
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

                      // Dismissible 依靠 key 区分列表项并跟踪滑动动画；如果 key
                      // 重复，Flutter 可能删除或复用错误的任务，所以必须使用唯一 ID。
                      return Dismissible(
                        key: ValueKey<String>(task.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _deleteTask(task),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.delete,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        // Card 的圆角和轻微阴影让每条任务层次更清晰。
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 2,
                          shadowColor: Colors.black26,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            leading: Checkbox(
                              value: task.isDone,
                              onChanged: (isDone) => _toggleTask(task, isDone),
                            ),
                            title: Text(
                              task.title,
                              style: TextStyle(
                                decoration: task.isDone
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                color: task.isDone ? Colors.grey : null,
                              ),
                            ),
                            subtitle: task.dueDate == null
                                ? null
                                : Text(
                                    '截止日期：${_formatDateTime(task.dueDate!)}',
                                    style: TextStyle(
                                      color: _isOverdue(task)
                                          ? Colors.red
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                            trailing: IconButton(
                              tooltip: '删除任务',
                              onPressed: () => _deleteTask(task),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taskController,
                      textInputAction: TextInputAction.done,
                      // onSubmitted 让软键盘的“完成/回车”与添加按钮作用相同。
                      onSubmitted: (_) => _addTask(),
                      decoration: const InputDecoration(
                        hintText: '请输入任务',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                        ),
                        // 获得焦点时用更粗的绿色边框高亮输入区域。
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          borderSide: BorderSide(
                            color: Color(0xFF4F8A5B),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 日历按钮依次选择日期和时间，选中后在输入框旁显示到分钟。
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey<String>('due-date-button'),
                        tooltip: '选择截止日期和时间',
                        onPressed: _pickDueDateTime,
                        icon: const Icon(Icons.calendar_month),
                      ),
                      if (_selectedDueDate != null)
                        Text(
                          _formatDateTime(_selectedDueDate!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4F6F56),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _addTask, child: const Text('添加')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
