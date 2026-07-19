import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '我的待办',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 用低饱和度绿色作为种子色，生成统一、柔和的 Material 配色。
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6F9D7A)),
        scaffoldBackgroundColor: const Color(0xFFF4F8F4),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE5F1E7),
          foregroundColor: Color(0xFF294E32),
          elevation: 0,
        ),
      ),
      home: const TodoPage(),
    );
  }
}

// String 只能保存任务文字，无法同时记录任务是否完成。
// 改用 Task 后，每一项任务就能把文字和完成状态放在同一个数据结构中管理。
class Task {
  Task({String? id, required this.title, this.isDone = false, this.dueDate})
    : id = id ?? _generateId();

  static int _idSequence = 0;

  // 时间戳加递增序号，即使同一微秒创建多个任务也能得到不同 ID。
  static String _generateId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';
  }

  final String id;
  final String title;
  bool isDone;
  final DateTime? dueDate;

  // 把 Task 转成可被 JSON 编码的 Map，便于保存到本地。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isDone': isDone,
    // JSON 没有原生 DateTime 类型，因此用 ISO8601 字符串保存；
    // 这种标准格式跨平台一致，也能用 DateTime.tryParse 安全还原。
    'dueDate': dueDate?.toIso8601String(),
  };

  // 从 JSON Map 还原 Task，让保存的数据能重新变成应用中的对象。
  factory Task.fromJson(Map<String, dynamic> json) {
    final String? savedId = json['id']?.toString();

    return Task(
      // 旧版本 JSON 没有 id，此时传入 null，由构造函数自动补一个唯一 ID。
      id: savedId == null || savedId.isEmpty ? null : savedId,
      // 不再强制把 null 转成 String，避免损坏或旧数据导致启动崩溃。
      title: json['title']?.toString() ?? '',
      isDone: json['isDone'] == true,
      // 老数据没有 dueDate 时得到 null；无效日期字符串也安全降级为 null。
      dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? ''),
    );
  }
}

// 页面中的任务列表会随着用户添加任务而变化，因此要使用 StatefulWidget。
// StatefulWidget 可以把会变化的数据保存在对应的 State 对象中。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  static const String _tasksStorageKey = 'tasks';

  final List<Task> _tasks = [
    Task(title: '买菜'),
    Task(title: '写代码'),
    Task(title: '跑步'),
  ];
  final TextEditingController _taskController = TextEditingController();
  DateTime? _selectedDueDate;

  @override
  void initState() {
    super.initState();
    // initState 是 State 创建后只执行一次的初始化方法，适合在页面启动时读取存档。
    // initState 本身不能标记为 async，所以把异步读取放到单独的方法中调用。
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    // 本地存储读写需要时间并返回 Future，因此用 async/await 等待结果，
    // 避免在数据尚未读取完成时就继续处理它。
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? tasksJson = preferences.getString(_tasksStorageKey);

    // 没有存档说明是首次启动：显示示例任务，并立刻保存到用户设备。
    if (tasksJson == null) {
      await _saveTasks();
      return;
    }

    // 旧版本可能保存的是字符串数组；无效 JSON 则保留示例任务，不让 App 崩溃。
    final dynamic decodedJson;
    try {
      decodedJson = jsonDecode(tasksJson);
    } on FormatException {
      return;
    }

    if (decodedJson is! List) {
      return;
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
        if (taskJson['id'] == null || taskJson['id'].toString().isEmpty) {
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
        );
        usedIds.add(task.id);
        needsMigration = true;
      }

      savedTasks.add(task);
    }

    // 异步读取结束时页面可能已被销毁，mounted 可避免更新已销毁的 State。
    if (!mounted) {
      return;
    }

    setState(() {
      _tasks
        ..clear()
        ..addAll(savedTasks);
    });

    // 读取旧格式后立即写回新结构，下次启动即可直接使用带 ID 的 JSON。
    if (needsMigration) {
      await _saveTasks();
    }
  }

  Future<void> _saveTasks() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String tasksJson = jsonEncode(
      _tasks.map((task) => task.toJson()).toList(),
    );

    // await 保证本次写入完成后，调用方才继续执行。
    await preferences.setString(_tasksStorageKey, tasksJson);
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
    await _saveTasks();

    if (!mounted) {
      return;
    }

    // 添加成功后给用户一个短暂反馈，不会打断继续输入。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已添加')));
  }

  Future<void> _pickDueDate() async {
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

    // 日期选择器关闭时页面可能已销毁，更新 State 前必须检查 mounted。
    if (!mounted || pickedDate == null) {
      return;
    }

    setState(() {
      _selectedDueDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
      );
    });
  }

  Future<void> _toggleTask(Task task, bool? isDone) async {
    // 完成状态属于页面数据，必须在 setState 中修改，界面才会重新构建。
    setState(() {
      task.isDone = isDone ?? false;
    });
    await _saveTasks();
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
    final Future<void> saveOperation = _saveTasks();

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
    await _saveTasks();
  }

  @override
  void dispose() {
    // 页面销毁时释放输入控制器，避免占用不再需要的资源。
    _taskController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final DateTime localDate = date.toLocal();
    final String month = localDate.month.toString().padLeft(2, '0');
    final String day = localDate.day.toString().padLeft(2, '0');
    return '${localDate.year}-$month-$day';
  }

  bool _isOverdue(Task task) {
    if (task.isDone || task.dueDate == null) {
      return false;
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime localDueDate = task.dueDate!.toLocal();
    final DateTime dueDay = DateTime(
      localDueDate.year,
      localDueDate.month,
      localDueDate.day,
    );

    // 只比较年月日，今天到期不算过期，早于今天且未完成才标红。
    return dueDay.isBefore(today);
  }

  @override
  Widget build(BuildContext context) {
    // 每次状态变化重新 build 时统计，标题会立即反映最新完成进度。
    final int completedCount = _tasks.where((task) => task.isDone).length;

    // Scaffold 是 Material Design 页面结构，提供 AppBar、主体等常用区域。
    return Scaffold(
      appBar: AppBar(
        title: Text('我的待办 ($completedCount/${_tasks.length})'),
        centerTitle: true,
      ),
      body: Column(
        children: [
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
                    itemCount: _tasks.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final Task task = _tasks[index];

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
                                    '截止日期：${_formatDate(task.dueDate!)}',
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
                  // 日历按钮打开日期选择器，选中后在输入框旁显示日期。
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey<String>('due-date-button'),
                        tooltip: '选择截止日期',
                        onPressed: _pickDueDate,
                        icon: const Icon(Icons.calendar_month),
                      ),
                      if (_selectedDueDate != null)
                        Text(
                          _formatDate(_selectedDueDate!),
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
