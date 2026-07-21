import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';

typedef TaskNotificationTapCallback = void Function(String taskId);

/// 页面依赖这个抽象接口，测试可以注入内存实现，不必调用真实系统通知。
abstract interface class TaskNotificationScheduler {
  bool get isAvailable;

  Future<String?> initialize({
    required TaskNotificationTapCallback onTaskSelected,
  });

  Future<bool> requestPermissions();

  Future<void> reconcile(List<Task> tasks);

  Future<void> openNotificationSettings();
}

class TaskNotificationService implements TaskNotificationScheduler {
  TaskNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int applePendingLimit = 64;
  static const String _payloadPrefix = 'task:';
  static const String _channelId = 'task_due_reminders';

  final FlutterLocalNotificationsPlugin _plugin;
  TaskNotificationTapCallback? _onTaskSelected;
  bool _initialized = false;

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  bool get isAvailable => _isSupportedPlatform && _initialized;

  @override
  Future<String?> initialize({
    required TaskNotificationTapCallback onTaskSelected,
  }) async {
    _onTaskSelected = onTaskSelected;
    if (!_isSupportedPlatform) {
      return null;
    }

    try {
      tz_data.initializeTimeZones();
      final bool? initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: IOSInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final String? taskId = _taskIdFromPayload(response.payload);
          if (taskId != null) {
            _onTaskSelected?.call(taskId);
          }
        },
      );
      _initialized = initialized != false;
      if (!_initialized) {
        return null;
      }

      // App 被通知冷启动时，普通点击回调尚未来得及触发，因此单独读取启动载荷。
      final NotificationAppLaunchDetails? launchDetails = await _plugin
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        return _taskIdFromPayload(launchDetails?.notificationResponse?.payload);
      }
    } on Exception {
      // 插件缺失或平台初始化失败时关闭提醒能力，待办主体仍可正常使用。
      _initialized = false;
    }
    return null;
  }

  @override
  Future<bool> requestPermissions() async {
    if (!isAvailable) {
      return false;
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, sound: true) ??
            false;
      }
      return await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    } on Exception {
      return false;
    }
  }

  Future<bool> _hasPermissions() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled() ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final NotificationsEnabledOptions? permissions = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
        return permissions?.isEnabled ?? false;
      }
      final NotificationsEnabledOptions? permissions = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return permissions?.isEnabled ?? false;
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> reconcile(List<Task> tasks) async {
    if (!isAvailable) {
      return;
    }

    try {
      // 只取消本功能仍在等待的通知，不清除已经送达的通知或其他功能的通知。
      final List<PendingNotificationRequest> pending = await _plugin
          .pendingNotificationRequests();
      for (final PendingNotificationRequest request in pending) {
        if (request.payload?.startsWith(_payloadPrefix) ?? false) {
          await _plugin.cancel(id: request.id);
        }
      }

      if (!await _hasPermissions()) {
        return;
      }

      final List<Task> scheduledTasks = eligibleTasks(
        tasks,
        now: DateTime.now(),
        limit: _isApplePlatform ? applePendingLimit : null,
      );
      final Set<int> occupiedIds = <int>{};
      for (final Task task in scheduledTasks) {
        int notificationId = _notificationId(task.id);
        while (!occupiedIds.add(notificationId)) {
          notificationId = notificationId == 0x7fffffff
              ? 1
              : notificationId + 1;
        }

        await _plugin.zonedSchedule(
          id: notificationId,
          title: '任务到期',
          body: task.title,
          payload: '$_payloadPrefix${task.id}',
          // UTC 时区表示固定绝对时刻；设备旅行后不会按新的墙上时间重算。
          scheduledDate: tz.TZDateTime.from(task.dueDate!.toUtc(), tz.UTC),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              '任务到期提醒',
              channelDescription: '在待办任务截止时显示提醒',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              groupKey: 'todo_due_tasks',
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
              threadIdentifier: 'todo_due_tasks',
            ),
            macOS: DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
              threadIdentifier: 'todo_due_tasks',
            ),
          ),
          // 用户接受分钟级提醒，不申请 Android 精确闹钟权限。
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } on Exception {
      // 调度失败不能影响任务保存和页面操作，下次恢复前台时会再次对账。
    }
  }

  @override
  Future<void> openNotificationSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } on Exception {
      // 系统不支持通知专页时退回应用设置页。
      try {
        await AppSettings.openAppSettings();
      } on Exception {
        // 设置页也无法打开时保持当前页面，不影响待办操作。
      }
    }
  }

  bool get _isApplePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// 返回未来、未完成且已开启提醒的任务，并按到期时刻取最近若干条。
  @visibleForTesting
  static List<Task> eligibleTasks(
    List<Task> tasks, {
    required DateTime now,
    int? limit,
  }) {
    final List<Task> result =
        tasks.where((task) => task.isEligibleForReminderAt(now)).toList()
          ..sort((first, second) => first.dueDate!.compareTo(second.dueDate!));
    if (limit != null && result.length > limit) {
      return result.sublist(0, limit);
    }
    return result;
  }

  static String? _taskIdFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(_payloadPrefix)) {
      return null;
    }
    final String id = payload.substring(_payloadPrefix.length);
    return id.isEmpty ? null : id;
  }

  // FNV-1a 生成稳定的 31 位通知 ID；极少数碰撞在本轮调度中线性避让。
  static int _notificationId(String taskId) {
    int hash = 0x811c9dc5;
    for (final int codeUnit in taskId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
