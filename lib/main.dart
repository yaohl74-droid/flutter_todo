import 'package:flutter/material.dart';

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

// 页面中的任务列表会随着用户添加任务而变化，因此要使用 StatefulWidget。
// StatefulWidget 可以把会变化的数据保存在对应的 State 对象中。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final List<String> _tasks = ['买菜', '写代码', '跑步'];
  final TextEditingController _taskController = TextEditingController();

  void _addTask() {
    final String task = _taskController.text.trim();

    // 输入为空或只有空格时，不添加任务。
    if (task.isEmpty) {
      return;
    }

    // setState 告诉 Flutter 状态已经改变，需要重新执行 build 方法，
    // 这样新加入 _tasks 的任务才会显示在界面上。
    setState(() {
      _tasks.add(task);
    });
    _taskController.clear();
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
                  leading: const Icon(Icons.radio_button_unchecked),
                  title: Text(task),
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
