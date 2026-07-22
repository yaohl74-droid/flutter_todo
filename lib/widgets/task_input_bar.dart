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
    required this.onAddTask,
    required this.onPickDueDate,
    required this.onReminderChanged,
    required this.onShowTrash,
  });

  final TextEditingController controller;
  final DateTime? selectedDueDate;
  final bool reminderEnabled;
  final bool canEnableReminder;
  final Future<void> Function(String input) onAddTask;
  final VoidCallback onPickDueDate;
  final ValueChanged<bool> onReminderChanged;
  final VoidCallback onShowTrash;

  bool get _dueDateIsPast =>
      selectedDueDate != null && !selectedDueDate!.isAfter(DateTime.now());

  /// 提醒开关不可用时的说明：未设日期不提示；已过期提示过期；
  /// 日期有效但平台不支持（Web/Windows/Linux）时说明平台限制，
  /// 避免把“不支持”误显示成“已过期”。
  String? get _reminderDisabledReason {
    if (selectedDueDate == null || canEnableReminder) {
      return null;
    }
    return _dueDateIsPast ? '截止时间已过，无法设置提醒' : '当前平台不支持到期提醒';
  }

  Future<void> _addTask() => onAddTask(controller.text);

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
                    onSubmitted: (_) => _addTask(),
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
                  onPressed: _addTask,
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
            if (_reminderDisabledReason != null)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _reminderDisabledReason!,
                  style: TextStyle(
                    fontSize: 11,
                    // 过期是用户可纠正的错误，标红；平台不支持是客观限制，用中性色。
                    color: _dueDateIsPast ? Colors.red : const Color(0xFF4F6F56),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
