import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_todo/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('显示待办清单', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('我的待办 (0/3)'), findsOneWidget);
    expect(find.text('买菜'), findsOneWidget);
    expect(find.text('写代码'), findsOneWidget);
    expect(find.text('跑步'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.byType(Card), findsNWidgets(3));
  });

  testWidgets('添加非空任务并清空输入框', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField), '学习 Flutter');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(find.text('学习 Flutter'), findsOneWidget);
    expect(find.text('我的待办 (0/4)'), findsOneWidget);
    expect(find.text('已添加'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(4));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('输入为空时不添加任务', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(find.byType(Checkbox), findsNWidgets(3));
  });

  testWidgets('点击复选框切换任务完成样式', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    final Finder firstCheckbox = find.byType(Checkbox).first;
    await tester.tap(firstCheckbox);
    await tester.pump();

    expect(tester.widget<Checkbox>(firstCheckbox).value, isTrue);
    expect(find.text('我的待办 (1/3)'), findsOneWidget);
    Text taskText = tester.widget<Text>(find.text('买菜'));
    expect(taskText.style?.decoration, TextDecoration.lineThrough);
    expect(taskText.style?.color, Colors.grey);

    await tester.tap(firstCheckbox);
    await tester.pump();

    expect(tester.widget<Checkbox>(firstCheckbox).value, isFalse);
    expect(find.text('我的待办 (0/3)'), findsOneWidget);
    taskText = tester.widget<Text>(find.text('买菜'));
    expect(taskText.style?.decoration, TextDecoration.none);
    expect(taskText.style?.color, isNull);
  });

  testWidgets('启动时读取已保存的任务', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {'title': '已保存任务', 'isDone': true},
      ]),
    });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('已保存任务'), findsOneWidget);
    expect(find.text('买菜'), findsNothing);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(find.text('我的待办 (1/1)'), findsOneWidget);
  });

  testWidgets('空列表显示引导提示', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'tasks': '[]'});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('我的待办 (0/0)'), findsOneWidget);
    expect(find.byIcon(Icons.task_alt), findsOneWidget);
    expect(find.text('还没有任务,添加一条吧'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('按回车提交任务并显示提示', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '回车添加');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('回车添加'), findsOneWidget);
    expect(find.text('已添加'), findsOneWidget);
    expect(find.text('我的待办 (0/4)'), findsOneWidget);
  });

  testWidgets('添加、勾选和删除任务后自动保存', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '持久化任务');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    SharedPreferences preferences = await SharedPreferences.getInstance();
    List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.last, {'title': '持久化任务', 'isDone': false});

    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    preferences = await SharedPreferences.getInstance();
    savedTasks = jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.last, {'title': '持久化任务', 'isDone': true});

    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();
    preferences = await SharedPreferences.getInstance();
    savedTasks = jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.where((task) => task['title'] == '持久化任务'), isEmpty);
  });
}
