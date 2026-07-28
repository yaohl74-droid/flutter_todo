import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_todo/main.dart';
import 'package:my_todo/models/task.dart';
import 'package:my_todo/models/todo_model.dart';
import 'package:my_todo/pages/todo_page.dart';
import 'package:my_todo/services/cloud_settings.dart';
import 'package:my_todo/pages/stats_page.dart';
import 'package:my_todo/services/task_notification_service.dart';
import 'package:my_todo/utils/natural_language_task_parser.dart';

class _MemoryCloudSettingsStore implements CloudSettingsStore {
  _MemoryCloudSettingsStore([this.settings = const CloudSettings()]);

  CloudSettings settings;

  @override
  Future<CloudSettings> read() async => settings;

  @override
  Future<void> write(CloudSettings settings) async {
    this.settings = settings;
  }
}

class _FakeNotificationScheduler implements TaskNotificationScheduler {
  _FakeNotificationScheduler({
    this.isAvailable = false,
    this.permission = true,
  });

  @override
  final bool isAvailable;
  bool permission;
  int permissionRequestCount = 0;
  int settingsOpenCount = 0;
  final List<List<Task>> reconciliations = <List<Task>>[];
  TaskNotificationTapCallback? onTaskSelected;
  String? initialTaskId;

  @override
  Future<String?> initialize({
    required TaskNotificationTapCallback onTaskSelected,
  }) async {
    this.onTaskSelected = onTaskSelected;
    return initialTaskId;
  }

  @override
  Future<void> openNotificationSettings() async {
    settingsOpenCount++;
  }

  @override
  Future<void> reconcile(List<Task> tasks) async {
    reconciliations.add(List<Task>.of(tasks));
  }

  @override
  Future<bool> requestPermissions() async {
    permissionRequestCount++;
    return permission;
  }
}

Widget _buildTestApp({
  _FakeNotificationScheduler? notificationScheduler,
  CloudSettingsStore? cloudSettingsStore,
  CloudTaskResolver? cloudTaskResolver,
}) {
  return MyApp(
    notificationScheduler:
        notificationScheduler ?? _FakeNotificationScheduler(),
    cloudSettingsStore: cloudSettingsStore ?? _MemoryCloudSettingsStore(),
    cloudTaskResolver: cloudTaskResolver,
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
    expect(find.byType(Card), findsNWidgets(3));
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

  testWidgets('快速添加解析标题和截止时间，按钮与回车共用规则', (WidgetTester tester) async {
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler();
    await tester.pumpWidget(_buildTestApp(notificationScheduler: scheduler));
    await tester.pumpAndSettle();

    final DateTime beforeSubmit = DateTime.now();
    await tester.enterText(find.byType(TextField), '明天下午3点开会');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(find.text('开会'), findsOneWidget);
    expect(find.text('明天下午3点开会'), findsNothing);

    await tester.enterText(find.byType(TextField), '后天上午9点写周报');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('写周报'), findsOneWidget);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    final DateTime firstDueDate = DateTime.parse(
      savedTasks[savedTasks.length - 2]['dueDateUtc'] as String,
    ).toLocal();
    final DateTime secondDueDate = DateTime.parse(
      savedTasks.last['dueDateUtc'] as String,
    ).toLocal();
    final DateTime expectedTomorrow = DateTime(
      beforeSubmit.year,
      beforeSubmit.month,
      beforeSubmit.day + 1,
      15,
    );
    final DateTime expectedDayAfterTomorrow = DateTime(
      beforeSubmit.year,
      beforeSubmit.month,
      beforeSubmit.day + 2,
      9,
    );
    expect(firstDueDate, expectedTomorrow);
    expect(secondDueDate, expectedDayAfterTomorrow);
    expect(scheduler.permissionRequestCount, 0);
  });

  testWidgets('明确拒绝时保留整句、无期限添加并提示用户', (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '每周一开会');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(find.text('每周一开会'), findsOneWidget);
    expect(find.text('该时间表达暂不支持，已按无期限任务添加'), findsOneWidget);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.last['dueDateUtc'], isNull);
  });

  testWidgets('本地能定论的拒绝原因绝不调用云端', (WidgetTester tester) async {
    var cloudCalls = 0;
    await tester.pumpWidget(
      _buildTestApp(
        cloudSettingsStore: _MemoryCloudSettingsStore(
          const CloudSettings(enabled: true, apiKey: 'sk-test'),
        ),
        cloudTaskResolver: (input, now, settings) async {
          cloudCalls++;
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    for (final input in <String>['每天晚上8点吃药', '买牛奶', '明早开会']) {
      await tester.enterText(find.byType(TextField).first, input);
      await tester.tap(find.text('添加'));
      await tester.pump();
    }

    expect(cloudCalls, 0);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(
      savedTasks.skip(savedTasks.length - 3).map((task) => task['title']),
      <String>['每天晚上8点吃药', '买牛奶', '明早开会'],
    );
  });

  testWidgets('规则不认识时调用已配置的云端', (WidgetTester tester) async {
    var cloudCalls = 0;
    await tester.pumpWidget(
      _buildTestApp(
        cloudSettingsStore: _MemoryCloudSettingsStore(
          const CloudSettings(enabled: true, apiKey: 'sk-test'),
        ),
        cloudTaskResolver: (input, now, settings) async {
          cloudCalls++;
          expect(input, '下午三点十五分开会');
          expect(settings.isConfigured, isTrue);
          return ParsedTaskInput(
            title: '开会',
            dueDate: DateTime(now.year, now.month, now.day, 15, 15),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '下午三点十五分开会');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(cloudCalls, 1);
    expect(find.text('开会'), findsOneWidget);
    expect(find.text('下午三点十五分开会'), findsNothing);
  });

  testWidgets('云端异常时仍按无期限任务保存原句', (WidgetTester tester) async {
    var cloudCalls = 0;
    await tester.pumpWidget(
      _buildTestApp(
        cloudSettingsStore: _MemoryCloudSettingsStore(
          const CloudSettings(enabled: true, apiKey: 'sk-test'),
        ),
        cloudTaskResolver: (input, now, settings) async {
          cloudCalls++;
          throw StateError('offline');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '下午三点十五分开会');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(cloudCalls, 1);
    expect(find.text('下午三点十五分开会'), findsOneWidget);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.last['title'], '下午三点十五分开会');
    expect(savedTasks.last['dueDateUtc'], isNull);
  });

  testWidgets('云端未开启时只提示一次且主界面保留设置入口', (WidgetTester tester) async {
    final store = _MemoryCloudSettingsStore();
    await tester.pumpWidget(_buildTestApp(cloudSettingsStore: store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '下午三点十五分开会');
    await tester.tap(find.text('添加'));
    await tester.pump();
    expect(find.text('去开启'), findsOneWidget);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '下午三点十五分复盘');
    await tester.tap(find.text('添加'));
    await tester.pump();
    expect(find.text('去开启'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('cloud-settings-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('模型与云端设置'), findsOneWidget);
    expect(find.textContaining('任务文本会发送到第三方服务器'), findsOneWidget);
  });

  testWidgets('解析出的未来时间自动申请权限并开启提醒', (WidgetTester tester) async {
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler(
      isAvailable: true,
    );
    await tester.pumpWidget(_buildTestApp(notificationScheduler: scheduler));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '明天下午3点提醒任务');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(scheduler.permissionRequestCount, 1);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.last['title'], '提醒任务');
    expect(savedTasks.last['reminderEnabled'], isTrue);
  });

  testWidgets('解析提醒权限被拒绝时仍保存任务并关闭提醒', (WidgetTester tester) async {
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler(
      isAvailable: true,
      permission: false,
    );
    await tester.pumpWidget(_buildTestApp(notificationScheduler: scheduler));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '明天下午3点权限任务');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('通知权限未开启'), findsOneWidget);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.last['title'], '权限任务');
    expect(savedTasks.last['reminderEnabled'], isFalse);
  });

  testWidgets('明确今天的过期时间不申请提醒权限', (WidgetTester tester) async {
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler(
      isAvailable: true,
    );
    await tester.pumpWidget(_buildTestApp(notificationScheduler: scheduler));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '今天00:00过期任务');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(scheduler.permissionRequestCount, 0);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.last['title'], '过期任务');
    expect(savedTasks.last['reminderEnabled'], isFalse);
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

  test('截止日期使用 UTC ISO8601 字符串序列化并能还原', () {
    final DateTime dueDate = DateTime(2026, 7, 31);
    final Task task = Task(title: '有截止日期', dueDate: dueDate);

    final Map<String, dynamic> json = task.toJson();
    final Task restoredTask = Task.fromJson(json);

    expect(json['dueDateUtc'], dueDate.toUtc().toIso8601String());
    expect(restoredTask.dueDate, dueDate.toUtc());
    expect(restoredTask.dueDate!.isUtc, isTrue);
    expect(restoredTask.reminderEnabled, isFalse);
  });

  testWidgets('旧截止时间迁移为 UTC 且旧任务默认关闭提醒', (WidgetTester tester) async {
    final DateTime legacyDueDate = DateTime(2026, 8, 20, 9, 30);
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {
          'id': 'legacy-time',
          'title': '旧日期任务',
          'isDone': false,
          'dueDate': legacyDueDate.toIso8601String(),
        },
      ]),
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    final Map<String, dynamic> savedTask = Map<String, dynamic>.from(
      savedTasks.single as Map,
    );
    expect(savedTask.containsKey('dueDate'), isFalse);
    expect(DateTime.parse(savedTask['dueDateUtc'] as String).isUtc, isTrue);
    expect(savedTask['reminderEnabled'], isFalse);
  });

  testWidgets('编辑任务可开启提醒并保存名称', (WidgetTester tester) async {
    final DateTime futureDueDate = DateTime.now()
        .add(const Duration(days: 1))
        .toUtc();
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {
          'id': 'editable',
          'title': '需要提醒',
          'isDone': false,
          'dueDateUtc': futureDueDate.toIso8601String(),
          'reminderEnabled': false,
        },
      ]),
    });
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler(
      isAvailable: true,
    );

    await tester.pumpWidget(_buildTestApp(notificationScheduler: scheduler));
    await tester.pumpAndSettle();
    await tester.tap(find.text('需要提醒'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('edit-reminder-switch')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('edit-task-title')),
      '修改后的任务',
    );
    await tester.tap(find.byKey(const ValueKey<String>('save-edited-task')));
    await tester.pumpAndSettle();

    expect(find.text('修改后的任务'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    expect(scheduler.permissionRequestCount, 1);
    expect(scheduler.reconciliations.last.single.reminderEnabled, isTrue);

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.single['title'], '修改后的任务');
    expect(savedTasks.single['reminderEnabled'], isTrue);
  });

  testWidgets('不支持提醒的平台编辑未来任务显示平台提示而非过期', (WidgetTester tester) async {
    // 默认 fake scheduler 的 isAvailable 为 false，模拟 Web/Windows/Linux。
    final DateTime futureDue = DateTime.now()
        .add(const Duration(days: 1))
        .toUtc();
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {
          'id': 'future-task',
          'title': '未来任务',
          'isDone': false,
          'dueDateUtc': futureDue.toIso8601String(),
          'reminderEnabled': false,
        },
      ]),
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('未来任务'));
    await tester.pumpAndSettle();

    expect(find.text('当前平台不支持到期提醒'), findsOneWidget);
    expect(find.text('截止时间已过，无法设置提醒'), findsNothing);
  });

  testWidgets('编辑已过期任务仍显示过期提示', (WidgetTester tester) async {
    final DateTime pastDue = DateTime.now()
        .subtract(const Duration(days: 1))
        .toUtc();
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {
          'id': 'past-task',
          'title': '过期任务',
          'isDone': false,
          'dueDateUtc': pastDue.toIso8601String(),
          'reminderEnabled': false,
        },
      ]),
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('过期任务'));
    await tester.pumpAndSettle();

    expect(find.text('截止时间已过，无法设置提醒'), findsOneWidget);
    expect(find.text('当前平台不支持到期提醒'), findsNothing);
  });

  testWidgets('不支持提醒的平台选未来日期在录入区显示平台提示', (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('due-date-button')));
    await tester.pumpAndSettle();
    final CalendarDatePicker picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    picker.onDateChanged(DateTime.now().add(const Duration(days: 1)));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();

    expect(find.text('当前平台不支持到期提醒'), findsOneWidget);
    expect(find.text('截止时间已过，无法设置提醒'), findsNothing);
  });

  testWidgets('通知权限拒绝后提醒回退关闭并可前往设置', (WidgetTester tester) async {
    final DateTime futureDueDate = DateTime.now()
        .add(const Duration(days: 1))
        .toUtc();
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {
          'id': 'permission-denied',
          'title': '权限测试',
          'isDone': false,
          'dueDateUtc': futureDueDate.toIso8601String(),
          'reminderEnabled': false,
        },
      ]),
    });
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler(
      isAvailable: true,
      permission: false,
    );

    await tester.pumpWidget(_buildTestApp(notificationScheduler: scheduler));
    await tester.pumpAndSettle();
    await tester.tap(find.text('权限测试'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('edit-reminder-switch')),
    );
    await tester.pumpAndSettle();

    expect(find.text('通知权限未开启'), findsOneWidget);
    await tester.tap(find.text('前往系统设置'));
    await tester.pumpAndSettle();
    expect(scheduler.settingsOpenCount, 1);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey<String>('edit-reminder-switch')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('点击通知会定位并短暂高亮对应任务', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {
          'id': 'notification-target',
          'title': '通知目标任务',
          'isDone': false,
          'dueDateUtc': null,
          'reminderEnabled': false,
        },
      ]),
    });
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler()
      ..initialTaskId = 'notification-target';

    await tester.pumpWidget(_buildTestApp(notificationScheduler: scheduler));
    await tester.pumpAndSettle();

    final Finder taskCard = find.ancestor(
      of: find.text('通知目标任务'),
      matching: find.byType(Card),
    );
    expect(tester.widget<Card>(taskCard).color, const Color(0xFFFFF4C2));

    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<Card>(taskCard).color, isNull);
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

    await tester.enterText(find.byType(TextField), '明天下午3点手动日期任务');
    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(find.text('手动日期任务'), findsOneWidget);
    expect(find.text('明天下午3点手动日期任务'), findsNothing);
    expect(find.text('截止日期：$displayedDateTime'), findsOneWidget);
    expect(find.text(displayedDateTime), findsNothing);

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    final DateTime savedDueDate = DateTime.parse(
      savedTasks.last['dueDateUtc'] as String,
    );
    expect(savedDueDate.second, 0);
    expect(savedDueDate.millisecond, 0);
  });

  testWidgets('新任务选择未来截止时间后默认开启提醒', (WidgetTester tester) async {
    final _FakeNotificationScheduler scheduler = _FakeNotificationScheduler(
      isAvailable: true,
    );
    await tester.pumpWidget(_buildTestApp(notificationScheduler: scheduler));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('due-date-button')));
    await tester.pumpAndSettle();
    final CalendarDatePicker datePicker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    datePicker.onDateChanged(DateTime.now().add(const Duration(days: 1)));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();

    expect(scheduler.permissionRequestCount, 1);
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey<String>('new-reminder-switch')),
          )
          .value,
      isTrue,
    );

    await tester.enterText(find.byType(TextField).first, '默认提醒任务');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.last['reminderEnabled'], isTrue);
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

  testWidgets('从主页进入统计页显示完成率与最近 7 天趋势', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    // 固定为今天正午，避免测试运行时刻不同导致归属日期漂移。
    final DateTime todayNoon = DateTime(now.year, now.month, now.day, 12);
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {
          'id': 'done-today',
          'title': '今天完成',
          'isDone': true,
          'completedAtUtc': todayNoon.toUtc().toIso8601String(),
        },
        // 旧格式已完成任务没有 completedAtUtc：计入完成率，但不计入趋势。
        {'id': 'legacy-done', 'title': '升级前完成', 'isDone': true},
        {'id': 'open', 'title': '未完成', 'isDone': false},
      ]),
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('stats-button')));
    await tester.pumpAndSettle();

    expect(find.text('统计'), findsOneWidget);
    expect(find.text('最近 7 天'), findsOneWidget);
    // 完成率 2/3 ≈ 67%；趋势里只有今天一根非零柱。
    expect(find.byKey(const ValueKey<String>('stats-rate')), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('已完成 2 / 共 3'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('stats-note')), findsOneWidget);
    expect(find.textContaining('不计入趋势'), findsOneWidget);
    for (int index = 0; index < 7; index++) {
      expect(find.byKey(ValueKey<String>('trend-bar-$index')), findsOneWidget);
    }
    expect(find.text('今天'), findsOneWidget);
  });

  testWidgets('统计页柱状图在不同桌面窗口高度下不溢出', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'tasks': jsonEncode([
        {
          'id': 'done-today',
          'title': '今天完成',
          'isDone': true,
          'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
        },
      ]),
    });

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('stats-button')));
    await tester.pumpAndSettle();

    for (final double height in <double>[900, 640, 480]) {
      await tester.binding.setSurfaceSize(Size(1280, height));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '桌面窗口高度 $height 不应触发 RenderFlex 溢出',
      );
      expect(find.byKey(const ValueKey<String>('trend-bar-6')), findsOneWidget);
    }
  });

  testWidgets('没有任务时统计页显示空态', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'tasks': '[]'});

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('stats-button')));
    await tester.pumpAndSettle();

    expect(find.text('还没有任务，暂无统计数据'), findsOneWidget);
    expect(find.text('最近 7 天'), findsNothing);
  });

  testWidgets('勾选后完成时间写入存档，重启后仍进入趋势', (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    // 示例任务均无截止日期，显示顺序即添加顺序，第一个是“买菜”。
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    SharedPreferences preferences = await SharedPreferences.getInstance();
    List<dynamic> savedTasks =
        jsonDecode(preferences.getString('tasks')!) as List<dynamic>;
    expect(savedTasks.first['title'], '买菜');
    expect(savedTasks.first['isDone'], isTrue);
    final String? completedAtUtc =
        savedTasks.first['completedAtUtc'] as String?;
    expect(completedAtUtc, isNotNull);
    expect(DateTime.parse(completedAtUtc!).isUtc, isTrue);

    // 模拟重启：趋势数据必须来自存档而不是内存。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('stats-button')));
    await tester.pumpAndSettle();

    // 今天的柱子计数为 1，其余 6 天为 0；限定在统计页内查找，
    // 避免匹配到仍挂在路由栈里的上一页文本。
    final Finder statsPage = find.byType(StatsPage);
    expect(
      find.descendant(of: statsPage, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: statsPage, matching: find.text('0')),
      findsNWidgets(6),
    );
  });
}
