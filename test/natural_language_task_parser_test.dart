import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo/utils/natural_language_task_parser.dart';

void main() {
  group('明确拒绝 vs 未识别', () {
    test('明确拒绝的表达返回 true', () {
      for (final String input in <String>[
        '每天晚上8点吃药',
        '每周一开会',
        '三月一号交房租',
        '2月15号体检',
        '这个礼拜三开会',
        '下下周一开会',
        '月底结账',
        '3天后开会',
        '明早开会',
      ]) {
        expect(hasUnsupportedTimeExpression(input), isTrue, reason: input);
      }
    });

    test('未识别和正常可解析的表达返回 false', () {
      for (final String input in <String>[
        '整理会议记录',
        '买牛奶',
        '明天下午3点开会',
        '明早九点开会',
        '周三体检',
        '三天后交周报',
      ]) {
        expect(hasUnsupportedTimeExpression(input), isFalse, reason: input);
      }
    });
  });

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

    test('大后天按三天后解析且不影响后天', () {
      final ParsedTaskInput threeDaysLater = parseNaturalLanguageTask(
        '大后天整理桌面',
        now: now,
      )!;
      final ParsedTaskInput dayAfterTomorrow = parseNaturalLanguageTask(
        '后天整理桌面',
        now: now,
      )!;

      expect(threeDaysLater.title, '整理桌面');
      expect(threeDaysLater.dueDate, DateTime(2026, 7, 23, 23, 59));
      expect(dayAfterTomorrow.title, '整理桌面');
      expect(dayAfterTomorrow.dueDate, DateTime(2026, 7, 22, 23, 59));
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

    test('下个周、星期和礼拜按下一个自然周计算', () {
      final DateTime monday = DateTime(2026, 7, 20, 9);
      final Map<String, DateTime> cases = <String, DateTime>{
        '下个周三评审': DateTime(2026, 7, 29, 23, 59),
        '下个星期五交付': DateTime(2026, 7, 31, 23, 59),
        '下个礼拜天复盘': DateTime(2026, 8, 2, 23, 59),
      };

      for (final MapEntry<String, DateTime> entry in cases.entries) {
        expect(
          parseNaturalLanguageTask(entry.key, now: monday)!.dueDate,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('上个等不支持的星期词整体拒绝，不降级成未来裸星期', () {
      final DateTime monday = DateTime(2026, 7, 20, 9);
      const List<String> inputs = <String>[
        '上个周三复盘',
        '上个星期三复盘',
        '上个礼拜三复盘',
        '这个礼拜三开会',
        '每个星期三开会',
      ];

      for (final String input in inputs) {
        expect(
          parseNaturalLanguageTask(input, now: monday),
          isNull,
          reason: input,
        );
      }
    });

    test('今天的裸周几时间已过时推进七天', () {
      final ParsedTaskInput result = parseNaturalLanguageTask(
        '周三下午3点开会',
        now: DateTime(2026, 7, 22, 17),
      )!;

      expect(result.dueDate, DateTime(2026, 7, 29, 15));
    });

    test('礼拜和星期按周几规则归一化', () {
      final DateTime monday = DateTime(2026, 7, 20, 9);
      final Map<String, DateTime> cases = <String, DateTime>{
        '礼拜一开会': DateTime(2026, 7, 20, 23, 59),
        '礼拜天复盘': DateTime(2026, 7, 26, 23, 59),
        '星期天复盘': DateTime(2026, 7, 26, 23, 59),
        '星期日复盘': DateTime(2026, 7, 26, 23, 59),
        '下礼拜二交付': DateTime(2026, 7, 28, 23, 59),
        '下星期三评审': DateTime(2026, 7, 29, 23, 59),
      };

      for (final MapEntry<String, DateTime> entry in cases.entries) {
        expect(
          parseNaturalLanguageTask(entry.key, now: monday)!.dueDate,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('下星期词必须整体匹配，不能从内部降级成裸星期词', () {
      final ParsedTaskInput result = parseNaturalLanguageTask(
        '下星期三评审',
        now: DateTime(2026, 7, 20, 9),
      )!;

      expect(result.title, '评审');
      expect(result.dueDate, DateTime(2026, 7, 29, 23, 59));
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

    test('早上、清早和傍晚按对应时段处理', () {
      final DateTime earlyMorning = DateTime(2026, 7, 20, 5);

      expect(
        parseNaturalLanguageTask('早上九点晨会', now: earlyMorning)!.dueDate,
        DateTime(2026, 7, 20, 9),
      );
      expect(
        parseNaturalLanguageTask('清早六点跑步', now: earlyMorning)!.dueDate,
        DateTime(2026, 7, 20, 6),
      );
      expect(
        parseNaturalLanguageTask('傍晚六点散步', now: earlyMorning)!.dueDate,
        DateTime(2026, 7, 20, 18),
      );
    });

    test('中文数字小时支持一至十一和两', () {
      final DateTime midnight = DateTime(2026, 7, 20);
      const Map<String, int> cases = <String, int>{
        '一点任务': 1,
        '二点任务': 2,
        '两点任务': 2,
        '三点任务': 3,
        '四点任务': 4,
        '五点任务': 5,
        '六点任务': 6,
        '七点任务': 7,
        '八点任务': 8,
        '九点任务': 9,
        '十点任务': 10,
        '十一点任务': 11,
      };

      for (final MapEntry<String, int> entry in cases.entries) {
        expect(
          parseNaturalLanguageTask(entry.key, now: midnight)!.dueDate,
          DateTime(2026, 7, 20, entry.value),
          reason: entry.key,
        );
      }
    });

    test('半、一刻、三刻和数字分转换为分钟并完整移除', () {
      final DateTime now = DateTime(2026, 7, 20, 8);
      final Map<String, DateTime> cases = <String, DateTime>{
        '下午3点半评审': DateTime(2026, 7, 20, 15, 30),
        '晚上8点一刻运动': DateTime(2026, 7, 20, 20, 15),
        '早上9点三刻出门': DateTime(2026, 7, 20, 9, 45),
        '上午9点30分开会': DateTime(2026, 7, 20, 9, 30),
        '上午九点30分晨会': DateTime(2026, 7, 20, 9, 30),
        '下午3点30分评审': DateTime(2026, 7, 20, 15, 30),
        '下午两点同步': DateTime(2026, 7, 20, 14),
        '8点半早餐': DateTime(2026, 7, 20, 8, 30),
        '8点一刻早餐': DateTime(2026, 7, 20, 8, 15),
        '8点三刻早餐': DateTime(2026, 7, 20, 8, 45),
        '九点5分喝水': DateTime(2026, 7, 20, 9, 5),
        '15点30分提交': DateTime(2026, 7, 20, 15, 30),
      };
      const Map<String, String> titles = <String, String>{
        '下午3点半评审': '评审',
        '晚上8点一刻运动': '运动',
        '早上9点三刻出门': '出门',
        '上午9点30分开会': '开会',
        '上午九点30分晨会': '晨会',
        '下午3点30分评审': '评审',
        '下午两点同步': '同步',
        '8点半早餐': '早餐',
        '8点一刻早餐': '早餐',
        '8点三刻早餐': '早餐',
        '九点5分喝水': '喝水',
        '15点30分提交': '提交',
      };

      for (final MapEntry<String, DateTime> entry in cases.entries) {
        final ParsedTaskInput result = parseNaturalLanguageTask(
          entry.key,
          now: now,
        )!;
        expect(result.dueDate, entry.value, reason: entry.key);
        expect(result.title, titles[entry.key], reason: entry.key);
      }
    });

    test('中午消解十二点并支持口语分钟', () {
      final DateTime now = DateTime(2026, 7, 20, 9);
      final Map<String, DateTime> cases = <String, DateTime>{
        '中午开会': DateTime(2026, 7, 20, 12),
        '明天中午开会': DateTime(2026, 7, 21, 12),
        '中午12点吃饭': DateTime(2026, 7, 20, 12),
        '中午十二点半吃饭': DateTime(2026, 7, 20, 12, 30),
        '中午12点一刻提醒': DateTime(2026, 7, 20, 12, 15),
        '中午12点30分提醒': DateTime(2026, 7, 20, 12, 30),
      };

      for (final MapEntry<String, DateTime> entry in cases.entries) {
        expect(
          parseNaturalLanguageTask(entry.key, now: now)!.dueDate,
          entry.value,
          reason: entry.key,
        );
      }
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

    test('明早、今晚和明晚携带日期与时段语义', () {
      final ParsedTaskInput tomorrowMorning = parseNaturalLanguageTask(
        '明早九点开会',
        now: now,
      )!;
      final ParsedTaskInput explicitTomorrowMorning = parseNaturalLanguageTask(
        '明天早上九点开会',
        now: now,
      )!;
      final ParsedTaskInput tonight = parseNaturalLanguageTask(
        '今晚8点聚餐',
        now: now,
      )!;
      final ParsedTaskInput tomorrowEvening = parseNaturalLanguageTask(
        '明晚八点一刻电影',
        now: now,
      )!;

      expect(tomorrowMorning.title, '开会');
      expect(tomorrowMorning.dueDate, DateTime(2026, 7, 21, 9));
      expect(explicitTomorrowMorning.title, '开会');
      expect(explicitTomorrowMorning.dueDate, DateTime(2026, 7, 21, 9));
      expect(tonight.title, '聚餐');
      expect(tonight.dueDate, DateTime(2026, 7, 20, 20));
      expect(tomorrowEvening.title, '电影');
      expect(tomorrowEvening.dueDate, DateTime(2026, 7, 21, 20, 15));
    });

    test('下周一上午9点30分解析为完整组合', () {
      final ParsedTaskInput result = parseNaturalLanguageTask(
        '下周一上午9点30分项目会',
        now: now,
      )!;

      expect(result.title, '项目会');
      expect(result.dueDate, DateTime(2026, 7, 27, 9, 30));
    });
  });

  group('保守失败', () {
    final DateTime now = DateTime(2026, 7, 20, 9);

    test('没有受支持时间表达式时不解析', () {
      expect(parseNaturalLanguageTask('整理会议记录', now: now), isNull);
      expect(parseNaturalLanguageTask('tomorrow meeting', now: now), isNull);
    });

    test('日期加裸时段但无精确时刻时不解析', () {
      const List<String> inputs = <String>[
        '明早开会',
        '今晚开会',
        '今天下午开会',
        '明天早上开会',
        '明天晚上聚餐',
      ];

      for (final String input in inputs) {
        expect(
          parseNaturalLanguageTask(input, now: now),
          isNull,
          reason: input,
        );
      }
    });

    test('重复语义不能被丢弃后当成一次性任务', () {
      const List<String> inputs = <String>[
        '每天晚上8点吃药',
        '每晚8点吃药',
        '每日上午9点打卡',
        '每月15号交房租',
        '每年3月1号体检',
      ];

      for (final String input in inputs) {
        expect(
          parseNaturalLanguageTask(input, now: now),
          isNull,
          reason: input,
        );
      }
    });

    test('中文数字绝对日期整句不解析', () {
      const List<String> inputs = <String>[
        '三月一号交房租',
        '二月十五号交周报',
        '三月一号上午9点30分面试',
        '十二月三十一号复盘',
        '2015年3月3号开会',
        '二零一五年三月三號纪念',
      ];

      for (final String input in inputs) {
        expect(
          parseNaturalLanguageTask(input, now: now),
          isNull,
          reason: input,
        );
      }
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
        '每星期一开会',
        '每礼拜一开会',
        '每周下午3点开会',
        '每星期下午3点开会',
        '本星期一开会',
        '下下礼拜一开会',
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
        '今天下午3点整开会',
        '今天下午 3点开会',
        '今天十二点开会',
        '今天二十点开会',
        '今天九点三十分开会',
        '今天凌晨三点开会',
        '今天后半晌3点开会',
        '今天夜里八点开会',
        '今天深夜十点开会',
        '今天中午一点开会',
        '今天中午九点开会',
        '今天中午十二点三十分开会',
        '明早上午九点开会',
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
