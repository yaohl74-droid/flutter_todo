import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo/utils/natural_language_task_parser.dart';

void main() {
  group('相对日期', () {
    final DateTime now = DateTime(2026, 7, 20, 12, 34, 56);

    test('今天、明天、后天默认到当天 23:59', () {
      expect(
        parseNaturalLanguageTask('今天整理桌面', now: now)!.dueDate,
        DateTime(2026, 7, 20, 23, 59),
      );
      expect(
        parseNaturalLanguageTask('明天整理桌面', now: now)!.dueDate,
        DateTime(2026, 7, 21, 23, 59),
      );
      expect(
        parseNaturalLanguageTask('后天整理桌面', now: now)!.dueDate,
        DateTime(2026, 7, 22, 23, 59),
      );
    });

    test('明确写今天时保留已经过去的时间', () {
      final ParsedTaskInput result = parseNaturalLanguageTask(
        '今天下午3点复盘',
        now: DateTime(2026, 7, 20, 17),
      )!;

      expect(result.title, '复盘');
      expect(result.dueDate, DateTime(2026, 7, 20, 15));
    });
  });

  group('星期日期', () {
    test('裸周几取本周尚未过去的日期，否则取下周', () {
      final DateTime wednesday = DateTime(2026, 7, 22, 12);
      final Map<String, int> expectedOffsets = <String, int>{
        '周一': 5,
        '周二': 6,
        '周三': 0,
        '周四': 1,
        '周五': 2,
        '周六': 3,
        '周日': 4,
      };

      for (final MapEntry<String, int> entry in expectedOffsets.entries) {
        final ParsedTaskInput result = parseNaturalLanguageTask(
          '${entry.key}做计划',
          now: wednesday,
        )!;
        final DateTime expectedDay = DateTime(
          2026,
          7,
          22,
        ).add(Duration(days: entry.value));
        expect(
          result.dueDate,
          DateTime(
            expectedDay.year,
            expectedDay.month,
            expectedDay.day,
            23,
            59,
          ),
          reason: entry.key,
        );
      }
    });

    test('下周按下一个自然周计算', () {
      final DateTime sunday = DateTime(2026, 7, 26, 10);

      expect(
        parseNaturalLanguageTask('下周一开会', now: sunday)!.dueDate,
        DateTime(2026, 7, 27, 23, 59),
      );
      expect(
        parseNaturalLanguageTask('下周日复盘', now: sunday)!.dueDate,
        DateTime(2026, 8, 2, 23, 59),
      );
    });

    test('今天的裸周几时间已过时推进七天', () {
      final ParsedTaskInput result = parseNaturalLanguageTask(
        '周三下午3点开会',
        now: DateTime(2026, 7, 22, 17),
      )!;

      expect(result.dueDate, DateTime(2026, 7, 29, 15));
    });
  });

  group('时间格式', () {
    final DateTime now = DateTime(2026, 7, 20, 8);

    test('上午、下午和晚上转换为 24 小时制', () {
      expect(
        parseNaturalLanguageTask('上午9点晨会', now: now)!.dueDate,
        DateTime(2026, 7, 20, 9),
      );
      expect(
        parseNaturalLanguageTask('下午3点评审', now: now)!.dueDate,
        DateTime(2026, 7, 20, 15),
      );
      expect(
        parseNaturalLanguageTask('晚上8点运动', now: now)!.dueDate,
        DateTime(2026, 7, 20, 20),
      );
    });

    test('冒号和点分格式保留分钟并清零秒以下字段', () {
      final ParsedTaskInput colon = parseNaturalLanguageTask(
        '15:05提交报告',
        now: now,
      )!;
      final ParsedTaskInput point = parseNaturalLanguageTask(
        '15点30提交报告',
        now: now,
      )!;

      expect(colon.dueDate, DateTime(2026, 7, 20, 15, 5));
      expect(point.dueDate, DateTime(2026, 7, 20, 15, 30));
      expect(point.dueDate.second, 0);
      expect(point.dueDate.millisecond, 0);
      expect(point.dueDate.microsecond, 0);
    });

    test('仅时间已经过去时取明天同一时间', () {
      final ParsedTaskInput result = parseNaturalLanguageTask(
        '下午3点开会',
        now: DateTime(2026, 7, 20, 17),
      )!;

      expect(result.dueDate, DateTime(2026, 7, 21, 15));
    });
  });

  group('组合与标题清理', () {
    final DateTime now = DateTime(2026, 7, 20, 9);

    test('日期和时间组合后只保留正文', () {
      final ParsedTaskInput relative = parseNaturalLanguageTask(
        '明天下午3点开会',
        now: now,
      )!;
      final ParsedTaskInput weekday = parseNaturalLanguageTask(
        '准备  下周三 上午10点',
        now: now,
      )!;

      expect(relative.title, '开会');
      expect(relative.dueDate, DateTime(2026, 7, 21, 15));
      expect(weekday.title, '准备');
      expect(weekday.dueDate, DateTime(2026, 7, 29, 10));
    });

    test('时间词位于正文后方时同样抽走并合并空白', () {
      final ParsedTaskInput result = parseNaturalLanguageTask(
        '提交 报告 明天 15:00',
        now: now,
      )!;

      expect(result.title, '提交 报告');
      expect(result.dueDate, DateTime(2026, 7, 21, 15));
    });

    test('只有时间词时返回空标题，由添加流程拒绝空任务', () {
      expect(parseNaturalLanguageTask('明天下午3点', now: now)!.title, isEmpty);
    });
  });

  group('保守失败', () {
    final DateTime now = DateTime(2026, 7, 20, 9);

    test('没有受支持时间表达式时不解析', () {
      expect(parseNaturalLanguageTask('整理会议记录', now: now), isNull);
      expect(parseNaturalLanguageTask('tomorrow meeting', now: now), isNull);
    });

    test('明确排除的日期表达式整句不解析', () {
      const List<String> unsupported = <String>[
        '每周一开会',
        '月底结账',
        '月初复盘',
        '3月5号开会',
        '3月5日开会',
        '3天后开会',
        '本周一开会',
        '上周一复盘',
        '下下周一开会',
        '星期一开会',
      ];

      for (final String input in unsupported) {
        expect(
          parseNaturalLanguageTask(input, now: now),
          isNull,
          reason: input,
        );
      }
    });

    test('非法或未列出的时间格式不做部分解析', () {
      const List<String> unsupported = <String>[
        '今天上午12点开会',
        '今天下午12点开会',
        '今天晚上5点开会',
        '今天下午3点30开会',
        '今天24:00开会',
        '今天15:60开会',
        '今天15：00开会',
        '今天15点开会',
        '今天3点5开会',
        '今天15点30分开会',
        '今天下午3点整开会',
        '今天下午 3点开会',
        '今天三点开会',
      ];

      for (final String input in unsupported) {
        expect(
          parseNaturalLanguageTask(input, now: now),
          isNull,
          reason: input,
        );
      }
    });

    test('多个日期或时间候选不猜测', () {
      expect(parseNaturalLanguageTask('今天明天开会', now: now), isNull);
      expect(parseNaturalLanguageTask('下午3点晚上8点开会', now: now), isNull);
    });
  });
}
