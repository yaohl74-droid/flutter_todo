import 'package:flutter/material.dart';

import '../models/task.dart';

/// 单条任务的纯展示组件；所有修改动作都通过回调交还页面 State。
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.contentKey,
    required this.highlighted,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  final Task task;
  final Key contentKey;
  final bool highlighted;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  String _formatDateTime(DateTime date) {
    final DateTime localDate = date.toLocal();
    final String month = localDate.month.toString().padLeft(2, '0');
    final String day = localDate.day.toString().padLeft(2, '0');
    final String hour = localDate.hour.toString().padLeft(2, '0');
    final String minute = localDate.minute.toString().padLeft(2, '0');
    return '${localDate.year}-$month-$day $hour:$minute';
  }

  bool get _isOverdue {
    if (task.isDone || task.dueDate == null) {
      return false;
    }

    final DateTime localDueDate = task.dueDate!.toLocal();
    final DateTime dueMinute = DateTime(
      localDueDate.year,
      localDueDate.month,
      localDueDate.day,
      localDueDate.hour,
      localDueDate.minute,
    );
    final DateTime now = DateTime.now();
    final DateTime currentMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );

    // 精确到分钟比较；当前分钟内不算过期，进入下一分钟后才标红。
    return dueMinute.isBefore(currentMinute);
  }

  @override
  Widget build(BuildContext context) {
    // Dismissible 使用任务唯一 ID，避免列表更新时复用或删除错误条目。
    return Dismissible(
      key: ValueKey<String>(task.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white, size: 30),
      ),
      child: AnimatedContainer(
        key: contentKey,
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: highlighted
              ? Border.all(color: Colors.amber.shade700, width: 2)
              : null,
        ),
        child: Card(
          margin: EdgeInsets.zero,
          color: highlighted ? const Color(0xFFFFF4C2) : null,
          elevation: 2,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            onTap: onEdit,
            leading: Checkbox(value: task.isDone, onChanged: onToggle),
            title: Text(
              task.title,
              style: TextStyle(
                decoration: task.isDone
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                color: task.isDone ? Colors.grey : null,
              ),
            ),
            subtitle: task.dueDate == null
                ? null
                : Text(
                    '截止日期：${_formatDateTime(task.dueDate!)}',
                    style: TextStyle(
                      color: _isOverdue ? Colors.red : Colors.grey.shade600,
                    ),
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (task.reminderEnabled && !task.isDone)
                  const Tooltip(
                    message: '已开启到期提醒',
                    child: Icon(
                      Icons.notifications_active_outlined,
                      size: 20,
                      color: Color(0xFF4F8A5B),
                    ),
                  ),
                IconButton(
                  tooltip: '删除任务',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
