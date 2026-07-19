import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/todo_model.dart';
import '../utils/date_format.dart';

/// 底部录入区；任务写入 Provider，日期和提醒草稿仍由页面 State 持有。
class TaskInputBar extends StatelessWidget {
  const TaskInputBar({
    super.key,
    required this.controller,
    required this.selectedDueDate,
    required this.reminderEnabled,
    required this.canEnableReminder,
    required this.onTaskAdded,
    required this.onPickDueDate,
    required this.onReminderChanged,
    required this.onShowTrash,
  });

  final TextEditingController controller;
  final DateTime? selectedDueDate;
  final bool reminderEnabled;
  final bool canEnableReminder;
  final VoidCallback onTaskAdded;
  final VoidCallback onPickDueDate;
  final ValueChanged<bool> onReminderChanged;
  final VoidCallback onShowTrash;

  bool get _dueDateIsPast =>
      selectedDueDate != null &&
      !selectedDueDate!.isAfter(DateTime.now().toUtc());

  Future<void> _addTask(BuildContext context) async {
    final bool added = await context.read<TodoModel>().addTask(
      title: controller.text,
      dueDate: selectedDueDate,
      reminderEnabled: reminderEnabled,
    );
    if (!added || !context.mounted) {
      return;
    }
    controller.clear();
    onTaskAdded();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已添加')));
  }

  @override
  Widget build(BuildContext context) {
    final int activeDeletedTaskCount = context
        .watch<TodoModel>()
        .activeDeletedTaskCount;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addTask(context),
                    decoration: const InputDecoration(
                      hintText: '请输入任务',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(
                          color: Color(0xFF4F8A5B),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _addTask(context),
                  child: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      key: const ValueKey<String>('trash-button'),
                      tooltip: '回收站',
                      onPressed: onShowTrash,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                    if (activeDeletedTaskCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$activeDeletedTaskCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  key: const ValueKey<String>('due-date-button'),
                  tooltip: '选择截止日期和时间',
                  onPressed: onPickDueDate,
                  icon: const Icon(Icons.calendar_month),
                ),
                Expanded(
                  child: Text(
                    selectedDueDate == null
                        ? '未设置截止时间'
                        : formatDateTime(selectedDueDate!),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4F6F56),
                    ),
                  ),
                ),
                const Text('到期提醒'),
                Switch(
                  key: const ValueKey<String>('new-reminder-switch'),
                  value: reminderEnabled && canEnableReminder,
                  onChanged: canEnableReminder ? onReminderChanged : null,
                ),
              ],
            ),
            if (_dueDateIsPast)
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '截止时间已过，无法设置提醒',
                  style: TextStyle(fontSize: 11, color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
