import 'package:flutter/material.dart';

/// 底部录入区的纯展示组件；输入值、日期和提醒状态均由页面 State 持有。
class TaskInputBar extends StatelessWidget {
  const TaskInputBar({
    super.key,
    required this.controller,
    required this.selectedDueDate,
    required this.reminderEnabled,
    required this.canEnableReminder,
    required this.activeDeletedTaskCount,
    required this.onAdd,
    required this.onPickDueDate,
    required this.onReminderChanged,
    required this.onShowTrash,
  });

  final TextEditingController controller;
  final DateTime? selectedDueDate;
  final bool reminderEnabled;
  final bool canEnableReminder;
  final int activeDeletedTaskCount;
  final VoidCallback onAdd;
  final VoidCallback onPickDueDate;
  final ValueChanged<bool> onReminderChanged;
  final VoidCallback onShowTrash;

  String _formatDateTime(DateTime date) {
    final DateTime localDate = date.toLocal();
    final String month = localDate.month.toString().padLeft(2, '0');
    final String day = localDate.day.toString().padLeft(2, '0');
    final String hour = localDate.hour.toString().padLeft(2, '0');
    final String minute = localDate.minute.toString().padLeft(2, '0');
    return '${localDate.year}-$month-$day $hour:$minute';
  }

  bool get _dueDateIsPast =>
      selectedDueDate != null &&
      !selectedDueDate!.isAfter(DateTime.now().toUtc());

  @override
  Widget build(BuildContext context) {
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
                    onSubmitted: (_) => onAdd(),
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
                ElevatedButton(onPressed: onAdd, child: const Text('添加')),
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
                        : _formatDateTime(selectedDueDate!),
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
