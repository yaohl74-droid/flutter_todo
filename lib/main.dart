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

class TodoPage extends StatelessWidget {
  const TodoPage({super.key});

  static const List<String> _tasks = ['买菜', '写代码', '跑步'];

  @override
  Widget build(BuildContext context) {
    // Scaffold 是 Material Design 页面结构，提供 AppBar、主体等常用区域。
    return Scaffold(
      appBar: AppBar(title: const Text('我的待办')),
      // ListView 是可滚动的列表组件，会按顺序纵向排列多个子组件。
      body: ListView(
        children: _tasks.map((task) {
          // ListTile 是一行标准列表项，可方便地放置前置图标和标题文字。
          return ListTile(
            leading: const Icon(Icons.radio_button_unchecked),
            title: Text(task),
          );
        }).toList(),
      ),
    );
  }
}
