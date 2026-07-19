// String 只能保存任务文字，无法同时记录任务是否完成。
// 改用 Task 后，每一项任务就能把文字和完成状态放在同一个数据结构中管理。
class Task {
  Task({
    String? id,
    required this.title,
    this.isDone = false,
    DateTime? dueDate,
    this.reminderEnabled = false,
  }) : id = id ?? _generateId(),
       // 内存中始终保存 UTC 绝对时刻，避免设备切换时区后提醒时刻漂移。
       dueDate = dueDate?.toUtc();

  static int _idSequence = 0;

  // 时间戳加递增序号，即使同一微秒创建多个任务也能得到不同 ID。
  static String _generateId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';
  }

  final String id;
  String title;
  bool isDone;
  DateTime? dueDate;
  bool reminderEnabled;

  // 把 Task 转成可被 JSON 编码的 Map，便于保存到本地。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isDone': isDone,
    // 新格式明确以 UTC 保存固定绝对时刻，末尾 Z 可避免跨时区解析歧义。
    'dueDateUtc': dueDate?.toUtc().toIso8601String(),
    'reminderEnabled': reminderEnabled,
  };

  // 从 JSON Map 还原 Task，让保存的数据能重新变成应用中的对象。
  factory Task.fromJson(Map<String, dynamic> json) {
    final String? savedId = json['id']?.toString();
    final String? utcText = json['dueDateUtc']?.toString();
    final DateTime? utcDueDate = DateTime.tryParse(utcText ?? '');
    final DateTime? legacyDueDate = DateTime.tryParse(
      json['dueDate']?.toString() ?? '',
    );

    return Task(
      // 旧版本 JSON 没有 id，此时传入 null，由构造函数自动补一个唯一 ID。
      id: savedId == null || savedId.isEmpty ? null : savedId,
      // 不再强制把 null 转成 String，避免损坏或旧数据导致启动崩溃。
      title: json['title']?.toString() ?? '',
      isDone: json['isDone'] == true,
      // 旧 dueDate 没有时区信息：迁移时按当前设备本地时区解释，再转成 UTC。
      dueDate: utcDueDate ?? legacyDueDate?.toUtc(),
      // 旧任务默认不提醒，避免升级后未经用户确认突然产生通知。
      reminderEnabled: json['reminderEnabled'] == true,
    );
  }
}
