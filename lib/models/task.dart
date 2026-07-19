// String 只能保存任务文字，无法同时记录任务是否完成。
// 改用 Task 后，每一项任务就能把文字和完成状态放在同一个数据结构中管理。
class Task {
  Task({String? id, required this.title, this.isDone = false, this.dueDate})
    : id = id ?? _generateId();

  static int _idSequence = 0;

  // 时间戳加递增序号，即使同一微秒创建多个任务也能得到不同 ID。
  static String _generateId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';
  }

  final String id;
  final String title;
  bool isDone;
  final DateTime? dueDate;

  // 把 Task 转成可被 JSON 编码的 Map，便于保存到本地。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isDone': isDone,
    // JSON 没有原生 DateTime 类型，因此用 ISO8601 字符串保存；
    // 这种标准格式跨平台一致，也能用 DateTime.tryParse 安全还原。
    'dueDate': dueDate?.toIso8601String(),
  };

  // 从 JSON Map 还原 Task，让保存的数据能重新变成应用中的对象。
  factory Task.fromJson(Map<String, dynamic> json) {
    final String? savedId = json['id']?.toString();

    return Task(
      // 旧版本 JSON 没有 id，此时传入 null，由构造函数自动补一个唯一 ID。
      id: savedId == null || savedId.isEmpty ? null : savedId,
      // 不再强制把 null 转成 String，避免损坏或旧数据导致启动崩溃。
      title: json['title']?.toString() ?? '',
      isDone: json['isDone'] == true,
      // 老数据没有 dueDate 时得到 null；无效日期字符串也安全降级为 null。
      dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? ''),
    );
  }
}
