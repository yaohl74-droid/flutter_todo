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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const TodoPage(),
    );
  }
}

// String 只能保存任务文字，无法同时记录任务是否完成。
// 改用 Task 后，每一项任务就能把文字和完成状态放在同一个数据结构中管理。
class Task {
  Task({required this.title, this.isDone = false});

  final String title;
  bool isDone;

  // 把 Task 转成可被 JSON 编码的 Map，便于保存到本地。
  Map<String, dynamic> toJson() => {'title': title, 'isDone': isDone};

  // 从 JSON Map 还原 Task，让保存的数据能重新变成应用中的对象。
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      title: json['title'] as String,
      isDone: json['isDone'] as bool? ?? false,
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

    // 没有存档说明是首次启动，继续使用上面的示例任务。
    if (tasksJson == null) {
      return;
    }

    final List<dynamic> decodedTasks = jsonDecode(tasksJson) as List<dynamic>;
    final List<Task> savedTasks = decodedTasks
        .map((json) => Task.fromJson(Map<String, dynamic>.from(json as Map)))
        .toList();

    // 异步读取结束时页面可能已被销毁，mounted 可避免更新已销毁的 State。
    if (!mounted) {
      return;
    }

    setState(() {
      _tasks
        ..clear()
        ..addAll(savedTasks);
    });
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
      _tasks.add(Task(title: task));
    });
    _taskController.clear();
    await _saveTasks();
  }

  Future<void> _toggleTask(Task task, bool? isDone) async {
    // 完成状态属于页面数据，必须在 setState 中修改，界面才会重新构建。
    setState(() {
      task.isDone = isDone ?? false;
    });
    await _saveTasks();
  }

  Future<void> _deleteTask(Task task) async {
    setState(() {
      _tasks.remove(task);
    });
    await _saveTasks();
  }

  @override
  void dispose() {
    // 页面销毁时释放输入控制器，避免占用不再需要的资源。
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold 是 Material Design 页面结构，提供 AppBar、主体等常用区域。
    return Scaffold(
      appBar: AppBar(title: const Text('我的待办')),
      body: Column(
        children: [
          // Expanded 让任务列表占满输入区域之外的剩余空间。
          Expanded(
            // ListView 是可滚动的列表组件，会按顺序纵向排列多个子组件。
            child: ListView(
              children: _tasks.map((task) {
                // ListTile 是一行标准列表项，可方便地放置前置图标和标题文字。
                return ListTile(
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
                  trailing: IconButton(
                    tooltip: '删除任务',
                    onPressed: () => _deleteTask(task),
                    icon: const Icon(Icons.delete_outline),
                  ),
                );
              }).toList(),
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
                      decoration: const InputDecoration(
                        hintText: '请输入任务',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
