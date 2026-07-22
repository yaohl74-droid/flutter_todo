import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo/models/task.dart';
import 'package:my_todo/services/task_notification_service.dart';

/// 假的 macOS 平台实现：不碰真实 MethodChannel，initialize 直接回固定值，
/// 用来复现“插件把权限授予结果当 initialize 回值”这一 macOS 行为。
class _FakeMacOSNotifications extends MacOSFlutterLocalNotificationsPlugin {
  _FakeMacOSNotifications(this.initializeResult);

  final bool? initializeResult;

  @override
  Future<bool?> initialize({
    required DarwinInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async => initializeResult;

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async =>
      const NotificationAppLaunchDetails(false);
}

/// 假的 iOS 平台实现：iOS 的 initialize 回值是真正的初始化结果，对照用。
class _FakeIOSNotifications extends IOSFlutterLocalNotificationsPlugin {
  _FakeIOSNotifications(this.initializeResult);

  final bool? initializeResult;

  @override
  Future<bool?> initialize({
    required DarwinInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => initializeResult;

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async =>
      const NotificationAppLaunchDetails(false);
}

/// 中性假实现：只继承平台基类，resolve<任何具体平台插件> 都返回 null，
/// 正好模拟“该平台未注册插件 → initialize 回 null”（Android 用例走这条）。
class _NeutralFakeNotifications extends FlutterLocalNotificationsPlatform {}

/// 在指定平台下跑真实 TaskNotificationService.initialize，注入假平台实现，
/// 结束后恢复平台覆盖。注意：不能读 FlutterLocalNotificationsPlatform.instance
/// 来“保存原值”——测试环境里该 late 字段从未注册，读它会抛
/// LateInitializationError；恢复时只写一个中性假兜底（写不读，不会抛）。
Future<void> _runInitializeOn(
  TargetPlatform platform, {
  bool? initializeResult,
  required Future<void> Function(TaskNotificationService service) body,
}) async {
  final TargetPlatform? previousPlatform = debugDefaultTargetPlatformOverride;
  if (platform == TargetPlatform.macOS) {
    FlutterLocalNotificationsPlatform.instance =
        _FakeMacOSNotifications(initializeResult);
  } else if (platform == TargetPlatform.iOS) {
    FlutterLocalNotificationsPlatform.instance =
        _FakeIOSNotifications(initializeResult);
  } else {
    FlutterLocalNotificationsPlatform.instance = _NeutralFakeNotifications();
  }
  debugDefaultTargetPlatformOverride = platform;
  try {
    final TaskNotificationService service = TaskNotificationService();
    await service.initialize(onTaskSelected: (_) {});
    await body(service);
  } finally {
    debugDefaultTargetPlatformOverride = previousPlatform;
    FlutterLocalNotificationsPlatform.instance = _NeutralFakeNotifications();
  }
}

void main() {
  group('TaskNotificationService.initialize 对平台回值的判读', () {
    test('macOS：initialize 回 false 仍视为可用（回值实为权限结果）', () async {
      await _runInitializeOn(
        TargetPlatform.macOS,
        initializeResult: false,
        body: (service) async {
          expect(service.isAvailable, isTrue);
        },
      );
    });

    test('iOS：initialize 回 false 视为不可用（回值是初始化结果）', () async {
      await _runInitializeOn(
        TargetPlatform.iOS,
        initializeResult: false,
        body: (service) async {
          expect(service.isAvailable, isFalse);
        },
      );
    });

    test('Android：initialize 回 null 视为可用', () async {
      await _runInitializeOn(
        TargetPlatform.android,
        initializeResult: null,
        body: (service) async {
          expect(service.isAvailable, isTrue);
        },
      );
    });
  });

  group('TaskNotificationService.eligibleTasks', () {
    final DateTime now = DateTime.utc(2026, 7, 19, 4);

    test('只保留未来、未完成且已开启提醒的任务', () {
      final List<Task> result = TaskNotificationService.eligibleTasks([
        Task(
          title: '有效提醒',
          dueDate: now.add(const Duration(hours: 2)),
          reminderEnabled: true,
        ),
        Task(title: '未开启提醒', dueDate: now.add(const Duration(hours: 1))),
        Task(
          title: '已经完成',
          dueDate: now.add(const Duration(hours: 1)),
          reminderEnabled: true,
          isDone: true,
        ),
        Task(
          title: '已经过期',
          dueDate: now.subtract(const Duration(minutes: 1)),
          reminderEnabled: true,
        ),
        Task(title: '没有日期', reminderEnabled: true),
      ], now: now);

      expect(result.map((task) => task.title), ['有效提醒']);
    });

    test('按到期时间选择最近 64 条', () {
      final List<Task> tasks = List<Task>.generate(
        70,
        (index) => Task(
          title: '任务 $index',
          dueDate: now.add(Duration(minutes: 70 - index)),
          reminderEnabled: true,
        ),
      );

      final List<Task> result = TaskNotificationService.eligibleTasks(
        tasks,
        now: now,
        limit: TaskNotificationService.applePendingLimit,
      );

      expect(result, hasLength(64));
      expect(result.first.title, '任务 69');
      expect(result.last.title, '任务 6');
    });
  });
}
