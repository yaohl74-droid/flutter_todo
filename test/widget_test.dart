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
    await tester.pumpAndSettle();

    expect(find.text('我的待办 (0/3)'), findsOneWidget);
    expect(find.text('买菜'), findsOneWidget);
    expect(find.text('写代码'), findsOneWidget);
    expect(find.text('跑步'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.byType(Card), findsNWidgets(3));
    expect(find.byType(Dismissible), findsNWidgets(3));

    final Iterable<Key?> dismissibleKeys = tester
        .widgetList<Dismissible>(find.byType(Dismissible))
        .map((widget) => widget.key);
    expect(dismissibleKeys.toSet(), hasLength(3));

    // 首次启动虽然展示的是内置示例，也必须立即写入本地存档。
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks, hasLength(3));
    expect(savedTasks.map((task) => task['title']), ['买菜', '写代码', '跑步']);
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
    expect(savedTasks.last, containsPair('title', '持久化任务'));
    expect(savedTasks.last, containsPair('isDone', false));
    expect(savedTasks.last['id'], isNotEmpty);

    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    preferences = await SharedPreferences.getInstance();
    savedTasks = jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.last, containsPair('title', '持久化任务'));
    expect(savedTasks.last, containsPair('isDone', true));

    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();
    preferences = await SharedPreferences.getInstance();
    savedTasks = jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.where((task) => task['title'] == '持久化任务'), isEmpty);
  });

  testWidgets('左滑删除后可撤销并恢复原位置', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    // 等待异步保存结束，以及 SnackBar 的入场动画完成。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('买菜'), findsNothing);
    expect(find.text('已删除 买菜'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();

    expect(find.text('买菜'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('买菜')).dy,
      lessThan(tester.getTopLeft(find.text('写代码')).dy),
    );

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.first['title'], '买菜');
  });

  test('旧版 JSON 没有 id 时自动补全并可再次序列化', () {
    final Task task = Task.fromJson({'title': '旧任务', 'isDone': false});

    expect(task.id, isNotEmpty);
    expect(task.dueDate, isNull);
    expect(task.toJson()['id'], task.id);
  });

  test('截止日期使用 ISO8601 字符串序列化并能还原', () {
    final DateTime dueDate = DateTime(2026, 7, 31);
    final Task task = Task(title: '有截止日期', dueDate: dueDate);

    final Map<String, dynamic> json = task.toJson();
    final Task restoredTask = Task.fromJson(json);

    expect(json['dueDate'], dueDate.toIso8601String());
    expect(restoredTask.dueDate, dueDate);
  });

  testWidgets('选择截止日期和时间后显示并随新任务保存', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('due-date-button')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();

    final Finder selectedDateTime = find.textContaining(
      RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$'),
    );
    expect(selectedDateTime, findsOneWidget);
    final String displayedDateTime = tester
        .widget<Text>(selectedDateTime)
        .data!;

    await tester.enterText(find.byType(TextField), '今天到期');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(find.text('截止日期：$displayedDateTime'), findsOneWidget);
    expect(find.text(displayedDateTime), findsNothing);

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    final DateTime savedDueDate = DateTime.parse(
      savedTasks.last['dueDate'] as String,
    );
    expect(savedDueDate.second, 0);
    expect(savedDueDate.millisecond, 0);
  });

  testWidgets('已过期且未完成的日期显示红色', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final DateTime yesterday = DateTime(now.year, now.month, now.day - 1);
    final DateTime twoDaysAgo = DateTime(now.year, now.month, now.day - 2);
    String formatDateTime(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {
          'id': 'overdue-open',
          'title': '未完成过期任务',
          'isDone': false,
          'dueDate': yesterday.toIso8601String(),
        },
        {
          'id': 'overdue-done',
          'title': '已完成过期任务',
          'isDone': true,
          'dueDate': twoDaysAgo.toIso8601String(),
        },
      ]),
    });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final Text openDate = tester.widget<Text>(
      find.text('截止日期：${formatDateTime(yesterday)}'),
    );
    final Text doneDate = tester.widget<Text>(
      find.text('截止日期：${formatDateTime(twoDaysAgo)}'),
    );
    expect(openDate.style?.color, Colors.red);
    expect(doneDate.style?.color, isNot(Colors.red));
  });

  testWidgets('兼容字符串旧存档并跳过缺少标题的记录', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        '字符串旧任务',
        {'isDone': true},
        {'title': '有效旧任务', 'isDone': true},
      ]),
    });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('字符串旧任务'), findsOneWidget);
    expect(find.text('有效旧任务'), findsOneWidget);
    expect(find.text('我的待办 (1/2)'), findsOneWidget);

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> migratedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(migratedTasks, hasLength(2));
    expect(migratedTasks.every((task) => task['id'] != null), isTrue);
  });
}
