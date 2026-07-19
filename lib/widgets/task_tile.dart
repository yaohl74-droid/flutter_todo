import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../models/todo_model.dart';
import '../utils/date_format.dart';

/// 单条任务组件；通过 Provider 修改任务，编辑弹窗仍交由页面打开。
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.contentKey,
    required this.highlighted,
    required this.onEdit,
  });

  final Task task;
  final Key contentKey;
  final bool highlighted;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    // Dismissible 使用任务唯一 ID，避免列表更新时复用或删除错误条目。
    return Dismissible(
      key: ValueKey<String>(task.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => context.read<TodoModel>().deleteTask(task),
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
            leading: Checkbox(
              value: task.isDone,
              onChanged: (isDone) =>
                  context.read<TodoModel>().toggleTask(task, isDone),
            ),
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
                    '截止日期：${formatDateTime(task.dueDate!)}',
                    style: TextStyle(
                      color: task.isOverdue ? Colors.red : Colors.grey.shade600,
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
                  onPressed: () => context.read<TodoModel>().deleteTask(task),
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
