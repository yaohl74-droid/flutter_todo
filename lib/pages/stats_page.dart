import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/todo_model.dart';

/// 统计页：展示任务完成率与最近 7 天的完成趋势。
///
/// 宽窗口采用左右分栏，窄窗口采用上下分栏；两种布局都会占满页面可用区域。
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  static const Color _barColor = Color(0xFF6F9D7A);
  static const Color _emptyBarColor = Color(0xFFDCE9DE);
  static const Color _secondaryTextColor = Color(0xFF4F6F56);
  static const String _noteText = '注：统计功能上线前完成的任务没有记录完成时间，会计入完成率，但不计入趋势。';

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

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double padding = constraints.maxWidth >= 1100 ? 24 : 16;
            if (todoModel.tasks.isEmpty) {
              return Padding(
                padding: EdgeInsets.all(padding),
                child: const SizedBox.expand(
                  child: Card(
                    child: Center(
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
              );
            }

            final Widget rateCard = Card(
              key: const ValueKey<String>('stats-rate-card'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: _buildCompletionRate(todoModel),
              ),
            );
            final Widget trendCard = Card(
              key: const ValueKey<String>('stats-trend-card'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: _buildTrend(todoModel),
              ),
            );

            return Padding(
              padding: EdgeInsets.all(padding),
              child: constraints.maxWidth >= 760
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: rateCard),
                        SizedBox(width: padding),
                        Expanded(flex: 7, child: trendCard),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 2, child: rateCard),
                        SizedBox(height: padding),
                        Expanded(flex: 5, child: trendCard),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompletionRate(TodoModel todoModel) {
    final int percent = (todoModel.completionRate * 100).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double indicatorSize = constraints.biggest.shortestSide.clamp(
          72.0,
          132.0,
        );
        final Widget indicator = SizedBox.square(
          dimension: indicatorSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: todoModel.completionRate,
                strokeWidth: indicatorSize >= 100 ? 11 : 8,
                backgroundColor: _emptyBarColor,
                valueColor: const AlwaysStoppedAnimation<Color>(_barColor),
              ),
              Center(
                child: Text(
                  '$percent%',
                  key: const ValueKey<String>('stats-rate'),
                  style: TextStyle(
                    fontSize: indicatorSize >= 100 ? 24 : 17,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF294E32),
                  ),
                ),
              ),
            ],
          ),
        );
        final Widget summary = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '任务完成率',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '已完成 ${todoModel.completedCount} / 共 ${todoModel.tasks.length}',
              style: const TextStyle(fontSize: 14, color: _secondaryTextColor),
            ),
          ],
        );

        if (constraints.maxWidth < 280) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [indicator, const SizedBox(height: 16), summary],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            indicator,
            const SizedBox(width: 24),
            Flexible(child: summary),
          ],
        );
      },
    );
  }

  Widget _buildTrend(TodoModel todoModel) {
    final List<CompletionDay> trend = todoModel.completionTrend;
    final int maxCount = trend.fold<int>(
      0,
      (maxSoFar, day) => day.count > maxSoFar ? day.count : maxSoFar,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '最近 7 天',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
        const SizedBox(height: 12),
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
    final double heightFactor = entry.count == 0 || maxCount == 0
        ? 0.015
        : 0.16 + 0.84 * entry.count / maxCount;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          children: [
            Text(
              '${entry.count}',
              style: const TextStyle(fontSize: 12, color: _secondaryTextColor),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: heightFactor,
                  child: Container(
                    key: ValueKey<String>('trend-bar-$index'),
                    width: 28,
                    decoration: BoxDecoration(
                      color: entry.count == 0 ? _emptyBarColor : _barColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isToday ? '今天' : _weekdayLabels[entry.day.weekday - 1],
              style: const TextStyle(fontSize: 12, color: _secondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }
}
