import 'task.dart';

class DeletedTask {
  const DeletedTask({
    required this.task,
    required this.deletedAt,
    required this.originalIndex,
  });

  final Task task;
  final DateTime deletedAt;
  final int originalIndex;

  Map<String, dynamic> toJson() => {
    'task': task.toJson(),
    'deletedAt': deletedAt.toIso8601String(),
    'originalIndex': originalIndex,
  };

  static DeletedTask? fromJson(Map<String, dynamic> json) {
    final dynamic rawTask = json['task'];
    final DateTime? deletedAt = DateTime.tryParse(
      json['deletedAt']?.toString() ?? '',
    );
    if (rawTask is! Map || deletedAt == null) {
      return null;
    }

    final Task task = Task.fromJson(Map<String, dynamic>.from(rawTask));
    if (task.title.trim().isEmpty) {
      return null;
    }

    final int originalIndex = json['originalIndex'] is int
        ? json['originalIndex'] as int
        : int.tryParse(json['originalIndex']?.toString() ?? '') ?? 0;
    return DeletedTask(
      task: task,
      deletedAt: deletedAt,
      originalIndex: originalIndex < 0 ? 0 : originalIndex,
    );
  }
}
