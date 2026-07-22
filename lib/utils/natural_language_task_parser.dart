/// 快速添加文本中解析出的任务标题与本地截止时间。
class ParsedTaskInput {
  const ParsedTaskInput({required this.title, required this.dueDate});

  final String title;
  final DateTime dueDate;
}

final RegExp _unsupportedDatePattern = RegExp(
  r'(?:每|本|上|这)周[一二三四五六日]|下下周[一二三四五六日]|'
  r'星期[一二三四五六日天]|月初|月底|'
  r'\d{1,2}月\d{1,2}[日号]|\d+(?:天|周|个月|月)后',
);

final RegExp _datePattern = RegExp(r'下周[一二三四五六日]|今天|明天|后天|周[一二三四五六日]');

final RegExp _timePattern = RegExp(
  r'上午(?:[1-9]|1[01])点(?!\d)|'
  r'下午(?:[1-9]|1[01])点(?!\d)|'
  r'晚上(?:[6-9]|1[01])点(?!\d)|'
  r'(?:[01]?\d|2[0-3]):[0-5]\d(?!\d)|'
  r'(?:[01]?\d|2[0-3])点[0-5]\d(?!\d)',
);

// 用较宽的模式识别“看起来像时间但不受支持”的片段，避免在非法时间旁边
// 只解析日期，或从“下午3点30”中错误截取“3点30”。
final RegExp _timeLikePattern = RegExp(
  r'(?:上午|下午|晚上)\s*\d{1,3}点(?:\d{1,3})?(?:分|整)?|'
  r'(?:上午|下午|晚上)?[零一二三四五六七八九十两]{1,3}点|'
  r'\d{1,3}[:：]\d{1,3}(?:分)?|\d{1,3}点(?:\d{1,3})?(?:分|整)?',
);

const Map<String, int> _weekdayByText = <String, int>{
  '一': DateTime.monday,
  '二': DateTime.tuesday,
  '三': DateTime.wednesday,
  '四': DateTime.thursday,
  '五': DateTime.friday,
  '六': DateTime.saturday,
  '日': DateTime.sunday,
};

/// 从一句快速添加文本中抽取一个受支持的日期/时间表达式。
///
/// [now] 用于相对日期和已过时间的计算；解析按设备本地时区进行。
/// 没有唯一、完整的受支持表达式时返回 null，由调用方保留原句。
ParsedTaskInput? parseNaturalLanguageTask(
  String input, {
  required DateTime now,
}) {
  if (_unsupportedDatePattern.hasMatch(input)) {
    return null;
  }

  final List<RegExpMatch> dateMatches = _datePattern.allMatches(input).toList();
  final List<RegExpMatch> timeMatches = _timePattern.allMatches(input).toList();
  final List<RegExpMatch> timeLikeMatches = _timeLikePattern
      .allMatches(input)
      .toList();

  if (dateMatches.length > 1 || timeMatches.length > 1) {
    return null;
  }
  if (!_timeMatchesAreComplete(timeMatches, timeLikeMatches)) {
    return null;
  }
  if (dateMatches.isEmpty && timeMatches.isEmpty) {
    return null;
  }

  final DateTime localNow = now.toLocal();
  final String? dateText = dateMatches.singleOrNull?.group(0);
  final String? timeText = timeMatches.singleOrNull?.group(0);
  final ({int hour, int minute}) parsedTime = timeText == null
      ? (hour: 23, minute: 59)
      : _parseTime(timeText);

  DateTime dueDate = _resolveDate(
    dateText,
    localNow,
    parsedTime.hour,
    parsedTime.minute,
  );

  // 只写时间时默认取下一次到来的该时间，避免新建一个已经过期的任务。
  if (dateText == null && !dueDate.isAfter(localNow)) {
    dueDate = dueDate.add(const Duration(days: 1));
  }

  // 裸“周X”取最近一次尚未过去的目标时刻；显式“下周X”不走该分支。
  if (dateText?.startsWith('周') == true && !dueDate.isAfter(localNow)) {
    dueDate = dueDate.add(const Duration(days: 7));
  }

  final List<RegExpMatch> matchedTokens = <RegExpMatch>[
    ...dateMatches,
    ...timeMatches,
  ]..sort((first, second) => second.start.compareTo(first.start));
  String title = input;
  for (final RegExpMatch match in matchedTokens) {
    title = title.replaceRange(match.start, match.end, '');
  }
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

  return ParsedTaskInput(title: title, dueDate: dueDate);
}

bool _timeMatchesAreComplete(
  List<RegExpMatch> validMatches,
  List<RegExpMatch> timeLikeMatches,
) {
  if (validMatches.length != timeLikeMatches.length) {
    return false;
  }
  for (int index = 0; index < validMatches.length; index++) {
    final RegExpMatch valid = validMatches[index];
    final RegExpMatch candidate = timeLikeMatches[index];
    if (valid.start != candidate.start || valid.end != candidate.end) {
      return false;
    }
  }
  return true;
}

({int hour, int minute}) _parseTime(String text) {
  if (text.startsWith('上午')) {
    return (hour: _hourBeforePoint(text), minute: 0);
  }
  if (text.startsWith('下午') || text.startsWith('晚上')) {
    return (hour: _hourBeforePoint(text) + 12, minute: 0);
  }
  if (text.contains(':')) {
    final List<String> parts = text.split(':');
    return (hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }
  final List<String> parts = text.split('点');
  return (hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

int _hourBeforePoint(String text) {
  final int prefixLength =
      text.startsWith('上午') || text.startsWith('下午') || text.startsWith('晚上')
      ? 2
      : 0;
  return int.parse(text.substring(prefixLength, text.indexOf('点')));
}

DateTime _resolveDate(String? dateText, DateTime now, int hour, int minute) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  if (dateText == null || dateText == '今天') {
    return DateTime(today.year, today.month, today.day, hour, minute);
  }
  if (dateText == '明天') {
    final DateTime tomorrow = today.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, hour, minute);
  }
  if (dateText == '后天') {
    final DateTime dayAfterTomorrow = today.add(const Duration(days: 2));
    return DateTime(
      dayAfterTomorrow.year,
      dayAfterTomorrow.month,
      dayAfterTomorrow.day,
      hour,
      minute,
    );
  }

  final bool nextWeek = dateText.startsWith('下周');
  final int targetWeekday =
      _weekdayByText[dateText.substring(dateText.length - 1)]!;
  final int dayOffset = nextWeek
      ? DateTime.daysPerWeek - now.weekday + targetWeekday
      : (targetWeekday - now.weekday + DateTime.daysPerWeek) %
            DateTime.daysPerWeek;
  final DateTime targetDate = today.add(Duration(days: dayOffset));
  return DateTime(
    targetDate.year,
    targetDate.month,
    targetDate.day,
    hour,
    minute,
  );
}
