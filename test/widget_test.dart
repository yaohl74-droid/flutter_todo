import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_todo/main.dart';
import 'package:my_todo/models/task.dart';
import 'package:my_todo/pages/todo_page.dart';
import 'package:my_todo/services/quote_service.dart';

class _FakeQuoteService extends QuoteService {
  _FakeQuoteService(this._fetcher);

  final Future<Quote> Function(int callCount) _fetcher;
  int callCount = 0;
  bool isDisposed = false;

  @override
  Future<Quote> fetchQuote() => _fetcher(++callCount);

  @override
  void dispose() {
    isDisposed = true;
    super.dispose();
  }
}

Widget _buildTestApp({_FakeQuoteService? quoteService}) {
  return MyApp(
    quoteService:
        quoteService ??
        _FakeQuoteService(
          (_) async => const Quote(content: '测试名言', author: '测试作者'),
        ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('显示待办清单', (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('我的待办 (0/3)'), findsOneWidget);
    expect(find.text('买菜'), findsOneWidget);
    expect(find.text('写代码'), findsOneWidget);
    expect(find.text('跑步'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.byType(Card), findsNWidgets(4));
    expect(find.byType(Dismissible), findsNWidgets(3));
    expect(find.text('排序：按截止日期（升序）'), findsOneWidget);
    expect(find.byType(PopupMenuButton<TaskSortOrder>), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuButton<TaskSortOrder>>(
            find.byType(PopupMenuButton<TaskSortOrder>),
          )
          .initialValue,
      TaskSortOrder.dueDate,
    );

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
    await tester.pumpWidget(_buildTestApp());

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
    await tester.pumpWidget(_buildTestApp());

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(find.byType(Checkbox), findsNWidgets(3));
  });

  testWidgets('点击复选框切换任务完成样式', (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestApp());

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

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('已保存任务'), findsOneWidget);
    expect(find.text('买菜'), findsNothing);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(find.text('我的待办 (1/1)'), findsOneWidget);
  });

  testWidgets('空列表显示引导提示', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'tasks': '[]'});

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('我的待办 (0/0)'), findsOneWidget);
    expect(find.byIcon(Icons.task_alt), findsOneWidget);
    expect(find.text('还没有任务,添加一条吧'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('daily-quote-card')),
      findsOneWidget,
    );
    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets('按回车提交任务并显示提示', (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '回车添加');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('回车添加'), findsOneWidget);
    expect(find.text('已添加'), findsOneWidget);
    expect(find.text('我的待办 (0/4)'), findsOneWidget);
  });

  testWidgets('添加、勾选和删除任务后自动保存', (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestApp());
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
    final List<dynamic> deletedTasks =
        jsonDecode(preferences.getString('deleted_tasks')!) as List<dynamic>;
    expect(deletedTasks.single['task']['title'], '持久化任务');
  });

  testWidgets('左滑删除进入回收站并可恢复原位置', (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('买菜'), findsNothing);
    expect(find.text('撤销'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('trash-button')));
    await tester.pumpAndSettle();
    expect(find.text('回收站（保留 7 天）'), findsOneWidget);
    expect(find.text('买菜'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '恢复'));
    await tester.pumpAndSettle();

    expect(find.text('买菜'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('买菜')).dy,
      lessThan(tester.getTopLeft(find.text('写代码')).dy),
    );

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.first['title'], '买菜');
    final List<dynamic> deletedTasks =
        jsonDecode(preferences.getString('deleted_tasks')!) as List<dynamic>;
    expect(deletedTasks, isEmpty);
  });

  testWidgets('回收站自动清理超过七天的任务', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'tasks': '[]',
      'deleted_tasks': jsonEncode([
        {
          'task': {'id': 'expired', 'title': '八天前删除', 'isDone': false},
          'deletedAt': now.subtract(const Duration(days: 8)).toIso8601String(),
          'originalIndex': 0,
        },
        {
          'task': {'id': 'recent', 'title': '一天前删除', 'isDone': false},
          'deletedAt': now.subtract(const Duration(days: 1)).toIso8601String(),
          'originalIndex': 0,
        },
      ]),
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('trash-button')));
    await tester.pumpAndSettle();

    expect(find.text('八天前删除'), findsNothing);
    expect(find.text('一天前删除'), findsOneWidget);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> deletedTasks =
        jsonDecode(preferences.getString('deleted_tasks')!) as List<dynamic>;
    expect(deletedTasks, hasLength(1));
    expect(deletedTasks.single['task']['title'], '一天前删除');
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
    await tester.pumpWidget(_buildTestApp());
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

    await tester.pumpWidget(_buildTestApp());
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

  testWidgets('按截止日期显示且不改变任务原始顺序', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'task_sort_order': 'dueDate',
      'tasks': jsonEncode([
        {'id': 'no-date', 'title': '无日期', 'isDone': false},
        {
          'id': 'later',
          'title': '较晚到期',
          'isDone': false,
          'dueDate': '2026-08-20T10:00:00.000',
        },
        {
          'id': 'earlier',
          'title': '较早到期',
          'isDone': false,
          'dueDate': '2026-08-10T10:00:00.000',
        },
      ]),
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('排序：按截止日期（升序）'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('较早到期')).dy,
      lessThan(tester.getTopLeft(find.text('较晚到期')).dy),
    );
    expect(
      tester.getTopLeft(find.text('较晚到期')).dy,
      lessThan(tester.getTopLeft(find.text('无日期')).dy),
    );

    // 勾选当前显示的第一项会触发保存，JSON 顺序仍应是原始添加顺序。
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.map((task) => task['title']), ['无日期', '较晚到期', '较早到期']);

    await tester.tap(
      find.byKey(const ValueKey<String>('sort-direction-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('排序：按截止日期（降序）'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('较晚到期')).dy,
      lessThan(tester.getTopLeft(find.text('较早到期')).dy),
    );
    expect(
      tester.getTopLeft(find.text('较早到期')).dy,
      lessThan(tester.getTopLeft(find.text('无日期')).dy),
    );
    expect(preferences.getBool('task_sort_ascending'), isFalse);

    // 模拟重启页面，已保存的降序偏好应自动恢复。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();
    expect(find.text('排序：按截止日期（降序）'), findsOneWidget);
  });

  testWidgets('切换完成状态排序并持久化偏好', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {'id': 'done', 'title': '已完成任务', 'isDone': true},
        {'id': 'open', 'title': '未完成任务', 'isDone': false},
      ]),
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<TaskSortOrder>));
    await tester.pumpAndSettle();
    expect(find.text('按添加顺序'), findsOneWidget);
    expect(find.text('按截止日期'), findsOneWidget);
    expect(find.text('按完成状态'), findsOneWidget);

    final Finder completionMenuItem = find.byWidgetPredicate(
      (Widget widget) =>
          widget is CheckedPopupMenuItem<TaskSortOrder> &&
          widget.value == TaskSortOrder.completion,
    );
    await tester.tap(completionMenuItem);
    await tester.pumpAndSettle();

    expect(find.text('排序：按完成状态（升序）'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('未完成任务')).dy,
      lessThan(tester.getTopLeft(find.text('已完成任务')).dy),
    );

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('task_sort_order'), 'completion');
  });

  testWidgets('兼容字符串旧存档并跳过缺少标题的记录', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        '字符串旧任务',
        {'isDone': true},
        {'title': '有效旧任务', 'isDone': true},
      ]),
    });

    await tester.pumpWidget(_buildTestApp());
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

  testWidgets('每日一句加载成功并可手动刷新', (WidgetTester tester) async {
    final Completer<Quote> firstRequest = Completer<Quote>();
    final _FakeQuoteService service = _FakeQuoteService((int callCount) {
      if (callCount == 1) {
        return firstRequest.future;
      }
      return Future<Quote>.value(const Quote(content: '刷新后的名言', author: '新作者'));
    });

    await tester.pumpWidget(_buildTestApp(quoteService: service));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    firstRequest.complete(const Quote(content: '第一条名言', author: '作者甲'));
    await tester.pumpAndSettle();
    expect(find.text('“第一条名言”'), findsOneWidget);
    expect(find.text('—— 作者甲'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('refresh-quote-button')),
    );
    await tester.pumpAndSettle();
    expect(service.callCount, 2);
    expect(find.text('“刷新后的名言”'), findsOneWidget);
    expect(find.text('—— 新作者'), findsOneWidget);
  });

  testWidgets('非超时网络异常也会自动重连三次', (WidgetTester tester) async {
    final _FakeQuoteService service = _FakeQuoteService(
      (_) => Future<Quote>.error(const QuoteException('网络异常')),
    );

    await tester.pumpWidget(_buildTestApp(quoteService: service));
    await tester.pump();
    expect(find.text('正在联网获取名言,请稍等'), findsOneWidget);

    for (int retry = 1; retry <= 3; retry++) {
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(service.callCount, retry + 1);
    }

    expect(find.text('无法连接,无法显示名言'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('超时后每分钟重连且三次失败后停止', (WidgetTester tester) async {
    final _FakeQuoteService service = _FakeQuoteService(
      (_) => Future<Quote>.error(const QuoteTimeoutException()),
    );

    await tester.pumpWidget(_buildTestApp(quoteService: service));
    await tester.pump();
    expect(find.text('正在联网获取名言,请稍等'), findsOneWidget);
    expect(service.callCount, 1);

    for (int retry = 1; retry <= 3; retry++) {
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(service.callCount, retry + 1);
    }

    expect(find.text('无法连接,无法显示名言'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    expect(service.callCount, 4);
  });

  testWidgets('手动刷新会取消等待中的重连并重置计数', (WidgetTester tester) async {
    final _FakeQuoteService service = _FakeQuoteService(
      (_) => Future<Quote>.error(const QuoteTimeoutException()),
    );

    await tester.pumpWidget(_buildTestApp(quoteService: service));
    await tester.pump();
    expect(service.callCount, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('refresh-quote-button')),
    );
    await tester.pump();
    expect(service.callCount, 2);

    // 60 秒后只触发手动刷新创建的新 Timer，旧 Timer 已被取消。
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(service.callCount, 3);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(service.isDisposed, isTrue);
    await tester.pump(const Duration(seconds: 60));
    expect(service.callCount, 3);
  });
}
