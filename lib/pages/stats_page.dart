import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/todo_model.dart';

/// 统计页：展示任务完成率与最近 7 天的完成趋势。
/// 页面本身不持有状态，全部读取 TodoModel 的派生数据，任务变化时随 watch 刷新。
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  // 与主题种子色一致的低饱和度绿色。
  static const Color _barColor = Color(0xFF6F9D7A);
  static const Color _emptyBarColor = Color(0xFFDCE9DE);
  static const double _maxBarHeight = 120;
  static const String _noteText =
      '注：统计功能上线前完成的任务没有记录完成时间，会计入完成率，但不计入趋势。';

  static const List<String> _weekdayLabels = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) {
    final TodoModel todoModel = context.watch<TodoModel>();
    final bool hasTasks = todoModel.tasks.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      // 宽屏（Web/桌面）下把内容限制在 640 宽并水平居中，避免卡片铺满
      // 整个窗口、右边缘被截断；窄屏（手机）可用宽度不足 640，自然保持铺满。
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: hasTasks
                      ? _buildCompletionRate(todoModel)
                      : const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              '还没有任务，暂无统计数据',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF66806C),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              if (hasTasks) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildTrend(todoModel),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionRate(TodoModel todoModel) {
    final int percent = (todoModel.completionRate * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: todoModel.completionRate,
                strokeWidth: 8,
                backgroundColor: _emptyBarColor,
                valueColor: const AlwaysStoppedAnimation<Color>(_barColor),
              ),
              Center(
                child: Text(
                  '$percent%',
                  key: const ValueKey<String>('stats-rate'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF294E32),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('任务完成率', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              '已完成 ${todoModel.completedCount} / 共 ${todoModel.tasks.length}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF4F6F56)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrend(TodoModel todoModel) {
    final List<CompletionDay> trend = todoModel.completionTrend;
    final int maxCount = trend.fold<int>(
      0,
      (maxSoFar, day) => day.count > maxSoFar ? day.count : maxSoFar,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '最近 7 天',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        // 固定图表区高度：柱高按当天完成数占 7 天峰值的比例缩放。
        SizedBox(
          height: _maxBarHeight + 46,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int index = 0; index < trend.length; index++)
                _buildBar(
                  trend[index],
                  index,
                  maxCount,
                  isToday: index == trend.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          _noteText,
          key: ValueKey<String>('stats-note'),
          style: TextStyle(fontSize: 11, color: Color(0xFF66806C)),
        ),
      ],
    );
  }

  Widget _buildBar(
    CompletionDay entry,
    int index,
    int maxCount, {
    required bool isToday,
  }) {
    final double barHeight;
    if (entry.count == 0 || maxCount == 0) {
      // 全零时留一条浅灰底线，避免图表看起来像没渲染出来。
      barHeight = 2;
    } else {
      // 非零柱最低 24，保证只完成 1 件也看得出高度。
      barHeight = 24 + (_maxBarHeight - 24) * entry.count / maxCount;
    }

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '${entry.count}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF4F6F56)),
          ),
          const SizedBox(height: 4),
          Container(
            key: ValueKey<String>('trend-bar-$index'),
            width: 18,
            height: barHeight,
            decoration: BoxDecoration(
              color: entry.count == 0 ? _emptyBarColor : _barColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // DateTime.weekday 从周一=1 开始，正好对应标签表。
            isToday ? '今天' : _weekdayLabels[entry.day.weekday - 1],
            style: const TextStyle(fontSize: 11, color: Color(0xFF4F6F56)),
          ),
        ],
      ),
    );
  }
}
